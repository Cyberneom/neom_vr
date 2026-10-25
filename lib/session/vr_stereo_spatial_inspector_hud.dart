import 'package:flutter/material.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

import '../utils/constants/vr_constants.dart';
import '../utils/constants/vr_translation_constants.dart';
import 'vr_joystick_mini_frame_painter.dart';
import 'vr_spatial_tracking_service.dart';
import 'vr_tri_camera_frustum_painter.dart';

/// Sensor diagnostics in both eyes. A mini-frame and a body estimate do not
/// imply simultaneous cameras, optical body tracking or measured RF depth.
class VrStereoSpatialInspectorHud extends StatelessWidget {
  const VrStereoSpatialInspectorHud({
    super.key,
    required this.service,
    required this.effectivePassthroughMix,
    required this.showFullInspector,
  });

  final VrSpatialTrackingService service;
  final double effectivePassthroughMix;
  final bool showFullInspector;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service.visualTracking,
    builder: (context, _) => _buildHud(context),
  );

  Widget _buildHud(BuildContext context) {
    final simulated = service.simulationActive;
    final body = service.latestBodyState;
    final pct = (effectivePassthroughMix * 100).round();
    final rear = service.joystickRearMiniFrame;
    final front = service.joystickFrontMiniFrame;
    return IgnorePointer(
      child: StereoHudOverlay(
        alignment: const Alignment(0, -.76),
        child: Container(
          key: const ValueKey(VrConstants.keyStereoSpatialInspectorHud),
          constraints: const BoxConstraints(maxWidth: 332),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xDC060D1A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x9938BDF8)),
          ),
          child: DefaultTextStyle(
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 8,
              height: 1.4,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  simulated
                      ? 'SIMULACIÓN · datos sintéticos'
                      : VrTranslationConstants.stereoHudInspectorIdleHeader,
                  style: TextStyle(
                    color: simulated ? Colors.amber : const Color(0xFFE0F7FA),
                    fontSize: 9.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Passthrough: ${service.visorCameraPreviewEnabled ? "visible · mezcla $pct%" : "apagado"} · '
                  'VIO: ${service.tracking ? "activo" : service.reason}',
                ),
                if (service.controllerOpticalTrackingEnabled)
                  Text(
                    'Cámara de seguimiento independiente · '
                    '${service.visualTracking.controllerPositionStatus}',
                    key: const ValueKey('controller-optical-tracking-hud'),
                  ),
                if (showFullInspector) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _miniMonitor(
                        label: VrTranslationConstants.miniMonitorC2Label,
                        hasFrame: rear != null,
                        painter: VrJoystickMiniFramePainter(
                          lumaBytes: rear,
                          isFloorCamera: true,
                          isLiveActive: false,
                          showEstimates: simulated,
                          leftFootUv: simulated
                              ? service.joystickLeftFootUv
                              : null,
                          rightFootUv: simulated
                              ? service.joystickRightFootUv
                              : null,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _miniMonitor(
                        label: VrTranslationConstants.miniMonitorC3Label,
                        hasFrame: front != null,
                        painter: VrJoystickMiniFramePainter(
                          lumaBytes: front,
                          isFloorCamera: false,
                          isLiveActive: false,
                          showEstimates: simulated,
                          handUv: simulated ? service.joystickHandUv : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Resúmenes C1: ${service.visorCamFrames}\n'
                          'Mando tras./front.: ${service.joystickFloorFrames}/${service.joystickUpperFrames}\n'
                          'Estatura manual: ${body.anthropometry.statureMeters.toStringAsFixed(2)} m\n'
                          'Sin ToF, profundidad RF ni cuerpo 3D medidos',
                        ),
                      ),
                    ],
                  ),
                  if (simulated) ...[
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 72,
                      height: 54,
                      child: CustomPaint(
                        painter: VrTriCameraFrustumPainter(
                          bodyState: body,
                          passthroughMix: effectivePassthroughMix,
                          compact: true,
                        ),
                      ),
                    ),
                    Text(
                      'Esquema de demostración · ${service.scannedVoxelCount} puntos sintéticos',
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniMonitor({
    required String label,
    required bool hasFrame,
    required CustomPainter painter,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 48,
        height: 38,
        child: hasFrame
            ? CustomPaint(painter: painter)
            : const Center(
                child: Text('Sin imagen', style: TextStyle(fontSize: 7)),
              ),
      ),
      const SizedBox(height: 2),
      Text(
        label,
        style: const TextStyle(color: Color(0xFF7DD3FC), fontSize: 7.2),
      ),
    ],
  );
}
