import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_scene/vrlizate_scene.dart';

import '../beacon/vr_desktop_beacon_models.dart';
import '../beacon/vr_desktop_beacon_page.dart';
import '../beacon/vr_desktop_beacon_wire.dart';
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
      label: Text(
        service.beaconConnected
            ? 'Sensado · Faro IA'
            : (service.enabled ? 'Sensado · activado' : 'Cámaras y sensado'),
      ),
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
                const SizedBox(height: 16),
                _DesktopBeaconSettingsCard(service: service),
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

class _DesktopBeaconSettingsCard extends StatefulWidget {
  const _DesktopBeaconSettingsCard({required this.service});
  final VrSpatialTrackingService service;

  @override
  State<_DesktopBeaconSettingsCard> createState() =>
      _DesktopBeaconSettingsCardState();
}

class _DesktopBeaconSettingsCardState
    extends State<_DesktopBeaconSettingsCard> {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _inviteLinkController = TextEditingController();
  VrDiscoveredDesktopBeacon? _selectedStation;

  @override
  void dispose() {
    _pinController.dispose();
    _inviteLinkController.dispose();
    super.dispose();
  }

  Future<void> _connectSelected() async {
    final client = widget.service.beaconClient;
    final rawInvite = _inviteLinkController.text.trim();
    if (rawInvite.isNotEmpty) {
      final invite = VrDesktopBeaconPairingInvite.tryParse(rawInvite);
      if (invite == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('El enlace vrlizate://beacon no es válido.'),
          ),
        );
        return;
      }
      await client.connectWithInvite(invite);
      return;
    }

    final station =
        _selectedStation ??
        (client.discoveredStations.isNotEmpty
            ? client.discoveredStations.first
            : null);
    if (station == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Primero pulsa «Buscar en Wi-Fi» o pega el enlace de tu Estación Faro.',
          ),
        ),
      );
      return;
    }
    await client.connect(
      stationId: station.stationId,
      stationName: station.stationName,
      host: station.host,
      port: station.port,
      pin: _pinController.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.service.beaconClient;
    return ListenableBuilder(
      listenable: client,
      builder: (context, _) {
        final connected = client.isConnected;
        final sol = client.latestSolution;
        final stations = client.discoveredStations;
        if (_selectedStation == null && stations.isNotEmpty) {
          _selectedStation = stations.first;
        }

        return Card(
          color: const Color(0xFF10192D),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: connected ? const Color(0xFF00E5FF) : Colors.white12,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.radar_rounded,
                      color: Color(0xFF00E5FF),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Estación Faro Desktop (Triangulación + IA de Manos)',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      key: const ValueKey('open_desktop_beacon_station_button'),
                      onPressed: () => openVrDesktopBeaconPage(context),
                      icon: const Icon(Icons.desktop_mac_outlined, size: 16),
                      label: const Text(
                        'Modo Faro PC',
                        style: TextStyle(fontSize: 11.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Usa tu computadora personal con VRlizate Desktop como tercer nodo fijo (0,0,0) para calcular profundidad PC↔Visor↔Joystick y detectar manos alzadas o gestos con IA mientras el Visor corre la experiencia .vrlz.',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(height: 12),
                if (connected) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF081020),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.5),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Conectado a ${client.connectedStationName ?? "Estación Faro"} · ${client.packetsReceived} tramas 60 Hz',
                          style: const TextStyle(
                            color: Color(0xFF69F0AE),
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                        if (sol != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'd_CV=${sol.computerToVisorMeters.toStringAsFixed(2)} m · '
                            'd_CJ=${sol.computerToJoystickMeters.toStringAsFixed(2)} m · '
                            'd_VJ=${sol.visorToJoystickMeters.toStringAsFixed(2)} m · '
                            'Gesto IA: ${sol.gesture.name}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      key: const ValueKey('disconnect_desktop_beacon_button'),
                      onPressed: client.disconnect,
                      icon: const Icon(Icons.link_off_rounded, size: 16),
                      label: const Text('Desconectar Estación Faro'),
                    ),
                  ),
                ] else ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        key: const ValueKey('scan_desktop_beacon_lan_button'),
                        onPressed: client.isConnecting
                            ? null
                            : () => unawaited(client.scanLan()),
                        icon: const Icon(Icons.wifi_find_rounded, size: 16),
                        label: const Text('Buscar en Wi-Fi'),
                      ),
                      if (stations.isNotEmpty)
                        for (final st in stations)
                          ChoiceChip(
                            label: Text('${st.stationName} (${st.host})'),
                            selected:
                                _selectedStation?.stationId == st.stationId,
                            onSelected: (_) =>
                                setState(() => _selectedStation = st),
                          ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      SizedBox(
                        width: 145,
                        child: TextField(
                          key: const ValueKey('desktop_beacon_pin_field'),
                          controller: _pinController,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          decoration: const InputDecoration(
                            labelText: 'PIN (6 dígitos)',
                            counterText: '',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('desktop_beacon_invite_field'),
                          controller: _inviteLinkController,
                          decoration: const InputDecoration(
                            labelText: 'O pega enlace vrlizate://beacon?...',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (client.lastError != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      client.lastError!,
                      style: const TextStyle(
                        color: Colors.amberAccent,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      key: const ValueKey('connect_desktop_beacon_button'),
                      onPressed: client.isConnecting
                          ? null
                          : () => unawaited(_connectSelected()),
                      icon: const Icon(Icons.link_rounded, size: 16),
                      label: Text(
                        client.isConnecting
                            ? 'Conectando…'
                            : 'Vincular Estación Faro',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
