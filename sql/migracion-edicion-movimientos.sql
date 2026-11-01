-- Permite corregir la referencia y el detalle de movimientos sin alterar cantidades ni saldos de stock.
-- Ejecutar una sola vez en Supabase > SQL Editor.

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
