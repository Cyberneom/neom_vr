# neom_vr

Módulo de Realidad Virtual para aplicaciones del ecosistema **Open Neom**, con visores panorámicos 360° y puente de sesiones de renderizado entre [`vrlizate`](../vrlizate/README.md) y [`sint`](../../framework/sint/README.md).

> Versión actual: **1.4.0**. Consulta [CHANGELOG.md](CHANGELOG.md) para el historial de cambios.

## Características principales

- **Puente de sesiones con SINT (`package:neom_vr/neom_vr_sessions.dart`):**
  - `NeomVrSessionController` envuelve `VrSessionController` de `vrlizate` y refleja su estado en variables reactivas de SINT sin duplicar la máquina de estados del motor.
  - `NeomVrSessionHost` envuelve `VrSessionHost` con registro único por etiqueta (`registrationTag`) y limpieza segura al desmontar.
  - Incluye `VRBindings`, `VRController`, `VRSceneState`, `VRNavigator`, `VRRoutes` y traducciones VR consolidadas desde el antiguo `sint_vr`.
- **Visores 360° y Estéreo (`package:neom_vr/neom_vr.dart`):**
  - Motor de proyección equirectangular con `CustomPainter` (`NeomVr360Engine`).
  - Navegación por sensores IMU (acelerómetro/giroscopio) y pantalla dividida para visores tipo Cardboard.

## Instalación

```yaml
dependencies:
  neom_vr:
    git:
      url: git@github.com:Cyberneom/neom_vr.git
```

## Uso básico

### Host de sesión VR con SINT

```dart
import 'package:neom_vr/neom_vr_sessions.dart';

NeomVrSessionHost(
  adapter: adapter,
  builder: (context, controller, active) {
    return buildRenderer(context, active);
  },
);
```

### Rutas 360° y estéreo

```dart
import 'package:neom_vr/neom_vr.dart';

Navigator.pushNamed(context, VRRoutes.spatial360);
Navigator.pushNamed(context, VRRoutes.vrStereo);
```

## Verificación

```sh
flutter analyze
flutter test
```

## Licencia

Apache License 2.0 — consulta [LICENSE](LICENSE).
