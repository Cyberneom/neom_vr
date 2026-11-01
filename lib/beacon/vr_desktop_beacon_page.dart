import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:vrlizate_cast/vrlizate_cast.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart' show VrDepthColorPalette;

import 'vr_desktop_autonomous_bridge.dart';
import 'vr_desktop_beacon_models.dart';
import 'vr_desktop_beacon_station.dart';
import 'vr_desktop_beacon_wire.dart';
import 'vr_desktop_capabilities.dart';
import 'vr_desktop_media_vault.dart';

Future<void> openVrDesktopBeaconPage(BuildContext context) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/desktop-beacon'),
        builder: (_) => const VrDesktopBeaconPage(),
      ),
    );

/// Turns VRlizate Desktop into an interactive **Estación Faro** (fixed `(0,0,0)`
/// spatial & AI tracking station) that elevates a smartphone Visor running
/// `.vrlz` experiences natively.
class VrDesktopBeaconPage extends StatefulWidget {
  const VrDesktopBeaconPage({
    super.key,
    this.station,
    this.autoEnableWebcam = false,
    this.castPreviewBuilder,
  });

  final VrDesktopBeaconStation? station;
  final bool autoEnableWebcam;
  final Widget Function(BuildContext context, Uri uri)? castPreviewBuilder;

  @override
  State<VrDesktopBeaconPage> createState() => _VrDesktopBeaconPageState();
}

class _VrDesktopBeaconPageState extends State<VrDesktopBeaconPage> {
  late final VrDesktopBeaconStation _station =
      widget.station ?? VrDesktopBeaconStation();
  late final bool _ownsStation = widget.station == null;
  final TextEditingController _voiceConsoleController = TextEditingController();
  bool _theaterMode = false;
  bool _showJoystickQr = false;

  @override
  void initState() {
    super.initState();
    unawaited(_station.start(enableWebcam: widget.autoEnableWebcam));
  }

  @override
  void dispose() {
    _voiceConsoleController.dispose();
    if (_ownsStation) {
      _station.dispose();
    }
    super.dispose();
  }

  String _gestureLabel(VrBeaconHandGesture gesture) => switch (gesture) {
    VrBeaconHandGesture.none => 'Reposo · manos bajas',
    VrBeaconHandGesture.leftRaised => 'Mano izquierda alzada (apuntando)',
    VrBeaconHandGesture.rightRaised => 'Mano derecha alzada (apuntando)',
    VrBeaconHandGesture.bothRaised => 'Ambas manos alzadas',
    VrBeaconHandGesture.leftPinch => 'Pinza izquierda (selección activa)',
    VrBeaconHandGesture.rightPinch => 'Pinza derecha (selección activa)',
    VrBeaconHandGesture.wave => 'Movimiento / saludo detectado',
  };

  Color _gestureColor(VrBeaconHandGesture gesture) => switch (gesture) {
    VrBeaconHandGesture.none => Colors.blueGrey,
    VrBeaconHandGesture.leftRaised ||
    VrBeaconHandGesture.rightRaised => const Color(0xFF00E5FF),
    VrBeaconHandGesture.bothRaised => const Color(0xFF7C4DFF),
    VrBeaconHandGesture.leftPinch ||
    VrBeaconHandGesture.rightPinch => const Color(0xFFFFB300),
    VrBeaconHandGesture.wave => const Color(0xFF00E676),
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _station,
      builder: (context, _) {
        final sol = _station.latestSolution;
        final fb = _station.latestVisorFeedback;
        final invite = _station.pairingInvite;
        final connected = _station.isVisorConnected;

        return Scaffold(
          backgroundColor: const Color(0xFF070B14),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0B1222),
            title: const Row(
              children: [
                Icon(Icons.radar_rounded, color: Color(0xFF00E5FF), size: 22),
                SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'Estación Faro Desktop · Sensores + IA',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: connected
                          ? const Color(0xFF00E676).withValues(alpha: 0.16)
                          : const Color(0xFF2E90FA).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: connected
                            ? const Color(0xFF00E676)
                            : const Color(0xFF2E90FA),
                      ),
                    ),
                    child: Text(
                      connected
                          ? 'VISOR ACTIVO · ${fb?.activeExperience ?? ".vrlz"}'
                          : (_station.isRunning
                                ? 'FARO 60 Hz · ESPERANDO VISOR'
                                : 'INICIANDO FARO…'),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: connected
                            ? const Color(0xFF69F0AE)
                            : const Color(0xFF84CAFF),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: Stack(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 980;
                  final padding = _station.monitorFiducialEnabled ? 22.0 : 14.0;
                  return SingleChildScrollView(
                    padding: EdgeInsets.all(padding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildArchitectureBanner(connected, fb),
                        const SizedBox(height: 14),
                        if (wide && !_theaterMode)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 6,
                                child: _buildDesktopCastCard(connected, fb),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                flex: 5,
                                child: _buildAutonomousBridgeCard(
                                  connected,
                                  _station.latestDirective,
                                ),
                              ),
                            ],
                          )
                        else ...[
                          _buildDesktopCastCard(connected, fb),
                          const SizedBox(height: 14),
                          _buildAutonomousBridgeCard(
                            connected,
                            _station.latestDirective,
                          ),
                        ],
                        const SizedBox(height: 14),
                        if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 5,
                                child: _buildTriangulationCard(sol, fb),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                flex: 5,
                                child: _buildAiVisionCard(sol),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                flex: 4,
                                child: _buildPairingCard(invite),
                              ),
                            ],
                          )
                        else ...[
                          _buildPairingCard(invite),
                          const SizedBox(height: 14),
                          _buildTriangulationCard(sol, fb),
                          const SizedBox(height: 14),
                          _buildAiVisionCard(sol),
                        ],
                        const SizedBox(height: 14),
                        _buildHandsFreeVoiceAndFaceCard(sol, connected),
                        const SizedBox(height: 14),
                        _buildMediaVaultCard(connected),
                      ],
                    ),
                  );
                },
              ),
              if (_station.monitorFiducialEnabled)
                const IgnorePointer(child: _OpticalFiducialOverlay()),
            ],
          ),
        );
      },
    );
  }

  Widget _buildArchitectureBanner(bool connected, VrVisorBeaconFeedback? fb) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F192E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.precision_manufacturing_outlined,
            color: Color(0xFF00E5FF),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              connected
                  ? 'Three-Devices VR (3D-VR) activo: el Visor ejecuta «${fb?.activeExperience ?? ".vrlz"}» (${fb?.visorFps.round() ?? 60} FPS) con profundidad holográfica 3D, Bóveda LAN estéreo y puente autónomo a 60 Hz.'
                  : 'De Two-Devices VR (2D-VR) a Three-Devices VR (3D-VR): al detectar esta computadora se activa profundidad holográfica, Bóveda LAN de Videos 360° / WebVR libre y streaming doble al Smartphone Visor.',
              style: const TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopCastCard(bool connected, VrVisorBeaconFeedback? fb) {
    final castUri = _station.activeCastViewerUri;
    final castEnabled = _station.castToDesktopEnabled;

    return Card(
      key: const ValueKey('faro_desktop_cast_card'),
      color: const Color(0xFF0E1628),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: castUri != null
              ? const Color(0xFF00E676).withValues(alpha: 0.65)
              : Colors.white12,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  castUri != null ? Icons.connected_tv : Icons.desktop_windows,
                  color: castUri != null
                      ? const Color(0xFF69F0AE)
                      : const Color(0xFF00E5FF),
                  size: 19,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Pantalla del Visor en Vivo (Joystick Liberado)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (castUri != null)
                  TextButton.icon(
                    key: const ValueKey('faro_cast_theater_toggle'),
                    onPressed: () =>
                        setState(() => _theaterMode = !_theaterMode),
                    icon: Icon(
                      _theaterMode
                          ? Icons.fullscreen_exit_rounded
                          : Icons.fullscreen_rounded,
                      size: 16,
                    ),
                    label: Text(
                      _theaterMode ? 'Compactar' : 'Modo Teatro',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: _theaterMode ? 410 : 225,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: castUri != null
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          (widget.castPreviewBuilder != null
                              ? widget.castPreviewBuilder!(context, castUri)
                              : VrCastPreview(
                                  key: const ValueKey('faro_live_cast_preview'),
                                  uri: castUri,
                                )),
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFF69F0AE),
                                ),
                              ),
                              child: Text(
                                'EN VIVO EN PC · JOYSTICK LIBERADO · ${fb?.activeExperience ?? ".vrlz"}',
                                style: const TextStyle(
                                  color: Color(0xFF69F0AE),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : Container(
                        color: const Color(0xFF070C18),
                        padding: const EdgeInsets.all(18),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                castEnabled
                                    ? Icons.cast_for_education_rounded
                                    : Icons.cast_outlined,
                                size: 36,
                                color: Colors.white38,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                !castEnabled
                                    ? 'Transferencia a PC pausada: la vista permanece en el Joystick.'
                                    : connected
                                    ? 'Conectando vista Wi-Fi del Visor… El Joystick ya fue liberado de decodificar video.'
                                    : 'Al vincular el Visor, la vista estereoscópica se transfiere automáticamente a este monitor para liberar el GPU, batería y Wi-Fi del Joystick.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutonomousBridgeCard(
    bool connected,
    VrDesktopBridgeDirective? directive,
  ) {
    final castOff = directive?.offloadCastToDesktop ?? _station.castToDesktopEnabled;
    final cvOff = directive?.offloadJoystickVisionToDesktop ?? false;
    final joyHz = directive?.recommendedJoystickHz ?? (castOff ? 120 : 60);
    final qScale = directive?.recommendedVisorQualityScale ?? 1.0;
    final pcCaps = _station.desktopCapabilities;
    final fb = _station.latestVisorFeedback;
    final visorCaps = fb?.visorCapabilities;
    final joyCaps =
        _station.latestJoystickTelemetry?.capabilities ??
        fb?.joystickCapabilities;
    final pcTier = directive?.desktopTier ?? pcCaps?.computeTier;
    final topoMode = directive?.topologyMode;
    final log = _station.autonomousBridge.decisionHistory;

    return Card(
      key: const ValueKey('faro_autonomous_bridge_card'),
      color: const Color(0xFF0E1628),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Colors.white12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.hub_rounded, color: Color(0xFFB388FF), size: 19),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Puente Autónomo PC ↔ Visor ↔ Joystick',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              key: const ValueKey('faro_tri_device_matrix'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    topoMode != null
                        ? 'Topología óptima: ${topoMode.labelEs}'
                        : 'Perfil PC: ${pcTier?.labelEs ?? "Detectando hardware…"}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF69F0AE),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '• Computadora: ${pcCaps?.shortSummaryEs ?? "Sondeando CPU/GPU/RAM…"}',
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                  Text(
                    '• Visor: ${visorCaps?.shortSummaryEs ?? (connected ? "Conectado (${fb?.visorFps.round() ?? 60} FPS)" : "Esperando enlace…")}',
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                  Text(
                    '• Joystick 3D Set: ${_station.isDirectJoystickConnected ? "ACTIVO en LAN (${_station.joystickFramesCoordinated} tramas · Stick ${_station.coordinatorJoystickMirror.latestState.stickX.toStringAsFixed(2)}, ${_station.coordinatorJoystickMirror.latestState.stickY.toStringAsFixed(2)})" : (joyCaps?.shortSummaryEs ?? (fb?.joystickConnected == true ? "Conectado vía Visor BLE" : "Esperando mando en LAN o BLE…"))}',
                    style: TextStyle(
                      fontSize: 11,
                      color: _station.isDirectJoystickConnected
                          ? const Color(0xFF69F0AE)
                          : Colors.white70,
                      fontWeight: _station.isDirectJoystickConnected
                          ? FontWeight.w700
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _metricChip(
                  'Vista Joystick',
                  castOff ? 'Liberada → PC' : 'En Joystick',
                  castOff ? const Color(0xFF69F0AE) : Colors.white70,
                ),
                _metricChip(
                  'Visión CV Mando',
                  cvOff ? 'Delegada a IA PC' : 'Respaldo activo',
                  cvOff ? const Color(0xFF00E5FF) : Colors.amberAccent,
                ),
                _metricChip(
                  'Frecuencia Mando',
                  '$joyHz Hz puro',
                  const Color(0xFFB388FF),
                ),
                _metricChip(
                  'Modo Render',
                  (directive?.pcRendersStereoFrame ?? false)
                      ? 'Proyector PC-VR'
                      : '${(qScale * 100).round()}% · SLAM PC',
                  (directive?.pcRendersStereoFrame ?? false)
                      ? const Color(0xFF00E5FF)
                      : (qScale < 1.0
                            ? Colors.amberAccent
                            : const Color(0xFF69F0AE)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              key: const ValueKey('faro_cast_offload_switch'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Pasar pantalla a esta PC y liberar al Joystick',
                style: TextStyle(fontSize: 12.5),
              ),
              value: _station.castToDesktopEnabled,
              onChanged: _station.setCastToDesktopEnabled,
            ),
            SwitchListTile.adaptive(
              key: const ValueKey('faro_prefer_pc_projector'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Modo Visor para Computadora (Proyector PC-VR si hardware/Wi-Fi lo permiten)',
                style: TextStyle(fontSize: 12.5),
              ),
              value: _station.preferPcProjectorMode,
              onChanged:
                  pcCaps?.computeTier ==
                      VrDesktopComputeTier.fullPcVrProjectorCapable
                  ? _station.setPreferPcProjectorMode
                  : null,
            ),
            SwitchListTile.adaptive(
              key: const ValueKey('faro_autonomous_mode_switch'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Decisiones autónomas según capacidades de los 3 dispositivos',
                style: TextStyle(fontSize: 12.5),
              ),
              subtitle: Text(
                'Directivas compartidas: ${_station.directivesSent} · '
                '${connected ? (directive?.activeSummary ?? "Evaluando…") : "Esperando enlace"}',
                style: const TextStyle(fontSize: 11),
              ),
              value: _station.autonomousModeEnabled,
              onChanged: _station.setAutonomousModeEnabled,
            ),
            if (log.isNotEmpty) ...[
              const Divider(height: 14, color: Colors.white12),
              const Text(
                'Decisiones recientes de la computadora:',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 4),
              for (final item in log.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    '• $item',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF84CAFF),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTriangulationCard(
    VrTriNodeDepthSolution? sol,
    VrVisorBeaconFeedback? fb,
  ) {
    final dCv = sol?.computerToVisorMeters ?? 1.50;
    final dCj = sol?.computerToJoystickMeters ?? 1.18;
    final dVj = sol?.visorToJoystickMeters ?? 0.48;
    final clearance = sol?.deskClearanceMeters ?? 1.12;
    final warnDesk = clearance < 0.58;

    return Card(
      color: const Color(0xFF0E1628),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: warnDesk ? Colors.amberAccent : Colors.white12,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Triangulación Espacial 3-Nodos (PC ↔ Visor ↔ Joystick)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 210,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CustomPaint(
                  painter: _TriNodeRadarPainter(solution: sol),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _metricChip(
                  'PC ↔ Visor (d_CV)',
                  '${dCv.toStringAsFixed(2)} m',
                  const Color(0xFF00E5FF),
                ),
                _metricChip(
                  'PC ↔ Manos/Joy (d_CJ)',
                  '${dCj.toStringAsFixed(2)} m',
                  const Color(0xFF69F0AE),
                ),
                _metricChip(
                  'Visor ↔ Joy (d_VJ)',
                  '${dVj.toStringAsFixed(2)} m',
                  const Color(0xFFB388FF),
                ),
                _metricChip(
                  'Margen Escritorio',
                  '${(clearance * 100).round()} cm',
                  warnDesk ? Colors.amberAccent : Colors.white70,
                ),
                _metricChip(
                  'PnP 6-DoF (<3mm)',
                  (sol?.visorFiducialLocked ?? false)
                      ? 'LOCK ACTIVO'
                      : 'Cuerpo IA',
                  (sol?.visorFiducialLocked ?? false)
                      ? const Color(0xFF00E676)
                      : Colors.white60,
                ),
                if (sol?.estimatedUserIpdMeters case final ipdMeters?)
                  _metricChip(
                    'IPD Óptico Medido',
                    '${(ipdMeters * 1000.0).toStringAsFixed(1)} mm',
                    const Color(0xFF80D8FF),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Tramas 60 Hz enviadas: ${_station.packetsSent} · '
              'Telemetría Visor: ${_station.feedbackReceived} · '
              'Joystick BLE: ${(fb?.joystickConnected ?? false) ? "conectado" : "opcional"}',
              style: const TextStyle(color: Colors.white54, fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiVisionCard(VrTriNodeDepthSolution? sol) {
    final gesture = sol?.gesture ?? VrBeaconHandGesture.none;
    final frame = _station.latestVisionFrame;
    final leftPos = sol?.leftHandRelHead;
    final rightPos = sol?.rightHandRelHead;
    final sim = _station.syntheticVision;

    return Card(
      color: const Color(0xFF0E1628),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Colors.white12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'IA de Pose y Manos (Visión Computacional)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _gestureColor(gesture).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _gestureColor(gesture)),
                  ),
                  child: Text(
                    _gestureLabel(gesture),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _gestureColor(gesture),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 175,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CustomPaint(
                  painter: _VisionWireframePainter(
                    frame: frame,
                    solution: sol,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Profundidad SDK (.vrlz/.vrlw):  <=0.35m Coral/Ámbar · 0.35–0.75m Esmeralda/Cian (Zona eMudra) · 0.75–1.50m Azul · >1.50m Violeta',
              style: TextStyle(fontSize: 10.5, color: Color(0xFF80DEEA)),
            ),
            const SizedBox(height: 10),
            Text(
              'Expresión Facial: ${(sol?.facialExpression ?? VrFacialExpression.neutral).emoji} '
              '${(sol?.facialExpression ?? VrFacialExpression.neutral).labelEs} '
              '(${(sol?.facialExpression ?? VrFacialExpression.neutral).actionHintEs})\n'
              'Mano Izq (rel. cabeza): ${leftPos == null ? "—" : "(${leftPos.x.toStringAsFixed(2)}, ${leftPos.y.toStringAsFixed(2)}, ${leftPos.z.toStringAsFixed(2)}) m"} '
              '${(sol?.leftHandRaised ?? false) ? "· ALZADA" : ""}\n'
              'Mano Der (rel. cabeza): ${rightPos == null ? "—" : "(${rightPos.x.toStringAsFixed(2)}, ${rightPos.y.toStringAsFixed(2)}, ${rightPos.z.toStringAsFixed(2)}) m"} '
              '${(sol?.rightHandRaised ?? false) ? "· ALZADA" : ""}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
            const Divider(height: 18, color: Colors.white12),
            SwitchListTile.adaptive(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Webcam IA en vivo (Cuerpo + Manos)',
                style: TextStyle(fontSize: 12.5),
              ),
              subtitle: Text(
                _station.webcamNativeActive
                    ? 'Activa (${_station.nativeVisionFramesReceived} cuadros IA · Cuerpo=${_station.latestNativeVisionFrame?.hasUpperBody == true ? "Sí" : "—"} · Manos=${(_station.latestNativeVisionFrame?.hasLeftHand == true || _station.latestNativeVisionFrame?.hasRightHand == true) ? "Sí" : "—"})'
                    : 'Usa cámara de la computadora (Vision IA)',
                style: const TextStyle(fontSize: 11),
              ),
              value: _station.webcamEnabled,
              onChanged: (v) => unawaited(_station.setWebcamEnabled(v)),
            ),
            SwitchListTile.adaptive(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Marco Fiducial Óptico en Bordes del Monitor',
                style: TextStyle(fontSize: 12.5),
              ),
              value: _station.monitorFiducialEnabled,
              onChanged: _station.setMonitorFiducialEnabled,
            ),
            if (!_station.webcamNativeActive) ...[
              const SizedBox(height: 6),
              const Text(
                'Calibrador / Simulador de Gestos IA (sin webcam activa):',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
              Row(
                children: [
                  const Text(
                    'Profundidad:',
                    style: TextStyle(fontSize: 11.5, color: Colors.white60),
                  ),
                  Expanded(
                    child: Slider(
                      key: const ValueKey('faro_sim_distance_slider'),
                      min: 0.65,
                      max: 2.80,
                      value: sim.simulatedDistanceMeters.clamp(0.65, 2.80),
                      onChanged: (v) =>
                          setState(() => sim.simulatedDistanceMeters = v),
                    ),
                  ),
                  Text(
                    '${sim.simulatedDistanceMeters.toStringAsFixed(2)} m',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ],
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  FilterChip(
                    key: const ValueKey('faro_sim_left_raised'),
                    label: const Text(
                      'Alzar Mano Izq',
                      style: TextStyle(fontSize: 11),
                    ),
                    selected: sim.simulateLeftRaised,
                    onSelected: (v) =>
                        setState(() => sim.simulateLeftRaised = v),
                  ),
                  FilterChip(
                    key: const ValueKey('faro_sim_right_raised'),
                    label: const Text(
                      'Alzar Mano Der',
                      style: TextStyle(fontSize: 11),
                    ),
                    selected: sim.simulateRightRaised,
                    onSelected: (v) =>
                        setState(() => sim.simulateRightRaised = v),
                  ),
                  FilterChip(
                    key: const ValueKey('faro_sim_right_pinch'),
                    label: const Text(
                      'Pinza Der (Click)',
                      style: TextStyle(fontSize: 11),
                    ),
                    selected: sim.simulateRightPinch,
                    onSelected: (v) => setState(() {
                      sim.simulateRightPinch = v;
                      if (v) sim.simulateRightRaised = true;
                    }),
                  ),
                  FilterChip(
                    key: const ValueKey('faro_sim_wave'),
                    label: const Text(
                      'Mover / Saludar',
                      style: TextStyle(fontSize: 11),
                    ),
                    selected: sim.simulateWave,
                    onSelected: (v) => setState(() => sim.simulateWave = v),
                  ),
                  FilterChip(
                    key: const ValueKey('faro_sim_fiducial_pnp'),
                    label: const Text(
                      'Tag 6-DoF (<3mm)',
                      style: TextStyle(fontSize: 11),
                    ),
                    selected: sim.simulateFiducialTag,
                    onSelected: (v) =>
                        setState(() => sim.simulateFiducialTag = v),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHandsFreeVoiceAndFaceCard(
    VrTriNodeDepthSolution? sol,
    bool visorConnected,
  ) {
    final expr = sol?.facialExpression ?? VrFacialExpression.neutral;
    final guidance = _station.lastVoiceGuidance;
    const samplePhrases = <String>[
      'Abre Plaza Artz',
      'Camina adelante',
      'Gira a la derecha',
      'Media vuelta',
      'Detente',
      'Abre el menú',
      'Siguiente',
      'Seleccionar',
      'Llévame a Ciudad Solar',
      'Jugar Riviera Rush',
      'Volver al inicio',
    ];
    const testExpressions = <VrFacialExpression>[
      VrFacialExpression.eyebrowsRaised,
      VrFacialExpression.mouthOpen,
      VrFacialExpression.leftWink,
      VrFacialExpression.rightWink,
      VrFacialExpression.headNod,
      VrFacialExpression.smile,
      VrFacialExpression.headShake,
    ];

    void sendConsolePhrase(String raw) {
      final clean = raw.trim();
      if (clean.isEmpty) return;
      _station.submitVoiceCommand(clean, source: 'desktop_console');
    }

    return Card(
      key: const ValueKey('faro_hands_free_card'),
      color: const Color(0xFF0E1628),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0x5500E5FF)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.record_voice_over_rounded,
                  color: Color(0xFF00E5FF),
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Consola Manos Libres: Voz Natural (Itzli) + Expresión Facial (Sin Joystick)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _station.desktopVoiceListening
                        ? const Color(0xFF00E676).withValues(alpha: 0.18)
                        : Colors.white10,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _station.desktopVoiceListening
                          ? const Color(0xFF00E676)
                          : Colors.white24,
                    ),
                  ),
                  child: Text(
                    _station.desktopVoiceListening
                        ? '🎙️ ESCUCHANDO (${_station.desktopVoiceLocale})'
                        : '${expr.emoji} ${expr.labelEs}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _station.desktopVoiceListening
                          ? const Color(0xFF69F0AE)
                          : Colors.white70,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Habla a la computadora o al visor sin usar el Joystick: pide abrir plazas/experiencias («Abre Plaza Artz», «Llévame a Ciudad Solar»), desplazarte («Camina adelante», «Gira a la derecha», «Media vuelta», «Detente») o navegar con expresiones faciales (🤨 Cejas = Menú, 😮 Boca abierta = Escuchar, 😉/😜 Guiño = Mover opción, 🙂‍↕️/😊 Asentir o Sonrisa = Entrar, 🙂‍↔️ Negar = Cerrar).',
              style: const TextStyle(color: Colors.white60, fontSize: 11.5),
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              key: const ValueKey('faro_voice_listen_switch'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Escucha continua en Español con micrófono de esta computadora',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                _station.desktopVoicePartialText.isNotEmpty
                    ? 'Escuchando: «${_station.desktopVoicePartialText}…»'
                    : (_station.lastVoiceError ??
                          (visorConnected
                              ? 'Comandos enviados al Visor por UDP HMAC: ${_station.voiceCommandsSent}'
                              : 'Listo para probar localmente y retransmitir en cuanto vincules el Visor')),
                style: TextStyle(
                  fontSize: 11,
                  color: _station.lastVoiceError != null
                      ? Colors.amberAccent
                      : Colors.white70,
                ),
              ),
              value: _station.desktopVoiceListening,
              onChanged: (v) => unawaited(_station.setDesktopVoiceListening(v)),
            ),
            if (_station.lastVoiceTranscript.isNotEmpty &&
                guidance != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A1F33),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.45),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Última orden («${_station.lastVoiceTranscript}» · ${_station.lastVoiceSource}) → ${guidance.summaryEs}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF80DEEA),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Itzli: ${guidance.speechResponse}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('faro_voice_test_input'),
                    controller: _voiceConsoleController,
                    style: const TextStyle(fontSize: 12.5, color: Colors.white),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText:
                          'Prueba cualquier orden en español (ej. «camina adelante», «abre galleria milano»)…',
                      hintStyle: const TextStyle(
                        fontSize: 12,
                        color: Colors.white38,
                      ),
                      filled: true,
                      fillColor: const Color(0xFF080E1C),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                    ),
                    onSubmitted: (value) {
                      sendConsolePhrase(value);
                      _voiceConsoleController.clear();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  key: const ValueKey('faro_voice_send_btn'),
                  onPressed: () {
                    sendConsolePhrase(_voiceConsoleController.text);
                    _voiceConsoleController.clear();
                  },
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: const Text('Ejecutar'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final phrase in samplePhrases)
                  ActionChip(
                    label: Text(phrase, style: const TextStyle(fontSize: 11)),
                    onPressed: () => sendConsolePhrase(phrase),
                  ),
              ],
            ),
            const Divider(height: 18, color: Colors.white12),
            const Text(
              'Probar gestos de Expresión Facial / Cabeza en tiempo real (envía pulso al Visor):',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final item in testExpressions)
                  ActionChip(
                    key: ValueKey('faro_expr_${item.name}'),
                    avatar: Text(
                      item.emoji,
                      style: const TextStyle(fontSize: 12),
                    ),
                    label: Text(
                      '${item.labelEs} · ${item.actionHintEs}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    onPressed: () =>
                        _station.pulseSimulatedFacialExpression(item),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPairingCard(VrDesktopBeaconPairingInvite? invite) {
    final uriString = _showJoystickQr
        ? invite?.toJoystickUri().toString()
        : invite?.toUri().toString();
    final port = _station.boundPort;

    return Card(
      color: const Color(0xFF0E1628),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Colors.white12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Vincular 3D Set en Red Local (Visor + Joystick)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                ChoiceChip(
                  key: const ValueKey('faro_qr_mode_visor'),
                  label: const Text('QR Visor', style: TextStyle(fontSize: 11)),
                  selected: !_showJoystickQr,
                  onSelected: (_) => setState(() => _showJoystickQr = false),
                ),
                ChoiceChip(
                  key: const ValueKey('faro_qr_mode_joystick'),
                  label: const Text(
                    'QR Joystick 3D Set',
                    style: TextStyle(fontSize: 11),
                  ),
                  selected: _showJoystickQr,
                  onSelected: (_) => setState(() => _showJoystickQr = true),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'En tu teléfono Visor abre «Cámaras y sensado» → «Buscar Estación Faro en Wi-Fi» e ingresa este PIN de 6 dígitos:',
              style: TextStyle(color: Colors.white70, fontSize: 11.5),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF080D1A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF00E5FF)),
              ),
              child: Column(
                children: [
                  const Text(
                    'PIN DE AUTENTICACIÓN HMAC',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.2,
                      color: Colors.white54,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    _station.pin,
                    key: const ValueKey('faro_station_pin'),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 6,
                      color: Color(0xFF00E5FF),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    port == null
                        ? 'Abriendo puerto UDP…'
                        : '${_station.primaryHost}:$port',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            if (uriString != null) ...[
              const SizedBox(height: 12),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: QrImageView(
                    data: uriString,
                    size: 148,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: uriString));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Enlace Faro copiado al portapapeles'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 15),
                    label: const Text(
                      'Copiar enlace',
                      style: TextStyle(fontSize: 11.5),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _station.regeneratePin,
                    icon: const Icon(Icons.refresh_rounded, size: 15),
                    label: const Text(
                      'Nuevo PIN',
                      style: TextStyle(fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndRegisterVaultFile() async {
    if (kIsWeb) return;
    final picked = await FilePicker.pickFiles(
      allowMultiple: true,
      type: FileType.any,
    );
    if (picked == null || !mounted) return;
    var count = 0;
    for (final file in picked.files) {
      final path = file.path;
      if (path == null || path.trim().isEmpty) continue;
      final item = await _station.mediaVault.registerLocalFile(path);
      if (item != null) count++;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count > 0
                ? '$count experiencia(s) añadidas a la Bóveda LAN 3D-VR'
                : 'Selecciona archivos .mp4/.webm 360°, .vrlw, .vrlz o .glb válidos.',
          ),
        ),
      );
    }
  }

  Widget _buildMediaVaultCard(bool connected) {
    final vault = _station.mediaVault;
    final items = vault.items;
    final localWeb = vault.localWebLibraryUri?.toString();
    final lanWeb = vault.lanWebLibraryUri?.toString();

    return Card(
      key: const Key('faro_media_vault_card'),
      color: const Color(0xFF0E1729),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: const Color(0xFF00E5FF).withValues(alpha: 0.32),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.video_library_rounded,
                  color: Color(0xFF00E5FF),
                  size: 19,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Bóveda LAN & Proyector Web Doble · Three-Devices VR (3D-VR)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: vault.isRunning
                        ? const Color(0xFF12B76A).withValues(alpha: 0.16)
                        : Colors.white10,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: vault.isRunning
                          ? const Color(0xFF12B76A)
                          : Colors.white24,
                    ),
                  ),
                  child: Text(
                    vault.isRunning
                        ? '${items.length} ítems · LAN HTTP Range'
                        : 'Bóveda detenida',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: vault.isRunning
                          ? const Color(0xFF6CE9A6)
                          : Colors.white60,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Two-Devices VR (2D-VR): Smartphone Visor + Joystick portátiles  |  Three-Devices VR (3D-VR): esta PC sirve Videos 360°/SBS, mundos .vrlw/.vrlz y escenas holográficas en doble ojo al Visor sin ocupar espacio en el celular.',
              style: TextStyle(fontSize: 11.5, color: Colors.white70),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('faro_vault_add_file'),
                  onPressed: _pickAndRegisterVaultFile,
                  icon: const Icon(Icons.add_to_queue_rounded, size: 16),
                  label: const Text(
                    'Añadir Video 360° / .vrlz / .vrlw / .glb',
                    style: TextStyle(fontSize: 11.5),
                  ),
                ),
                if (localWeb != null)
                  OutlinedButton.icon(
                    key: const Key('faro_vault_copy_web'),
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: lanWeb ?? localWeb),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'URL de Biblioteca Web 3D-VR copiada al portapapeles',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.language_rounded, size: 16),
                    label: const Text(
                      'Copiar URL Biblioteca Web 3D-VR',
                      style: TextStyle(fontSize: 11.5),
                    ),
                  ),
                if (vault.localPrintableTagsUri case final tagsUri?)
                  OutlinedButton.icon(
                    key: const Key('faro_vault_copy_tags'),
                    onPressed: () {
                      final url = (vault.lanPrintableTagsUri ?? tagsUri)
                          .toString();
                      Clipboard.setData(ClipboardData(text: url));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Hoja imprimible 6-DoF (1:1 mm) copiada: $url',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.qr_code_2_rounded, size: 16),
                    label: const Text(
                      'Hoja Imprimible Tags 6-DoF (<3mm)',
                      style: TextStyle(fontSize: 11.5),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            for (final item in items.take(6))
              Container(
                margin: const EdgeInsets.only(bottom: 7),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF090F1E),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    Icon(
                      switch (item.kind) {
                        VrVaultMediaKind.video360OrCinema =>
                          Icons.vrpano_rounded,
                        VrVaultMediaKind.vrlwWorld => Icons.public_rounded,
                        VrVaultMediaKind.vrlzPackage =>
                          Icons.videogame_asset_rounded,
                        _ => Icons.view_in_ar_rounded,
                      },
                      size: 18,
                      color: const Color(0xFF00E5FF),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            '${item.requiredTier.shortCode} · ${item.stereoFormat.labelEs} · ${item.formattedSize}',
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: Colors.white60,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      key: Key('faro_vault_push_${item.id}'),
                      onPressed: () {
                        vault.pushItemToVisor(item.id);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              connected
                                  ? 'Enviado en 3D-VR al Visor: ${item.title}'
                                  : 'Proyección preparada (se enviará al conectar el Visor): ${item.title}',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.cast_connected_rounded, size: 15),
                      label: const Text(
                        'Proyectar 3D-VR',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _metricChip(String label, String value, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF080D1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: Colors.white54),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _OpticalFiducialOverlay extends StatelessWidget {
  const _OpticalFiducialOverlay();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: const [
        Positioned(top: 4, left: 4, child: _FiducialCorner(quarterTurns: 0)),
        Positioned(top: 4, right: 4, child: _FiducialCorner(quarterTurns: 1)),
        Positioned(
          bottom: 4,
          right: 4,
          child: _FiducialCorner(quarterTurns: 2),
        ),
        Positioned(bottom: 4, left: 4, child: _FiducialCorner(quarterTurns: 3)),
      ],
    );
  }
}

class _FiducialCorner extends StatelessWidget {
  const _FiducialCorner({required this.quarterTurns});
  final int quarterTurns;

  @override
  Widget build(BuildContext context) {
    return RotatedBox(
      quarterTurns: quarterTurns,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: Colors.black,
          border: Border.all(color: Colors.white, width: 2.5),
        ),
        child: Center(
          child: Container(width: 8, height: 8, color: const Color(0xFF00E5FF)),
        ),
      ),
    );
  }
}

class _TriNodeRadarPainter extends CustomPainter {
  const _TriNodeRadarPainter({required this.solution});
  final VrTriNodeDepthSolution? solution;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF070C18);
    canvas.drawRect(Offset.zero & size, bg);

    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final pcOrigin = Offset(size.width * 0.5, 24);
    final metersToPx = (size.height - 44) / 2.8;

    for (final rMeters in const [0.75, 1.50, 2.25]) {
      canvas.drawCircle(pcOrigin, rMeters * metersToPx, grid);
    }

    // Webcam FOV cone (~68 deg)
    final fovPath = Path()
      ..moveTo(pcOrigin.dx, pcOrigin.dy)
      ..lineTo(pcOrigin.dx - 1.8 * metersToPx, pcOrigin.dy + 2.6 * metersToPx)
      ..lineTo(pcOrigin.dx + 1.8 * metersToPx, pcOrigin.dy + 2.6 * metersToPx)
      ..close();
    canvas.drawPath(
      fovPath,
      Paint()..color = const Color(0xFF00E5FF).withValues(alpha: 0.05),
    );

    // Desk edge safety line (0.38 m in front of monitor)
    final deskY = pcOrigin.dy + 0.38 * metersToPx;
    canvas.drawLine(
      Offset(size.width * 0.15, deskY),
      Offset(size.width * 0.85, deskY),
      Paint()
        ..color = Colors.amberAccent.withValues(alpha: 0.55)
        ..strokeWidth = 2,
    );

    final dCv = solution?.computerToVisorMeters ?? 1.50;
    final visorX = solution?.visorRoomPosition.x ?? 0.0;
    final joyRoom = solution?.joystickRoomPosition;

    final visorPt = Offset(
      (pcOrigin.dx + visorX * metersToPx).clamp(18.0, size.width - 18.0),
      (pcOrigin.dy + dCv * metersToPx).clamp(28.0, size.height - 16.0),
    );
    final joyPt = Offset(
      (pcOrigin.dx + ((joyRoom?.x ?? 0.18) * metersToPx)).clamp(
        18.0,
        size.width - 18.0,
      ),
      (pcOrigin.dy + ((solution?.computerToJoystickMeters ?? 1.18) * metersToPx))
          .clamp(28.0, size.height - 16.0),
    );

    // Draw 3-node depth triangle
    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawLine(
      pcOrigin,
      visorPt,
      edgePaint..color = const Color(0xFF00E5FF),
    );
    canvas.drawLine(
      pcOrigin,
      joyPt,
      edgePaint..color = const Color(0xFF69F0AE),
    );
    canvas.drawLine(
      visorPt,
      joyPt,
      edgePaint..color = const Color(0xFFB388FF),
    );

    // Nodes
    canvas.drawCircle(pcOrigin, 7, Paint()..color = Colors.white);
    canvas.drawCircle(visorPt, 8, Paint()..color = const Color(0xFF00E5FF));
    canvas.drawCircle(joyPt, 6.5, Paint()..color = const Color(0xFF69F0AE));

    _drawLabel(canvas, 'PC Faro (0,0,0)', pcOrigin + const Offset(10, -6));
    _drawLabel(canvas, 'Visor (.vrlz)', visorPt + const Offset(10, -6));
    _drawLabel(canvas, 'Manos / Joy', joyPt + const Offset(10, -4));
  }

  void _drawLabel(Canvas canvas, String text, Offset offset) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _TriNodeRadarPainter oldDelegate) =>
      oldDelegate.solution != solution;
}

class _VisionWireframePainter extends CustomPainter {
  const _VisionWireframePainter({required this.frame, this.solution});
  final VrDesktopVisionFrame? frame;
  final VrTriNodeDepthSolution? solution;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF060A14),
    );
    final f = frame;
    if (f == null) return;

    final Uint8List? mini = f.miniFrameGray32x24;
    if (mini != null &&
        mini.length ==
            VrDesktopVisionFrame.miniWidth * VrDesktopVisionFrame.miniHeight) {
      final cw = size.width / VrDesktopVisionFrame.miniWidth;
      final ch = size.height / VrDesktopVisionFrame.miniHeight;
      final cellPaint = Paint();
      for (var y = 0; y < VrDesktopVisionFrame.miniHeight; y++) {
        for (var x = 0; x < VrDesktopVisionFrame.miniWidth; x++) {
          final srcX = f.mirrored
              ? x
              : (VrDesktopVisionFrame.miniWidth - 1 - x);
          final lum = mini[y * VrDesktopVisionFrame.miniWidth + srcX];
          cellPaint.color = Color.fromARGB(180, lum >> 2, lum >> 1, lum);
          canvas.drawRect(Rect.fromLTWH(x * cw, y * ch, cw + 0.5, ch + 0.5), cellPaint);
        }
      }
    }

    Offset? pt(VrDesktopKeypoint2D? kp) {
      if (kp == null || !kp.isValid) return null;
      final u = f.mirrored ? kp.u : (1.0 - kp.u);
      return Offset(u * size.width, kp.v * size.height);
    }

    final sol = solution;
    final bodyDist = sol?.computerToVisorMeters ?? 1.15;
    final leftHandDist = sol != null
        ? (bodyDist + sol.leftHandRelHead.z).clamp(0.18, 3.0)
        : 0.62;
    final rightHandDist = sol != null
        ? (bodyDist + sol.rightHandRelHead.z).clamp(0.18, 3.0)
        : 0.62;

    final torsoColor = VrDepthColorPalette.colorForDistanceMeters(bodyDist);
    final leftArmColor = VrDepthColorPalette.colorForDistanceMeters(
      0.5 * (bodyDist + leftHandDist),
    );
    final rightArmColor = VrDepthColorPalette.colorForDistanceMeters(
      0.5 * (bodyDist + rightHandDist),
    );
    final leftHandColor = VrDepthColorPalette.colorForDistanceMeters(
      leftHandDist,
    );
    final rightHandColor = VrDepthColorPalette.colorForDistanceMeters(
      rightHandDist,
    );

    void bone(
      VrDesktopKeypoint2D? a,
      VrDesktopKeypoint2D? b,
      Color color, {
      double depthMeters = 0.8,
    }) {
      final pa = pt(a);
      final pb = pt(b);
      if (pa == null || pb == null) return;
      final w =
          2.6 * VrDepthColorPalette.strokeScaleForDistanceMeters(depthMeters);
      canvas.drawLine(
        pa,
        pb,
        Paint()
          ..color = color.withValues(alpha: 0.30)
          ..strokeWidth = w * 2.2
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        pa,
        pb,
        Paint()
          ..color = color
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round,
      );
    }

    bone(
      f.leftShoulder,
      f.rightShoulder,
      torsoColor,
      depthMeters: bodyDist,
    );
    bone(
      f.leftShoulder,
      f.leftElbow,
      leftArmColor,
      depthMeters: 0.5 * (bodyDist + leftHandDist),
    );
    bone(
      f.leftElbow,
      f.leftWrist,
      leftHandColor,
      depthMeters: leftHandDist,
    );
    bone(
      f.rightShoulder,
      f.rightElbow,
      rightArmColor,
      depthMeters: 0.5 * (bodyDist + rightHandDist),
    );
    bone(
      f.rightElbow,
      f.rightWrist,
      rightHandColor,
      depthMeters: rightHandDist,
    );
    bone(
      f.leftWrist,
      f.leftIndexTip,
      leftHandColor,
      depthMeters: leftHandDist,
    );
    bone(
      f.rightWrist,
      f.rightIndexTip,
      rightHandColor,
      depthMeters: rightHandDist,
    );
    bone(
      f.leftWrist,
      f.leftThumbTip,
      leftHandColor,
      depthMeters: leftHandDist,
    );
    bone(
      f.rightWrist,
      f.rightThumbTip,
      rightHandColor,
      depthMeters: rightHandDist,
    );

    for (final (kp, c) in <(VrDesktopKeypoint2D?, Color)>[
      (f.nose, torsoColor),
      (f.leftEye, const Color(0xFF80D8FF)),
      (f.rightEye, const Color(0xFF80D8FF)),
      (f.mouthCenter, const Color(0xFFFFD54F)),
      (f.leftShoulder, torsoColor),
      (f.rightShoulder, torsoColor),
      (f.leftWrist, leftHandColor),
      (f.rightWrist, rightHandColor),
      (f.leftIndexTip, leftHandColor),
      (f.rightIndexTip, rightHandColor),
      (f.leftThumbTip, leftHandColor),
      (f.rightThumbTip, rightHandColor),
    ]) {
      final p = pt(kp);
      if (p != null) {
        canvas.drawCircle(p, 5.2, Paint()..color = c.withValues(alpha: 0.45));
        canvas.drawCircle(p, 3.4, Paint()..color = Colors.white);
      }
    }

    final activeExpr = sol?.facialExpression ?? f.facialExpression;
    if (activeExpr != VrFacialExpression.neutral) {
      final tp = TextPainter(
        text: TextSpan(
          text: '${activeExpr.emoji} ${activeExpr.labelEs}',
          style: const TextStyle(
            color: Color(0xFF69F0AE),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final bg = RRect.fromRectAndRadius(
        Rect.fromLTWH(8, 8, tp.width + 14, tp.height + 8),
        const Radius.circular(8),
      );
      canvas.drawRRect(bg, Paint()..color = const Color(0xCC081526));
      canvas.drawRRect(
        bg,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0xFF00E676),
      );
      tp.paint(canvas, const Offset(15, 12));
    }
  }

  @override
  bool shouldRepaint(covariant _VisionWireframePainter oldDelegate) =>
      oldDelegate.frame != frame || oldDelegate.solution != solution;
}
