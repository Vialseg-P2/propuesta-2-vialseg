-- Agrega campos de costo a Supabase, reemplaza el historial de movimientos por los 250 registros simulados con precios y cotizaciones históricas, y actualiza stock y costo promedio.
-- IMPORTANTE: este script borra TODOS los movimientos actuales de inventory_movements y los reconstruye con los 250 registros simulados. Conserva el catálogo.
-- Los precios unitarios ARS son inventados para la simulación. La cotización blue de venta proviene del histórico MonedAPI.
begin;

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
  p_item_id uuid, p_tipo text, p_cantidad numeric,
  p_nota text default '', p_referencia text default '', p_actor text default '',
  p_precio_unitario_ars numeric default null, p_precio_unitario_usd numeric default null,
  p_cotizacion_blue numeric default null, p_cotizacion_fecha timestamptz default null,
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
  else raise exception 'Tipo de movimiento inválido.';
  end if;
  v_nuevo_stock := v_item.stock + v_delta;
  if v_nuevo_stock < 0 then raise exception 'El ajuste no puede dejar stock negativo.'; end if;
  if p_tipo = 'ingreso' then
    v_costo_promedio_usd := case when v_nuevo_stock > 0
      then ((v_item.stock * coalesce(v_item.costo_promedio_usd, 0)) + (p_cantidad * p_precio_unitario_usd)) / v_nuevo_stock
      else p_precio_unitario_usd end;
    update public.inventory_items set stock = v_nuevo_stock, costo_unitario = p_precio_unitario_ars,
      costo_promedio_usd = v_costo_promedio_usd, cotizacion_blue_base = p_cotizacion_blue, updated_at = now()
      where id = p_item_id;
  else update public.inventory_items set stock = v_nuevo_stock, updated_at = now() where id = p_item_id;
  end if;
  insert into public.inventory_movements
    (item_id, sku, item_name, tipo, cantidad, stock_antes, stock_despues, nota, referencia, actor,
     precio_unitario_ars, precio_unitario_usd, cotizacion_blue, cotizacion_fecha, cotizacion_fuente)
  values (v_item.id, v_item.sku, v_item.nombre, p_tipo, v_delta, v_item.stock, v_nuevo_stock,
     coalesce(p_nota,''), coalesce(p_referencia,''), coalesce(p_actor,''),
     case when p_tipo='ingreso' then p_precio_unitario_ars end,
     case when p_tipo='ingreso' then p_precio_unitario_usd end,
     case when p_tipo='ingreso' then p_cotizacion_blue end,
     case when p_tipo='ingreso' then p_cotizacion_fecha end,
     case when p_tipo='ingreso' then coalesce(p_cotizacion_fuente,'DolarAPI') end)
  returning * into v_mov;
  return v_mov;
end;
$$;
revoke all on function public.registrar_movimiento(uuid, text, numeric, text, text, text, numeric, numeric, numeric, timestamptz, text) from public, anon;
grant execute on function public.registrar_movimiento(uuid, text, numeric, text, text, text, numeric, numeric, numeric, timestamptz, text) to authenticated;

insert into public.inventory_items
  (sku, nombre, categoria, unidad, stock, costo_unitario, consumo_mensual, stock_seguridad, plazo_dias, lote_reposicion, proveedor, ubicacion, se_repone, activo)
values
  ('MAT-001', 'Fusible industrial', 'Electricidad', 'u', 80::numeric, 760::numeric, 28::numeric, 20::numeric, 4::integer, 50::numeric, 'Electroinsumos Viales', 'Deposito - Estante B', true, true),
  ('MAT-002', 'Lampara de senalizacion LED', 'Electricidad', 'u', 24::numeric, 5400::numeric, 12::numeric, 10::numeric, 8::integer, 12::numeric, 'Electroinsumos Viales', 'Deposito - Estante C', true, true),
  ('MAT-003', 'Guantes de proteccion', 'Seguridad', 'par', 45::numeric, 6200::numeric, 18::numeric, 15::numeric, 5::integer, 20::numeric, 'Seguridad Laboral', 'Deposito - Estante D', true, true),
  ('MAT-004', 'Chaleco reflectivo', 'Seguridad', 'u', 16::numeric, 14800::numeric, 9::numeric, 8::numeric, 10::integer, 10::numeric, 'Seguridad Laboral', 'Deposito - Estante E', true, true),
  ('MAT-005', 'Soporte galvanizado para cartel', 'Mecanica', 'u', 19::numeric, 9200::numeric, 10::numeric, 8::numeric, 12::integer, 10::numeric, 'Metalúrgica del Centro', 'Deposito - Estante F', true, true),
  ('MAT-006', 'Conector estanco', 'Electricidad', 'u', 7::numeric, 3200::numeric, 5::numeric, 8::numeric, 9::integer, 10::numeric, 'Electroinsumos Viales', 'Deposito - Cajon 1', true, true),
  ('MAT-007', 'Sensor de velocidad', 'Electronica', 'u', 3::numeric, 46800::numeric, 7::numeric, 5::numeric, 22::integer, 5::numeric, 'Tecnología de Tránsito', 'Deposito - Patio', true, true),
  ('MAT-008', 'Cono vial 70 cm', 'Senalizacion', 'u', 38::numeric, 18500::numeric, 14::numeric, 12::numeric, 6::integer, 12::numeric, 'Señalización y Reflectivos', 'Deposito - Estante A', true, true),
  ('MAT-009', 'Cinta reflectiva roja y blanca', 'Senalizacion', 'rollo', 11::numeric, 22400::numeric, 5::numeric, 4::numeric, 8::integer, 6::numeric, 'Señalización y Reflectivos', 'Deposito - Estante B', true, true),
  ('MAT-010', 'Cartel desvio transitorio', 'Senalizacion', 'u', 9::numeric, 38500::numeric, 3::numeric, 3::numeric, 14::integer, 4::numeric, 'Señalización y Reflectivos', 'Deposito - Estante C', true, true),
  ('MAT-011', 'Tacha reflectiva vial', 'Senalizacion', 'u', 145::numeric, 2800::numeric, 65::numeric, 50::numeric, 10::integer, 100::numeric, 'Señalización y Reflectivos', 'Deposito - Estante D', true, true),
  ('MAT-012', 'Delineador flexible', 'Senalizacion', 'u', 18::numeric, 31200::numeric, 8::numeric, 6::numeric, 12::integer, 10::numeric, 'Señalización y Reflectivos', 'Deposito - Estante E', true, true),
  ('MAT-013', 'Lamina reflectiva grado ingenieria', 'Senalizacion', 'm2', 22::numeric, 42800::numeric, 9::numeric, 8::numeric, 18::integer, 10::numeric, 'Señalización y Reflectivos', 'Deposito - Estante F', true, true),
  ('MAT-014', 'Casco de seguridad', 'Seguridad', 'u', 12::numeric, 19800::numeric, 4::numeric, 4::numeric, 7::integer, 6::numeric, 'Seguridad Laboral', 'Deposito - Cajon 1', true, true),
  ('MAT-015', 'Anteojos de seguridad', 'Seguridad', 'u', 21::numeric, 8900::numeric, 8::numeric, 6::numeric, 5::integer, 12::numeric, 'Seguridad Laboral', 'Deposito - Patio', true, true),
  ('MAT-016', 'Botines de seguridad', 'Seguridad', 'par', 8::numeric, 68400::numeric, 3::numeric, 3::numeric, 10::integer, 4::numeric, 'Seguridad Laboral', 'Deposito - Estante A', true, true),
  ('MAT-017', 'Protector auditivo', 'Seguridad', 'u', 17::numeric, 7400::numeric, 6::numeric, 5::numeric, 6::integer, 10::numeric, 'Seguridad Laboral', 'Deposito - Estante B', true, true),
  ('MAT-018', 'Tablero de control vial', 'Electronica', 'u', 4::numeric, 186000::numeric, 2::numeric, 2::numeric, 25::integer, 2::numeric, 'Tecnología de Tránsito', 'Deposito - Estante C', true, true),
  ('MAT-019', 'Modulo controlador de semaforo', 'Electronica', 'u', 2::numeric, 325000::numeric, 1::numeric, 1::numeric, 30::integer, 1::numeric, 'Tecnología de Tránsito', 'Deposito - Estante D', true, true),
  ('MAT-020', 'Fuente de alimentacion 24V', 'Electronica', 'u', 6::numeric, 36500::numeric, 3::numeric, 3::numeric, 12::integer, 4::numeric, 'Tecnología de Tránsito', 'Deposito - Estante E', true, true),
  ('MAT-021', 'Bornera de conexion', 'Electricidad', 'u', 64::numeric, 1250::numeric, 24::numeric, 20::numeric, 5::integer, 50::numeric, 'Electroinsumos Viales', 'Deposito - Estante F', true, true),
  ('MAT-022', 'Cable subterraneo multipolar', 'Electricidad', 'm', 86::numeric, 6200::numeric, 38::numeric, 25::numeric, 12::integer, 50::numeric, 'Electroinsumos Viales', 'Deposito - Cajon 1', true, true),
  ('MAT-023', 'Caja estanca para conexiones', 'Electricidad', 'u', 14::numeric, 9700::numeric, 7::numeric, 6::numeric, 8::integer, 10::numeric, 'Electroinsumos Viales', 'Deposito - Patio', true, true),
  ('MAT-024', 'Prensaestopa industrial', 'Electricidad', 'u', 32::numeric, 2300::numeric, 13::numeric, 10::numeric, 6::integer, 20::numeric, 'Electroinsumos Viales', 'Deposito - Estante A', true, true),
  ('MAT-025', 'Pintura vial amarilla', 'Senalizacion', 'balde', 13::numeric, 58200::numeric, 6::numeric, 5::numeric, 9::integer, 8::numeric, 'Señalización y Reflectivos', 'Deposito - Estante B', true, true),
  ('MAT-026', 'Pintura vial blanca', 'Senalizacion', 'balde', 10::numeric, 55400::numeric, 5::numeric, 4::numeric, 9::integer, 8::numeric, 'Señalización y Reflectivos', 'Deposito - Estante C', true, true),
  ('MAT-027', 'Microesferas de vidrio', 'Senalizacion', 'bolsa', 26::numeric, 21800::numeric, 12::numeric, 10::numeric, 11::integer, 20::numeric, 'Señalización y Reflectivos', 'Deposito - Estante D', true, true),
  ('MAT-028', 'Cartel reglamentario metalico', 'Senalizacion', 'u', 7::numeric, 74800::numeric, 3::numeric, 3::numeric, 16::integer, 4::numeric, 'Señalización y Reflectivos', 'Deposito - Estante E', true, true),
  ('MAT-029', 'Poste galvanizado', 'Senalizacion', 'u', 11::numeric, 63500::numeric, 5::numeric, 4::numeric, 18::integer, 6::numeric, 'Señalización y Reflectivos', 'Deposito - Estante F', true, true),
  ('MAT-030', 'Abrazadera para poste', 'Mecanica', 'u', 57::numeric, 1850::numeric, 22::numeric, 18::numeric, 7::integer, 40::numeric, 'Metalúrgica del Centro', 'Deposito - Cajon 1', true, true),
  ('MAT-031', 'Tornillo galvanizado', 'Mecanica', 'u', 260::numeric, 180::numeric, 95::numeric, 80::numeric, 5::integer, 200::numeric, 'Metalúrgica del Centro', 'Deposito - Patio', true, true),
  ('MAT-032', 'Tuerca autofrenante', 'Mecanica', 'u', 185::numeric, 240::numeric, 70::numeric, 60::numeric, 5::integer, 150::numeric, 'Metalúrgica del Centro', 'Deposito - Estante A', true, true),
  ('MAT-033', 'Arandela plana galvanizada', 'Mecanica', 'u', 310::numeric, 95::numeric, 120::numeric, 100::numeric, 5::integer, 250::numeric, 'Metalúrgica del Centro', 'Deposito - Estante B', true, true),
  ('MAT-034', 'Disco de corte para amoladora', 'Herramientas', 'u', 27::numeric, 2850::numeric, 11::numeric, 10::numeric, 4::integer, 20::numeric, 'Herramientas Industriales', 'Deposito - Estante C', true, true),
  ('MAT-035', 'Mecha para metal', 'Herramientas', 'u', 18::numeric, 4600::numeric, 7::numeric, 6::numeric, 6::integer, 12::numeric, 'Herramientas Industriales', 'Deposito - Estante D', true, true),
  ('MAT-036', 'Precinto UV reforzado', 'Herramientas', 'bolsa', 33::numeric, 3850::numeric, 14::numeric, 12::numeric, 4::integer, 25::numeric, 'Herramientas Industriales', 'Deposito - Estante E', true, true),
  ('MAT-037', 'Cinta aisladora', 'Herramientas', 'rollo', 41::numeric, 1850::numeric, 16::numeric, 12::numeric, 3::integer, 30::numeric, 'Herramientas Industriales', 'Deposito - Estante F', true, true),
  ('MAT-038', 'Bornera para tablero de semaforo', 'Electricidad', 'u', 23::numeric, 3850::numeric, 9::numeric, 8::numeric, 8::integer, 15::numeric, 'Electroinsumos Viales', 'Deposito - Cajon 1', true, true),
  ('MAT-039', 'Protector facial', 'Seguridad', 'u', 9::numeric, 15800::numeric, 4::numeric, 4::numeric, 7::integer, 6::numeric, 'Seguridad Laboral', 'Deposito - Patio', true, true)
on conflict (sku) do nothing;

do $$
declare
  missing_codes text;
begin
  select string_agg(expected.sku, ', ')
    into missing_codes
  from (values
    ('MAT-001'),
    ('MAT-002'),
    ('MAT-003'),
    ('MAT-004'),
    ('MAT-005'),
    ('MAT-006'),
    ('MAT-007'),
    ('MAT-008'),
    ('MAT-009'),
    ('MAT-010'),
    ('MAT-011'),
    ('MAT-012'),
    ('MAT-013'),
    ('MAT-014'),
    ('MAT-015'),
    ('MAT-016'),
    ('MAT-017'),
    ('MAT-018'),
    ('MAT-019'),
    ('MAT-020'),
    ('MAT-021'),
    ('MAT-022'),
    ('MAT-023'),
    ('MAT-024'),
    ('MAT-025'),
    ('MAT-026'),
    ('MAT-027'),
    ('MAT-028'),
    ('MAT-029'),
    ('MAT-030'),
    ('MAT-031'),
    ('MAT-032'),
    ('MAT-033'),
    ('MAT-034'),
    ('MAT-035'),
    ('MAT-036'),
    ('MAT-037'),
    ('MAT-038'),
    ('MAT-039')
  ) as expected(sku)
  left join public.inventory_items i on i.sku = expected.sku
  where i.id is null;

  if missing_codes is not null then
    raise exception 'Faltan materiales del catálogo: %', missing_codes;
  end if;
end $$;

delete from public.inventory_movements;

with movement_data(sku,item_name,tipo,cantidad,stock_antes,stock_despues,nota,referencia,actor,created_at,precio_unitario_ars,precio_unitario_usd,cotizacion_blue,cotizacion_fecha,cotizacion_fuente) as (
  values
    ('MAT-033', 'Arandela plana galvanizada', 'consumo', -164::numeric, 310::numeric, 146::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0066', 'usuario1', '2026-01-04T00:02:26.932Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-035', 'Mecha para metal', 'ingreso', 18::numeric, 18::numeric, 36::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0151', 'usuario1', '2026-01-09T08:36:44.525Z'::timestamptz, 3940::numeric, 2.60066::numeric, 1515::numeric, '2026-01-07T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-011', 'Tacha reflectiva vial', 'ingreso', 104::numeric, 145::numeric, 249::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0039', 'usuario2', '2026-01-11T00:36:40.301Z'::timestamptz, 2530::numeric, 1.681063::numeric, 1505::numeric, '2026-01-09T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-003', 'Guantes de proteccion', 'ingreso', 58::numeric, 45::numeric, 103::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0011', 'usuario2', '2026-01-11T10:42:22.690Z'::timestamptz, 5160::numeric, 3.428571::numeric, 1505::numeric, '2026-01-09T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-006', 'Conector estanco', 'ingreso', 10::numeric, 7::numeric, 17::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0023', 'usuario2', '2026-01-13T13:00:32.239Z'::timestamptz, 2750::numeric, 1.827243::numeric, 1505::numeric, '2026-01-12T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-029', 'Poste galvanizado', 'ingreso', 14::numeric, 11::numeric, 25::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0107', 'usuario2', '2026-01-13T16:38:39.426Z'::timestamptz, 55920::numeric, 37.156146::numeric, 1505::numeric, '2026-01-12T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-031', 'Tornillo galvanizado', 'ingreso', 104::numeric, 260::numeric, 364::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0116', 'usuario2', '2026-01-15T00:48:24.808Z'::timestamptz, 160::numeric, 0.106312::numeric, 1505::numeric, '2026-01-13T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-012', 'Delineador flexible', 'ingreso', 23::numeric, 18::numeric, 41::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0047', 'usuario2', '2026-01-16T22:48:11.396Z'::timestamptz, 26980::numeric, 17.808581::numeric, 1515::numeric, '2026-01-15T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-032', 'Tuerca autofrenante', 'ingreso', 72::numeric, 185::numeric, 257::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0126', 'usuario2', '2026-01-17T09:52:02.609Z'::timestamptz, 220::numeric, 0.145215::numeric, 1515::numeric, '2026-01-15T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-023', 'Caja estanca para conexiones', 'ingreso', 23::numeric, 14::numeric, 37::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0085', 'usuario1', '2026-01-17T10:30:46.889Z'::timestamptz, 8690::numeric, 5.735974::numeric, 1515::numeric, '2026-01-15T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-016', 'Botines de seguridad', 'ingreso', 16::numeric, 8::numeric, 24::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0061', 'usuario2', '2026-01-17T21:52:00.865Z'::timestamptz, 59610::numeric, 39.346535::numeric, 1515::numeric, '2026-01-15T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-004', 'Chaleco reflectivo', 'ingreso', 28::numeric, 16::numeric, 44::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0015', 'usuario2', '2026-01-20T20:03:13.441Z'::timestamptz, 13100::numeric, 8.704319::numeric, 1505::numeric, '2026-01-19T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-033', 'Arandela plana galvanizada', 'ingreso', 72::numeric, 146::numeric, 218::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0135', 'usuario2', '2026-01-21T01:05:50.554Z'::timestamptz, 80::numeric, 0.053156::numeric, 1505::numeric, '2026-01-20T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-019', 'Modulo controlador de semaforo', 'ingreso', 5::numeric, 2::numeric, 7::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0069', 'usuario2', '2026-01-22T01:43:02.763Z'::timestamptz, 287010::numeric, 190.704319::numeric, 1505::numeric, '2026-01-20T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-017', 'Protector auditivo', 'ingreso', 21::numeric, 17::numeric, 38::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0063', 'usuario2', '2026-01-22T07:55:25.770Z'::timestamptz, 6170::numeric, 4.099668::numeric, 1505::numeric, '2026-01-20T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-021', 'Bornera de conexion', 'ingreso', 26::numeric, 64::numeric, 90::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0073', 'usuario1', '2026-01-22T18:10:22.386Z'::timestamptz, 1130::numeric, 0.750831::numeric, 1505::numeric, '2026-01-20T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-022', 'Cable subterraneo multipolar', 'consumo', -72::numeric, 86::numeric, 14::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0039', 'usuario2', '2026-01-23T08:11:55.283Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-005', 'Soporte galvanizado para cartel', 'ingreso', 19::numeric, 19::numeric, 38::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0019', 'usuario1', '2026-01-24T09:40:38.526Z'::timestamptz, 7930::numeric, 5.304348::numeric, 1495::numeric, '2026-01-23T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-030', 'Abrazadera para poste', 'ingreso', 53::numeric, 57::numeric, 110::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0111', 'usuario2', '2026-01-24T11:36:33.267Z'::timestamptz, 1650::numeric, 1.103679::numeric, 1495::numeric, '2026-01-23T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-015', 'Anteojos de seguridad', 'ingreso', 19::numeric, 21::numeric, 40::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0057', 'usuario1', '2026-01-25T05:23:21.278Z'::timestamptz, 7670::numeric, 5.130435::numeric, 1495::numeric, '2026-01-23T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-008', 'Cono vial 70 cm', 'ingreso', 55::numeric, 38::numeric, 93::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0030', 'usuario1', '2026-01-25T09:16:40.891Z'::timestamptz, 15500::numeric, 10.367893::numeric, 1495::numeric, '2026-01-23T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-039', 'Protector facial', 'ingreso', 12::numeric, 9::numeric, 21::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0167', 'usuario1', '2026-01-25T12:30:25.809Z'::timestamptz, 14030::numeric, 9.384615::numeric, 1495::numeric, '2026-01-23T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-001', 'Fusible industrial', 'ingreso', 39::numeric, 80::numeric, 119::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0001', 'usuario1', '2026-01-26T11:09:10.973Z'::timestamptz, 650::numeric, 0.434783::numeric, 1495::numeric, '2026-01-23T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-038', 'Bornera para tablero de semaforo', 'ingreso', 27::numeric, 23::numeric, 50::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0163', 'usuario1', '2026-01-27T09:15:18.807Z'::timestamptz, 3220::numeric, 2.16835::numeric, 1485::numeric, '2026-01-26T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-002', 'Lampara de senalizacion LED', 'ingreso', 44::numeric, 24::numeric, 68::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0007', 'usuario2', '2026-01-28T14:03:18.098Z'::timestamptz, 4560::numeric, 3.070707::numeric, 1485::numeric, '2026-01-26T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-013', 'Lamina reflectiva grado ingenieria', 'ingreso', 22::numeric, 22::numeric, 44::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0051', 'usuario2', '2026-01-29T09:50:14.013Z'::timestamptz, 35680::numeric, 23.946309::numeric, 1490::numeric, '2026-01-28T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-031', 'Tornillo galvanizado', 'ingreso', 57::numeric, 364::numeric, 421::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0117', 'usuario1', '2026-01-29T11:21:34.535Z'::timestamptz, 150::numeric, 0.100671::numeric, 1490::numeric, '2026-01-28T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-027', 'Microesferas de vidrio', 'ingreso', 21::numeric, 26::numeric, 47::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0101', 'usuario1', '2026-01-30T11:02:54.864Z'::timestamptz, 18740::numeric, 12.619529::numeric, 1485::numeric, '2026-01-29T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-026', 'Pintura vial blanca', 'ingreso', 16::numeric, 10::numeric, 26::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0097', 'usuario1', '2026-02-01T12:47:18.917Z'::timestamptz, 48920::numeric, 33.166102::numeric, 1475::numeric, '2026-01-30T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-032', 'Tuerca autofrenante', 'consumo', -256::numeric, 257::numeric, 1::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0062', 'usuario2', '2026-02-01T19:58:53.878Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-028', 'Cartel reglamentario metalico', 'ingreso', 14::numeric, 7::numeric, 21::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0105', 'usuario2', '2026-02-02T13:14:11.132Z'::timestamptz, 65780::numeric, 44.59661::numeric, 1475::numeric, '2026-01-30T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-024', 'Prensaestopa industrial', 'ingreso', 21::numeric, 32::numeric, 53::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0089', 'usuario1', '2026-02-03T13:34:55.438Z'::timestamptz, 2050::numeric, 1.394558::numeric, 1470::numeric, '2026-02-02T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-007', 'Sensor de velocidad', 'ingreso', 21::numeric, 3::numeric, 24::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0026', 'usuario1', '2026-02-05T19:53:03.859Z'::timestamptz, 39930::numeric, 27.537931::numeric, 1450::numeric, '2026-02-04T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-025', 'Pintura vial amarilla', 'ingreso', 10::numeric, 13::numeric, 23::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0093', 'usuario2', '2026-02-06T13:25:52.268Z'::timestamptz, 48350::numeric, 33.230241::numeric, 1455::numeric, '2026-02-05T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-034', 'Disco de corte para amoladora', 'ingreso', 32::numeric, 27::numeric, 59::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0147', 'usuario1', '2026-02-08T11:10:30.803Z'::timestamptz, 2480::numeric, 1.722222::numeric, 1440::numeric, '2026-02-06T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-037', 'Cinta aisladora', 'ingreso', 55::numeric, 41::numeric, 96::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0159', 'usuario2', '2026-02-09T02:31:40.083Z'::timestamptz, 1600::numeric, 1.111111::numeric, 1440::numeric, '2026-02-06T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-036', 'Precinto UV reforzado', 'ingreso', 32::numeric, 33::numeric, 65::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0155', 'usuario2', '2026-02-09T22:41:23.912Z'::timestamptz, 3110::numeric, 2.159722::numeric, 1440::numeric, '2026-02-06T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-011', 'Tacha reflectiva vial', 'consumo', -244::numeric, 249::numeric, 5::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0019', 'usuario2', '2026-02-10T21:23:51.658Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-033', 'Arandela plana galvanizada', 'ingreso', 81::numeric, 218::numeric, 299::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0136', 'usuario2', '2026-02-12T19:39:54.722Z'::timestamptz, 80::numeric, 0.055944::numeric, 1430::numeric, '2026-02-10T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-020', 'Fuente de alimentacion 24V', 'ingreso', 20::numeric, 6::numeric, 26::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0071', 'usuario2', '2026-02-17T15:37:24.335Z'::timestamptz, 29860::numeric, 20.736111::numeric, 1440::numeric, '2026-02-13T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-001', 'Fusible industrial', 'ingreso', 43::numeric, 119::numeric, 162::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0002', 'usuario1', '2026-02-18T13:13:45.696Z'::timestamptz, 640::numeric, 0.444444::numeric, 1440::numeric, '2026-02-17T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-032', 'Tuerca autofrenante', 'ingreso', 61::numeric, 1::numeric, 62::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0127', 'usuario2', '2026-02-21T07:52:41.281Z'::timestamptz, 190::numeric, 0.132867::numeric, 1430::numeric, '2026-02-20T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-021', 'Bornera de conexion', 'ingreso', 47::numeric, 90::numeric, 137::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0074', 'usuario2', '2026-02-21T20:35:50.236Z'::timestamptz, 1000::numeric, 0.699301::numeric, 1430::numeric, '2026-02-20T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-009', 'Cinta reflectiva roja y blanca', 'ingreso', 18::numeric, 11::numeric, 29::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0034', 'usuario1', '2026-02-23T08:11:19.616Z'::timestamptz, 18870::numeric, 13.195804::numeric, 1430::numeric, '2026-02-20T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-010', 'Cartel desvio transitorio', 'ingreso', 16::numeric, 9::numeric, 25::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0037', 'usuario1', '2026-02-23T15:13:23.908Z'::timestamptz, 32720::numeric, 22.881119::numeric, 1430::numeric, '2026-02-20T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-031', 'Tornillo galvanizado', 'consumo', -115::numeric, 421::numeric, 306::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0057', 'usuario2', '2026-02-27T09:38:55.506Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-037', 'Cinta aisladora', 'ingreso', 29::numeric, 96::numeric, 125::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0160', 'usuario2', '2026-02-28T15:53:21.149Z'::timestamptz, 1520::numeric, 1.066667::numeric, 1425::numeric, '2026-02-27T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-034', 'Disco de corte para amoladora', 'ingreso', 35::numeric, 59::numeric, 94::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0148', 'usuario2', '2026-03-01T01:38:32.888Z'::timestamptz, 2360::numeric, 1.65614::numeric, 1425::numeric, '2026-02-27T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-022', 'Cable subterraneo multipolar', 'ingreso', 58::numeric, 14::numeric, 72::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0079', 'usuario2', '2026-03-01T05:54:08.597Z'::timestamptz, 5250::numeric, 3.684211::numeric, 1425::numeric, '2026-02-27T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-033', 'Arandela plana galvanizada', 'consumo', -239::numeric, 299::numeric, 60::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0067', 'usuario1', '2026-03-01T09:19:03.629Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-005', 'Soporte galvanizado para cartel', 'ingreso', 28::numeric, 38::numeric, 66::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0020', 'usuario1', '2026-03-01T20:23:59.056Z'::timestamptz, 7380::numeric, 5.178947::numeric, 1425::numeric, '2026-02-27T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-011', 'Tacha reflectiva vial', 'ingreso', 84::numeric, 5::numeric, 89::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0040', 'usuario2', '2026-03-06T05:21:16.595Z'::timestamptz, 2300::numeric, 1.642857::numeric, 1400::numeric, '2026-03-05T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-002', 'Lampara de senalizacion LED', 'ingreso', 20::numeric, 68::numeric, 88::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0008', 'usuario2', '2026-03-06T10:28:57.007Z'::timestamptz, 4510::numeric, 3.221429::numeric, 1400::numeric, '2026-03-05T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-013', 'Lamina reflectiva grado ingenieria', 'ingreso', 31::numeric, 44::numeric, 75::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0052', 'usuario2', '2026-03-06T13:39:11.848Z'::timestamptz, 35930::numeric, 25.664286::numeric, 1400::numeric, '2026-03-05T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-014', 'Casco de seguridad', 'ingreso', 14::numeric, 12::numeric, 26::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0055', 'usuario2', '2026-03-08T09:56:11.353Z'::timestamptz, 16890::numeric, 11.936396::numeric, 1415::numeric, '2026-03-06T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-024', 'Prensaestopa industrial', 'ingreso', 34::numeric, 53::numeric, 87::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0090', 'usuario1', '2026-03-09T05:40:47.138Z'::timestamptz, 1900::numeric, 1.342756::numeric, 1415::numeric, '2026-03-06T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-018', 'Tablero de control vial', 'ingreso', 12::numeric, 4::numeric, 16::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0067', 'usuario1', '2026-03-10T01:53:39.083Z'::timestamptz, 149390::numeric, 105.575972::numeric, 1415::numeric, '2026-03-06T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-031', 'Tornillo galvanizado', 'consumo', -166::numeric, 306::numeric, 140::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0058', 'usuario2', '2026-03-15T21:56:31.950Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-021', 'Bornera de conexion', 'consumo', -101::numeric, 137::numeric, 36::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0036', 'usuario1', '2026-03-17T07:34:47.462Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-026', 'Pintura vial blanca', 'consumo', -24::numeric, 26::numeric, 2::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0048', 'usuario2', '2026-03-17T13:03:58.028Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-025', 'Pintura vial amarilla', 'ingreso', 19::numeric, 23::numeric, 42::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0094', 'usuario2', '2026-03-17T16:04:54.755Z'::timestamptz, 46610::numeric, 32.939929::numeric, 1415::numeric, '2026-03-16T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-027', 'Microesferas de vidrio', 'ingreso', 33::numeric, 47::numeric, 80::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0102', 'usuario1', '2026-03-18T06:47:31.119Z'::timestamptz, 18350::numeric, 12.877193::numeric, 1425::numeric, '2026-03-17T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-030', 'Abrazadera para poste', 'ingreso', 53::numeric, 110::numeric, 163::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0112', 'usuario1', '2026-03-18T14:13:39.471Z'::timestamptz, 1590::numeric, 1.115789::numeric, 1425::numeric, '2026-03-17T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-004', 'Chaleco reflectivo', 'ingreso', 28::numeric, 44::numeric, 72::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0016', 'usuario1', '2026-03-19T06:53:31.167Z'::timestamptz, 12300::numeric, 8.571429::numeric, 1435::numeric, '2026-03-18T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-003', 'Guantes de proteccion', 'consumo', -71::numeric, 103::numeric, 32::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0006', 'usuario1', '2026-03-21T12:23:54.155Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-033', 'Arandela plana galvanizada', 'ingreso', 126::numeric, 60::numeric, 186::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0137', 'usuario1', '2026-03-22T07:46:21.559Z'::timestamptz, 80::numeric, 0.055944::numeric, 1430::numeric, '2026-03-19T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-008', 'Cono vial 70 cm', 'ingreso', 24::numeric, 93::numeric, 117::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0031', 'usuario2', '2026-03-22T11:04:01.633Z'::timestamptz, 15880::numeric, 11.104895::numeric, 1430::numeric, '2026-03-19T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-035', 'Mecha para metal', 'ingreso', 24::numeric, 36::numeric, 60::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0152', 'usuario2', '2026-03-22T18:35:49.765Z'::timestamptz, 3770::numeric, 2.636364::numeric, 1430::numeric, '2026-03-19T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-007', 'Sensor de velocidad', 'ingreso', 11::numeric, 24::numeric, 35::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0027', 'usuario1', '2026-03-24T00:12:20.889Z'::timestamptz, 40150::numeric, 28.076923::numeric, 1430::numeric, '2026-03-19T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-011', 'Tacha reflectiva vial', 'ingreso', 75::numeric, 89::numeric, 164::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0041', 'usuario2', '2026-03-24T19:24:00.250Z'::timestamptz, 2300::numeric, 1.608392::numeric, 1430::numeric, '2026-03-19T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-032', 'Tuerca autofrenante', 'ingreso', 94::numeric, 62::numeric, 156::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0128', 'usuario2', '2026-03-27T03:11:26.969Z'::timestamptz, 210::numeric, 0.147368::numeric, 1425::numeric, '2026-03-25T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-017', 'Protector auditivo', 'ingreso', 12::numeric, 38::numeric, 50::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0064', 'usuario1', '2026-03-27T09:33:23.146Z'::timestamptz, 6210::numeric, 4.357895::numeric, 1425::numeric, '2026-03-25T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-023', 'Caja estanca para conexiones', 'consumo', -27::numeric, 37::numeric, 10::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0042', 'usuario1', '2026-03-27T20:46:39.281Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-001', 'Fusible industrial', 'ingreso', 79::numeric, 162::numeric, 241::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0003', 'usuario2', '2026-03-28T13:20:15.706Z'::timestamptz, 650::numeric, 0.45614::numeric, 1425::numeric, '2026-03-27T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-033', 'Arandela plana galvanizada', 'consumo', -130::numeric, 186::numeric, 56::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0068', 'usuario2', '2026-03-29T16:38:11.667Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-015', 'Anteojos de seguridad', 'ingreso', 15::numeric, 40::numeric, 55::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0058', 'usuario2', '2026-03-30T10:14:11.479Z'::timestamptz, 7750::numeric, 5.438596::numeric, 1425::numeric, '2026-03-27T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-038', 'Bornera para tablero de semaforo', 'ingreso', 29::numeric, 50::numeric, 79::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0164', 'usuario2', '2026-03-30T13:23:49.421Z'::timestamptz, 3240::numeric, 2.273684::numeric, 1425::numeric, '2026-03-27T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-031', 'Tornillo galvanizado', 'ingreso', 67::numeric, 140::numeric, 207::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0118', 'usuario2', '2026-03-31T03:23:21.944Z'::timestamptz, 160::numeric, 0.112281::numeric, 1425::numeric, '2026-03-30T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-022', 'Cable subterraneo multipolar', 'ingreso', 94::numeric, 72::numeric, 166::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0080', 'usuario1', '2026-04-01T07:02:09.240Z'::timestamptz, 5000::numeric, 3.546099::numeric, 1410::numeric, '2026-03-31T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-012', 'Delineador flexible', 'ingreso', 10::numeric, 41::numeric, 51::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0048', 'usuario2', '2026-04-02T07:03:16.938Z'::timestamptz, 26490::numeric, 18.787234::numeric, 1410::numeric, '2026-03-31T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-029', 'Poste galvanizado', 'ingreso', 14::numeric, 25::numeric, 39::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0108', 'usuario2', '2026-04-04T08:41:47.056Z'::timestamptz, 52430::numeric, 37.316726::numeric, 1405::numeric, '2026-04-03T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-036', 'Precinto UV reforzado', 'ingreso', 56::numeric, 65::numeric, 121::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0156', 'usuario1', '2026-04-04T22:58:24.812Z'::timestamptz, 3250::numeric, 2.313167::numeric, 1405::numeric, '2026-04-03T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-006', 'Conector estanco', 'ingreso', 18::numeric, 17::numeric, 35::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0024', 'usuario1', '2026-04-05T05:27:38.723Z'::timestamptz, 2660::numeric, 1.893238::numeric, 1405::numeric, '2026-04-03T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-033', 'Arandela plana galvanizada', 'ingreso', 122::numeric, 56::numeric, 178::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0138', 'usuario2', '2026-04-16T08:52:12.806Z'::timestamptz, 80::numeric, 0.056738::numeric, 1410::numeric, '2026-04-15T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-031', 'Tornillo galvanizado', 'ingreso', 107::numeric, 207::numeric, 314::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0119', 'usuario2', '2026-04-20T11:52:01.088Z'::timestamptz, 150::numeric, 0.106007::numeric, 1415::numeric, '2026-04-16T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-034', 'Disco de corte para amoladora', 'consumo', -60::numeric, 94::numeric, 34::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0072', 'usuario1', '2026-04-21T06:21:14.154Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-030', 'Abrazadera para poste', 'ingreso', 59::numeric, 163::numeric, 222::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0113', 'usuario1', '2026-04-23T02:16:15.733Z'::timestamptz, 1560::numeric, 1.106383::numeric, 1410::numeric, '2026-04-22T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-032', 'Tuerca autofrenante', 'consumo', -151::numeric, 156::numeric, 5::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0063', 'usuario1', '2026-04-23T15:58:57.555Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-022', 'Cable subterraneo multipolar', 'ingreso', 61::numeric, 166::numeric, 227::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0081', 'usuario2', '2026-04-23T22:36:58.467Z'::timestamptz, 5060::numeric, 3.575972::numeric, 1415::numeric, '2026-04-23T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-005', 'Soporte galvanizado para cartel', 'consumo', -48::numeric, 66::numeric, 18::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0010', 'usuario1', '2026-04-28T06:17:46.266Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-021', 'Bornera de conexion', 'ingreso', 56::numeric, 36::numeric, 92::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0075', 'usuario2', '2026-04-29T19:10:05.327Z'::timestamptz, 1080::numeric, 0.755245::numeric, 1430::numeric, '2026-04-28T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-024', 'Prensaestopa industrial', 'consumo', -57::numeric, 87::numeric, 30::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0044', 'usuario1', '2026-04-29T20:02:55.486Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-023', 'Caja estanca para conexiones', 'ingreso', 11::numeric, 10::numeric, 21::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0086', 'usuario2', '2026-04-30T15:59:16.542Z'::timestamptz, 8210::numeric, 5.741259::numeric, 1430::numeric, '2026-04-29T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-013', 'Lamina reflectiva grado ingenieria', 'consumo', -30::numeric, 75::numeric, 45::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0025', 'usuario2', '2026-04-30T20:47:17.005Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-011', 'Tacha reflectiva vial', 'consumo', -134::numeric, 164::numeric, 30::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0020', 'usuario1', '2026-05-01T11:39:06.163Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-025', 'Pintura vial amarilla', 'consumo', -22::numeric, 42::numeric, 20::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0046', 'usuario2', '2026-05-02T21:24:11.009Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-002', 'Lampara de senalizacion LED', 'ingreso', 20::numeric, 88::numeric, 108::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0009', 'usuario1', '2026-05-03T13:09:19.388Z'::timestamptz, 4550::numeric, 3.181818::numeric, 1430::numeric, '2026-04-29T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-035', 'Mecha para metal', 'consumo', -37::numeric, 60::numeric, 23::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0074', 'usuario1', '2026-05-03T22:59:18.749Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-026', 'Pintura vial blanca', 'ingreso', 9::numeric, 2::numeric, 11::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0098', 'usuario1', '2026-05-05T13:49:41.296Z'::timestamptz, 46580::numeric, 33.153025::numeric, 1405::numeric, '2026-05-04T12:04:02.481-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-033', 'Arandela plana galvanizada', 'ingreso', 78::numeric, 178::numeric, 256::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0139', 'usuario1', '2026-05-07T18:52:22.321Z'::timestamptz, 80::numeric, 0.057143::numeric, 1400::numeric, '2026-05-06T11:06:02.628-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-003', 'Guantes de proteccion', 'ingreso', 36::numeric, 32::numeric, 68::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0012', 'usuario1', '2026-05-08T09:28:32.170Z'::timestamptz, 5330::numeric, 3.807143::numeric, 1400::numeric, '2026-05-06T11:06:02.628-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-027', 'Microesferas de vidrio', 'ingreso', 27::numeric, 80::numeric, 107::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0103', 'usuario1', '2026-05-08T11:39:55.167Z'::timestamptz, 18910::numeric, 13.507143::numeric, 1400::numeric, '2026-05-06T11:06:02.628-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-001', 'Fusible industrial', 'consumo', -105::numeric, 241::numeric, 136::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0001', 'usuario1', '2026-05-08T15:08:41.259Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-015', 'Anteojos de seguridad', 'consumo', -41::numeric, 55::numeric, 14::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0028', 'usuario1', '2026-05-10T14:12:16.744Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-014', 'Casco de seguridad', 'ingreso', 26::numeric, 26::numeric, 52::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0056', 'usuario2', '2026-05-12T09:08:46.839Z'::timestamptz, 16790::numeric, 11.950178::numeric, 1405::numeric, '2026-05-11T12:04:02.536-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-009', 'Cinta reflectiva roja y blanca', 'ingreso', 18::numeric, 29::numeric, 47::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0035', 'usuario1', '2026-05-12T11:50:40.399Z'::timestamptz, 19040::numeric, 13.551601::numeric, 1405::numeric, '2026-05-11T12:04:02.536-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-012', 'Delineador flexible', 'ingreso', 27::numeric, 51::numeric, 78::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0049', 'usuario1', '2026-05-13T08:34:24.474Z'::timestamptz, 25740::numeric, 18.190813::numeric, 1415::numeric, '2026-05-12T13:08:02.745-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-036', 'Precinto UV reforzado', 'ingreso', 30::numeric, 121::numeric, 151::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0157', 'usuario1', '2026-05-13T14:40:10.553Z'::timestamptz, 3420::numeric, 2.416961::numeric, 1415::numeric, '2026-05-12T13:08:02.745-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-031', 'Tornillo galvanizado', 'ingreso', 144::numeric, 314::numeric, 458::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0120', 'usuario2', '2026-05-16T18:33:03.385Z'::timestamptz, 160::numeric, 0.113074::numeric, 1415::numeric, '2026-05-15T13:04:03.358-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-008', 'Cono vial 70 cm', 'ingreso', 29::numeric, 117::numeric, 146::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0032', 'usuario1', '2026-05-17T20:19:29.021Z'::timestamptz, 15160::numeric, 10.713781::numeric, 1415::numeric, '2026-05-15T13:04:03.358-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-032', 'Tuerca autofrenante', 'ingreso', 105::numeric, 5::numeric, 110::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0129', 'usuario1', '2026-05-18T03:53:24.051Z'::timestamptz, 210::numeric, 0.14841::numeric, 1415::numeric, '2026-05-15T13:04:03.358-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-017', 'Protector auditivo', 'ingreso', 16::numeric, 50::numeric, 66::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0065', 'usuario1', '2026-05-18T06:28:37.656Z'::timestamptz, 6380::numeric, 4.508834::numeric, 1415::numeric, '2026-05-15T13:04:03.358-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-004', 'Chaleco reflectivo', 'consumo', -56::numeric, 72::numeric, 16::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0008', 'usuario1', '2026-05-18T20:46:22.704Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-038', 'Bornera para tablero de semaforo', 'consumo', -48::numeric, 79::numeric, 31::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0080', 'usuario1', '2026-05-18T23:57:06.885Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-037', 'Cinta aisladora', 'ingreso', 27::numeric, 125::numeric, 152::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0161', 'usuario2', '2026-05-19T16:05:23.451Z'::timestamptz, 1550::numeric, 1.083916::numeric, 1430::numeric, '2026-05-19T12:04:02.819-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-011', 'Tacha reflectiva vial', 'ingreso', 100::numeric, 30::numeric, 130::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0042', 'usuario1', '2026-05-21T02:28:30.808Z'::timestamptz, 2330::numeric, 1.629371::numeric, 1430::numeric, '2026-05-20T11:04:01.964-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-007', 'Sensor de velocidad', 'ingreso', 19::numeric, 35::numeric, 54::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0028', 'usuario2', '2026-05-23T04:22:47.358Z'::timestamptz, 38800::numeric, 27.22807::numeric, 1425::numeric, '2026-05-22T15:04:02.516-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-029', 'Poste galvanizado', 'consumo', -22::numeric, 39::numeric, 17::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0053', 'usuario1', '2026-05-24T18:50:11.842Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-033', 'Arandela plana galvanizada', 'ingreso', 131::numeric, 256::numeric, 387::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0140', 'usuario1', '2026-05-24T23:25:35.600Z'::timestamptz, 80::numeric, 0.05614::numeric, 1425::numeric, '2026-05-22T15:04:02.516-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-021', 'Bornera de conexion', 'consumo', -63::numeric, 92::numeric, 29::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0037', 'usuario1', '2026-05-27T23:10:30.499Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-001', 'Fusible industrial', 'consumo', -112::numeric, 136::numeric, 24::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0002', 'usuario2', '2026-05-29T01:20:58.306Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-031', 'Tornillo galvanizado', 'ingreso', 141::numeric, 458::numeric, 599::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0121', 'usuario1', '2026-05-30T16:34:17.428Z'::timestamptz, 160::numeric, 0.111888::numeric, 1430::numeric, '2026-05-28T16:04:02.954-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-020', 'Fuente de alimentacion 24V', 'ingreso', 10::numeric, 26::numeric, 36::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0072', 'usuario1', '2026-06-02T11:16:20.958Z'::timestamptz, 30760::numeric, 21.43554::numeric, 1435::numeric, '2026-06-01T17:06:06.885-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-018', 'Tablero de control vial', 'ingreso', 8::numeric, 16::numeric, 24::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0068', 'usuario1', '2026-06-02T12:57:18.693Z'::timestamptz, 158410::numeric, 110.390244::numeric, 1435::numeric, '2026-06-01T17:06:06.885-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-030', 'Abrazadera para poste', 'ingreso', 23::numeric, 222::numeric, 245::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0114', 'usuario1', '2026-06-04T02:46:42.344Z'::timestamptz, 1590::numeric, 1.111888::numeric, 1430::numeric, '2026-06-03T16:04:02.773-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-039', 'Protector facial', 'ingreso', 28::numeric, 21::numeric, 49::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0168', 'usuario2', '2026-06-04T06:20:38.702Z'::timestamptz, 13190::numeric, 9.223776::numeric, 1430::numeric, '2026-06-03T16:04:02.773-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-033', 'Arandela plana galvanizada', 'ingreso', 62::numeric, 387::numeric, 449::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0141', 'usuario2', '2026-06-05T21:50:00.127Z'::timestamptz, 80::numeric, 0.055749::numeric, 1435::numeric, '2026-06-05T16:04:03.041-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-011', 'Tacha reflectiva vial', 'ingreso', 68::numeric, 130::numeric, 198::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0043', 'usuario2', '2026-06-08T00:44:13.950Z'::timestamptz, 2470::numeric, 1.721254::numeric, 1435::numeric, '2026-06-05T16:04:03.041-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-016', 'Botines de seguridad', 'ingreso', 14::numeric, 24::numeric, 38::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0062', 'usuario1', '2026-06-08T03:03:35.191Z'::timestamptz, 59900::numeric, 41.74216::numeric, 1435::numeric, '2026-06-05T16:04:03.041-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-022', 'Cable subterraneo multipolar', 'consumo', -142::numeric, 227::numeric, 85::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0040', 'usuario1', '2026-06-09T02:24:30.075Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-032', 'Tuerca autofrenante', 'ingreso', 55::numeric, 110::numeric, 165::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0130', 'usuario1', '2026-06-09T12:22:47.531Z'::timestamptz, 210::numeric, 0.145329::numeric, 1445::numeric, '2026-06-08T15:04:04.004-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-019', 'Modulo controlador de semaforo', 'ingreso', 5::numeric, 7::numeric, 12::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0070', 'usuario1', '2026-06-11T14:54:54.634Z'::timestamptz, 280290::numeric, 193.972318::numeric, 1445::numeric, '2026-06-11T11:04:03.853-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-007', 'Sensor de velocidad', 'ingreso', 19::numeric, 54::numeric, 73::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0029', 'usuario1', '2026-06-12T07:18:49.149Z'::timestamptz, 41750::numeric, 28.793103::numeric, 1450::numeric, '2026-06-11T15:04:04.381-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-008', 'Cono vial 70 cm', 'consumo', -69::numeric, 146::numeric, 77::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0015', 'usuario2', '2026-06-12T16:18:24.607Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-024', 'Prensaestopa industrial', 'ingreso', 33::numeric, 30::numeric, 63::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0091', 'usuario2', '2026-06-13T14:43:46.242Z'::timestamptz, 1990::numeric, 1.363014::numeric, 1460::numeric, '2026-06-12T16:04:05.105-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-036', 'Precinto UV reforzado', 'consumo', -88::numeric, 151::numeric, 63::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0076', 'usuario1', '2026-06-13T16:25:20.745Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-035', 'Mecha para metal', 'ingreso', 19::numeric, 23::numeric, 42::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0153', 'usuario2', '2026-06-13T17:26:14.612Z'::timestamptz, 3930::numeric, 2.691781::numeric, 1460::numeric, '2026-06-12T16:04:05.105-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-017', 'Protector auditivo', 'consumo', -27::numeric, 66::numeric, 39::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0031', 'usuario1', '2026-06-14T02:09:37.065Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-013', 'Lamina reflectiva grado ingenieria', 'ingreso', 20::numeric, 45::numeric, 65::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0053', 'usuario2', '2026-06-15T02:34:03.530Z'::timestamptz, 38490::numeric, 26.363014::numeric, 1460::numeric, '2026-06-12T16:04:05.105-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-037', 'Cinta aisladora', 'consumo', -94::numeric, 152::numeric, 58::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0078', 'usuario2', '2026-06-16T21:02:28.900Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-003', 'Guantes de proteccion', 'ingreso', 56::numeric, 68::numeric, 124::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0013', 'usuario2', '2026-06-17T01:47:51.932Z'::timestamptz, 5570::numeric, 3.789116::numeric, 1470::numeric, '2026-06-16T13:04:03.639-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-002', 'Lampara de senalizacion LED', 'consumo', -43::numeric, 108::numeric, 65::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0004', 'usuario2', '2026-06-17T22:33:20.226Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-012', 'Delineador flexible', 'consumo', -56::numeric, 78::numeric, 22::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0023', 'usuario1', '2026-06-19T01:00:39.013Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-038', 'Bornera para tablero de semaforo', 'ingreso', 14::numeric, 31::numeric, 45::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0165', 'usuario1', '2026-06-19T23:24:23.443Z'::timestamptz, 3600::numeric, 2.432432::numeric, 1480::numeric, '2026-06-19T12:04:02.779-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-029', 'Poste galvanizado', 'ingreso', 9::numeric, 17::numeric, 26::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0109', 'usuario1', '2026-06-22T16:10:32.329Z'::timestamptz, 55120::numeric, 37.243243::numeric, 1480::numeric, '2026-06-19T12:04:02.779-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-010', 'Cartel desvio transitorio', 'ingreso', 14::numeric, 25::numeric, 39::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0038', 'usuario1', '2026-06-23T08:19:49.687Z'::timestamptz, 36640::numeric, 24.508361::numeric, 1495::numeric, '2026-06-22T14:06:03.920-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-026', 'Pintura vial blanca', 'ingreso', 14::numeric, 11::numeric, 25::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0099', 'usuario1', '2026-06-23T14:29:24.080Z'::timestamptz, 50870::numeric, 34.026756::numeric, 1495::numeric, '2026-06-22T14:06:03.920-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-023', 'Caja estanca para conexiones', 'ingreso', 23::numeric, 21::numeric, 44::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0087', 'usuario2', '2026-06-26T03:17:08.490Z'::timestamptz, 8920::numeric, 5.830065::numeric, 1530::numeric, '2026-06-24T16:06:04.933-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-005', 'Soporte galvanizado para cartel', 'ingreso', 24::numeric, 18::numeric, 42::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0021', 'usuario2', '2026-06-27T17:46:33.323Z'::timestamptz, 8620::numeric, 5.689769::numeric, 1515::numeric, '2026-06-26T17:08:04.655-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-004', 'Chaleco reflectivo', 'ingreso', 14::numeric, 16::numeric, 30::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0017', 'usuario2', '2026-06-27T18:12:41.695Z'::timestamptz, 14080::numeric, 9.293729::numeric, 1515::numeric, '2026-06-26T17:08:04.655-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-015', 'Anteojos de seguridad', 'ingreso', 19::numeric, 14::numeric, 33::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0059', 'usuario2', '2026-06-28T09:10:13.481Z'::timestamptz, 8180::numeric, 5.39934::numeric, 1515::numeric, '2026-06-26T17:08:04.655-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-001', 'Fusible industrial', 'ingreso', 33::numeric, 24::numeric, 57::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0004', 'usuario1', '2026-06-29T06:34:12.395Z'::timestamptz, 720::numeric, 0.475248::numeric, 1515::numeric, '2026-06-26T17:08:04.655-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-031', 'Tornillo galvanizado', 'ingreso', 140::numeric, 599::numeric, 739::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0122', 'usuario1', '2026-06-29T10:50:27.719Z'::timestamptz, 170::numeric, 0.112211::numeric, 1515::numeric, '2026-06-26T17:08:04.655-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-006', 'Conector estanco', 'ingreso', 22::numeric, 35::numeric, 57::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0025', 'usuario1', '2026-06-30T05:52:13.983Z'::timestamptz, 3000::numeric, 1.986755::numeric, 1510::numeric, '2026-06-29T12:06:03.749-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-032', 'Tuerca autofrenante', 'ingreso', 48::numeric, 165::numeric, 213::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0131', 'usuario1', '2026-06-30T07:40:15.264Z'::timestamptz, 220::numeric, 0.145695::numeric, 1510::numeric, '2026-06-29T12:06:03.749-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-028', 'Cartel reglamentario metalico', 'ingreso', 16::numeric, 21::numeric, 37::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0106', 'usuario1', '2026-07-01T14:10:49.467Z'::timestamptz, 68420::numeric, 45.161716::numeric, 1515::numeric, '2026-06-30T16:06:03.150-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-034', 'Disco de corte para amoladora', 'ingreso', 22::numeric, 34::numeric, 56::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0149', 'usuario1', '2026-07-01T21:05:57.596Z'::timestamptz, 2620::numeric, 1.718033::numeric, 1525::numeric, '2026-07-01T15:06:02.985-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-033', 'Arandela plana galvanizada', 'consumo', -231::numeric, 449::numeric, 218::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0069', 'usuario2', '2026-07-03T06:12:18.367Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-027', 'Microesferas de vidrio', 'consumo', -80::numeric, 107::numeric, 27::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0050', 'usuario2', '2026-07-06T17:03:39.140Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-022', 'Cable subterraneo multipolar', 'ingreso', 56::numeric, 85::numeric, 141::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0082', 'usuario2', '2026-07-07T21:20:30.228Z'::timestamptz, 5930::numeric, 3.914191::numeric, 1515::numeric, '2026-07-06T12:06:02.461-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-011', 'Tacha reflectiva vial', 'consumo', -153::numeric, 198::numeric, 45::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0021', 'usuario1', '2026-07-08T04:46:18.989Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-021', 'Bornera de conexion', 'ingreso', 25::numeric, 29::numeric, 54::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0076', 'usuario2', '2026-07-10T17:05:10.899Z'::timestamptz, 1140::numeric, 0.75::numeric, 1520::numeric, '2026-07-08T11:48:02.327-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-030', 'Abrazadera para poste', 'ingreso', 32::numeric, 245::numeric, 277::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0115', 'usuario2', '2026-07-12T14:14:13.253Z'::timestamptz, 1670::numeric, 1.10596::numeric, 1510::numeric, '2026-07-11T20:06:02.713-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-033', 'Arandela plana galvanizada', 'consumo', -206::numeric, 218::numeric, 12::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0070', 'usuario1', '2026-07-12T17:29:12.455Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-025', 'Pintura vial amarilla', 'ingreso', 21::numeric, 20::numeric, 41::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0095', 'usuario2', '2026-07-13T09:19:51.072Z'::timestamptz, 53150::numeric, 35.198675::numeric, 1510::numeric, '2026-07-11T20:06:02.713-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-009', 'Cinta reflectiva roja y blanca', 'ingreso', 14::numeric, 47::numeric, 61::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0036', 'usuario2', '2026-07-13T17:37:10.060Z'::timestamptz, 20740::numeric, 13.644737::numeric, 1520::numeric, '2026-07-13T12:30:01.717-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-031', 'Tornillo galvanizado', 'ingreso', 64::numeric, 739::numeric, 803::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0123', 'usuario1', '2026-07-20T00:51:11.712Z'::timestamptz, 170::numeric, 0.111111::numeric, 1530::numeric, '2026-07-17T14:22:01.865-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-032', 'Tuerca autofrenante', 'ingreso', 107::numeric, 213::numeric, 320::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0132', 'usuario1', '2026-07-22T18:28:12.767Z'::timestamptz, 230::numeric, 0.14791::numeric, 1555::numeric, '2026-07-22T14:08:01.617-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-033', 'Arandela plana galvanizada', 'ingreso', 99::numeric, 12::numeric, 111::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0142', 'usuario2', '2026-07-28T18:32:11.996Z'::timestamptz, 100::numeric, 0.063694::numeric, 1570::numeric, '2026-07-28T11:08:02.024-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-038', 'Bornera para tablero de semaforo', 'consumo', -42::numeric, 45::numeric, 3::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0081', 'usuario2', '2026-07-31T04:38:04.876Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-003', 'Guantes de proteccion', 'ingreso', 30::numeric, 124::numeric, 154::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0014', 'usuario1', '2026-07-31T19:26:08.619Z'::timestamptz, 5920::numeric, 3.794872::numeric, 1560::numeric, '2026-07-31T13:04:01.574-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-005', 'Soporte galvanizado para cartel', 'ingreso', 29::numeric, 42::numeric, 71::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0022', 'usuario2', '2026-08-02T03:10:38.564Z'::timestamptz, 9160::numeric, 5.871795::numeric, 1560::numeric, '2026-07-31T13:04:01.574-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-037', 'Cinta aisladora', 'ingreso', 49::numeric, 58::numeric, 107::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0162', 'usuario1', '2026-08-02T23:39:52.583Z'::timestamptz, 1850::numeric, 1.185897::numeric, 1560::numeric, '2026-07-31T13:04:01.574-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-013', 'Lamina reflectiva grado ingenieria', 'ingreso', 17::numeric, 65::numeric, 82::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0054', 'usuario1', '2026-08-05T05:46:20.542Z'::timestamptz, 41060::numeric, 26.576052::numeric, 1545::numeric, '2026-08-04T11:08:02.996-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-021', 'Bornera de conexion', 'ingreso', 23::numeric, 54::numeric, 77::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0077', 'usuario2', '2026-08-06T09:40:36.413Z'::timestamptz, 1210::numeric, 0.785714::numeric, 1540::numeric, '2026-08-05T11:08:01.677-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-024', 'Prensaestopa industrial', 'ingreso', 42::numeric, 63::numeric, 105::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0092', 'usuario2', '2026-08-06T21:17:01.825Z'::timestamptz, 2120::numeric, 1.385621::numeric, 1530::numeric, '2026-08-06T11:10:02.128-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-031', 'Tornillo galvanizado', 'ingreso', 63::numeric, 803::numeric, 866::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0124', 'usuario2', '2026-08-08T09:04:28.437Z'::timestamptz, 170::numeric, 0.111475::numeric, 1525::numeric, '2026-08-07T10:56:02.043-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-029', 'Poste galvanizado', 'ingreso', 13::numeric, 26::numeric, 39::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0110', 'usuario1', '2026-08-09T04:30:01.450Z'::timestamptz, 61100::numeric, 40.065574::numeric, 1525::numeric, '2026-08-07T10:56:02.043-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-034', 'Disco de corte para amoladora', 'consumo', -50::numeric, 56::numeric, 6::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0073', 'usuario2', '2026-08-10T12:09:16.061Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-017', 'Protector auditivo', 'consumo', -33::numeric, 39::numeric, 6::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0032', 'usuario1', '2026-08-11T03:36:36.008Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-011', 'Tacha reflectiva vial', 'ingreso', 90::numeric, 45::numeric, 135::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0044', 'usuario2', '2026-08-11T05:44:02.678Z'::timestamptz, 2580::numeric, 1.680782::numeric, 1535::numeric, '2026-08-10T12:50:02.450-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-016', 'Botines de seguridad', 'consumo', -30::numeric, 38::numeric, 8::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0030', 'usuario2', '2026-08-12T10:38:08.098Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-027', 'Microesferas de vidrio', 'ingreso', 39::numeric, 27::numeric, 66::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0104', 'usuario1', '2026-08-13T11:59:48.933Z'::timestamptz, 21360::numeric, 13.915309::numeric, 1535::numeric, '2026-08-12T12:16:02.757-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-022', 'Cable subterraneo multipolar', 'ingreso', 48::numeric, 141::numeric, 189::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0083', 'usuario1', '2026-08-14T03:09:18.183Z'::timestamptz, 5730::numeric, 3.720779::numeric, 1540::numeric, '2026-08-13T10:58:02.809-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-001', 'Fusible industrial', 'ingreso', 37::numeric, 57::numeric, 94::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0005', 'usuario1', '2026-08-14T05:15:41.971Z'::timestamptz, 730::numeric, 0.474026::numeric, 1540::numeric, '2026-08-13T10:58:02.809-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-036', 'Precinto UV reforzado', 'ingreso', 22::numeric, 63::numeric, 85::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0158', 'usuario1', '2026-08-17T08:37:22.958Z'::timestamptz, 3810::numeric, 2.466019::numeric, 1545::numeric, '2026-08-14T16:14:03.459-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-033', 'Arandela plana galvanizada', 'ingreso', 127::numeric, 111::numeric, 238::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0143', 'usuario2', '2026-08-17T11:54:19.225Z'::timestamptz, 90::numeric, 0.058252::numeric, 1545::numeric, '2026-08-14T16:14:03.459-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-015', 'Anteojos de seguridad', 'ingreso', 27::numeric, 33::numeric, 60::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0060', 'usuario2', '2026-08-17T16:47:58.224Z'::timestamptz, 8460::numeric, 5.475728::numeric, 1545::numeric, '2026-08-14T16:14:03.459-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-032', 'Tuerca autofrenante', 'ingreso', 107::numeric, 320::numeric, 427::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0133', 'usuario1', '2026-08-20T00:05:13.645Z'::timestamptz, 230::numeric, 0.147436::numeric, 1560::numeric, '2026-08-19T14:44:05.106-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-031', 'Tornillo galvanizado', 'consumo', -253::numeric, 866::numeric, 613::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0059', 'usuario2', '2026-08-23T02:02:31.407Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-012', 'Delineador flexible', 'ingreso', 20::numeric, 22::numeric, 42::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0050', 'usuario2', '2026-08-27T01:12:38.101Z'::timestamptz, 30210::numeric, 19.427653::numeric, 1555::numeric, '2026-08-26T11:30:04.589-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-039', 'Protector facial', 'consumo', -40::numeric, 49::numeric, 9::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0082', 'usuario1', '2026-08-27T15:02:18.344Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-014', 'Casco de seguridad', 'consumo', -40::numeric, 52::numeric, 12::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0027', 'usuario1', '2026-08-28T23:42:43.803Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-004', 'Chaleco reflectivo', 'ingreso', 20::numeric, 30::numeric, 50::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0018', 'usuario2', '2026-08-29T05:19:06.260Z'::timestamptz, 13860::numeric, 8.913183::numeric, 1555::numeric, '2026-08-26T11:30:04.589-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-008', 'Cono vial 70 cm', 'consumo', -71::numeric, 77::numeric, 6::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0016', 'usuario1', '2026-08-29T13:16:00.452Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-023', 'Caja estanca para conexiones', 'ingreso', 13::numeric, 44::numeric, 57::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0088', 'usuario1', '2026-08-29T17:14:55.905Z'::timestamptz, 9320::numeric, 5.993569::numeric, 1555::numeric, '2026-08-26T11:30:04.589-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-030', 'Abrazadera para poste', 'consumo', -103::numeric, 277::numeric, 174::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0055', 'usuario2', '2026-08-30T12:32:59.610Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-035', 'Mecha para metal', 'consumo', -33::numeric, 42::numeric, 9::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0075', 'usuario1', '2026-08-30T13:54:47.437Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-033', 'Arandela plana galvanizada', 'ingreso', 111::numeric, 238::numeric, 349::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0144', 'usuario1', '2026-08-30T18:38:45.548Z'::timestamptz, 90::numeric, 0.057878::numeric, 1555::numeric, '2026-08-26T11:30:04.589-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-002', 'Lampara de senalizacion LED', 'ingreso', 36::numeric, 65::numeric, 101::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0010', 'usuario1', '2026-08-31T17:34:58.480Z'::timestamptz, 5400::numeric, 3.461538::numeric, 1560::numeric, '2026-08-31T12:02:02.096-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-021', 'Bornera de conexion', 'ingreso', 63::numeric, 77::numeric, 140::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0078', 'usuario2', '2026-08-31T18:32:44.608Z'::timestamptz, 1220::numeric, 0.784566::numeric, 1555::numeric, '2026-08-31T14:58:01.816-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-026', 'Pintura vial blanca', 'ingreso', 11::numeric, 25::numeric, 36::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0100', 'usuario1', '2026-09-01T09:46:17.704Z'::timestamptz, 54030::numeric, 34.745981::numeric, 1555::numeric, '2026-08-31T14:58:01.816-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-007', 'Sensor de velocidad', 'consumo', -44::numeric, 73::numeric, 29::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0013', 'usuario2', '2026-09-02T02:11:30.057Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-022', 'Cable subterraneo multipolar', 'consumo', -166::numeric, 189::numeric, 23::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0041', 'usuario1', '2026-09-03T00:43:10.856Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-025', 'Pintura vial amarilla', 'consumo', -38::numeric, 41::numeric, 3::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0047', 'usuario2', '2026-09-04T01:03:43.925Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-011', 'Tacha reflectiva vial', 'ingreso', 53::numeric, 135::numeric, 188::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0045', 'usuario1', '2026-09-04T12:34:15.778Z'::timestamptz, 2680::numeric, 1.734628::numeric, 1545::numeric, '2026-09-03T11:30:02.070-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-032', 'Tuerca autofrenante', 'ingreso', 51::numeric, 427::numeric, 478::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0134', 'usuario1', '2026-09-04T14:01:59.029Z'::timestamptz, 230::numeric, 0.148867::numeric, 1545::numeric, '2026-09-03T11:30:02.070-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-006', 'Conector estanco', 'consumo', -50::numeric, 57::numeric, 7::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0012', 'usuario2', '2026-09-06T18:03:21.070Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-028', 'Cartel reglamentario metalico', 'consumo', -30::numeric, 37::numeric, 7::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0052', 'usuario2', '2026-09-07T20:46:55.735Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-010', 'Cartel desvio transitorio', 'consumo', -30::numeric, 39::numeric, 9::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0018', 'usuario2', '2026-09-17T22:45:22.611Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-031', 'Tornillo galvanizado', 'ingreso', 63::numeric, 613::numeric, 676::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0125', 'usuario1', '2026-09-18T05:23:39.016Z'::timestamptz, 170::numeric, 0.109325::numeric, 1555::numeric, '2026-09-17T11:25:03.443-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-005', 'Soporte galvanizado para cartel', 'consumo', -52::numeric, 71::numeric, 19::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0011', 'usuario2', '2026-09-21T20:44:52.824Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-004', 'Chaleco reflectivo', 'consumo', -34::numeric, 50::numeric, 16::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0009', 'usuario1', '2026-09-22T01:12:09.021Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-019', 'Modulo controlador de semaforo', 'consumo', -10::numeric, 12::numeric, 2::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0034', 'usuario1', '2026-09-23T02:59:20.773Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-001', 'Fusible industrial', 'ingreso', 49::numeric, 94::numeric, 143::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0006', 'usuario2', '2026-09-24T00:16:02.377Z'::timestamptz, 720::numeric, 0.463023::numeric, 1555::numeric, '2026-09-23T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-015', 'Anteojos de seguridad', 'consumo', -39::numeric, 60::numeric, 21::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0029', 'usuario1', '2026-09-24T09:16:33.311Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-027', 'Microesferas de vidrio', 'consumo', -40::numeric, 66::numeric, 26::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0051', 'usuario1', '2026-09-25T04:25:31.259Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-033', 'Arandela plana galvanizada', 'consumo', -230::numeric, 349::numeric, 119::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0071', 'usuario1', '2026-09-26T03:00:18.062Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-023', 'Caja estanca para conexiones', 'consumo', -43::numeric, 57::numeric, 14::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0043', 'usuario1', '2026-09-27T02:26:40.215Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-011', 'Tacha reflectiva vial', 'consumo', -119::numeric, 188::numeric, 69::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0022', 'usuario1', '2026-09-27T04:44:47.125Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-038', 'Bornera para tablero de semaforo', 'ingreso', 20::numeric, 3::numeric, 23::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0166', 'usuario1', '2026-09-28T07:41:46.379Z'::timestamptz, 3870::numeric, 2.480769::numeric, 1560::numeric, '2026-09-24T18:00:00.000-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-031', 'Tornillo galvanizado', 'consumo', -153::numeric, 676::numeric, 523::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0060', 'usuario1', '2026-10-03T10:08:26.507Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-020', 'Fuente de alimentacion 24V', 'consumo', -30::numeric, 36::numeric, 6::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0035', 'usuario2', '2026-10-05T10:47:04.735Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-032', 'Tuerca autofrenante', 'consumo', -181::numeric, 478::numeric, 297::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0064', 'usuario2', '2026-10-05T19:41:19.500Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-007', 'Sensor de velocidad', 'consumo', -26::numeric, 29::numeric, 3::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0014', 'usuario2', '2026-10-05T23:13:04.026Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-033', 'Arandela plana galvanizada', 'ingreso', 111::numeric, 119::numeric, 230::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0145', 'usuario1', '2026-10-06T17:58:49.316Z'::timestamptz, 90::numeric, 0.058252::numeric, 1545::numeric, '2026-10-06T11:10:58.848-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-017', 'Protector auditivo', 'ingreso', 11::numeric, 6::numeric, 17::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0066', 'usuario2', '2026-10-08T12:14:35.266Z'::timestamptz, 7570::numeric, 4.868167::numeric, 1555::numeric, '2026-10-07T11:49:02.003-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-013', 'Lamina reflectiva grado ingenieria', 'consumo', -60::numeric, 82::numeric, 22::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0026', 'usuario2', '2026-10-09T05:09:01.883Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-037', 'Cinta aisladora', 'consumo', -66::numeric, 107::numeric, 41::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0079', 'usuario1', '2026-10-10T03:40:31.783Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-024', 'Prensaestopa industrial', 'consumo', -73::numeric, 105::numeric, 32::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0045', 'usuario2', '2026-10-10T05:01:24.744Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-035', 'Mecha para metal', 'ingreso', 9::numeric, 9::numeric, 18::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0154', 'usuario2', '2026-10-10T11:15:48.214Z'::timestamptz, 4330::numeric, 2.811688::numeric, 1540::numeric, '2026-10-08T15:53:30.471-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-030', 'Abrazadera para poste', 'consumo', -117::numeric, 174::numeric, 57::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0056', 'usuario2', '2026-10-11T06:57:39.662Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-018', 'Tablero de control vial', 'consumo', -20::numeric, 24::numeric, 4::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0033', 'usuario2', '2026-10-12T17:36:15.417Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-002', 'Lampara de senalizacion LED', 'consumo', -77::numeric, 101::numeric, 24::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0005', 'usuario1', '2026-10-13T11:58:52.014Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-008', 'Cono vial 70 cm', 'ingreso', 32::numeric, 6::numeric, 38::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0033', 'usuario1', '2026-10-13T16:36:44.893Z'::timestamptz, 18720::numeric, 12.038585::numeric, 1555::numeric, '2026-10-13T11:47:37.032-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-009', 'Cinta reflectiva roja y blanca', 'consumo', -50::numeric, 61::numeric, 11::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0017', 'usuario1', '2026-10-14T02:33:48.453Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-025', 'Pintura vial amarilla', 'ingreso', 10::numeric, 3::numeric, 13::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0096', 'usuario1', '2026-10-16T09:30:19.113Z'::timestamptz, 55690::numeric, 36.045307::numeric, 1545::numeric, '2026-10-15T11:50:33.034-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-003', 'Guantes de proteccion', 'consumo', -109::numeric, 154::numeric, 45::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0007', 'usuario1', '2026-10-16T23:22:27.266Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-034', 'Disco de corte para amoladora', 'ingreso', 21::numeric, 6::numeric, 27::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0150', 'usuario1', '2026-10-17T04:12:37.069Z'::timestamptz, 2800::numeric, 1.800643::numeric, 1555::numeric, '2026-10-16T17:15:37.572-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-031', 'Tornillo galvanizado', 'consumo', -263::numeric, 523::numeric, 260::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0061', 'usuario1', '2026-10-17T04:16:39.546Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-011', 'Tacha reflectiva vial', 'ingreso', 76::numeric, 69::numeric, 145::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0046', 'usuario1', '2026-10-18T11:30:59.007Z'::timestamptz, 2810::numeric, 1.807074::numeric, 1555::numeric, '2026-10-16T17:15:37.572-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-029', 'Poste galvanizado', 'consumo', -28::numeric, 39::numeric, 11::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0054', 'usuario1', '2026-10-19T18:07:42.243Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-001', 'Fusible industrial', 'consumo', -63::numeric, 143::numeric, 80::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0003', 'usuario2', '2026-10-20T02:28:10.614Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-022', 'Cable subterraneo multipolar', 'ingreso', 63::numeric, 23::numeric, 86::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0084', 'usuario2', '2026-10-22T09:39:07.431Z'::timestamptz, 6090::numeric, 3.891374::numeric, 1565::numeric, '2026-10-21T16:20:30.695-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta'),
    ('MAT-036', 'Precinto UV reforzado', 'consumo', -52::numeric, 85::numeric, 33::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0077', 'usuario1', '2026-10-23T13:01:00.259Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-021', 'Bornera de conexion', 'consumo', -76::numeric, 140::numeric, 64::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0038', 'usuario2', '2026-10-23T23:41:39.774Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-012', 'Delineador flexible', 'consumo', -24::numeric, 42::numeric, 18::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0024', 'usuario2', '2026-10-24T11:37:55.888Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-026', 'Pintura vial blanca', 'consumo', -26::numeric, 36::numeric, 10::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0049', 'usuario2', '2026-10-25T11:41:39.333Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-032', 'Tuerca autofrenante', 'consumo', -112::numeric, 297::numeric, 185::numeric, 'Material utilizado en mantenimiento vial', 'OT-2026-0065', 'usuario1', '2026-10-28T15:02:16.177Z'::timestamptz, null::numeric, null::numeric, null::numeric, null::timestamptz, null::text),
    ('MAT-033', 'Arandela plana galvanizada', 'ingreso', 80::numeric, 230::numeric, 310::numeric, 'Recepción de reposición del proveedor', 'OC-2026-0146', 'usuario2', '2026-10-29T21:16:57.948Z'::timestamptz, 90::numeric, 0.057508::numeric, 1565::numeric, '2026-10-28T14:45:57.833-03:00'::timestamptz, 'MonedAPI · histórico USD/BLUE · venta')
)
insert into public.inventory_movements
  (item_id,sku,item_name,tipo,cantidad,stock_antes,stock_despues,nota,referencia,actor,created_at,
   precio_unitario_ars,precio_unitario_usd,cotizacion_blue,cotizacion_fecha,cotizacion_fuente)
select i.id,m.sku,m.item_name,m.tipo,m.cantidad,m.stock_antes,m.stock_despues,m.nota,m.referencia,m.actor,m.created_at,
       m.precio_unitario_ars,m.precio_unitario_usd,m.cotizacion_blue,m.cotizacion_fecha,m.cotizacion_fuente
from movement_data m
join public.inventory_items i on i.sku=m.sku;

update public.inventory_items as i
set stock=v.stock, costo_unitario=v.costo_unitario, costo_promedio_usd=v.costo_promedio_usd,
    cotizacion_blue_base=v.cotizacion_blue_base, updated_at=now()
from (values
    ('MAT-001', 80::numeric, 720::numeric, 0.465542::numeric, 1555::numeric),
    ('MAT-002', 24::numeric, 5400::numeric, 3.246184::numeric, 1560::numeric),
    ('MAT-003', 45::numeric, 5920::numeric, 3.731963::numeric, 1560::numeric),
    ('MAT-004', 16::numeric, 13860::numeric, 8.922628::numeric, 1555::numeric),
    ('MAT-005', 19::numeric, 9160::numeric, 5.651924::numeric, 1560::numeric),
    ('MAT-006', 7::numeric, 3000::numeric, 1.911248::numeric, 1510::numeric),
    ('MAT-007', 3::numeric, 41750::numeric, 27.839537::numeric, 1450::numeric),
    ('MAT-008', 38::numeric, 18720::numeric, 11.815909::numeric, 1555::numeric),
    ('MAT-009', 11::numeric, 20740::numeric, 13.347202::numeric, 1520::numeric),
    ('MAT-010', 9::numeric, 36640::numeric, 23.294362::numeric, 1495::numeric),
    ('MAT-011', 145::numeric, 2810::numeric, 1.751897::numeric, 1555::numeric),
    ('MAT-012', 18::numeric, 30210::numeric, 18.730782::numeric, 1555::numeric),
    ('MAT-013', 22::numeric, 41060::numeric, 25.578015::numeric, 1545::numeric),
    ('MAT-014', 12::numeric, 16790::numeric, 11.816407::numeric, 1405::numeric),
    ('MAT-015', 21::numeric, 8460::numeric, 5.389491::numeric, 1545::numeric),
    ('MAT-016', 8::numeric, 59900::numeric, 40.226803::numeric, 1435::numeric),
    ('MAT-017', 17::numeric, 7570::numeric, 4.662687::numeric, 1555::numeric),
    ('MAT-018', 4::numeric, 158410::numeric, 107.41221::numeric, 1435::numeric),
    ('MAT-019', 2::numeric, 280290::numeric, 191.432092::numeric, 1445::numeric),
    ('MAT-020', 6::numeric, 30760::numeric, 20.972781::numeric, 1435::numeric),
    ('MAT-021', 64::numeric, 1220::numeric, 0.769507::numeric, 1555::numeric),
    ('MAT-022', 86::numeric, 6090::numeric, 3.84542::numeric, 1565::numeric),
    ('MAT-023', 14::numeric, 9320::numeric, 5.823242::numeric, 1555::numeric),
    ('MAT-024', 32::numeric, 2120::numeric, 1.367732::numeric, 1530::numeric),
    ('MAT-025', 13::numeric, 55690::numeric, 35.621901::numeric, 1545::numeric),
    ('MAT-026', 10::numeric, 54030::numeric, 33.952352::numeric, 1555::numeric),
    ('MAT-027', 26::numeric, 21360::numeric, 13.501124::numeric, 1535::numeric),
    ('MAT-028', 7::numeric, 68420::numeric, 44.541941::numeric, 1515::numeric),
    ('MAT-029', 11::numeric, 61100::numeric, 38.092672::numeric, 1525::numeric),
    ('MAT-030', 57::numeric, 1670::numeric, 1.099331::numeric, 1510::numeric),
    ('MAT-031', 260::numeric, 170::numeric, 0.109982::numeric, 1555::numeric),
    ('MAT-032', 185::numeric, 230::numeric, 0.147431::numeric, 1545::numeric),
    ('MAT-033', 310::numeric, 90::numeric, 0.058582::numeric, 1565::numeric),
    ('MAT-034', 27::numeric, 2800::numeric, 1.776305::numeric, 1555::numeric),
    ('MAT-035', 18::numeric, 4330::numeric, 2.734368::numeric, 1540::numeric),
    ('MAT-036', 33::numeric, 3810::numeric, 2.327858::numeric, 1545::numeric),
    ('MAT-037', 41::numeric, 1850::numeric, 1.131241::numeric, 1560::numeric),
    ('MAT-038', 23::numeric, 3870::numeric, 2.455405::numeric, 1560::numeric),
    ('MAT-039', 9::numeric, 13190::numeric, 9.237908::numeric, 1430::numeric)
) as v(sku,stock,costo_unitario,costo_promedio_usd,cotizacion_blue_base)
where i.sku=v.sku;

notify pgrst, 'reload schema';
commit;

select tipo, count(*) as cantidad
from public.inventory_movements
group by tipo
order by tipo;
