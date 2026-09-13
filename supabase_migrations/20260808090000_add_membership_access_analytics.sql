-- Active membership access analytics.
--
-- Historical rows are reconstructed from the current membership, lifecycle, and
-- family-link records and are marked estimated. Once a Bucharest day closes, a
-- durable snapshot is stored so later edits/deletes cannot alter the report.

create schema if not exists private;

revoke all on schema private from public;
revoke all on schema private from anon;
revoke all on schema private from authenticated;

create table if not exists private.membership_access_daily_snapshots (
  snapshot_date date not null,
  selling_gym_id uuid null,
  -- Internal key makes the all-gyms (NULL gym) row unique as well.
  scope_key text generated always as (
    coalesce(selling_gym_id::text, '__all_gyms__')
  ) stored,
  active_people integer not null check (active_people >= 0),
  new_activations integer not null check (new_activations >= 0),
  is_estimated boolean not null default false,
  computed_at timestamptz not null default clock_timestamp(),
  primary key (snapshot_date, scope_key)
);

comment on table private.membership_access_daily_snapshots is
  'Private, immutable-after-close daily access snapshots. NULL selling_gym_id is the distinct all-gym population.';

create index if not exists membership_access_daily_snapshots_gym_date_idx
  on private.membership_access_daily_snapshots (selling_gym_id, snapshot_date desc);

create table if not exists private.membership_access_audit (
  id bigint generated always as identity primary key,
  recorded_at timestamptz not null default clock_timestamp(),
  operation text not null check (
    operation in (
      'owner_baseline', 'owner_created', 'owner_changed', 'owner_deleted',
      'family_baseline', 'family_joined', 'family_changed', 'family_removed'
    )
  ),
  access_role text not null check (access_role in ('owner', 'family')),
  membership_id uuid not null,
  person_id uuid not null,
  selling_gym_id uuid null,
  plan_id uuid null,
  plan_kind text null,
  effective_start_date date null,
  end_date date null,
  canceled_at timestamptz null,
  is_frozen boolean null,
  family_link_created_at timestamptz null,
  source_row jsonb not null
);

comment on table private.membership_access_audit is
  'Append-only, structured owner and family-access audit. It intentionally has no foreign keys so deleted source rows remain auditable.';

create index if not exists membership_access_audit_membership_recorded_idx
  on private.membership_access_audit (membership_id, recorded_at desc);
create index if not exists membership_access_audit_person_recorded_idx
  on private.membership_access_audit (person_id, recorded_at desc);

-- These cover the repeated as-of lookups used by the twelve-month backfill and
-- the daily close job without changing the operational membership queries.
create index if not exists memberships_access_analytics_scope_idx
  on public.memberships (
    plan_id,
    sold_at_gym_id,
    (coalesce(effective_start_date, start_date)),
    end_date
  );
create index if not exists membership_events_access_analytics_idx
  on public.membership_events (membership_id, at desc, id desc);
create index if not exists family_memberships_access_analytics_idx
  on public.family_memberships (membership_id, created_at, user_id);

alter table private.membership_access_daily_snapshots enable row level security;
alter table private.membership_access_audit enable row level security;

revoke all on table private.membership_access_daily_snapshots from public;
revoke all on table private.membership_access_daily_snapshots from anon;
revoke all on table private.membership_access_daily_snapshots from authenticated;
revoke all on table private.membership_access_audit from public;
revoke all on table private.membership_access_audit from anon;
revoke all on table private.membership_access_audit from authenticated;

-- Returns unique people with package-membership access at the close of a
-- Bucharest calendar date. This is also the reconstruction source for the
-- estimated historical backfill.
create or replace function private.membership_access_people_at(
  p_snapshot_date date,
  p_gym_id uuid default null
)
returns table(person_id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  with membership_state as (
    select
      m.id,
      m.user_id,
      m.sold_at_gym_id,
      coalesce(
        (
          select me.new_start_date::date
          from public.membership_events me
          where me.membership_id = m.id
            and me.at::date <= p_snapshot_date
            and me.new_start_date is not null
          order by me.at desc, me.id desc
          limit 1
        ),
        (
          select me.old_start_date::date
          from public.membership_events me
          where me.membership_id = m.id
            and me.at::date > p_snapshot_date
            and me.old_start_date is not null
          order by me.at asc, me.id asc
          limit 1
        ),
        coalesce(m.effective_start_date, m.start_date)::date
      ) as effective_start_date,
      coalesce(
        (
          select me.new_end_date::date
          from public.membership_events me
          where me.membership_id = m.id
            and me.at::date <= p_snapshot_date
            and me.new_end_date is not null
          order by me.at desc, me.id desc
          limit 1
        ),
        (
          select me.old_end_date::date
          from public.membership_events me
          where me.membership_id = m.id
            and me.at::date > p_snapshot_date
            and me.old_end_date is not null
          order by me.at asc, me.id asc
          limit 1
        ),
        m.end_date::date
      ) as effective_end_date,
      coalesce(
        (
          select me.event_type = 'paused'
          from public.membership_events me
          where me.membership_id = m.id
            and me.event_type in ('paused', 'resumed')
            and me.at::date <= p_snapshot_date
          order by me.at desc, me.id desc
          limit 1
        ),
        coalesce(m.is_frozen, false)
          and (m.frozen_at is null or m.frozen_at::date <= p_snapshot_date),
        false
      ) as was_frozen,
      exists (
        select 1
        from public.membership_events me
        where me.membership_id = m.id
          and me.event_type = 'canceled'
          and me.at::date <= p_snapshot_date
      )
      or (m.canceled_at is not null and m.canceled_at::date <= p_snapshot_date) as was_canceled
    from public.memberships m
    join public.membership_plans mp on mp.id = m.plan_id
    where mp.plan_kind = 'package'
      -- This also protects the metric if legacy day passes were incorrectly
      -- attached to a package plan.
      and lower(coalesce(m.membership_type, '')) not in ('day_pass', 'day-pass', 'daily')
      and (p_gym_id is null or m.sold_at_gym_id = p_gym_id)
  ),
  active_memberships as (
    select ms.*
    from membership_state ms
    where ms.effective_start_date <= p_snapshot_date
      and ms.effective_end_date >= p_snapshot_date
      and not ms.was_canceled
      and not ms.was_frozen
  ),
  access_people as (
    select am.user_id as person_id
    from active_memberships am
    union
    select fm.user_id as person_id
    from active_memberships am
    join public.family_memberships fm on fm.membership_id = am.id
    where fm.created_at::date <= p_snapshot_date
  )
  select distinct ap.person_id
  from access_people ap;
$$;

-- A reactivation after an unrelated state transition (for example, unfreezing)
-- is not a new activation. Candidates are deliberately limited to an owner
-- access start or a family link being added on this reporting date.
create or replace function private.membership_access_activation_candidates_at(
  p_snapshot_date date,
  p_gym_id uuid default null
)
returns table(person_id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  with package_memberships as (
    select
      m.id,
      m.user_id,
      coalesce(
        (
          select me.new_start_date::date
          from public.membership_events me
          where me.membership_id = m.id
            and me.at::date <= p_snapshot_date
            and me.new_start_date is not null
          order by me.at desc, me.id desc
          limit 1
        ),
        (
          select me.old_start_date::date
          from public.membership_events me
          where me.membership_id = m.id
            and me.at::date > p_snapshot_date
            and me.old_start_date is not null
          order by me.at asc, me.id asc
          limit 1
        ),
        coalesce(m.effective_start_date, m.start_date)::date
      ) as effective_start_date
    from public.memberships m
    join public.membership_plans mp on mp.id = m.plan_id
    where mp.plan_kind = 'package'
      and lower(coalesce(m.membership_type, '')) not in ('day_pass', 'day-pass', 'daily')
      and (p_gym_id is null or m.sold_at_gym_id = p_gym_id)
  )
  select pm.user_id as person_id
  from package_memberships pm
  where pm.effective_start_date = p_snapshot_date
  union
  select fm.user_id as person_id
  from package_memberships pm
  join public.family_memberships fm on fm.membership_id = pm.id
  where fm.created_at::date = p_snapshot_date;
$$;

-- Reads a stored point when available. Missing and in-progress points are
-- deliberately calculated live and returned as estimated rather than silently
-- disappearing from a range.
create or replace function private.membership_access_metric_at(
  p_snapshot_date date,
  p_gym_id uuid default null
)
returns table(
  active_people integer,
  new_activations integer,
  is_estimated boolean,
  computed_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  return query
  select
    s.active_people,
    s.new_activations,
    s.is_estimated,
    s.computed_at
  from private.membership_access_daily_snapshots s
  where s.snapshot_date = p_snapshot_date
    and s.selling_gym_id is not distinct from p_gym_id;

  if found then
    return;
  end if;

  return query
  with current_people as (
    select p.person_id
    from private.membership_access_people_at(p_snapshot_date, p_gym_id) p
  ),
  prior_people as (
    select p.person_id
    from private.membership_access_people_at(p_snapshot_date - 1, p_gym_id) p
  ),
  activation_candidates as (
    select p.person_id
    from private.membership_access_activation_candidates_at(p_snapshot_date, p_gym_id) p
  )
  select
    count(*)::integer as active_people,
    count(*) filter (
      where prior_people.person_id is null
        and activation_candidates.person_id is not null
    )::integer as new_activations,
    true as is_estimated,
    clock_timestamp() as computed_at
  from current_people
  left join prior_people using (person_id)
  left join activation_candidates using (person_id);
end;
$$;

create or replace function private.refresh_membership_access_daily_snapshot(
  p_snapshot_date date,
  p_is_estimated boolean default false
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gym_id uuid;
  v_existing_is_estimated boolean;
  v_active_people integer;
  v_new_activations integer;
  v_computed_at timestamptz;
begin
  if p_snapshot_date is null then
    raise exception 'snapshot date is required' using errcode = '22004';
  end if;

  if p_snapshot_date > (now() at time zone 'Europe/Bucharest')::date then
    raise exception 'cannot create a future membership access snapshot' using errcode = '22007';
  end if;

  -- A closed exact snapshot is immutable. This is what protects future reports
  -- from a later membership/family edit or deletion.
  select s.is_estimated
  into v_existing_is_estimated
  from private.membership_access_daily_snapshots s
  where s.snapshot_date = p_snapshot_date
    and s.selling_gym_id is null;

  if found and not v_existing_is_estimated then
    return;
  end if;

  with current_people as (
    select p.person_id
    from private.membership_access_people_at(p_snapshot_date, null) p
  ),
  prior_people as (
    select p.person_id
    from private.membership_access_people_at(p_snapshot_date - 1, null) p
  ),
  activation_candidates as (
    select p.person_id
    from private.membership_access_activation_candidates_at(p_snapshot_date, null) p
  )
  select
    count(*)::integer,
    count(*) filter (
      where prior_people.person_id is null
        and activation_candidates.person_id is not null
    )::integer,
    clock_timestamp()
  into v_active_people, v_new_activations, v_computed_at
  from current_people
  left join prior_people using (person_id)
  left join activation_candidates using (person_id);

  insert into private.membership_access_daily_snapshots (
    snapshot_date, selling_gym_id, active_people, new_activations, is_estimated, computed_at
  ) values (
    p_snapshot_date, null, v_active_people, v_new_activations, p_is_estimated, v_computed_at
  )
  on conflict (snapshot_date, scope_key) do update
  set active_people = excluded.active_people,
      new_activations = excluded.new_activations,
      is_estimated = excluded.is_estimated,
      computed_at = excluded.computed_at
  where private.membership_access_daily_snapshots.is_estimated;

  for v_gym_id in select g.id from public.gyms g loop
    select s.is_estimated
    into v_existing_is_estimated
    from private.membership_access_daily_snapshots s
    where s.snapshot_date = p_snapshot_date
      and s.selling_gym_id = v_gym_id;

    if found and not v_existing_is_estimated then
      continue;
    end if;

    with current_people as (
      select p.person_id
      from private.membership_access_people_at(p_snapshot_date, v_gym_id) p
    ),
    prior_people as (
      select p.person_id
      from private.membership_access_people_at(p_snapshot_date - 1, v_gym_id) p
    ),
    activation_candidates as (
      select p.person_id
      from private.membership_access_activation_candidates_at(p_snapshot_date, v_gym_id) p
    )
    select
      count(*)::integer,
      count(*) filter (
        where prior_people.person_id is null
          and activation_candidates.person_id is not null
      )::integer,
      clock_timestamp()
    into v_active_people, v_new_activations, v_computed_at
    from current_people
    left join prior_people using (person_id)
    left join activation_candidates using (person_id);

    insert into private.membership_access_daily_snapshots (
      snapshot_date, selling_gym_id, active_people, new_activations, is_estimated, computed_at
    ) values (
      p_snapshot_date, v_gym_id, v_active_people, v_new_activations, p_is_estimated, v_computed_at
    )
    on conflict (snapshot_date, scope_key) do update
    set active_people = excluded.active_people,
        new_activations = excluded.new_activations,
        is_estimated = excluded.is_estimated,
        computed_at = excluded.computed_at
    where private.membership_access_daily_snapshots.is_estimated;
  end loop;
end;
$$;

create or replace function private.capture_closed_bucharest_membership_access_snapshot()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.refresh_membership_access_daily_snapshot(
    ((now() at time zone 'Europe/Bucharest')::date - 1),
    false
  );
end;
$$;

create or replace function private.audit_membership_owner_access()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_plan_kind text;
begin
  if tg_op = 'DELETE' then
    select mp.plan_kind into v_plan_kind
    from public.membership_plans mp
    where mp.id = old.plan_id;

    insert into private.membership_access_audit (
      operation, access_role, membership_id, person_id, selling_gym_id, plan_id,
      plan_kind, effective_start_date, end_date, canceled_at, is_frozen, source_row
    ) values (
      'owner_deleted', 'owner', old.id, old.user_id, old.sold_at_gym_id, old.plan_id,
      v_plan_kind, coalesce(old.effective_start_date, old.start_date)::date,
      old.end_date::date, old.canceled_at, coalesce(old.is_frozen, false),
      pg_catalog.jsonb_build_object(
        'id', old.id, 'user_id', old.user_id, 'plan_id', old.plan_id,
        'sold_at_gym_id', old.sold_at_gym_id, 'start_date', old.start_date,
        'effective_start_date', old.effective_start_date, 'end_date', old.end_date,
        'canceled_at', old.canceled_at, 'is_frozen', old.is_frozen
      )
    );
  else
    select mp.plan_kind into v_plan_kind
    from public.membership_plans mp
    where mp.id = new.plan_id;

    insert into private.membership_access_audit (
      operation, access_role, membership_id, person_id, selling_gym_id, plan_id,
      plan_kind, effective_start_date, end_date, canceled_at, is_frozen, source_row
    ) values (
      case when tg_op = 'INSERT' then 'owner_created' else 'owner_changed' end,
      'owner', new.id, new.user_id, new.sold_at_gym_id, new.plan_id,
      v_plan_kind, coalesce(new.effective_start_date, new.start_date)::date,
      new.end_date::date, new.canceled_at, coalesce(new.is_frozen, false),
      pg_catalog.jsonb_build_object(
        'id', new.id, 'user_id', new.user_id, 'plan_id', new.plan_id,
        'sold_at_gym_id', new.sold_at_gym_id, 'start_date', new.start_date,
        'effective_start_date', new.effective_start_date, 'end_date', new.end_date,
        'canceled_at', new.canceled_at, 'is_frozen', new.is_frozen
      )
    );
  end if;

  return null;
end;
$$;

create or replace function private.audit_membership_family_access()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_membership_id uuid;
  v_person_id uuid;
  v_link_created_at timestamptz;
  v_operation text;
begin
  if tg_op = 'DELETE' then
    v_membership_id := old.membership_id;
    v_person_id := old.user_id;
    v_link_created_at := old.created_at;
    v_operation := 'family_removed';
  else
    v_membership_id := new.membership_id;
    v_person_id := new.user_id;
    v_link_created_at := new.created_at;
    v_operation := case when tg_op = 'INSERT' then 'family_joined' else 'family_changed' end;
  end if;

  insert into private.membership_access_audit (
    operation, access_role, membership_id, person_id, selling_gym_id, plan_id,
    plan_kind, effective_start_date, end_date, canceled_at, is_frozen,
    family_link_created_at, source_row
  )
  select
    v_operation,
    'family',
    v_membership_id,
    v_person_id,
    m.sold_at_gym_id,
    m.plan_id,
    mp.plan_kind,
    coalesce(m.effective_start_date, m.start_date)::date,
    m.end_date::date,
    m.canceled_at,
    coalesce(m.is_frozen, false),
    v_link_created_at,
    pg_catalog.jsonb_build_object(
      'membership_id', v_membership_id, 'user_id', v_person_id,
      'created_at', v_link_created_at
    )
  from public.memberships m
  right join (
    select v_membership_id as membership_id,
           v_person_id as person_id,
           v_link_created_at as link_created_at,
           v_operation as operation
  ) input on m.id = input.membership_id
  left join public.membership_plans mp on mp.id = m.plan_id
  ;

  return null;
end;
$$;

drop trigger if exists membership_access_audit_owner on public.memberships;
create trigger membership_access_audit_owner
after insert or update or delete on public.memberships
for each row execute function private.audit_membership_owner_access();

drop trigger if exists membership_access_audit_family on public.family_memberships;
create trigger membership_access_audit_family
after insert or update or delete on public.family_memberships
for each row execute function private.audit_membership_family_access();

-- Seed an auditable baseline for every relation that exists at deployment.
insert into private.membership_access_audit (
  operation, access_role, membership_id, person_id, selling_gym_id, plan_id,
  plan_kind, effective_start_date, end_date, canceled_at, is_frozen, source_row
)
select
  'owner_baseline', 'owner', m.id, m.user_id, m.sold_at_gym_id, m.plan_id,
  mp.plan_kind, coalesce(m.effective_start_date, m.start_date)::date,
  m.end_date::date, m.canceled_at, coalesce(m.is_frozen, false),
  pg_catalog.jsonb_build_object(
    'id', m.id, 'user_id', m.user_id, 'plan_id', m.plan_id,
    'sold_at_gym_id', m.sold_at_gym_id, 'start_date', m.start_date,
    'effective_start_date', m.effective_start_date, 'end_date', m.end_date,
    'canceled_at', m.canceled_at, 'is_frozen', m.is_frozen
  )
from public.memberships m
left join public.membership_plans mp on mp.id = m.plan_id;

insert into private.membership_access_audit (
  operation, access_role, membership_id, person_id, selling_gym_id, plan_id,
  plan_kind, effective_start_date, end_date, canceled_at, is_frozen,
  family_link_created_at, source_row
)
select
  'family_baseline', 'family', fm.membership_id, fm.user_id,
  m.sold_at_gym_id, m.plan_id, mp.plan_kind,
  coalesce(m.effective_start_date, m.start_date)::date, m.end_date::date,
  m.canceled_at, coalesce(m.is_frozen, false), fm.created_at,
  pg_catalog.jsonb_build_object(
    'membership_id', fm.membership_id, 'user_id', fm.user_id,
    'created_at', fm.created_at
  )
from public.family_memberships fm
join public.memberships m on m.id = fm.membership_id
left join public.membership_plans mp on mp.id = m.plan_id;

-- Reconstruct the trailing twelve calendar months. The current open day is not
-- backfilled: its first post-close cron run becomes the first exact snapshot.
do $$
declare
  v_snapshot_date date;
  v_start_date date := ((now() at time zone 'Europe/Bucharest')::date - interval '12 months')::date;
  v_end_date date := (now() at time zone 'Europe/Bucharest')::date - 1;
begin
  for v_snapshot_date in
    select generated_day::date
    from pg_catalog.generate_series(v_start_date, v_end_date, interval '1 day') generated_day
  loop
    perform private.refresh_membership_access_daily_snapshot(v_snapshot_date, true);
  end loop;
end;
$$;

-- 22:15 UTC is after midnight Europe/Bucharest in winter and summer (00:15 or
-- 01:15 local), so this stays DST-safe without relying on the server cron timezone.
do $$
declare
  v_job_id bigint;
begin
  for v_job_id in
    select j.jobid
    from cron.job j
    where j.jobname = 'membership-access-daily-snapshot'
  loop
    perform cron.unschedule(v_job_id);
  end loop;

  perform cron.schedule(
    'membership-access-daily-snapshot',
    '15 22 * * *',
    $cron$select private.capture_closed_bucharest_membership_access_snapshot();$cron$
  );
end;
$$;

create or replace function public.get_admin_membership_access_trend(
  p_range text,
  p_gym_id uuid default null
)
returns table(
  period_start date,
  period_end date,
  active_people integer,
  new_activations integer,
  is_estimated boolean,
  computed_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_range text := lower(coalesce(p_range, ''));
  v_today date := (now() at time zone 'Europe/Bucharest')::date;
  v_start date;
  v_period_start date;
  v_period_end date;
  v_active_people integer;
  v_new_activations integer;
  v_active_is_estimated boolean;
  v_activations_are_estimated boolean;
  v_active_computed_at timestamptz;
  v_activations_computed_at timestamptz;
begin
  if not public.is_admin() then
    raise exception 'Admin access required' using errcode = '42501';
  end if;

  if v_range not in ('7d', '30d', '12w', '12m') then
    raise exception 'Unsupported membership trend range: %', p_range using errcode = '22023';
  end if;

  if v_range in ('7d', '30d') then
    v_start := v_today - case when v_range = '7d' then 6 else 29 end;

    for v_period_start in
      select generated_day::date
      from pg_catalog.generate_series(v_start, v_today, interval '1 day') generated_day
    loop
      v_period_end := v_period_start;

      select m.active_people, m.is_estimated, m.computed_at
      into v_active_people, v_active_is_estimated, v_active_computed_at
      from private.membership_access_metric_at(v_period_end, p_gym_id) m;

      select m.new_activations, m.is_estimated, m.computed_at
      into v_new_activations, v_activations_are_estimated, v_activations_computed_at
      from private.membership_access_metric_at(v_period_start, p_gym_id) m;

      period_start := v_period_start;
      period_end := v_period_end;
      active_people := v_active_people;
      new_activations := v_new_activations;
      is_estimated := v_active_is_estimated or v_activations_are_estimated;
      computed_at := greatest(v_active_computed_at, v_activations_computed_at);
      return next;
    end loop;
  elsif v_range = '12w' then
    v_start := v_today - (extract(isodow from v_today)::integer - 1) - 77;

    for v_period_start in
      select generated_day::date
      from pg_catalog.generate_series(v_start, v_start + 77, interval '7 day') generated_day
    loop
      v_period_end := least(v_period_start + 6, v_today);

      select m.active_people, m.is_estimated, m.computed_at
      into v_active_people, v_active_is_estimated, v_active_computed_at
      from private.membership_access_metric_at(v_period_end, p_gym_id) m;

      select
        coalesce(sum(m.new_activations), 0)::integer,
        coalesce(bool_or(m.is_estimated), true),
        max(m.computed_at)
      into v_new_activations, v_activations_are_estimated, v_activations_computed_at
      from pg_catalog.generate_series(v_period_start, v_period_end, interval '1 day') d
      cross join lateral private.membership_access_metric_at(d::date, p_gym_id) m;

      period_start := v_period_start;
      period_end := v_period_end;
      active_people := v_active_people;
      new_activations := v_new_activations;
      is_estimated := v_active_is_estimated or v_activations_are_estimated;
      computed_at := greatest(v_active_computed_at, v_activations_computed_at);
      return next;
    end loop;
  else
    v_start := (date_trunc('month', v_today)::date - interval '11 months')::date;

    for v_period_start in
      select generated_month::date
      from pg_catalog.generate_series(v_start, v_start + interval '11 months', interval '1 month') generated_month
    loop
      v_period_end := least(
        (v_period_start + interval '1 month - 1 day')::date,
        v_today
      );

      select m.active_people, m.is_estimated, m.computed_at
      into v_active_people, v_active_is_estimated, v_active_computed_at
      from private.membership_access_metric_at(v_period_end, p_gym_id) m;

      select
        coalesce(sum(m.new_activations), 0)::integer,
        coalesce(bool_or(m.is_estimated), true),
        max(m.computed_at)
      into v_new_activations, v_activations_are_estimated, v_activations_computed_at
      from pg_catalog.generate_series(v_period_start, v_period_end, interval '1 day') d
      cross join lateral private.membership_access_metric_at(d::date, p_gym_id) m;

      period_start := v_period_start;
      period_end := v_period_end;
      active_people := v_active_people;
      new_activations := v_new_activations;
      is_estimated := v_active_is_estimated or v_activations_are_estimated;
      computed_at := greatest(v_active_computed_at, v_activations_computed_at);
      return next;
    end loop;
  end if;
end;
$$;

revoke all on function public.get_admin_membership_access_trend(text, uuid) from public;
revoke all on function public.get_admin_membership_access_trend(text, uuid) from anon;
revoke all on function public.get_admin_membership_access_trend(text, uuid) from authenticated;
grant execute on function public.get_admin_membership_access_trend(text, uuid) to authenticated;

comment on function public.get_admin_membership_access_trend(text, uuid) is
  'Admin-only package membership access trend. Romanian reporting days use Europe/Bucharest; historical reconstructed rows remain estimated.';
