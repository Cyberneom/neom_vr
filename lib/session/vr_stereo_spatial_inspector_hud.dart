import 'package:flutter/material.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

import '../utils/constants/vr_constants.dart';
import '../utils/constants/vr_translation_constants.dart';
import 'vr_joystick_mini_frame_painter.dart';
import 'vr_spatial_tracking_service.dart';
import 'vr_tri_camera_frustum_painter.dart';

/// Stereoscopic HUD rendered inside both eyes of the VR Visor to display
/// the 3 synchronized cameras (`visor_front`, `joystick_rear`, `joystick_front`),
/// live Joystick camera feeds (C2 Floor & C3 Hands/Torso), the Breakthrough
/// Passthrough curtain status, and the real-time biometric/spatial calculations.
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
  Widget build(BuildContext context) {
    final pct = (effectivePassthroughMix * 100).round();
    final body = service.latestBodyState;
    final profile = service.deviceProfile;
    final floorSpan = profile.floorCoverageDiameterMeters(
      joystickHeightMeters: VrConstants.defaultJoystickWaistHeightMeters,
    );
    final tofCm = (body.headToJoystickDistanceMeters * 100).round();
    final tofUs =
        (body.headToJoystickDistanceMeters *
                2.0 /
                VrConstants.defaultSpeedOfSoundMetersPerSec *
                1000000)
            .round();
    final isC2Active =
        service.joystickActiveCameraRole != VrConstants.cameraRoleFront &&
        service.joystickActiveCameraRole != VrConstants.cameraRoleFrontUpper;

    return IgnorePointer(
      child: StereoHudOverlay(
        alignment: const Alignment(0, -0.76),
        child: Container(
          key: const ValueKey(VrConstants.keyStereoSpatialInspectorHud),
          constraints: const BoxConstraints(maxWidth: 332),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xDC060D1A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: effectivePassthroughMix > 0.01
                  ? const Color(0xFF00E5FF)
                  : const Color(0x9938BDF8),
              width: 1.2,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x5500E5FF),
                blurRadius: 10,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    effectivePassthroughMix > 0.01
                        ? Icons.visibility_rounded
                        : Icons.videocam_rounded,
                    size: 13,
                    color: const Color(0xFF00E5FF),
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      effectivePassthroughMix > 0.01
                          ? 'BREAKTHROUGH ESTÉREO: $pct% · 3 CÁM + IA 3D'
                          : VrTranslationConstants.stereoHudInspectorIdleHeader,
                      style: const TextStyle(
                        color: Color(0xFFE0F7FA),
                        fontSize: 9.2,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.25,
                      ),
                    ),
                  ),
                ],
              ),
              if (effectivePassthroughMix > 0.01) ...[
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: effectivePassthroughMix.clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: const Color(0x3300E5FF),
                    color: effectivePassthroughMix > 0.85
                        ? const Color(0xFF34D399)
                        : const Color(0xFF00E5FF),
                  ),
                ),
              ],
              if (showFullInspector) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 1. Tri-Camera Radar
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
                    const SizedBox(width: 5),
                    // 2. Live Joystick Camera C2 (Floor & Feet)
                    _buildMiniCameraMonitor(
                      label: VrTranslationConstants.miniMonitorC2Label,
                      accent: const Color(0xFF10B981),
                      painter: VrJoystickMiniFramePainter(
                        lumaBytes: service.joystickRearMiniFrame,
                        isFloorCamera: true,
                        isLiveActive: isC2Active,
                        leftFootUv: service.joystickLeftFootUv,
                        rightFootUv: service.joystickRightFootUv,
                      ),
                    ),
                    const SizedBox(width: 5),
                    // 3. Live Joystick Camera C3 (Upper Body & Hands)
                    _buildMiniCameraMonitor(
                      label: VrTranslationConstants.miniMonitorC3Label,
                      accent: const Color(0xFFA855F7),
                      painter: VrJoystickMiniFramePainter(
                        lumaBytes: service.joystickFrontMiniFrame,
                        isFloorCamera: false,
                        isLiveActive: !isC2Active,
                        handUv: service.joystickHandUv,
                      ),
                    ),
                    const SizedBox(width: 6),
                    // 4. Live Calculations & Ultrasonic Ranging
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'C1 IA:${service.visorLiveEdgeCells}b · Vóxeles:${service.scannedVoxelCount} · Prof:${service.traversedDepthMeters.toStringAsFixed(2)}m',
                            style: const TextStyle(
                              color: Color(0xFF7DD3FC),
                              fontSize: 7.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'ToF 19.4kHz: d_VJ=$tofCm cm ($tofUsµs)',
                            style: const TextStyle(
                              color: Color(0xFFFCD34D),
                              fontSize: 7.8,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'H_user=${body.anthropometry.statureMeters.toStringAsFixed(2)}m · Piso=${floorSpan.toStringAsFixed(1)}m',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 7.6,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Pies L(${body.leftFootPosition.x.toStringAsFixed(2)},${body.leftFootPosition.z.toStringAsFixed(2)}) '
                            'R(${body.rightFootPosition.x.toStringAsFixed(2)},${body.rightFootPosition.z.toStringAsFixed(2)})',
                            style: const TextStyle(
                              color: Color(0xFF6EE7B7),
                              fontSize: 7.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniCameraMonitor({
    required String label,
    required Color accent,
    required CustomPainter painter,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: 48,
            height: 38,
            child: CustomPaint(painter: painter),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: accent,
            fontSize: 7.2,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
