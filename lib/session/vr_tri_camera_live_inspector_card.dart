import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

import '../utils/constants/vr_constants.dart';
import '../utils/constants/vr_translation_constants.dart';
import 'vr_joystick_mini_frame_painter.dart';
import 'vr_passthrough_camera_feed.dart';
import 'vr_spatial_tracking_service.dart';
import 'vr_tri_camera_frustum_painter.dart';

/// Unified interactive inspector card in Settings that displays all 3
/// synchronized cameras (`visor_front`, `joystick_rear`, `joystick_front`),
/// live physical camera preview + 3D AI wireframe contours, Breakthrough
/// curtain controls, and real-time mathematical calculations.
class VrTriCameraLiveInspectorCard extends StatefulWidget {
  const VrTriCameraLiveInspectorCard({
    super.key,
    required this.service,
  });

  final VrSpatialTrackingService service;

  @override
  State<VrTriCameraLiveInspectorCard> createState() =>
      _VrTriCameraLiveInspectorCardState();
}

class _VrTriCameraLiveInspectorCardState
    extends State<VrTriCameraLiveInspectorCard> {
  bool _liveCameraOpen = true;
  CameraLensDirection _lensDirection = CameraLensDirection.back;

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
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
    final mixPct = (service.passthroughMix * 100).round();
    final segments = service.spaceMapper.allContourSegments;
    final stature = body.anthropometry.statureMeters;
    final shoulderHeight = (body.headHeightMeters - 0.22).clamp(0.80, 1.85);
    final isC2Active =
        service.joystickActiveCameraRole != VrConstants.cameraRoleFront &&
        service.joystickActiveCameraRole != VrConstants.cameraRoleFrontUpper;

    return Container(
      key: const ValueKey(VrConstants.keyTriCameraLiveInspectorCard),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1325),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF00E5FF), width: 1.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.cameraswitch_rounded,
                color: Color(0xFF00E5FF),
                size: 22,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  VrTranslationConstants.triCameraInspectorTitle,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0x3310B981),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF10B981)),
                ),
                child: Text(
                  'IA: ${service.visorLiveEdgeCells} bordes · 19.4kHz',
                  style: const TextStyle(
                    color: Color(0xFF6EE7B7),
                    fontSize: 10.0,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Referencia activa: ${profile.visorModelName} (Visor) + '
            '${profile.joystickModelName} (Joystick)',
            style: const TextStyle(
              color: Color(0xFF7DD3FC),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),

          // Live Tri-Camera Frustum & 3D Skeleton Schematic
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
          const SizedBox(height: 12),

          // Live Joystick Dual-Camera Monitors (C2 Floor & C3 Hands/Torso)
          Row(
            children: [
              Expanded(
                child: _buildJoystickMonitorTile(
                  badge: VrTranslationConstants.badgeCam2FloorTitle,
                  accent: const Color(0xFF10B981),
                  subtitle:
                      'Pies UV: L(${service.joystickLeftFootUv.x.toStringAsFixed(2)},${service.joystickLeftFootUv.y.toStringAsFixed(2)}) '
                      'R(${service.joystickRightFootUv.x.toStringAsFixed(2)},${service.joystickRightFootUv.y.toStringAsFixed(2)})',
                  painter: VrJoystickMiniFramePainter(
                    lumaBytes: service.joystickRearMiniFrame,
                    isFloorCamera: true,
                    isLiveActive: isC2Active,
                    leftFootUv: service.joystickLeftFootUv,
                    rightFootUv: service.joystickRightFootUv,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildJoystickMonitorTile(
                  badge: VrTranslationConstants.badgeCam3HandsTitle,
                  accent: const Color(0xFFA855F7),
                  subtitle:
                      'Mano UV: (${service.joystickHandUv.x.toStringAsFixed(2)},${service.joystickHandUv.y.toStringAsFixed(2)}) · '
                      'ToF: $tofCm cm',
                  painter: VrJoystickMiniFramePainter(
                    lumaBytes: service.joystickFrontMiniFrame,
                    isFloorCamera: false,
                    isLiveActive: !isC2Active,
                    handUv: service.joystickHandUv,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 3 Camera Cards Grid
          _buildCameraStreamRow(
            badge: VrTranslationConstants.badgeCam1VisorTitle,
            accent: const Color(0xFF00E5FF),
            title: VrTranslationConstants.cam1StreamTitle,
            metrics:
                'FOV ${profile.visorForwardCameraFovDegrees.round()}° · '
                'Obstáculo IA: ${service.visorObstacleDistanceMeters.toStringAsFixed(2)} m · '
                'Bordes Sobel: ${service.visorLiveEdgeCells} · Aristas 3D: ${segments.length}',
          ),
          const SizedBox(height: 8),
          _buildCameraStreamRow(
            badge: VrTranslationConstants.badgeCam2StreamTitle,
            accent: const Color(0xFF10B981),
            title: VrTranslationConstants.cam2StreamTitle,
            metrics:
                'Cobertura Piso D_floor = ${floorSpan.toStringAsFixed(2)} m · '
                'Pie Izq (${body.leftFootPosition.x.toStringAsFixed(2)}, ${body.leftFootPosition.z.toStringAsFixed(2)}) m · '
                'Pie Der (${body.rightFootPosition.x.toStringAsFixed(2)}, ${body.rightFootPosition.z.toStringAsFixed(2)}) m',
          ),
          const SizedBox(height: 8),
          _buildCameraStreamRow(
            badge: VrTranslationConstants.badgeCam3StreamTitle,
            accent: const Color(0xFFA855F7),
            title: VrTranslationConstants.cam3StreamTitle,
            metrics:
                'Distancia Visor↔Mando d_VJ = $tofCm cm ($tofUs µs ToF · SNR ${service.ultrasonicSnrDb.toStringAsFixed(1)} dB) · '
                'Postura: ${body.postureState.name} · '
                'Hombros: ${body.anthropometry.shoulderWidthMeters.toStringAsFixed(2)} m',
          ),
          const SizedBox(height: 12),

          // Live Physical Camera + 3D AI Wireframe Preview Toggle
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  key: const ValueKey(
                    VrConstants.keyToggleLiveCameraInspectorBtn,
                  ),
                  onPressed: () =>
                      setState(() => _liveCameraOpen = !_liveCameraOpen),
                  icon: Icon(
                    _liveCameraOpen
                        ? Icons.videocam_off_rounded
                        : Icons.videocam_rounded,
                    size: 17,
                  ),
                  label: Text(
                    _liveCameraOpen
                        ? VrTranslationConstants.hideLiveCameraBtnLabel
                        : VrTranslationConstants.showLiveCameraBtnLabel,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              if (_liveCameraOpen) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  key: const ValueKey(
                    VrConstants.keySwitchInspectorCameraLensBtn,
                  ),
                  onPressed: () {
                    setState(() {
                      _lensDirection =
                          _lensDirection == CameraLensDirection.back
                          ? CameraLensDirection.front
                          : CameraLensDirection.back;
                    });
                  },
                  icon: const Icon(Icons.flip_camera_android_rounded, size: 16),
                  label: Text(
                    _lensDirection == CameraLensDirection.back
                        ? VrTranslationConstants.lensBackLabel
                        : VrTranslationConstants.lensFrontLabel,
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
              ],
            ],
          ),
          if (_liveCameraOpen) ...[
            const SizedBox(height: 10),
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
                    ),
                    CustomPaint(
                      painter: VrSpatialWireframePainter(
                        segments: segments,
                        viewerPosition: service.latestHeadPosition,
                        viewerOrientation: service.latestHeadOrientation,
                        eyeOffsetMeters: 0.0,
                        opacity: 0.95,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const Divider(height: 24, color: Colors.white24),

          // Toggle to show 3-Camera + Calculations HUD inside the stereoscopic Visor
          SwitchListTile.adaptive(
            key: const ValueKey(VrConstants.keySpatialInspectorStereoHudSwitch),
            contentPadding: EdgeInsets.zero,
            title: const Text(
              VrTranslationConstants.stereoHudSwitchTitle,
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: const Text(
              VrTranslationConstants.stereoHudSwitchSubtitle,
              style: TextStyle(color: Colors.white70, fontSize: 11.5),
            ),
            value: service.spatialInspectorHudEnabled,
            onChanged: service.setSpatialInspectorHudEnabled,
          ),

          const SizedBox(height: 8),

          // Breakthrough / Passthrough Curtain Slider (0% -> 100%)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                VrTranslationConstants.passthroughCurtainTitle,
                style: TextStyle(
                  color: Color(0xFF00E5FF),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '$mixPct%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          Slider(
            key: const ValueKey(VrConstants.keySettingsPassthroughMixSlider),
            value: service.passthroughMix,
            min: 0.0,
            max: 1.0,
            divisions: 20,
            activeColor: const Color(0xFF00E5FF),
            label: '$mixPct%',
            onChanged: service.setPassthroughMix,
          ),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildQuickMixChip(
                VrTranslationConstants.quickMix0Label,
                0.0,
                service,
              ),
              _buildQuickMixChip(
                VrTranslationConstants.quickMix35Label,
                0.35,
                service,
              ),
              _buildQuickMixChip(
                VrTranslationConstants.quickMix65Label,
                0.65,
                service,
              ),
              _buildQuickMixChip(
                VrTranslationConstants.quickMix100Label,
                1.0,
                service,
              ),
            ],
          ),

          const Divider(height: 24, color: Colors.white24),

          // User Stature Calibration & Mathematical Calculations Panel
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                VrTranslationConstants.statureCalibrationTitle,
                style: TextStyle(
                  color: Color(0xFFFCD34D),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${stature.toStringAsFixed(2)} m',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
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
            activeColor: const Color(0xFFF59E0B),
            label: '${stature.toStringAsFixed(2)} m',
            onChanged: service.calibrateUserStature,
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF060B16),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  VrTranslationConstants.liveMathSectionTitle,
                  style: TextStyle(
                    color: Color(0xFF80DEEA),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '• Estatura y ojos: H_user = H_head (${body.headHeightMeters.toStringAsFixed(2)} m) + Δ_crown (0.11 m) = ${stature.toStringAsFixed(2)} m\n'
                  '• Hombros y torso: H_shoulder = ${shoulderHeight.toStringAsFixed(2)} m · ΔP barométrico S25: ±6.5 cm\n'
                  '• Sonar Ultrasónico (20 kHz): d_VJ = (c_sound · Δt) / 2 = (343.2 · $tofUsµs) / 2 = ${body.headToJoystickDistanceMeters.toStringAsFixed(2)} m\n'
                  '• Cobertura de Piso (Cám 2 Ultrawide 119°): D_floor = 2 · H_chest · tan(FOV/2) = ${floorSpan.toStringAsFixed(2)} m · Vel. Pies = ${(-body.locomotionVelocity.z).clamp(0.0, 5.0).toStringAsFixed(2)} m/s\n'
                  '• Escaneo 360° (Cám 1 + Sonar + BLE + Wi-Fi): ${service.scannedVoxelCount} vóxeles activos · ${segments.length} aristas 3D · Profundidad recorrida: ${service.traversedDepthMeters.toStringAsFixed(2)} m',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Live Input Binding Verification Matrix & Self-Test Harness
          Container(
            key: const ValueKey(
              VrConstants.keySpatialInputBindingVerificationPanel,
            ),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF071122),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x6610B981)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.verified_rounded,
                      color: Color(0xFF34D399),
                      size: 16,
                    ),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        VrTranslationConstants.verificationSectionTitle,
                        style: TextStyle(
                          color: Color(0xFF6EE7B7),
                          fontSize: 11.8,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '1. IMU Visor (${service.rigImuFrames}f) -> Orientación 360° · '
                  '2. Cám 1 Mundo (${service.visorCamFrames}f) -> Odometría/Bordes\n'
                  '3. Cám 2 Piso (${service.joystickFloorFrames}f) -> Pies 3D + Caminata · '
                  '4. Cám 3 Torso (${service.joystickUpperFrames}f) -> Manos + Visor\n'
                  '5. Sonar 19.4kHz (${service.ultrasonicEchoCount} ecos) -> ToF $tofCm cm · '
                  '6. BLE+Wi-Fi RF (${service.rfBeaconSamples} muestras) -> ${service.scannedVoxelCount} vóxeles',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey(VrConstants.keyVerifyBipedalWalkBtn),
                      onPressed: service.simulateBipedalWalkStep,
                      icon: const Icon(Icons.directions_walk_rounded, size: 14),
                      label: const Text(
                        VrTranslationConstants.verifyBipedalWalkLabel,
                        style: TextStyle(fontSize: 10.5),
                      ),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey(VrConstants.keyVerify360ScanBtn),
                      onPressed: service.simulate360MultiModalScanSweep,
                      icon: const Icon(Icons.radar_rounded, size: 14),
                      label: const Text(
                        VrTranslationConstants.verify360ScanLabel,
                        style: TextStyle(fontSize: 10.5),
                      ),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey(VrConstants.keyVerifyHandTofBtn),
                      onPressed: service.simulateHandAndUltrasonicRanging,
                      icon: const Icon(Icons.pan_tool_alt_rounded, size: 14),
                      label: const Text(
                        VrTranslationConstants.verifyHandTofLabel,
                        style: TextStyle(fontSize: 10.5),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      key: const ValueKey(VrConstants.keyVerifyAllChannelsBtn),
                      onPressed: service.runFullSpatialBindingVerification,
                      icon: const Icon(Icons.fact_check_rounded, size: 14),
                      label: const Text(
                        VrTranslationConstants.verifyAllChannelsLabel,
                        style: TextStyle(fontSize: 10.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  service.lastVerificationReport,
                  key: const ValueKey(
                    VrConstants.keySpatialVerificationReportText,
                  ),
                  style: const TextStyle(
                    color: Color(0xFFA7F3D0),
                    fontSize: 10.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraStreamRow({
    required String badge,
    required Color accent,
    required String title,
    required String metrics,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF070E1C),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    color: accent,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            metrics,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJoystickMonitorTile({
    required String badge,
    required Color accent,
    required String subtitle,
    required CustomPainter painter,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF070E1C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            badge,
            style: TextStyle(
              color: accent,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 82,
              width: double.infinity,
              child: CustomPaint(painter: painter),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickMixChip(
    String label,
    double value,
    VrSpatialTrackingService service,
  ) {
    final selected = (service.passthroughMix - value).abs() < 0.05;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: selected,
      onSelected: (_) => service.setPassthroughMix(value),
    );
  }
}
