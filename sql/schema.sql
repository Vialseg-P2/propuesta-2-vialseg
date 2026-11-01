-- Vialseg Inventario: tablas separadas de la aplicación de recorridos.
-- Ejecutar en el SQL Editor de un proyecto Supabase nuevo.
create extension if not exists pgcrypto;

create table if not exists public.inventory_items (
  id uuid primary key default gen_random_uuid(),
  sku text not null unique,
  nombre text not null,
  categoria text not null default 'General',
  unidad text not null default 'u',
  stock numeric(14,2) not null default 0 check (stock >= 0),
  costo_unitario numeric(14,2) not null default 0 check (costo_unitario >= 0),
  consumo_mensual numeric(14,2) not null default 0 check (consumo_mensual >= 0),
  stock_seguridad numeric(14,2) not null default 0 check (stock_seguridad >= 0),
  plazo_dias integer not null default 0 check (plazo_dias >= 0),
  lote_reposicion numeric(14,2) not null default 1 check (lote_reposicion > 0),
  proveedor text not null default '',
  ubicacion text not null default '',
  se_repone boolean not null default true,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  item_id uuid references public.inventory_items(id) on delete set null,
  sku text not null,
  item_name text not null,
  tipo text not null check (tipo in ('ingreso', 'consumo', 'ajuste')),
  cantidad numeric(14,2) not null,
  stock_antes numeric(14,2) not null,
  stock_despues numeric(14,2) not null,
  nota text not null default '',
  referencia text not null default '',
  actor text not null default '',
  created_at timestamptz not null default now()
);
create index if not exists inventory_movements_item_date_idx on public.inventory_movements (item_id, created_at desc);
create index if not exists inventory_movements_created_at_idx on public.inventory_movements (created_at desc);

create table if not exists public.inventory_members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  rol text not null default 'deposito' check (rol in ('admin', 'deposito')),
  activo boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.inventory_members enable row level security;
alter table public.inventory_items enable row level security;
alter table public.inventory_movements enable row level security;

drop policy if exists "inventory_members_read_self" on public.inventory_members;
create policy "inventory_members_read_self"
  on public.inventory_members for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "inventory_items_authorized_all" on public.inventory_items;
create policy "inventory_items_authorized_all"
  on public.inventory_items for all to authenticated
  using (exists (select 1 from public.inventory_members m where m.user_id = auth.uid() and m.activo = true))
  with check (exists (select 1 from public.inventory_members m where m.user_id = auth.uid() and m.activo = true));

drop policy if exists "inventory_movements_authorized_read" on public.inventory_movements;
create policy "inventory_movements_authorized_read"
  on public.inventory_movements for select to authenticated
  using (exists (select 1 from public.inventory_members m where m.user_id = auth.uid() and m.activo = true));

drop policy if exists "inventory_movements_authorized_insert" on public.inventory_movements;
create policy "inventory_movements_authorized_insert"
  on public.inventory_movements for insert to authenticated
  with check (exists (select 1 from public.inventory_members m where m.user_id = auth.uid() and m.activo = true));

grant select on public.inventory_members to authenticated;
grant select, insert, update, delete on public.inventory_items to authenticated;
grant select, insert on public.inventory_movements to authenticated;

-- Actualiza el stock y registra el movimiento en una transacción atómica.
create or replace function public.registrar_movimiento(
  p_item_id uuid, p_tipo text, p_cantidad numeric,
  p_nota text default '', p_referencia text default '', p_actor text default ''
)
returns public.inventory_movements
language plpgsql security invoker set search_path = public
as $$
declare
  v_item public.inventory_items%rowtype;
  v_delta numeric(14,2);
  v_nuevo_stock numeric(14,2);
  v_mov public.inventory_movements%rowtype;
begin
  if p_cantidad < 0 then raise exception 'La cantidad debe ser cero o mayor.'; end if;
  select * into v_item from public.inventory_items where id = p_item_id and activo = true for update;
  if not found then raise exception 'No se encontró el material activo.'; end if;
  if p_tipo = 'ingreso' then
    if p_cantidad <= 0 then raise exception 'El ingreso debe ser mayor que cero.'; end if;
    v_delta := p_cantidad;
  elsif p_tipo = 'consumo' then
    if p_cantidad <= 0 then raise exception 'El consumo debe ser mayor que cero.'; end if;
    if p_cantidad > v_item.stock then raise exception 'El consumo supera el stock disponible.'; end if;
    v_delta := -p_cantidad;
  elsif p_tipo = 'ajuste' then
    v_delta := p_cantidad - v_item.stock;
  else
    raise exception 'Tipo de movimiento inválido.';
  end if;
  v_nuevo_stock := v_item.stock + v_delta;
  update public.inventory_items set stock = v_nuevo_stock, updated_at = now() where id = p_item_id;
  insert into public.inventory_movements
    (item_id, sku, item_name, tipo, cantidad, stock_antes, stock_despues, nota, referencia, actor)
  values
    (v_item.id, v_item.sku, v_item.nombre, p_tipo, v_delta, v_item.stock, v_nuevo_stock,
     coalesce(p_nota, ''), coalesce(p_referencia, ''), coalesce(p_actor, ''))
  returning * into v_mov;
  return v_mov;
end;
$$;
revoke all on function public.registrar_movimiento(uuid, text, numeric, text, text, text) from public, anon;
grant execute on function public.registrar_movimiento(uuid, text, numeric, text, text, text) to authenticated;


-- Evolución de esquema para precios de compra en ARS y USD.
-- Registra el costo de cada compra en ARS y su equivalente en USD.
-- Ejecutar una sola vez en Supabase > SQL Editor. No borra materiales ni movimientos.

alter table public.inventory_items
  add column if not exists costo_promedio_usd numeric(14,4) not null default 0,
  add column if not exists cotizacion_blue_base numeric(14,4);

alter table public.inventory_movements
  add column if not exists precio_unitario_ars numeric(14,4),
  add column if not exists precio_unitario_usd numeric(14,6),
  add column if not exists cotizacion_blue numeric(14,4),
  add column if not exists cotizacion_fecha timestamptz,
  add column if not exists cotizacion_fuente text;

drop function if exists public.registrar_movimiento(uuid, text, numeric, text, text, text);

create function public.registrar_movimiento(
  p_item_id uuid,
  p_tipo text,
  p_cantidad numeric,
  p_nota text default '',
  p_referencia text default '',
  p_actor text default '',
  p_precio_unitario_ars numeric default null,
  p_precio_unitario_usd numeric default null,
  p_cotizacion_blue numeric default null,
  p_cotizacion_fecha timestamptz default null,
  p_cotizacion_fuente text default null
)
returns public.inventory_movements
language plpgsql security invoker set search_path = public
as $$
declare
  v_item public.inventory_items%rowtype;
  v_delta numeric(14,2);
  v_nuevo_stock numeric(14,2);
  v_mov public.inventory_movements%rowtype;
  v_costo_promedio_usd numeric(14,4);
begin
  if p_cantidad < 0 then raise exception 'La cantidad debe ser cero o mayor.'; end if;
  select * into v_item from public.inventory_items where id = p_item_id and activo = true for update;
  if not found then raise exception 'No se encontró el material activo.'; end if;

  if p_tipo = 'ingreso' then
    if p_cantidad <= 0 then raise exception 'El ingreso debe ser mayor que cero.'; end if;
    if coalesce(p_precio_unitario_ars, 0) <= 0 then raise exception 'Ingresá el precio pagado por unidad en ARS.'; end if;
    if coalesce(p_cotizacion_blue, 0) <= 0 or coalesce(p_precio_unitario_usd, 0) <= 0 then
      raise exception 'No se recibió una cotización válida para convertir el precio a USD.';
    end if;
    if abs((p_precio_unitario_ars / p_cotizacion_blue) - p_precio_unitario_usd) > 0.02 then
      raise exception 'El precio en USD no coincide con el precio en ARS y la cotización informada.';
    end if;
    v_delta := p_cantidad;
  elsif p_tipo = 'consumo' then
    if p_cantidad <= 0 then raise exception 'El consumo debe ser mayor que cero.'; end if;
    if p_cantidad > v_item.stock then raise exception 'El consumo supera el stock disponible.'; end if;
    v_delta := -p_cantidad;
  elsif p_tipo = 'ajuste' then
    v_delta := p_cantidad - v_item.stock;
  else
    raise exception 'Tipo de movimiento inválido.';
  end if;

  v_nuevo_stock := v_item.stock + v_delta;
  if v_nuevo_stock < 0 then raise exception 'El ajuste no puede dejar stock negativo.'; end if;

  if p_tipo = 'ingreso' then
    v_costo_promedio_usd := case
      when v_nuevo_stock > 0 then
        ((v_item.stock * coalesce(v_item.costo_promedio_usd, 0)) + (p_cantidad * p_precio_unitario_usd)) / v_nuevo_stock
      else p_precio_unitario_usd
    end;
    update public.inventory_items
      set stock = v_nuevo_stock,
          costo_unitario = p_precio_unitario_ars,
          costo_promedio_usd = v_costo_promedio_usd,
          cotizacion_blue_base = p_cotizacion_blue,
          updated_at = now()
      where id = p_item_id;
  else
    update public.inventory_items set stock = v_nuevo_stock, updated_at = now() where id = p_item_id;
  end if;

  insert into public.inventory_movements
    (item_id, sku, item_name, tipo, cantidad, stock_antes, stock_despues, nota, referencia, actor,
     precio_unitario_ars, precio_unitario_usd, cotizacion_blue, cotizacion_fecha, cotizacion_fuente)
  values
    (v_item.id, v_item.sku, v_item.nombre, p_tipo, v_delta, v_item.stock, v_nuevo_stock,
     coalesce(p_nota, ''), coalesce(p_referencia, ''), coalesce(p_actor, ''),
     case when p_tipo = 'ingreso' then p_precio_unitario_ars end,
     case when p_tipo = 'ingreso' then p_precio_unitario_usd end,
     case when p_tipo = 'ingreso' then p_cotizacion_blue end,
     case when p_tipo = 'ingreso' then p_cotizacion_fecha end,
     case when p_tipo = 'ingreso' then coalesce(p_cotizacion_fuente, 'DolarAPI') end)
  returning * into v_mov;
  return v_mov;
end;
$$;

revoke all on function public.registrar_movimiento(uuid, text, numeric, text, text, text, numeric, numeric, numeric, timestamptz, text) from public, anon;
grant execute on function public.registrar_movimiento(uuid, text, numeric, text, text, text, numeric, numeric, numeric, timestamptz, text) to authenticated;

notify pgrst, 'reload schema';

-- Edición segura de referencia y detalle de movimientos.
create or replace function public.editar_datos_movimiento(
  p_movimiento_id uuid,
  p_nota text,
  p_referencia text
)
returns public.inventory_movements
language plpgsql
security definer
set search_path = public
as $$
declare
  v_movimiento public.inventory_movements%rowtype;
begin
  if auth.uid() is null or not exists (
    select 1
    from public.inventory_members m
    where m.user_id = auth.uid()
      and m.activo = true
  ) then
    raise exception 'No tenés permiso para editar movimientos.';
  end if;

  update public.inventory_movements
  set nota = left(coalesce(p_nota, ''), 300),
      referencia = left(coalesce(p_referencia, ''), 80)
  where id = p_movimiento_id
  returning * into v_movimiento;

  if not found then
    raise exception 'No se encontró el movimiento.';
  end if;

  return v_movimiento;
end;
$$;

revoke all on function public.editar_datos_movimiento(uuid, text, text) from public, anon;
grant execute on function public.editar_datos_movimiento(uuid, text, text) to authenticated;

notify pgrst, 'reload schema';
