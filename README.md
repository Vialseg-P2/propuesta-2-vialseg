# Vialseg · Gestión de inventario

Sitio web independiente para administrar existencias, movimientos y sugerencias de reposición. No modifica ni depende del sitio de planificación de recorridos.

## Publicar en Vercel

1. Subir el contenido de esta carpeta a un repositorio GitHub propio.
2. En Vercel, importar ese repositorio.
3. Dejar **Root Directory** en `./`.
4. Elegir **Other** como preset, `npm run build` como comando de compilación y `dist` como carpeta de salida.
5. Para habilitar usuarios y datos compartidos, configurar `SUPABASE_URL` y `SUPABASE_PUBLISHABLE_KEY` en Vercel. Si el proyecto Supabase es antiguo, la clave puede llamarse `SUPABASE_ANON_KEY`.

Sin esas variables, la aplicación permite entrar en modo demostración con datos ficticios guardados solo en ese navegador.

## Preparar Supabase para uso compartido

1. Crear un proyecto Supabase separado del que se use para recorridos.
2. Ejecutar `sql/schema.sql` desde **SQL Editor**. Si la base ya estaba creada, ejecutar `sql/migracion-costos-compra-usd.sql` si todavía no se aplicó. Para habilitar la edición de referencias y detalles de movimientos, ejecutar también `sql/migracion-edicion-movimientos.sql`.
3. Desactivar el registro público en **Authentication** y crear las cuentas autorizadas.
4. Incorporar cada cuenta a `public.inventory_members` con el rol `admin` o `deposito`.

### Cuentas con nombre de usuario

La pantalla pide un nombre de usuario. Para autenticarlo con Supabase, la aplicación lo convierte internamente en una dirección de correo de inicio de sesión: `usuario1` corresponde a `usuario1@vialseg-inventario.example.com`. Creá la cuenta desde **Authentication → Users** con esa dirección y una contraseña segura; no hace falta que exista una casilla de correo. Repetí el patrón para cada usuario y habilitalos en `inventory_members`. La aplicación no permite registrarse públicamente.

La clave publicable/anon puede usarse en el navegador porque las políticas RLS del esquema restringen el acceso. Nunca usar una clave `service_role` en esta página.

### Edición del historial

En el historial se pueden corregir la referencia y el detalle de un movimiento. La cantidad, el tipo y los saldos se conservan para no alterar el historial de stock. La referencia es un dato opcional que identifica un comprobante asociado, por ejemplo una orden de compra (OC), orden de trabajo (OT), factura o ticket.

## Cálculos incluidos

- Punto de reposición = stock de seguridad + consumo diario promedio × plazo de entrega en días. El consumo diario se estima como consumo mensual / 30.
- La sugerencia busca llegar al punto de reposición más un lote, redondeando al múltiplo configurado.
- El costo de cada ingreso se registra en ARS y su conversión a USD se guarda junto con la cotización blue vendedora informada por DolarAPI. El valor actual del stock usa el costo promedio ponderado en USD. La clasificación ABC usa el valor anual de consumo: consumo mensual × 12 × costo promedio unitario en USD. A llega hasta 80% acumulado, B hasta 95% y C comprende el resto.
- Los insumos marcados como “No se repone” aparecen en seguimiento y no generan sugerencias automáticas.

Los registros de ejemplo son ficticios. Reemplazarlos por datos verificados antes de tomar decisiones de compra.


## Evolución de precios

La pestaña **Costos** grafica por material cada precio unitario de ingreso registrado, en ARS y USD. El dato en USD se calcula con la cotización blue vendedora obtenida al registrar el ingreso; se conserva la cotización y su fecha para explicar la conversión. Los movimientos anteriores a esta mejora no tienen un precio histórico y no aparecerán en esos gráficos.
