-- Membership writes are deliberately centralized here. The mobile client uses
-- these RPCs instead of composing independent membership and ledger requests.

alter table public.revenue_ledger
  add column if not exists idempotency_key text;

create unique index if not exists revenue_ledger_idempotency_key_unique
  on public.revenue_ledger (idempotency_key)
  where idempotency_key is not null;

create or replace function public.admin_save_membership(
  p_membership_id uuid,
  p_user_id uuid,
  p_plan_id uuid,
  p_gym_id uuid,
  p_start_date date,
  p_end_date date,
  p_is_active boolean,
  p_membership_type text,
  p_price_paid_cents integer,
  p_payment_method text
)
returns table (
  membership_id uuid,
  revenue_ledger_id uuid,
  was_created boolean
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_existing_user_id uuid;
  v_ledger_id uuid;
  v_active_base_charge_count integer;
  v_deleted_base_charge_count integer;
  v_was_created boolean := false;
begin
  if not public.is_admin() then
    raise exception 'Admin access required' using errcode = '42501';
  end if;

  if p_membership_id is null
    or p_user_id is null
    or p_plan_id is null
    or p_gym_id is null
    or p_start_date is null
    or p_end_date is null then
    raise exception 'Date obligatorii lipsă pentru abonament' using errcode = '22004';
  end if;

  if p_end_date < p_start_date then
    raise exception 'Data de sfârșit trebuie să fie după data de început' using errcode = '22007';
  end if;

  if coalesce(p_price_paid_cents, -1) < 0 then
    raise exception 'Prețul abonamentului nu poate fi negativ' using errcode = '22003';
  end if;

  if coalesce(lower(trim(p_payment_method)), '') not in ('cash', 'card') then
    raise exception 'Metoda de plată nu este acceptată' using errcode = '22023';
  end if;

  if coalesce(trim(p_membership_type), '') = '' then
    raise exception 'Tipul abonamentului este obligatoriu' using errcode = '22023';
  end if;

  if not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'Membrul selectat nu există' using errcode = '23503';
  end if;
  if not exists (select 1 from public.membership_plans where id = p_plan_id) then
    raise exception 'Planul selectat nu există' using errcode = '23503';
  end if;
  if not exists (select 1 from public.gyms where id = p_gym_id) then
    raise exception 'Sala selectată nu există' using errcode = '23503';
  end if;

  select m.user_id
  into v_existing_user_id
  from public.memberships m
  where m.id = p_membership_id
  for update;

  select count(*)::integer,
         count(*) filter (where coalesce(r.is_deleted, false))::integer
  into v_active_base_charge_count, v_deleted_base_charge_count
  from public.revenue_ledger r
  where r.membership_id = p_membership_id
    and r.entry_kind = 'charge'
    and r.source in ('membership', 'membership_sale');

  v_active_base_charge_count := v_active_base_charge_count - v_deleted_base_charge_count;

  if v_active_base_charge_count > 1
    or (v_active_base_charge_count = 0 and v_deleted_base_charge_count > 0) then
    raise exception 'KRATOS_LEDGER_RECONCILIATION_REQUIRED'
      using errcode = 'P0001',
            detail = 'Abonamentul are înregistrări de venit ambigue și trebuie reconciliat înainte de editare.';
  end if;

  if v_existing_user_id is null then
    insert into public.memberships (
      id, user_id, plan_id, sold_at_gym_id, start_date, end_date,
      is_active, membership_type, price_paid_cents, payment_method
    ) values (
      p_membership_id, p_user_id, p_plan_id, p_gym_id, p_start_date, p_end_date,
      p_is_active, trim(p_membership_type), p_price_paid_cents, lower(trim(p_payment_method))
    );
    v_was_created := true;
  else
    update public.memberships
    set user_id = p_user_id,
        plan_id = p_plan_id,
        sold_at_gym_id = p_gym_id,
        start_date = p_start_date,
        end_date = p_end_date,
        is_active = p_is_active,
        membership_type = trim(p_membership_type),
        price_paid_cents = p_price_paid_cents,
        payment_method = lower(trim(p_payment_method))
    where id = p_membership_id;
  end if;

  if v_active_base_charge_count = 1 then
    select r.id
    into v_ledger_id
    from public.revenue_ledger r
    where r.membership_id = p_membership_id
      and r.entry_kind = 'charge'
      and r.source in ('membership', 'membership_sale')
      and coalesce(r.is_deleted, false) = false
    for update;

    update public.revenue_ledger
    set plan_id = p_plan_id,
        gym_id = p_gym_id,
        amount_cents = p_price_paid_cents,
        payment_method = lower(trim(p_payment_method)),
        source = 'membership',
        entry_kind = 'charge',
        currency = 'RON',
        idempotency_key = 'membership-sale:' || p_membership_id::text
    where id = v_ledger_id;
  else
    insert into public.revenue_ledger (
      membership_id, plan_id, gym_id, amount_cents, currency, source,
      entry_kind, payment_method, recorded_by, idempotency_key
    ) values (
      p_membership_id, p_plan_id, p_gym_id, p_price_paid_cents, 'RON', 'membership',
      'charge', lower(trim(p_payment_method)), auth.uid(),
      'membership-sale:' || p_membership_id::text
    )
    returning id into v_ledger_id;
  end if;

  return query select p_membership_id, v_ledger_id, v_was_created;
end;
$$;

revoke all on function public.admin_save_membership(
  uuid, uuid, uuid, uuid, date, date, boolean, text, integer, text
) from public;
revoke all on function public.admin_save_membership(
  uuid, uuid, uuid, uuid, date, date, boolean, text, integer, text
) from anon;
grant execute on function public.admin_save_membership(
  uuid, uuid, uuid, uuid, date, date, boolean, text, integer, text
) to authenticated;

create or replace function public.admin_delete_membership(p_membership_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_revenue_count integer := 0;
  v_check_in_count integer := 0;
  v_family_count integer := 0;
  v_event_count integer := 0;
  v_membership_count integer := 0;
begin
  if not public.is_admin() then
    raise exception 'Admin access required' using errcode = '42501';
  end if;

  if not exists (select 1 from public.memberships where id = p_membership_id) then
    raise exception 'Abonamentul nu a fost găsit' using errcode = 'P0002';
  end if;

  delete from public.revenue_ledger where membership_id = p_membership_id;
  get diagnostics v_revenue_count = row_count;

  delete from public.check_ins where membership_id = p_membership_id;
  get diagnostics v_check_in_count = row_count;

  delete from public.family_memberships where membership_id = p_membership_id;
  get diagnostics v_family_count = row_count;

  delete from public.membership_events where membership_id = p_membership_id;
  get diagnostics v_event_count = row_count;

  -- The existing private audit trigger observes this delete before the function
  -- returns, retaining the owner-delete evidence without exposing it publicly.
  delete from public.memberships where id = p_membership_id;
  get diagnostics v_membership_count = row_count;

  return jsonb_build_object(
    'revenue_ledger', v_revenue_count,
    'check_ins', v_check_in_count,
    'family_memberships', v_family_count,
    'membership_events', v_event_count,
    'memberships', v_membership_count
  );
end;
$$;

revoke all on function public.admin_delete_membership(uuid) from public;
revoke all on function public.admin_delete_membership(uuid) from anon;
grant execute on function public.admin_delete_membership(uuid) to authenticated;

-- Rebuild the as-of access functions so all timestamp-to-calendar conversions
-- explicitly use Bucharest civil time and inactive memberships never grant access.
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
      coalesce(
        (
          select me.new_start_date::date
          from public.membership_events me
          where me.membership_id = m.id
            and (me.at at time zone 'Europe/Bucharest')::date <= p_snapshot_date
            and me.new_start_date is not null
          order by me.at desc, me.id desc limit 1
        ),
        (
          select me.old_start_date::date
          from public.membership_events me
          where me.membership_id = m.id
            and (me.at at time zone 'Europe/Bucharest')::date > p_snapshot_date
            and me.old_start_date is not null
          order by me.at asc, me.id asc limit 1
        ),
        coalesce(m.effective_start_date, m.start_date)::date
      ) as effective_start_date,
      coalesce(
        (
          select me.new_end_date::date
          from public.membership_events me
          where me.membership_id = m.id
            and (me.at at time zone 'Europe/Bucharest')::date <= p_snapshot_date
            and me.new_end_date is not null
          order by me.at desc, me.id desc limit 1
        ),
        (
          select me.old_end_date::date
          from public.membership_events me
          where me.membership_id = m.id
            and (me.at at time zone 'Europe/Bucharest')::date > p_snapshot_date
            and me.old_end_date is not null
          order by me.at asc, me.id asc limit 1
        ),
        m.end_date::date
      ) as effective_end_date,
      coalesce(
        (
          select me.event_type = 'paused'
          from public.membership_events me
          where me.membership_id = m.id
            and me.event_type in ('paused', 'resumed')
            and (me.at at time zone 'Europe/Bucharest')::date <= p_snapshot_date
          order by me.at desc, me.id desc limit 1
        ),
        coalesce(m.is_frozen, false)
          and (m.frozen_at is null or (m.frozen_at at time zone 'Europe/Bucharest')::date <= p_snapshot_date),
        false
      ) as was_frozen,
      exists (
        select 1 from public.membership_events me
        where me.membership_id = m.id
          and me.event_type = 'canceled'
          and (me.at at time zone 'Europe/Bucharest')::date <= p_snapshot_date
      ) or (m.canceled_at is not null
        and (m.canceled_at at time zone 'Europe/Bucharest')::date <= p_snapshot_date) as was_canceled
    from public.memberships m
    join public.membership_plans mp on mp.id = m.plan_id
    where mp.plan_kind = 'package'
      and coalesce(m.is_active, false)
      and lower(coalesce(m.membership_type, '')) not in ('day_pass', 'day-pass', 'daily')
      and (p_gym_id is null or m.sold_at_gym_id = p_gym_id)
  ), active_memberships as (
    select ms.* from membership_state ms
    where ms.effective_start_date <= p_snapshot_date
      and ms.effective_end_date >= p_snapshot_date
      and not ms.was_canceled and not ms.was_frozen
  ), access_people as (
    select am.user_id as person_id from active_memberships am
    union
    select fm.user_id as person_id
    from active_memberships am
    join public.family_memberships fm on fm.membership_id = am.id
    where (fm.created_at at time zone 'Europe/Bucharest')::date <= p_snapshot_date
  )
  select distinct ap.person_id from access_people ap;
$$;

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
    select m.id, m.user_id,
      coalesce(
        (select me.new_start_date::date from public.membership_events me
          where me.membership_id = m.id
            and (me.at at time zone 'Europe/Bucharest')::date <= p_snapshot_date
            and me.new_start_date is not null
          order by me.at desc, me.id desc limit 1),
        (select me.old_start_date::date from public.membership_events me
          where me.membership_id = m.id
            and (me.at at time zone 'Europe/Bucharest')::date > p_snapshot_date
            and me.old_start_date is not null
          order by me.at asc, me.id asc limit 1),
        coalesce(m.effective_start_date, m.start_date)::date
      ) as effective_start_date
    from public.memberships m
    join public.membership_plans mp on mp.id = m.plan_id
    where mp.plan_kind = 'package'
      and coalesce(m.is_active, false)
      and lower(coalesce(m.membership_type, '')) not in ('day_pass', 'day-pass', 'daily')
      and (p_gym_id is null or m.sold_at_gym_id = p_gym_id)
  )
  select pm.user_id as person_id from package_memberships pm
  where pm.effective_start_date = p_snapshot_date
  union
  select fm.user_id as person_id
  from package_memberships pm
  join public.family_memberships fm on fm.membership_id = pm.id
  where (fm.created_at at time zone 'Europe/Bucharest')::date = p_snapshot_date;
$$;
