-- Admin product analytics RPCs for kratos-gym-mobile
-- Purpose: allow admin app to read cross-gym product/stock/sales data via RPCs.

create index if not exists product_stock_movements_gym_product_created_idx
  on public.product_stock_movements(gym_id, product_id, created_at, id);

create index if not exists product_sales_sold_at_idx
  on public.product_sales(sold_at desc);

create index if not exists product_sales_gym_sold_by_idx
  on public.product_sales(gym_id, sold_by, sold_at desc);

create index if not exists product_sale_items_gym_product_idx
  on public.product_sale_items(gym_id, product_id);

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
  sales_revenue_cents bigint
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
    select s.id, s.total_cents
    from public.product_sales s
    where (p_gym_id is null or s.gym_id = p_gym_id)
      and (p_date_start is null or s.sold_at >= p_date_start)
      and (p_date_end is null or s.sold_at <= p_date_end)
  ),
  sales_metrics as (
    select
      count(*)::bigint as sales_count,
      coalesce(sum(total_cents), 0)::bigint as sales_revenue_cents
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
    sm.sales_revenue_cents
  from product_metrics pm
  cross join sales_metrics sm
  cross join item_metrics im;
end;
$$;

create or replace function public.get_admin_products_overview(
  p_gym_id uuid default null,
  p_search_query text default null,
  p_include_inactive boolean default true,
  p_low_stock_threshold integer default null,
  p_limit integer default 200,
  p_offset integer default 0
)
returns table(
  product_id uuid,
  gym_id uuid,
  gym_name text,
  product_name text,
  price_cents integer,
  currency text,
  is_active boolean,
  barcode text,
  sku text,
  stock integer,
  stock_value_cents bigint,
  total_count bigint
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
      p.name as product_name,
      p.price_cents,
      p.currency,
      p.is_active,
      p.barcode,
      p.sku,
      coalesce(sum(m.delta_quantity), 0)::integer as stock
    from public.products p
    left join public.product_stock_movements m
      on m.product_id = p.id
      and m.gym_id = p.gym_id
    where (p_gym_id is null or p.gym_id = p_gym_id)
    group by
      p.id,
      p.gym_id,
      p.name,
      p.price_cents,
      p.currency,
      p.is_active,
      p.barcode,
      p.sku
  ),
  filtered as (
    select
      ps.product_id,
      ps.gym_id,
      g.name as gym_name,
      ps.product_name,
      ps.price_cents,
      ps.currency,
      ps.is_active,
      ps.barcode,
      ps.sku,
      ps.stock,
      (ps.stock::bigint * ps.price_cents::bigint) as stock_value_cents
    from product_stock ps
    join public.gyms g on g.id = ps.gym_id
    where (p_include_inactive or ps.is_active)
      and (
        p_low_stock_threshold is null
        or ps.stock <= p_low_stock_threshold
      )
      and (
        p_search_query is null
        or btrim(p_search_query) = ''
        or lower(ps.product_name) like '%' || lower(btrim(p_search_query)) || '%'
        or lower(coalesce(ps.barcode, '')) like '%' || lower(btrim(p_search_query)) || '%'
        or lower(coalesce(ps.sku, '')) like '%' || lower(btrim(p_search_query)) || '%'
      )
  )
  select
    f.product_id,
    f.gym_id,
    f.gym_name,
    f.product_name,
    f.price_cents,
    f.currency,
    f.is_active,
    f.barcode,
    f.sku,
    f.stock,
    f.stock_value_cents,
    count(*) over()::bigint as total_count
  from filtered f
  order by f.gym_name asc, f.product_name asc
  limit greatest(coalesce(p_limit, 200), 1)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

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

create or replace function public.get_admin_employee_product_sales(
  p_gym_id uuid default null,
  p_employee_id uuid default null,
  p_date_start timestamptz default null,
  p_date_end timestamptz default null,
  p_limit integer default 100
)
returns table(
  employee_id uuid,
  employee_name text,
  gym_id uuid,
  gym_name text,
  sales_count bigint,
  items_sold bigint,
  revenue_cents bigint,
  cash_revenue_cents bigint,
  card_revenue_cents bigint,
  avg_sale_value_cents numeric
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
  with sale_scope as (
    select
      s.id,
      s.gym_id,
      s.sold_by,
      s.total_cents,
      s.payment_method
    from public.product_sales s
    where (p_gym_id is null or s.gym_id = p_gym_id)
      and (p_employee_id is null or s.sold_by = p_employee_id)
      and (p_date_start is null or s.sold_at >= p_date_start)
      and (p_date_end is null or s.sold_at <= p_date_end)
  ),
  items_per_sale as (
    select
      psi.sale_id,
      coalesce(sum(psi.quantity), 0)::bigint as items_sold
    from public.product_sale_items psi
    join sale_scope ss on ss.id = psi.sale_id
    group by psi.sale_id
  )
  select
    ss.sold_by as employee_id,
    coalesce(pr.full_name, ss.sold_by::text) as employee_name,
    ss.gym_id,
    g.name as gym_name,
    count(ss.id)::bigint as sales_count,
    coalesce(sum(ips.items_sold), 0)::bigint as items_sold,
    coalesce(sum(ss.total_cents), 0)::bigint as revenue_cents,
    coalesce(
      sum(case when ss.payment_method = 'cash' then ss.total_cents else 0 end),
      0
    )::bigint as cash_revenue_cents,
    coalesce(
      sum(case when ss.payment_method = 'card' then ss.total_cents else 0 end),
      0
    )::bigint as card_revenue_cents,
    case
      when count(ss.id) = 0 then 0::numeric
      else round(sum(ss.total_cents)::numeric / count(ss.id)::numeric, 2)
    end as avg_sale_value_cents
  from sale_scope ss
  left join items_per_sale ips on ips.sale_id = ss.id
  left join public.profiles pr on pr.id = ss.sold_by
  left join public.gyms g on g.id = ss.gym_id
  group by ss.sold_by, pr.full_name, ss.gym_id, g.name
  order by revenue_cents desc, items_sold desc
  limit greatest(coalesce(p_limit, 100), 1);
end;
$$;

create or replace function public.get_admin_product_stock_movements(
  p_gym_id uuid default null,
  p_product_id uuid default null,
  p_employee_id uuid default null,
  p_reason text default null,
  p_date_start timestamptz default null,
  p_date_end timestamptz default null,
  p_search_query text default null,
  p_limit integer default 100,
  p_offset integer default 0
)
returns table(
  movement_id uuid,
  gym_id uuid,
  gym_name text,
  product_id uuid,
  product_name text,
  delta_quantity integer,
  reason text,
  stock_before integer,
  stock_after integer,
  created_at timestamptz,
  created_by uuid,
  created_by_name text,
  verified_against_user_id uuid,
  verified_against_user_name text,
  counted_stock integer,
  notes text,
  total_count bigint
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
  with base as (
    select
      m.id as movement_id,
      m.gym_id,
      g.name as gym_name,
      m.product_id,
      p.name as product_name,
      m.delta_quantity,
      m.reason,
      m.created_at,
      m.created_by,
      coalesce(actor.full_name, m.created_by::text) as created_by_name,
      m.verified_against_user_id,
      coalesce(against_profile.full_name, m.verified_against_user_id::text) as verified_against_user_name,
      m.counted_stock,
      m.notes
    from public.product_stock_movements m
    join public.products p
      on p.id = m.product_id
      and p.gym_id = m.gym_id
    join public.gyms g on g.id = m.gym_id
    left join public.profiles actor on actor.id = m.created_by
    left join public.profiles against_profile on against_profile.id = m.verified_against_user_id
    where (p_gym_id is null or m.gym_id = p_gym_id)
      and (p_product_id is null or m.product_id = p_product_id)
  ),
  with_running_stock as (
    select
      b.*,
      coalesce(
        sum(b.delta_quantity) over (
          partition by b.gym_id, b.product_id
          order by b.created_at asc, b.movement_id asc
          rows between unbounded preceding and 1 preceding
        ),
        0
      )::integer as stock_before,
      coalesce(
        sum(b.delta_quantity) over (
          partition by b.gym_id, b.product_id
          order by b.created_at asc, b.movement_id asc
          rows between unbounded preceding and current row
        ),
        0
      )::integer as stock_after
    from base b
  ),
  filtered as (
    select *
    from with_running_stock rs
    where (p_employee_id is null or rs.created_by = p_employee_id)
      and (
        p_reason is null
        or btrim(p_reason) = ''
        or rs.reason = p_reason
      )
      and (p_date_start is null or rs.created_at >= p_date_start)
      and (p_date_end is null or rs.created_at <= p_date_end)
      and (
        p_search_query is null
        or btrim(p_search_query) = ''
        or lower(rs.product_name) like '%' || lower(btrim(p_search_query)) || '%'
        or lower(rs.created_by_name) like '%' || lower(btrim(p_search_query)) || '%'
        or lower(coalesce(rs.verified_against_user_name, '')) like '%' || lower(btrim(p_search_query)) || '%'
        or lower(coalesce(rs.notes, '')) like '%' || lower(btrim(p_search_query)) || '%'
      )
  )
  select
    f.movement_id,
    f.gym_id,
    f.gym_name,
    f.product_id,
    f.product_name,
    f.delta_quantity,
    f.reason,
    f.stock_before,
    f.stock_after,
    f.created_at,
    f.created_by,
    f.created_by_name,
    f.verified_against_user_id,
    f.verified_against_user_name,
    f.counted_stock,
    f.notes,
    count(*) over()::bigint as total_count
  from filtered f
  order by f.created_at desc, f.movement_id desc
  limit greatest(coalesce(p_limit, 100), 1)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

create or replace function public.get_admin_product_employees(
  p_gym_id uuid default null
)
returns table(
  employee_id uuid,
  employee_name text,
  gym_id uuid,
  gym_name text
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
    e.user_id as employee_id,
    coalesce(p.full_name, e.user_id::text) as employee_name,
    e.gym_id,
    g.name as gym_name
  from public.employees e
  join public.gyms g on g.id = e.gym_id
  left join public.profiles p on p.id = e.user_id
  where e.is_active = true
    and (p_gym_id is null or e.gym_id = p_gym_id)
  order by employee_name asc;
end;
$$;

grant execute on function public.get_admin_product_dashboard_kpis(uuid, timestamptz, timestamptz, integer) to authenticated;
grant execute on function public.get_admin_products_overview(uuid, text, boolean, integer, integer, integer) to authenticated;
grant execute on function public.get_admin_top_selling_products(uuid, timestamptz, timestamptz, integer) to authenticated;
grant execute on function public.get_admin_employee_product_sales(uuid, uuid, timestamptz, timestamptz, integer) to authenticated;
grant execute on function public.get_admin_product_stock_movements(uuid, uuid, uuid, text, timestamptz, timestamptz, text, integer, integer) to authenticated;
grant execute on function public.get_admin_product_employees(uuid) to authenticated;
