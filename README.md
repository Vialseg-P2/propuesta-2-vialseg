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
2. Ejecutar `sql/schema.sql` desde **SQL Editor**.
3. Desactivar el registro público en **Authentication** y crear las cuentas autorizadas.
4. Incorporar cada cuenta a `public.inventory_members` con el rol `admin` o `deposito`.

### Cuentas con nombre de usuario

La pantalla pide un nombre de usuario. Para autenticarlo con Supabase, la aplicación lo convierte internamente en una dirección de correo de inicio de sesión: `usuario1` corresponde a `usuario1@vialseg-inventario.example.com`. Creá la cuenta desde **Authentication → Users** con esa dirección y una contraseña segura; no hace falta que exista una casilla de correo. Repetí el patrón para cada usuario y habilitalos en `inventory_members`. La aplicación no permite registrarse públicamente.

La clave publicable/anon puede usarse en el navegador porque las políticas RLS del esquema restringen el acceso. Nunca usar una clave `service_role` en esta página.

## Cálculos incluidos

- Punto de reposición = stock de seguridad + consumo diario promedio × plazo de entrega en días. El consumo diario se estima como consumo mensual / 30.
- La sugerencia busca llegar al punto de reposición más un lote, redondeando al múltiplo configurado.
- La clasificación ABC usa el valor anual de consumo: consumo mensual × 12 × costo unitario. A llega hasta 80% acumulado, B hasta 95% y C comprende el resto.
- Los insumos marcados como “No se repone” aparecen en seguimiento y no generan sugerencias automáticas.

Los registros de ejemplo son ficticios. Reemplazarlos por datos verificados antes de tomar decisiones de compra.
