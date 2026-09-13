-- Read-only psql report. It intentionally makes no corrections.
-- Usage: psql "$SUPABASE_DB_URL" -f supabase_reports/membership_ledger_reconciliation.sql
-- The output contains identifiers and operational fields only; no member PII.

\pset pager off
\pset format aligned
\echo 'Membership / ledger reconciliation detail'

with base as (
  select
    m.id as membership_id,
    m.plan_id as membership_plan_id,
    m.sold_at_gym_id as membership_gym_id,
    m.price_paid_cents as membership_amount_cents,
    m.payment_method as membership_payment_method,
    r.id as ledger_id,
    r.source,
    r.entry_kind,
    r.is_deleted,
    r.plan_id as ledger_plan_id,
    r.gym_id as ledger_gym_id,
    r.amount_cents as ledger_amount_cents,
    r.payment_method as ledger_payment_method,
    r.idempotency_key,
    r.paid_at,
    r.created_at
  from public.memberships m
  left join public.revenue_ledger r on r.membership_id = m.id
    and r.entry_kind = 'charge'
    and r.source in ('membership', 'membership_sale')
), grouped as (
  select
    membership_id, membership_plan_id, membership_gym_id, membership_amount_cents,
    membership_payment_method,
    count(ledger_id) filter (where coalesce(is_deleted, false) = false) as active_count,
    count(ledger_id) filter (where coalesce(is_deleted, false)) as deleted_count,
    min(ledger_id) filter (where coalesce(is_deleted, false) = false) as proposed_ledger_id,
    jsonb_agg(jsonb_build_object(
      'ledger_id', ledger_id, 'source', source, 'entry_kind', entry_kind,
      'is_deleted', is_deleted, 'amount_cents', ledger_amount_cents,
      'plan_id', ledger_plan_id, 'gym_id', ledger_gym_id,
      'payment_method', ledger_payment_method, 'idempotency_key', idempotency_key,
      'paid_at', paid_at, 'created_at', created_at
    ) order by paid_at nulls last, created_at nulls last) filter (where ledger_id is not null) as ledger_rows,
    bool_or(
      coalesce(is_deleted, false) = false and (
        source is distinct from 'membership' or entry_kind is distinct from 'charge'
        or ledger_plan_id is distinct from membership_plan_id
        or ledger_gym_id is distinct from membership_gym_id
        or ledger_amount_cents is distinct from membership_amount_cents
        or ledger_payment_method is distinct from membership_payment_method
        or idempotency_key is distinct from ('membership-sale:' || membership_id::text)
      )
    ) as has_field_drift
  from base
  group by membership_id, membership_plan_id, membership_gym_id,
    membership_amount_cents, membership_payment_method
), report as (
  select *, case
    when active_count = 0 and deleted_count = 0 then 'missing_base_charge'
    when active_count = 0 and deleted_count > 0 then 'deleted_only_base_charge'
    when active_count > 1 then 'duplicate_active_base_charges'
    when has_field_drift then 'single_row_field_drift'
    else 'safe_or_already_canonical'
  end as category
  from grouped
)
select category, membership_id, proposed_ledger_id, active_count, deleted_count,
  membership_plan_id, membership_gym_id, membership_amount_cents,
  membership_payment_method, ledger_rows,
  jsonb_build_object(
    'source', 'membership', 'entry_kind', 'charge', 'currency', 'RON',
    'idempotency_key', 'membership-sale:' || membership_id::text,
    'plan_id', membership_plan_id, 'gym_id', membership_gym_id,
    'amount_cents', membership_amount_cents, 'payment_method', membership_payment_method
  ) as proposed_canonical_candidate
from report
order by category, membership_id;

\echo 'Summary JSON'
with base as (
  select m.id membership_id, r.id ledger_id, r.is_deleted, r.source, r.entry_kind,
    r.plan_id, r.gym_id, r.amount_cents, r.payment_method, r.idempotency_key,
    m.plan_id membership_plan_id, m.sold_at_gym_id membership_gym_id,
    m.price_paid_cents membership_amount_cents, m.payment_method membership_payment_method
  from public.memberships m left join public.revenue_ledger r on r.membership_id = m.id
    and r.entry_kind = 'charge' and r.source in ('membership', 'membership_sale')
), grouped as (
  select membership_id,
    count(ledger_id) filter (where coalesce(is_deleted, false) = false) active_count,
    count(ledger_id) filter (where coalesce(is_deleted, false)) deleted_count,
    bool_or(coalesce(is_deleted, false) = false and (
      source is distinct from 'membership' or plan_id is distinct from membership_plan_id
      or gym_id is distinct from membership_gym_id or amount_cents is distinct from membership_amount_cents
      or payment_method is distinct from membership_payment_method
      or idempotency_key is distinct from ('membership-sale:' || membership_id::text)
    )) has_drift
  from base group by membership_id
), report as (
  select case when active_count = 0 and deleted_count = 0 then 'missing_base_charge'
    when active_count = 0 and deleted_count > 0 then 'deleted_only_base_charge'
    when active_count > 1 then 'duplicate_active_base_charges'
    when has_drift then 'single_row_field_drift'
    else 'safe_or_already_canonical' end category
  from grouped
)
select jsonb_object_agg(category, count) as reconciliation_summary
from (select category, count(*)::integer from report group by category) summary;

\echo 'Review-only correction SQL (never execute without separate approval)'
with base as (
  select m.id membership_id, min(r.id) filter (where coalesce(r.is_deleted, false) = false) ledger_id,
    m.plan_id, m.sold_at_gym_id, m.price_paid_cents, m.payment_method,
    count(r.id) filter (where coalesce(r.is_deleted, false) = false) active_count,
    count(r.id) filter (where coalesce(r.is_deleted, false)) deleted_count,
    bool_or(coalesce(r.is_deleted, false) = false and (
      r.source is distinct from 'membership' or r.plan_id is distinct from m.plan_id
      or r.gym_id is distinct from m.sold_at_gym_id or r.amount_cents is distinct from m.price_paid_cents
      or r.payment_method is distinct from m.payment_method
      or r.idempotency_key is distinct from ('membership-sale:' || m.id::text)
    )) has_drift
  from public.memberships m left join public.revenue_ledger r on r.membership_id = m.id
    and r.entry_kind = 'charge' and r.source in ('membership', 'membership_sale')
  group by m.id, m.plan_id, m.sold_at_gym_id, m.price_paid_cents, m.payment_method
)
select case
  when active_count = 1 and has_drift then format(
    'UPDATE public.revenue_ledger SET plan_id = %L::uuid, gym_id = %L::uuid, amount_cents = %s, payment_method = %L, source = ''membership'', entry_kind = ''charge'', currency = ''RON'', idempotency_key = %L WHERE id = %L::uuid;',
    plan_id, sold_at_gym_id, price_paid_cents, lower(payment_method),
    'membership-sale:' || membership_id::text, ledger_id)
  when active_count = 0 and deleted_count = 0 then format(
    '-- REVIEW REQUIRED: INSERT canonical base charge for membership %s (paid_at and recorded_by require an approved source).', membership_id)
  when active_count > 1 or deleted_count > 0 then format(
    '-- MANUAL RECONCILIATION REQUIRED for membership %s.', membership_id)
end as review_only_sql
from base
where active_count <> 1 or has_drift
order by membership_id;
