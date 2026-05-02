-- Detailed per-transaction product sales for admin analytics.

create or replace function public.get_admin_employee_product_sale_transactions(
  p_gym_id uuid default null,
  p_employee_id uuid default null,
  p_date_start timestamptz default null,
  p_date_end timestamptz default null,
  p_limit integer default 200
)
returns table(
  sale_id uuid,
  sold_at timestamptz,
  payment_method text,
  total_cents integer,
  total_items bigint,
  employee_id uuid,
  employee_name text,
  gym_id uuid,
  gym_name text,
  items jsonb
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
  with scoped_sales as (
    select
      s.id,
      s.sold_at,
      s.payment_method,
      s.total_cents,
      s.sold_by,
      s.gym_id
    from public.product_sales s
    where (p_gym_id is null or s.gym_id = p_gym_id)
      and (p_employee_id is null or s.sold_by = p_employee_id)
      and (p_date_start is null or s.sold_at >= p_date_start)
      and (p_date_end is null or s.sold_at <= p_date_end)
  ),
  items_agg as (
    select
      psi.sale_id,
      coalesce(sum(psi.quantity), 0)::bigint as total_items,
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'product_id', psi.product_id,
            'product_name', coalesce(psi.product_name_snapshot, p.name, 'Produs necunoscut'),
            'quantity', psi.quantity,
            'unit_price_cents', psi.unit_price_cents,
            'line_total_cents', psi.line_total_cents
          )
          order by coalesce(psi.product_name_snapshot, p.name, '')
        ),
        '[]'::jsonb
      ) as items
    from public.product_sale_items psi
    join scoped_sales ss on ss.id = psi.sale_id
    left join public.products p on p.id = psi.product_id
    group by psi.sale_id
  )
  select
    ss.id as sale_id,
    ss.sold_at,
    ss.payment_method,
    ss.total_cents,
    ia.total_items,
    ss.sold_by as employee_id,
    coalesce(pr.full_name, ss.sold_by::text) as employee_name,
    ss.gym_id,
    g.name as gym_name,
    ia.items
  from scoped_sales ss
  join items_agg ia on ia.sale_id = ss.id
  left join public.profiles pr on pr.id = ss.sold_by
  left join public.gyms g on g.id = ss.gym_id
  order by ss.sold_at desc, ss.id desc
  limit greatest(coalesce(p_limit, 200), 1);
end;
$$;

grant execute on function public.get_admin_employee_product_sale_transactions(
  uuid,
  uuid,
  timestamptz,
  timestamptz,
  integer
) to authenticated;
