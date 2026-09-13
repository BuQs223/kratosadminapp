-- Run on the Supabase development branch after applying
-- 20260808090000_add_membership_access_analytics.sql.
--
-- This file rolls back all fixtures. It deliberately uses real profile and gym
-- IDs so it exercises the deployed foreign keys, triggers, RLS helpers, and
-- the same function bodies used in production.

begin;

create or replace function pg_temp.assert_true(p_condition boolean, p_message text)
returns void
language plpgsql
as $$
begin
  if p_condition is distinct from true then
    raise exception 'membership access analytics test failed: %', p_message;
  end if;
end;
$$;

do $$
declare
  v_people uuid[];
  v_admin uuid;
  v_gyms uuid[];
  v_package_plan uuid := gen_random_uuid();
  v_day_pass_plan uuid := gen_random_uuid();
  v_owner_membership uuid := gen_random_uuid();
  v_overlapping_membership uuid := gen_random_uuid();
  v_day_pass_membership uuid := gen_random_uuid();
  v_canceled_membership uuid := gen_random_uuid();
  v_frozen_membership uuid := gen_random_uuid();
  v_active_count integer;
  v_new_activations integer;
  v_is_estimated boolean;
  v_point_count integer;
  v_today date := (now() at time zone 'Europe/Bucharest')::date;
begin
  select array_agg(p.id order by p.id)
  into v_people
  from (
    select id
    from public.profiles
    order by id
    limit 5
  ) p;
  select p.id into v_admin from public.profiles p where p.is_admin = true order by p.id limit 1;
  select array_agg(g.id order by g.id)
  into v_gyms
  from (
    select id
    from public.gyms
    order by id
    limit 2
  ) g;

  perform pg_temp.assert_true(cardinality(v_people) = 5, 'five fixture profiles are required');
  perform pg_temp.assert_true(v_admin is not null, 'an admin profile is required');
  perform pg_temp.assert_true(cardinality(v_gyms) = 2, 'two fixture gyms are required');

  insert into public.membership_plans (
    id, name, tier, gym_id, monthly_price_cents, yearly_price_cents,
    student_discount_cents, currency, plan_kind, is_active, is_family_plan,
    is_good_morning, duration_months, duration_days, created_at, updated_at
  ) values
    (v_package_plan, 'SQL test package access', 'basic', v_gyms[1], 0, 0, 0, 'RON', 'package', true, true, false, 1, 0, clock_timestamp(), clock_timestamp()),
    (v_day_pass_plan, 'SQL test day pass', 'basic', v_gyms[1], 0, 0, 0, 'RON', 'day_pass', true, false, false, 0, 1, clock_timestamp(), clock_timestamp());

  insert into public.memberships (
    id, user_id, plan_id, membership_type, start_date, effective_start_date,
    end_date, duration_months, duration_days, is_active, is_student,
    price_paid_cents, currency, payment_method, sold_at_gym_id, created_at,
    updated_at, canceled_at, is_frozen, frozen_at
  ) values
    -- Owner starts on the 24th; the later extension must not add an activation.
    (v_owner_membership, v_people[1], v_package_plan, 'monthly', date '2000-03-24', date '2000-03-24', date '2000-03-28', 1, 0, true, false, 0, 'RON', 'cash', v_gyms[1], clock_timestamp(), clock_timestamp(), null, false, null),
    -- Same person and same gym: overlaps but must not increase a distinct count.
    (v_overlapping_membership, v_people[1], v_package_plan, 'monthly', date '2000-03-25', date '2000-03-25', date '2000-04-10', 1, 0, true, false, 0, 'RON', 'cash', v_gyms[1], clock_timestamp(), clock_timestamp(), null, false, null),
    (v_day_pass_membership, v_people[3], v_day_pass_plan, 'day_pass', date '2000-03-24', date '2000-03-24', date '2000-03-24', 0, 1, true, false, 0, 'RON', 'cash', v_gyms[1], clock_timestamp(), clock_timestamp(), null, false, null),
    (v_canceled_membership, v_people[4], v_package_plan, 'monthly', date '2000-03-24', date '2000-03-24', date '2000-04-10', 1, 0, true, false, 0, 'RON', 'cash', v_gyms[1], clock_timestamp(), clock_timestamp(), timestamptz '2000-03-23 12:00:00+00', false, null),
    (v_frozen_membership, v_people[5], v_package_plan, 'monthly', date '2000-03-24', date '2000-03-24', date '2000-04-10', 1, 0, true, false, 0, 'RON', 'cash', v_gyms[1], clock_timestamp(), clock_timestamp(), null, true, timestamptz '2000-03-24 12:00:00+00');

  insert into public.family_memberships (user_id, membership_id, created_at)
  values (v_people[2], v_owner_membership, timestamptz '2000-03-26 12:00:00+00');

  insert into public.membership_events (
    membership_id, event_type, at, old_end_date, new_end_date
  ) values (
    v_owner_membership, 'extended', timestamptz '2000-03-28 12:00:00+00', date '2000-03-28', date '2000-04-10'
  );

  select count(*)::integer into v_active_count
  from private.membership_access_people_at(date '2000-03-25', v_gyms[1]);
  perform pg_temp.assert_true(v_active_count = 1, 'owner activation is distinct despite overlapping access');

  select count(*)::integer into v_active_count
  from private.membership_access_people_at(date '2000-03-26', v_gyms[1]);
  perform pg_temp.assert_true(v_active_count = 2, 'family join adds one distinct person; day pass, canceled, and frozen access are excluded');

  select count(*)::integer into v_active_count
  from private.membership_access_people_at(date '2000-03-26', null);
  perform pg_temp.assert_true(v_active_count = 2, 'all-gym population is distinct people, not a sum of gym rows');

  select count(*)::integer into v_active_count
  from private.membership_access_people_at(date '2000-03-26', v_gyms[2]);
  perform pg_temp.assert_true(v_active_count = 0, 'selling-gym filter excludes access sold by another gym');

  select m.new_activations into v_new_activations
  from private.membership_access_metric_at(date '2000-03-28', v_gyms[1]) m;
  perform pg_temp.assert_true(v_new_activations = 0, 'an extension does not count as an activation');

  -- 2000-03-26 is the Bucharest spring DST transition; date-based boundaries
  -- must remain stable across it. The October transition is covered too.
  perform pg_temp.assert_true(
    (select count(*) from private.membership_access_people_at(date '2000-03-26', v_gyms[1])) = 2
    and (select count(*) from private.membership_access_people_at(date '2000-10-29', v_gyms[1])) = 0,
    'Bucharest DST dates preserve date-boundary access evaluation'
  );

  perform private.refresh_membership_access_daily_snapshot(date '2000-03-28', true);
  select m.is_estimated into v_is_estimated
  from private.membership_access_metric_at(date '2000-03-28', v_gyms[1]) m;
  perform pg_temp.assert_true(v_is_estimated, 'reconstructed rows are visibly estimated');

  perform private.refresh_membership_access_daily_snapshot(date '2000-03-28', false);
  select m.is_estimated into v_is_estimated
  from private.membership_access_metric_at(date '2000-03-28', v_gyms[1]) m;
  perform pg_temp.assert_true(not v_is_estimated, 'a closed snapshot promotes an estimate to exact');

  perform pg_temp.assert_true(
    exists (
      select 1 from private.membership_access_audit a
      where a.membership_id = v_owner_membership and a.operation = 'owner_created'
    ) and exists (
      select 1 from private.membership_access_audit a
      where a.membership_id = v_owner_membership and a.operation = 'family_joined'
    ),
    'owner and family changes create structured access audit rows'
  );

  -- public.is_admin() reads this standard Supabase request claim setting.
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  select count(*)::integer into v_point_count
  from public.get_admin_membership_access_trend('30d', null);
  perform pg_temp.assert_true(v_point_count = 30, '30D returns daily points including the partial current day');

  select count(*)::integer into v_point_count
  from public.get_admin_membership_access_trend('12w', null)
  where extract(isodow from period_start) = 1
    and period_end <= v_today;
  perform pg_temp.assert_true(v_point_count = 12, '12W uses twelve Monday-started buckets with a partial current bucket');

  select count(*)::integer into v_point_count
  from public.get_admin_membership_access_trend('12m', null)
  where extract(day from period_start) = 1
    and period_end <= v_today;
  perform pg_temp.assert_true(v_point_count = 12, '12M uses calendar-month buckets with a partial current month');
end;
$$;

-- Anonymous/authenticated execution must not be public. The public RPC still
-- performs its own admin assertion after the authenticated grant.
do $$
begin
  perform set_config('request.jwt.claim.sub', '', true);
  begin
    perform public.get_admin_membership_access_trend('7d', null);
    raise exception 'expected admin authorization failure';
  exception when sqlstate '42501' then
    null;
  end;
end;
$$;

rollback;

-- Run separately as the authenticated development-branch admin after the
-- transaction above. Capture this output with the rollout evidence:
--
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT * FROM public.get_admin_membership_access_trend('12m', NULL);
