import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_scene/vrlizate_scene.dart';

import 'vr_spatial_tracking_service.dart';
import 'vr_tri_camera_live_inspector_card.dart';

Future<void> openVrSpatialTrackingSettings(BuildContext context) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/spatial-tracking-settings'),
        builder: (_) => const VrSpatialTrackingSettingsPage(),
      ),
    );

/// Both eye viewports receive the same non-interactive fallback status.
class VrSpatialTrackingStatusOverlay extends StatelessWidget {
  const VrSpatialTrackingStatusOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final service = VrSpatialSettingsScope.maybeOf(context);
    if (service == null ||
        !service.enabled ||
        !service.hasVisibleScene ||
        service.tracking) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: StereoHudOverlay(
        alignment: const Alignment(0, -.5),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 235),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            service.statusText,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ),
      ),
    );
  }
}

class VrSpatialTrackingSettingsButton extends StatelessWidget {
  const VrSpatialTrackingSettingsButton({super.key});

  @override
  Widget build(BuildContext context) {
    final service = VrSpatialSettingsScope.maybeOf(context);
    if (service == null) return const SizedBox.shrink();
    return OutlinedButton.icon(
      key: const ValueKey('spatial_tracking_settings'),
      onPressed: () => openVrSpatialTrackingSettings(context),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: const Size(0, 28),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        textStyle: const TextStyle(fontSize: 11),
      ),
      icon: const Icon(Icons.view_in_ar_outlined, size: 15),
      label: Text(service.enabled ? 'Sensado · activado' : 'Cámaras y sensado'),
    );
  }
}

class VrSpatialTrackingSettingsPage extends StatelessWidget {
  const VrSpatialTrackingSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = VrSpatialSettingsScope.maybeOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Cámaras y sensado del visor')),
      body: service == null
          ? const Center(child: Text('Seguimiento espacial no disponible'))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                VrTriCameraLiveInspectorCard(service: service),
                const SizedBox(height: 18),
                SwitchListTile.adaptive(
                  key: const ValueKey('spatial_tracking_switch'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Seguimiento espacial experimental'),
                  subtitle: const Text(
                    'Inclinarte y desplazarte cambia tu posición en la escena.',
                  ),
                  value: service.enabled,
                  onChanged: service.enabling
                      ? null
                      : (enabled) async {
                          if (enabled) {
                            await service.enable();
                          } else {
                            await service.disable();
                          }
                        },
                ),
                const SizedBox(height: 8),
                Semantics(liveRegion: true, child: Text(service.statusText)),
                const SizedBox(height: 16),
                const Text(
                  'La cámara trasera debe quedar descubierta y ver un entorno iluminado '
                  'con detalles. Se utiliza al abrir el visor; no se guardan fotografías. '
                  'Si se pierde la referencia, continúan la orientación y el mando.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Este modo sigue la cabeza. Las manos y el cuerpo todavía no tienen '
                  'posición física medida. No incluye detección de obstáculos.',
                ),
                const Divider(height: 40),
                Text(
                  'Montaje de cámara y ojos',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Indica dónde queda el centro entre tus ojos respecto a la cámara '
                  'con el teléfono colocado en horizontal. Los valores iniciales de '
                  'cero no representan una calibración de tu visor. '
                  'Al cambiar el montaje, vuelve a revisar estas medidas.',
                ),
                const SizedBox(height: 12),
                for (var axis = 0; axis < 3; axis++)
                  _MountOffsetSlider(service: service, axis: axis),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () =>
                        service.setCameraToEyeTranslation(vm.Vector3.zero()),
                    child: const Text('Restablecer desplazamientos'),
                  ),
                ),
                const Text(
                  'La distancia entre ojos y los ajustes ópticos se configuran en '
                  'Calibración del visor. Este ajuste supone la cámara alineada '
                  'con la pantalla; un soporte inclinado requiere calibración adicional.',
                ),
              ],
            ),
    );
  }
}

class _MountOffsetSlider extends StatelessWidget {
  const _MountOffsetSlider({required this.service, required this.axis});
  final VrSpatialTrackingService service;
  final int axis;

  @override
  Widget build(BuildContext context) {
    final offset = service.cameraToEyeTranslation;
    final millimeters = offset[axis] * 1000;
    final label = const [
      'Horizontal · positivo hacia la derecha',
      'Vertical · positivo hacia arriba',
      'Profundidad · positivo hacia tus ojos',
    ][axis];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${millimeters.round()} mm'),
        Slider(
          key: ValueKey('camera_eye_offset_$axis'),
          min: -200,
          max: 200,
          divisions: 400,
          value: millimeters,
          label: '${millimeters.round()} mm',
          onChanged: (value) {
            offset[axis] = value / 1000;
            service.setCameraToEyeTranslation(offset);
          },
        ),
      ],
    );
  }
}
