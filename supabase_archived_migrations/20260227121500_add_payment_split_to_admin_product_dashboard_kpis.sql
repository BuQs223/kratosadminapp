drop function if exists public.get_admin_product_dashboard_kpis(
  uuid,
  timestamptz,
  timestamptz,
  integer
);

create or replace function public.get_admin_product_dashboard_kpis(
  p_gym_id uuid default null,
  p_date_start timestamptz default null,
  p_date_end timestamptz default null,
  p_low_stock_threshold integer default 5
)
returns table(
  total_products bigint,
  active_products bigint,
  inactive_products bigint,
  total_stock_units bigint,
  low_stock_products bigint,
  out_of_stock_products bigint,
  stock_value_cents bigint,
  sales_count bigint,
  items_sold bigint,
  sales_revenue_cents bigint,
  cash_revenue_cents bigint,
  card_revenue_cents bigint
)
language plpgsql
stable
security definer
set search_path = 'public'
as $$
begin
  if not public.is_admin() then
    raise exception 'Admin access required' using errcode = '42501';
  end if;

  return query
  with product_stock as (
    select
      p.id as product_id,
      p.gym_id,
      p.is_active,
      p.price_cents,
      coalesce(sum(m.delta_quantity), 0)::bigint as stock_units
    from public.products p
    left join public.product_stock_movements m
      on m.product_id = p.id
      and m.gym_id = p.gym_id
    where (p_gym_id is null or p.gym_id = p_gym_id)
    group by p.id, p.gym_id, p.is_active, p.price_cents
  ),
  product_metrics as (
    select
      count(*)::bigint as total_products,
      count(*) filter (where is_active)::bigint as active_products,
      count(*) filter (where not is_active)::bigint as inactive_products,
      coalesce(sum(stock_units), 0)::bigint as total_stock_units,
      count(*) filter (
        where stock_units > 0
          and stock_units <= greatest(coalesce(p_low_stock_threshold, 0), 0)
      )::bigint as low_stock_products,
      count(*) filter (where stock_units <= 0)::bigint as out_of_stock_products,
      coalesce(sum(greatest(stock_units, 0) * price_cents::bigint), 0)::bigint as stock_value_cents
    from product_stock
  ),
  sales_scope as (
    select s.id, s.total_cents, s.payment_method
    from public.product_sales s
    where (p_gym_id is null or s.gym_id = p_gym_id)
      and (p_date_start is null or s.sold_at >= p_date_start)
      and (p_date_end is null or s.sold_at <= p_date_end)
  ),
  sales_metrics as (
    select
      count(*)::bigint as sales_count,
      coalesce(sum(total_cents), 0)::bigint as sales_revenue_cents,
      coalesce(
        sum(case when payment_method = 'cash' then total_cents else 0 end),
        0
      )::bigint as cash_revenue_cents,
      coalesce(
        sum(case when payment_method = 'card' then total_cents else 0 end),
        0
      )::bigint as card_revenue_cents
    from sales_scope
  ),
  item_metrics as (
    select
      coalesce(sum(psi.quantity), 0)::bigint as items_sold
    from public.product_sale_items psi
    join sales_scope s on s.id = psi.sale_id
  )
  select
    pm.total_products,
    pm.active_products,
    pm.inactive_products,
    pm.total_stock_units,
    pm.low_stock_products,
    pm.out_of_stock_products,
    pm.stock_value_cents,
    sm.sales_count,
    im.items_sold,
    sm.sales_revenue_cents,
    sm.cash_revenue_cents,
    sm.card_revenue_cents
  from product_metrics pm
  cross join sales_metrics sm
  cross join item_metrics im;
end;
$$;

grant execute on function public.get_admin_product_dashboard_kpis(
  uuid,
  timestamptz,
  timestamptz,
  integer
) to authenticated;
