# CHAT ARGENTINA — respaldo técnico

Fecha de corte: 2026-11-16

## Qué contiene
- Código fuente Android y WebView del repositorio.
- Frontend completo de CHAT ARGENTINA de la rama de desarrollo.
- Configuración de compilación Gradle y flujos de GitHub Actions.
- Documentación SQL existente.
- Catálogo de esquema de Supabase: tablas, columnas, tipos, valores por defecto, restricciones, claves, índices, políticas RLS, funciones PostgreSQL, vistas, triggers y extensiones.
- Código fuente de las Edge Functions activas: Chat-Bot, admin-api y bright-processor.
- Inventario de migraciones aplicadas y metadatos del proyecto.

## Qué NO contiene
- Filas de usuarios, perfiles, mensajes públicos o privados.
- Cuentas ni sesiones de Supabase Auth.
- Denuncias, registros de moderación o datos de actividad.
- Objetos ni archivos de Storage.
- Secretos, service_role keys, tokens, contraseñas ni PIN en texto claro.

## Acceso root de UNIX
El respaldo conserva el código y el esquema que implementan el acceso administrativo de UNIX, incluidas las funciones de verificación de PIN y las tablas/columnas relacionadas. Por seguridad no se exporta el PIN ni su hash ni la cuenta de autenticación del administrador.

Para recuperar el acceso después de restaurar en otro proyecto:
1. Restaurar el esquema y las funciones desde el catálogo SQL/JSON y las migraciones documentadas.
2. Crear o recuperar por separado la cuenta de Supabase Auth que utiliza el administrador.
3. Volver a configurar el PIN administrativo mediante el procedimiento seguro vigente del proyecto. No reutilizar un PIN dentro de archivos públicos.
4. Verificar que el usuario administrador tenga su autorización en las tablas de administración correspondientes.

## Proyecto y ramas
- Repositorio: https://github.com/jonitalp2023-collab/Wichat
- Rama de origen: feature/chat-argentina-expansion
- Rama de respaldo: backup/chat-argentina-2026-11-16
- Proyecto Supabase: pqnnzkqxkndzelsbtxvv (Wi chat), región us-east-1.

## Advertencias
Este respaldo es de código y metadatos de esquema, no un clon ejecutable de producción. Las variables secretas, credenciales de proveedor, configuración de Auth, DNS, dominios y archivos de Storage deben configurarse de nuevo en un entorno de restauración. No contiene datos de conversaciones ni información personal de usuarios.
