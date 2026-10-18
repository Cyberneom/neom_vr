# Perfil y muro de VRlizate

`VrEcosystemProfilePage` muestra el perfil del `UserService` compartido por la
sesión y delega su cierre en `VrEcosystemSession.signOut`. El contenido deja de
mostrarse cuando cambia la identidad.

`VrEcosystemSocialPage` utiliza `NeomVrEcosystemSocialSource`, que adapta los
controladores existentes de `neom_timeline` y `neom_posts`. Cada sala tiene su
propio `TimelineController(sessionManaged: true)` y un `PostUploadController`
temporal; no registra ni reemplaza un controlador global del muro. El callback
`onPostCreated` confirma el guardado sin disparar la navegación global de SINT.

`VrPostsAccountLease` comparte el almacenamiento entre salas de la misma
identidad. Cerrar una sala no invalida las otras; el último propietario libera
el ámbito y una sala antigua no puede reiniciar la cuenta o perfil que la
reemplazó. El adaptador toma prestado `AppHiveService` si existe, o inicializa
Hive y registra su propio servicio; solo elimina el servicio que él creó una
vez que no queden prestatarios.

Los borradores pertenecen a la página activa. Un cambio de cuenta o cierre de
sesión los borra, oculta las publicaciones y descarta respuestas tardías.
Un fallo de guardado conserva el texto para reintentar. La interfaz diferencia
el guardado local del envío: las entradas pendientes muestran su estado y el
botón Actualizar reintenta la cola mediante `PostsSyncService`. Este adaptador
no inicia un sincronizador global ni promete entrega automática en segundo
plano.

Validación local: análisis Dart limpio y 8 pruebas aprobadas en
`test/ecosystem_social_test.dart`, con concurrencia 1. Cubren dos préstamos
simultáneos sobre `PostsHiveController` real, reemplazo de cuenta/perfil,
envíos duplicados, respuestas tardías, borradores, reintento, perfil y cierre
de sesión. Los widgets usan fuentes simuladas; no se enviaron publicaciones
a Firebase ni se verificó entrega real con una cuenta remota.
