-- Run on a Supabase development branch after
-- 20260813110000_atomic_membership_ledger_and_access_fixes.sql.
-- The enclosing transaction deliberately leaves no fixture data behind.

begin;

create or replace function pg_temp.assert_true(p_condition boolean, p_message text)
returns void language plpgsql as $$
begin
  if p_condition is distinct from true then
    raise exception 'atomic membership ledger test failed: %', p_message;
  end if;
end;
$$;

do $$
declare
  v_admin uuid;
  v_member uuid;
  v_non_admin uuid;
  v_gym uuid;
  v_plan_a uuid := gen_random_uuid();
  v_plan_b uuid := gen_random_uuid();
  v_membership uuid := gen_random_uuid();
  v_legacy_membership uuid := gen_random_uuid();
  v_missing_membership uuid := gen_random_uuid();
  v_deleted_membership uuid := gen_random_uuid();
  v_duplicate_membership uuid := gen_random_uuid();
  v_delete_membership uuid := gen_random_uuid();
  v_ledger uuid;
  v_created boolean;
  v_counts jsonb;
  v_failed boolean;
begin
  select id into v_admin from public.profiles where is_admin = true order by id limit 1;
  select id into v_member from public.profiles order by id limit 1;
  select id into v_non_admin from public.profiles where coalesce(is_admin, false) = false order by id limit 1;
  select id into v_gym from public.gyms order by id limit 1;
  perform pg_temp.assert_true(v_admin is not null and v_member is not null and v_gym is not null,
    'an admin, a profile, and a gym fixture are required');

  insert into public.membership_plans (
    id, name, tier, gym_id, monthly_price_cents, yearly_price_cents,
    student_discount_cents, currency, plan_kind, is_active, is_family_plan,
    is_good_morning, duration_months, duration_days, created_at, updated_at
  ) values
    (v_plan_a, 'Atomic SQL plan A', 'basic', v_gym, 10000, 0, 0, 'RON', 'package', true, false, false, 1, 0, clock_timestamp(), clock_timestamp()),
    (v_plan_b, 'Atomic SQL plan B', 'gold', v_gym, 12000, 0, 0, 'RON', 'package', true, false, false, 1, 0, clock_timestamp(), clock_timestamp());

  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  select membership_id, revenue_ledger_id, was_created
  into v_membership, v_ledger, v_created
  from public.admin_save_membership(
    v_membership, v_member, v_plan_a, v_gym, date '2026-03-01', date '2026-03-31',
    true, 'monthly', 10000, 'cash'
  );
  perform pg_temp.assert_true(v_created and v_ledger is not null,
    'create writes both membership and canonical base charge');
  perform pg_temp.assert_true(
    (select count(*) from public.revenue_ledger where membership_id = v_membership
      and idempotency_key = 'membership-sale:' || v_membership::text) = 1,
    'new charge has exactly one canonical idempotency key');

  -- A lost response retry returns the same logical membership without another charge.
  select membership_id, revenue_ledger_id, was_created
  into v_membership, v_ledger, v_created
  from public.admin_save_membership(
    v_membership, v_member, v_plan_a, v_gym, date '2026-03-01', date '2026-03-31',
    true, 'monthly', 10000, 'cash'
  );
  perform pg_temp.assert_true(not v_created and
    (select count(*) from public.revenue_ledger where membership_id = v_membership) = 1,
    'same client-generated ID is idempotent');

  perform public.admin_save_membership(
    v_membership, v_member, v_plan_b, v_gym, date '2026-03-02', date '2026-04-01',
    true, 'monthly', 10000, 'card'
  );
  perform pg_temp.assert_true(
    (select plan_id = v_plan_b and gym_id = v_gym and amount_cents = 10000
      and payment_method = 'card' from public.revenue_ledger where id = v_ledger),
    'unchanged price still updates plan, gym, amount, and payment method');

  insert into public.memberships (
    id, user_id, plan_id, sold_at_gym_id, start_date, end_date,
    is_active, membership_type, price_paid_cents, payment_method
  ) values (v_legacy_membership, v_member, v_plan_a, v_gym, date '2026-03-01', date '2026-03-31', true, 'monthly', 10000, 'cash');
  insert into public.revenue_ledger (
    membership_id, plan_id, gym_id, amount_cents, currency, source, entry_kind,
    payment_method, recorded_by
  ) values (v_legacy_membership, v_plan_a, v_gym, 9000, 'RON', 'membership_sale', 'charge', 'cash', v_admin);
  perform public.admin_save_membership(
    v_legacy_membership, v_member, v_plan_b, v_gym, date '2026-03-01', date '2026-03-31', true, 'monthly', 10000, 'card'
  );
  perform pg_temp.assert_true(
    (select source = 'membership' and idempotency_key = 'membership-sale:' || v_legacy_membership::text
      and amount_cents = 10000 and plan_id = v_plan_b
      from public.revenue_ledger where membership_id = v_legacy_membership),
    'one legacy base charge is canonicalized');

  insert into public.memberships (
    id, user_id, plan_id, sold_at_gym_id, start_date, end_date,
    is_active, membership_type, price_paid_cents, payment_method
  ) values (v_missing_membership, v_member, v_plan_a, v_gym, date '2026-03-01', date '2026-03-31', true, 'monthly', 10000, 'cash');
  perform public.admin_save_membership(
    v_missing_membership, v_member, v_plan_a, v_gym, date '2026-03-01', date '2026-03-31', true, 'monthly', 10000, 'cash'
  );
  perform pg_temp.assert_true(
    (select count(*) from public.revenue_ledger where membership_id = v_missing_membership) = 1,
    'missing base charge is repaired atomically');

  insert into public.memberships (
    id, user_id, plan_id, sold_at_gym_id, start_date, end_date,
    is_active, membership_type, price_paid_cents, payment_method
  ) values (v_deleted_membership, v_member, v_plan_a, v_gym, date '2026-03-01', date '2026-03-31', true, 'monthly', 10000, 'cash');
  insert into public.revenue_ledger (
    membership_id, plan_id, gym_id, amount_cents, currency, source, entry_kind,
    payment_method, is_deleted, recorded_by
  ) values (v_deleted_membership, v_plan_a, v_gym, 10000, 'RON', 'membership', 'charge', 'cash', true, v_admin);
  v_failed := false;
  begin
    perform public.admin_save_membership(v_deleted_membership, v_member, v_plan_b, v_gym,
      date '2026-03-02', date '2026-04-01', true, 'monthly', 11000, 'card');
  exception when sqlstate 'P0001' then
    v_failed := true;
  end;
  perform pg_temp.assert_true(v_failed and
    (select plan_id = v_plan_a from public.memberships where id = v_deleted_membership),
    'deleted-only ledger history blocks save and rolls back membership changes');

  insert into public.memberships (
    id, user_id, plan_id, sold_at_gym_id, start_date, end_date,
    is_active, membership_type, price_paid_cents, payment_method
  ) values (v_duplicate_membership, v_member, v_plan_a, v_gym, date '2026-03-01', date '2026-03-31', true, 'monthly', 10000, 'cash');
  insert into public.revenue_ledger (
    membership_id, plan_id, gym_id, amount_cents, currency, source, entry_kind, payment_method, recorded_by
  ) values
    (v_duplicate_membership, v_plan_a, v_gym, 10000, 'RON', 'membership', 'charge', 'cash', v_admin),
    (v_duplicate_membership, v_plan_a, v_gym, 10000, 'RON', 'membership_sale', 'charge', 'cash', v_admin);
  v_failed := false;
  begin
    perform public.admin_save_membership(v_duplicate_membership, v_member, v_plan_b, v_gym,
      date '2026-03-02', date '2026-04-01', true, 'monthly', 11000, 'card');
  exception when sqlstate 'P0001' then
    v_failed := true;
  end;
  perform pg_temp.assert_true(v_failed and
    (select count(*) from public.revenue_ledger where membership_id = v_duplicate_membership) = 2,
    'duplicate active base charges block save without a partial write');

  if v_non_admin is not null then
    perform set_config('request.jwt.claim.sub', v_non_admin::text, true);
    v_failed := false;
    begin
      perform public.admin_save_membership(gen_random_uuid(), v_member, v_plan_a, v_gym,
        date '2026-03-01', date '2026-03-31', true, 'monthly', 10000, 'cash');
    exception when sqlstate '42501' then
      v_failed := true;
    end;
    perform pg_temp.assert_true(v_failed, 'non-admin cannot save a membership');
    perform set_config('request.jwt.claim.sub', v_admin::text, true);
  end if;

  insert into public.memberships (
    id, user_id, plan_id, sold_at_gym_id, start_date, end_date,
    is_active, membership_type, price_paid_cents, payment_method
  ) values (v_delete_membership, v_member, v_plan_a, v_gym, date '2026-03-01', date '2026-03-31', true, 'monthly', 10000, 'cash');
  insert into public.revenue_ledger (
    membership_id, plan_id, gym_id, amount_cents, currency, source, entry_kind, payment_method, recorded_by
  ) values (v_delete_membership, v_plan_a, v_gym, 10000, 'RON', 'membership', 'charge', 'cash', v_admin);
  insert into public.membership_events (membership_id, event_type, at)
  values (v_delete_membership, 'created', clock_timestamp());
  v_counts := public.admin_delete_membership(v_delete_membership);
  perform pg_temp.assert_true((v_counts ->> 'memberships')::integer = 1 and
    (v_counts ->> 'revenue_ledger')::integer = 1 and
    not exists (select 1 from public.memberships where id = v_delete_membership),
    'delete removes dependent rows and membership in one transaction');

  begin
    insert into public.revenue_ledger (
      membership_id, plan_id, gym_id, amount_cents, currency, source, entry_kind,
      payment_method, idempotency_key, recorded_by
    ) values (v_missing_membership, v_plan_a, v_gym, 1, 'RON', 'membership', 'charge', 'cash',
      'membership-sale:' || v_missing_membership::text, v_admin);
    raise exception 'expected unique idempotency violation';
  exception when unique_violation then
    null;
  end;
end;
$$;

rollback;
