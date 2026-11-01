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
