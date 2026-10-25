import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

import '../utils/constants/vr_constants.dart';
import '../utils/constants/vr_translation_constants.dart';
import 'vr_joystick_mini_frame_painter.dart';
import 'vr_passthrough_camera_feed.dart';
import 'vr_spatial_tracking_service.dart';
import 'vr_tri_camera_frustum_painter.dart';
import 'vr_visual_tracking_panel.dart';

/// Camera ownership, received summaries and an explicitly separate simulation.
/// A two-device connection is not proof of three simultaneous camera streams.
class VrTriCameraLiveInspectorCard extends StatefulWidget {
  const VrTriCameraLiveInspectorCard({super.key, required this.service});
  final VrSpatialTrackingService service;

  @override
  State<VrTriCameraLiveInspectorCard> createState() =>
      _VrTriCameraLiveInspectorCardState();
}

class _VrTriCameraLiveInspectorCardState
    extends State<VrTriCameraLiveInspectorCard> {
  CameraLensDirection _lensDirection = CameraLensDirection.back;
  Map<dynamic, dynamic>? _cameraDiagnostics;
  bool _readingCameraDiagnostics = false;

  Future<void> _readCameraDiagnostics() async {
    setState(() => _readingCameraDiagnostics = true);
    final result = await widget.service.readCameraCalibrationDiagnostics();
    if (!mounted) return;
    setState(() {
      _cameraDiagnostics = result;
      _readingCameraDiagnostics = false;
    });
    if (!const bool.fromEnvironment('dart.vm.product')) {
      debugPrint('[VrCameraCalibration] ${jsonEncode(result)}');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.service,
    builder: (context, _) => _buildInspector(context),
  );

  Widget _buildInspector(BuildContext context) {
    final service = widget.service;
    final body = service.latestBodyState;
    final simulated = service.simulationActive;
    final stature = body.anthropometry.statureMeters;
    final mixPct = (service.passthroughMix * 100).round();
    final previewEnabled = service.visorCameraPreviewEnabled;
    final segments = service.spaceMapper.allContourSegments;
    final rearFrame = service.joystickRearMiniFrame;
    final frontFrame = service.joystickFrontMiniFrame;

    return Container(
      key: const ValueKey(VrConstants.keyTriCameraLiveInspectorCard),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1325),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF00E5FF), width: 1.3),
      ),
      child: Material(
        color: Colors.transparent,
        child: DefaultTextStyle(
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11.5,
            height: 1.4,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                VrTranslationConstants.triCameraInspectorTitle,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                simulated
                    ? 'SIMULACIÓN · los objetos y medidas siguientes son de demostración.'
                    : 'Datos recibidos y estado de cámaras · sin medición de cuerpo, ToF ni profundidad por Wi-Fi/Bluetooth.',
              ),
              const SizedBox(height: 8),
              Text(
                'VIO visor: ${service.tracking ? "seguimiento activo" : service.statusText}',
              ),
              Text(
                'Análisis C1: ${service.visorCamFrames} resúmenes · '
                'Mando trasera: ${service.joystickFloorFrames} · frontal: ${service.joystickUpperFrames}',
              ),
              VrVisualTrackingPanel(service: service),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _monitor(
                      badge: VrTranslationConstants.badgeCam2FloorTitle,
                      hasFrame: rearFrame != null,
                      painter: VrJoystickMiniFramePainter(
                        lumaBytes: rearFrame,
                        isFloorCamera: true,
                        isLiveActive:
                            rearFrame != null &&
                            service.joystickActiveCameraRole ==
                                VrConstants.cameraRoleRearFloor,
                        showEstimates: simulated,
                        leftFootUv: simulated
                            ? service.joystickLeftFootUv
                            : null,
                        rightFootUv: simulated
                            ? service.joystickRightFootUv
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _monitor(
                      badge: VrTranslationConstants.badgeCam3HandsTitle,
                      hasFrame: frontFrame != null,
                      painter: VrJoystickMiniFramePainter(
                        lumaBytes: frontFrame,
                        isFloorCamera: false,
                        isLiveActive:
                            frontFrame != null &&
                            service.joystickActiveCameraRole ==
                                VrConstants.cameraRoleFrontUpper,
                        showEstimates: simulated,
                        handUv: simulated ? service.joystickHandUv : null,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Miniaturas de luminancia 24 × 18; no son video completo. '
                'El mando usa una lente cada vez. No se ha medido la posición 3D de manos o pies.',
              ),
              const Divider(height: 24, color: Colors.white24),
              SwitchListTile.adaptive(
                key: const ValueKey(
                  VrConstants.keyToggleLiveCameraInspectorBtn,
                ),
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Cámara y passthrough del visor',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
                subtitle: const Text(
                  'Apagar quita la imagen y su mezcla de la vista VR. '
                  'El seguimiento óptico explícito puede seguir analizando sin mostrarla. '
                  'Textura GPU a 15 FPS solicitados; análisis limitado por separado. '
                  'Pausa VIO mientras la cámara esté abierta; '
                  'en el visor se comparte la misma lente entre ambos ojos.',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
                value: previewEnabled,
                onChanged: service.setVisorCameraPreviewEnabled,
              ),
              if (previewEnabled) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    key: const ValueKey(
                      VrConstants.keySwitchInspectorCameraLensBtn,
                    ),
                    onPressed: () => setState(() {
                      _lensDirection =
                          _lensDirection == CameraLensDirection.back
                          ? CameraLensDirection.front
                          : CameraLensDirection.back;
                    }),
                    icon: const Icon(
                      Icons.flip_camera_android_rounded,
                      size: 16,
                    ),
                    label: Text(
                      _lensDirection == CameraLensDirection.back
                          ? VrTranslationConstants.lensBackLabel
                          : VrTranslationConstants.lensFrontLabel,
                    ),
                  ),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    height: 190,
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        VrPassthroughCameraFeed(
                          lensDirection: _lensDirection,
                          service: service,
                          showLensBadge: true,
                          enableHardwareCamera: previewEnabled,
                        ),
                        if (simulated)
                          CustomPaint(
                            painter: VrSpatialWireframePainter(
                              segments: segments,
                              viewerPosition: service.latestHeadPosition,
                              viewerOrientation: service.latestHeadOrientation,
                              eyeOffsetMeters: 0,
                              opacity: 0.65,
                            ),
                          ),
                        if (simulated)
                          const Align(
                            alignment: Alignment.topCenter,
                            child: Text(
                              'Contornos de demostración',
                              style: TextStyle(color: Colors.amber),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              SwitchListTile.adaptive(
                key: const ValueKey(
                  VrConstants.keySpatialInspectorStereoHudSwitch,
                ),
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  VrTranslationConstants.stereoHudSwitchTitle,
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
                subtitle: const Text(
                  VrTranslationConstants.stereoHudSwitchSubtitle,
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
                value: service.spatialInspectorHudEnabled,
                onChanged: service.setSpatialInspectorHudEnabled,
              ),
              Text(
                '${VrTranslationConstants.passthroughCurtainTitle} · $mixPct%',
              ),
              Slider(
                key: const ValueKey(
                  VrConstants.keySettingsPassthroughMixSlider,
                ),
                value: service.passthroughMix,
                min: 0,
                max: 1,
                divisions: 20,
                label: '$mixPct%',
                onChanged: service.setPassthroughMix,
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _mixChip('Solo VR', 0, service),
                  _mixChip('35%', .35, service),
                  _mixChip('65%', .65, service),
                  _mixChip('Solo cámara', 1, service),
                ],
              ),
              const Text(
                'La cámara física debe estar habilitada para ver el entorno. '
                'Esta vista no detecta obstáculos ni sustituye mirar fuera del visor.',
              ),
              const Divider(height: 24, color: Colors.white24),
              Text(
                '${VrTranslationConstants.statureCalibrationTitle}: ${stature.toStringAsFixed(2)} m',
              ),
              Slider(
                key: const ValueKey(VrConstants.keySettingsUserStatureSlider),
                value: stature.clamp(
                  VrConstants.minStatureSliderMeters,
                  VrConstants.maxStatureSliderMeters,
                ),
                min: VrConstants.minStatureSliderMeters,
                max: VrConstants.maxStatureSliderMeters,
                divisions: 65,
                label: '${stature.toStringAsFixed(2)} m',
                onChanged: service.calibrateUserStature,
              ),
              const Text(
                'Estatura introducida por el usuario; la postura del avatar es una estimación, no una lectura biométrica.',
              ),
              const Divider(height: 24, color: Colors.white24),
              ExpansionTile(
                title: const Text('Diagnóstico avanzado de lentes'),
                subtitle: const Text(
                  'Datos ópticos publicados por el fabricante; no calculan la posición del otro teléfono.',
                ),
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('read-camera-calibration-diagnostics'),
                    onPressed: _readingCameraDiagnostics
                        ? null
                        : _readCameraDiagnostics,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: Text(
                      _readingCameraDiagnostics
                          ? 'Consultando…'
                          : 'Leer datos de lentes',
                    ),
                  ),
                  if (_cameraDiagnostics != null) ...[
                    const Text(
                      'Esta consulta solo aporta metadatos estáticos. El registro visual se calibra por separado.',
                    ),
                    SizedBox(
                      height: 180,
                      child: SingleChildScrollView(
                        child: SelectableText(
                          const JsonEncoder.withIndent(
                            '  ',
                          ).convert(_cameraDiagnostics),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              Container(
                key: const ValueKey(
                  VrConstants.keySpatialInputBindingVerificationPanel,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      VrTranslationConstants.verificationSectionTitle,
                      style: TextStyle(
                        color: Colors.amber,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Estos botones generan datos sintéticos para revisar el dibujo y las conexiones internas. '
                      'No verifican sensores físicos, escaneo RF, sonar o seguimiento corporal.',
                    ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        OutlinedButton(
                          key: const ValueKey(
                            VrConstants.keyVerifyBipedalWalkBtn,
                          ),
                          onPressed: service.simulateBipedalWalkStep,
                          child: const Text(
                            VrTranslationConstants.verifyBipedalWalkLabel,
                          ),
                        ),
                        OutlinedButton(
                          key: const ValueKey(VrConstants.keyVerify360ScanBtn),
                          onPressed: service.simulate360MultiModalScanSweep,
                          child: const Text(
                            VrTranslationConstants.verify360ScanLabel,
                          ),
                        ),
                        OutlinedButton(
                          key: const ValueKey(VrConstants.keyVerifyHandTofBtn),
                          onPressed: service.simulateHandAndUltrasonicRanging,
                          child: const Text(
                            VrTranslationConstants.verifyHandTofLabel,
                          ),
                        ),
                        OutlinedButton(
                          key: const ValueKey(
                            VrConstants.keyVerifyAllChannelsBtn,
                          ),
                          onPressed: service.runFullSpatialBindingVerification,
                          child: const Text(
                            VrTranslationConstants.verifyAllChannelsLabel,
                          ),
                        ),
                        if (simulated)
                          TextButton.icon(
                            onPressed: service.clearSimulation,
                            icon: const Icon(Icons.close),
                            label: const Text('Cerrar simulación'),
                          ),
                      ],
                    ),
                    if (simulated) ...[
                      SizedBox(
                        height: 145,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: VrTriCameraFrustumPainter(
                            bodyState: body,
                            passthroughMix: service.passthroughMix,
                          ),
                        ),
                      ),
                      Text(
                        'Esquema de demostración · ${segments.length} segmentos · '
                        '${service.scannedVoxelCount} puntos sintéticos',
                      ),
                    ],
                    Text(
                      service.lastVerificationReport,
                      key: const ValueKey(
                        VrConstants.keySpatialVerificationReportText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _monitor({
    required String badge,
    required bool hasFrame,
    required CustomPainter painter,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        badge,
        style: const TextStyle(color: Color(0xFF7DD3FC), fontSize: 10),
      ),
      const SizedBox(height: 4),
      SizedBox(
        height: 82,
        width: double.infinity,
        child: hasFrame
            ? CustomPaint(painter: painter)
            : const Center(child: Text('Sin fotograma recibido')),
      ),
      Text(
        hasFrame ? 'Última miniatura recibida · 24 × 18' : 'Sin medición',
        style: const TextStyle(fontSize: 9.5),
      ),
    ],
  );

  Widget _mixChip(
    String label,
    double value,
    VrSpatialTrackingService service,
  ) => ChoiceChip(
    label: Text(label),
    selected: (service.passthroughMix - value).abs() < .05,
    onSelected: (_) => service.setPassthroughMix(value),
  );
}
