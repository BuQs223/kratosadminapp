drop function if exists public.get_admin_top_selling_products(
  uuid,
  timestamptz,
  timestamptz,
  integer
);

create or replace function public.get_admin_top_selling_products(
  p_gym_id uuid default null,
  p_date_start timestamptz default null,
  p_date_end timestamptz default null,
  p_limit integer default 20
)
returns table(
  product_id uuid,
  gym_id uuid,
  gym_name text,
  product_name text,
  quantity_sold bigint,
  total_revenue_cents bigint,
  cash_revenue_cents bigint,
  card_revenue_cents bigint,
  sales_count bigint,
  avg_unit_price_cents numeric
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
  select
    psi.product_id,
    s.gym_id,
    g.name as gym_name,
    coalesce(max(psi.product_name_snapshot), max(p.name), 'Produs necunoscut') as product_name,
    coalesce(sum(psi.quantity), 0)::bigint as quantity_sold,
    coalesce(sum(psi.line_total_cents), 0)::bigint as total_revenue_cents,
    coalesce(
      sum(case when s.payment_method = 'cash' then psi.line_total_cents else 0 end),
      0
    )::bigint as cash_revenue_cents,
    coalesce(
      sum(case when s.payment_method = 'card' then psi.line_total_cents else 0 end),
      0
    )::bigint as card_revenue_cents,
    count(distinct s.id)::bigint as sales_count,
    round(avg(psi.unit_price_cents)::numeric, 2) as avg_unit_price_cents
  from public.product_sale_items psi
  join public.product_sales s on s.id = psi.sale_id
  left join public.products p on p.id = psi.product_id
  left join public.gyms g on g.id = s.gym_id
  where (p_gym_id is null or s.gym_id = p_gym_id)
    and (p_date_start is null or s.sold_at >= p_date_start)
    and (p_date_end is null or s.sold_at <= p_date_end)
  group by psi.product_id, s.gym_id, g.name
  order by quantity_sold desc, total_revenue_cents desc
  limit greatest(coalesce(p_limit, 20), 1);
end;
$$;

grant execute on function public.get_admin_top_selling_products(
  uuid,
  timestamptz,
  timestamptz,
  integer
) to authenticated;
