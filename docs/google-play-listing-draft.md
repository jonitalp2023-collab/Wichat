# Google Play — ficha preliminar de ChatArgentina

Estado: borrador de preparación; no es una declaración enviada a Google Play.
Última revisión: 23 de noviembre de 2026.

## Datos base verificados en el proyecto

- Nombre público: ChatArgentina
- Identificador Android: `com.wichat.app`
- Versión Android revisada: `1.6` (versionCode `7`)
- SDK objetivo configurado: Android 36
- Edad mínima declarada en la aplicación y sus políticas: 18 años
- Responsable y contacto: Jonatan Alvarez — jonitalp2023@gmail.com
- Sitio y políticas: se deben verificar las URLs públicas de GitHub Pages antes de copiarlas a Play Console.

## Ficha de tienda — texto propuesto

### Nombre (13/30)
ChatArgentina

### Descripción breve (propuesta)
Conectate y conversá con personas de Argentina en salas y mensajes privados.

### Descripción completa (propuesta)
¡Los chats volvieron! 🇦🇷

ChatArgentina es un espacio para conectarte y conversar con personas de distintos lugares del país. Sumate a salas públicas, participá de charlas y mantené conversaciones privadas desde tu celular.

¿Qué podés hacer?
• Participar en salas públicas y conocer comunidades.
• Enviar mensajes privados.
• Compartir mensajes de voz en salas y conversaciones privadas.
• Crear y personalizar tu perfil.
• Bloquear usuarios y denunciar mensajes o cuentas que incumplan las normas.
• Recibir notificaciones cuando estén habilitadas en tu dispositivo.

ChatArgentina está destinada exclusivamente a personas mayores de 18 años. Antes de usarla, leé y aceptá los términos y las normas de convivencia. Utilizá las herramientas de bloqueo y denuncia para ayudar a mantener un espacio respetuoso.

Contacto: jonitalp2023@gmail.com

### Categoría sugerida
Social

### Etiquetas sugeridas
Chat, comunicación, comunidades, Argentina, mensajes

## Enlaces legales que deben comprobarse públicamente

- Política de privacidad: `/privacy-policy.html`
- Solicitud de eliminación de cuenta: `/delete-account.html`
- Normas de seguridad infantil: `/child-safety-standards.html`
- Términos y condiciones: `/terms.html`

No pegar rutas relativas en Play Console: reemplazarlas por las URLs HTTPS públicas definitivas y probarlas sin iniciar sesión.

## Material gráfico pendiente para la ficha

- Icono de tienda: 512 × 512 px, PNG de alta calidad, sin transparencias innecesarias.
- Imagen destacada: 1024 × 500 px.
- Capturas reales de la app en teléfono: preparar al menos 2; recomendadas 4–6, sin datos personales ni conversaciones reales identificables.
- Revisar que las capturas correspondan a la versión que se va a publicar.

## Declaraciones que requieren completar/verificar en Play Console

1. Seguridad de los datos: declarar con exactitud los datos recogidos/compartidos por la app y los proveedores (incluidos Supabase y Firebase), finalidades, cifrado y controles de eliminación. No completar por suposición.
2. Acceso a la app: proporcionar instrucciones y credenciales de revisión si Google necesita una cuenta para entrar; nunca publicar contraseñas en este repositorio.
3. Clasificación de contenido: completar el cuestionario de clasificación de contenido con las funciones y contenido reales.
4. Público objetivo: configurar de acuerdo con la restricción de uso exclusivo para mayores de 18 años.
5. Anuncios: confirmar si la app muestra anuncios antes de declarar esta sección.
6. Permisos: justificar el uso del micrófono para grabar mensajes de voz y las notificaciones para avisos, según el comportamiento real.
7. Moderación: comprobar que bloqueo, denuncia, revisión de reportes y normas publicadas funcionan como se describen.
8. Eliminación de cuenta: probar tanto el flujo dentro de la app como el formulario web y confirmar que las solicitudes se procesan realmente.

## Control técnico antes de subir

- Volver a generar el AAB de producción desde el commit definitivo.
- Verificar que el AAB está firmado con la clave de subida correcta y conservar una copia segura de la clave.
- Confirmar que versionCode sea mayor que el de cualquier versión ya cargada en Play Console.
- Probar el AAB en una pista interna y comprobar inicio de sesión, salas, mensajes privados, audio, notificaciones, bloqueo, denuncias y eliminación de cuenta.
- Revisar consistencia entre la versión Android, la versión web y la política de privacidad (incluida la retención/eliminación de audios).

## Pendientes que impiden marcar la ficha como lista

- Confirmar URLs HTTPS públicas de todas las páginas legales.
- Revisar y alinear la política de privacidad con la retención real de audios (incluida la eliminación automática a los 7 días si ya está activa).
- Crear/seleccionar icono, banner y capturas definitivas.
- Confirmar anuncios, datos recogidos/compartidos y credenciales de revisión.
- Completar las declaraciones y formularios dentro de Play Console una vez creada la cuenta.

Este archivo es una guía interna de preparación. La información final debe reflejar el comportamiento real de la aplicación y verificarse antes de enviarla a Google.
