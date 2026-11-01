import 'dart:typed_data';

import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_scene/vrlizate_scene.dart';

import 'vr_desktop_capabilities.dart';
import 'vr_fiducial_tag_codec.dart';

/// Oriented 4-corner planar fiducial tag (`vrlizate://tag?node=visor&mm=48`)
/// detected in a Desktop webcam frame for millimeter `6-DoF` PnP pose solving.
class VrFiducialMarkerObservation {
  const VrFiducialMarkerObservation({
    required this.payload,
    required this.node,
    required this.markerSizeMeters,
    required this.corners,
    this.frameWidth = 640,
    this.frameHeight = 480,
  });

  final String payload;
  final VrFiducialNodeKind node;
  final double markerSizeMeters;

  /// Normalized `[0..1]` corners in `[topLeft, topRight, bottomRight, bottomLeft]`
  /// semantic order of the QR symbol.
  final List<VrDesktopKeypoint2D> corners;
  final int frameWidth;
  final int frameHeight;

  bool get isValid =>
      corners.length == 4 &&
      corners.every((c) => c.isValid) &&
      frameWidth >= 64 &&
      frameHeight >= 64 &&
      markerSizeMeters.isFinite &&
      markerSizeMeters >= (VrFiducialTagSpec.minSizeMm / 1000.0) &&
      markerSizeMeters <= (VrFiducialTagSpec.maxSizeMm / 1000.0);

  Map<String, Object?> toJson() => {
    'payload': payload,
    'node': node.wireName,
    'mm': markerSizeMeters * 1000.0,
    'frameWidth': frameWidth,
    'frameHeight': frameHeight,
    'corners': [for (final c in corners) c.toJson()],
  };

  static VrFiducialMarkerObservation? fromMap(
    Object? raw, {
    int defaultWidth = 640,
    int defaultHeight = 480,
  }) {
    if (raw is! Map) return null;
    final payload = (raw['payload'] as String?)?.trim() ?? '';
    final spec = VrFiducialTagSpec.tryParse(payload);
    final node = spec?.node ?? VrFiducialNodeKind.fromWire(raw['node'] as String?);
    if (node == null) return null;
    final mmRaw = (raw['mm'] as num?)?.toDouble() ?? spec?.markerSizeMm ?? node.defaultSizeMm;
    if (!mmRaw.isFinite ||
        mmRaw < VrFiducialTagSpec.minSizeMm ||
        mmRaw > VrFiducialTagSpec.maxSizeMm) {
      return null;
    }
    final rawCorners = raw['corners'];
    if (rawCorners is! List || rawCorners.length != 4) return null;
    final parsedCorners = <VrDesktopKeypoint2D>[];
    for (final entry in rawCorners) {
      final kp = VrDesktopKeypoint2D.fromMap(entry);
      if (kp == null) return null;
      parsedCorners.add(kp);
    }
    final fw = (raw['frameWidth'] as num?)?.toInt() ?? defaultWidth;
    final fh = (raw['frameHeight'] as num?)?.toInt() ?? defaultHeight;
    if (fw < 64 || fh < 64) return null;
    return VrFiducialMarkerObservation(
      payload: payload.isNotEmpty
          ? payload
          : VrFiducialTagSpec(node: node, markerSizeMm: mmRaw).toUri().toString(),
      node: node,
      markerSizeMeters: mmRaw / 1000.0,
      corners: List.unmodifiable(parsedCorners),
      frameWidth: fw,
      frameHeight: fh,
    );
  }
}

/// Semantic AI hand/arm gesture recognized by VRlizate Desktop Estación Faro.
enum VrBeaconHandGesture {
  none,
  leftRaised,
  rightRaised,
  bothRaised,
  leftPinch,
  rightPinch,
  wave,
}

/// Real-time facial expression or kinematic head gesture recognized by
/// Estación Faro (`VNDetectFaceLandmarksRequest` + Visor IMU fusion) for
/// 100% hands-free interaction without a Joystick.
enum VrFacialExpression {
  neutral,
  smile,
  mouthOpen,
  eyebrowsRaised,
  leftWink,
  rightWink,
  headNod,
  headShake,
  headTiltLeft,
  headTiltRight;

  String get labelEs => switch (this) {
    VrFacialExpression.neutral => 'Neutral',
    VrFacialExpression.smile => 'Sonrisa',
    VrFacialExpression.mouthOpen => 'Boca abierta',
    VrFacialExpression.eyebrowsRaised => 'Cejas alzadas',
    VrFacialExpression.leftWink => 'Guiño izquierdo',
    VrFacialExpression.rightWink => 'Guiño derecho',
    VrFacialExpression.headNod => 'Asentir (Sí)',
    VrFacialExpression.headShake => 'Negar (No)',
    VrFacialExpression.headTiltLeft => 'Inclinación izq.',
    VrFacialExpression.headTiltRight => 'Inclinación der.',
  };

  String get emoji => switch (this) {
    VrFacialExpression.neutral => '😐',
    VrFacialExpression.smile => '😊',
    VrFacialExpression.mouthOpen => '😮',
    VrFacialExpression.eyebrowsRaised => '🤨',
    VrFacialExpression.leftWink => '😉',
    VrFacialExpression.rightWink => '😜',
    VrFacialExpression.headNod => '🙂‍↕️',
    VrFacialExpression.headShake => '🙂‍↔️',
    VrFacialExpression.headTiltLeft => '↖️',
    VrFacialExpression.headTiltRight => '↗️',
  };

  String get actionHintEs => switch (this) {
    VrFacialExpression.neutral => 'En espera',
    VrFacialExpression.smile => 'Confirmar / Seleccionar',
    VrFacialExpression.mouthOpen => 'Activar micrófono Itzli',
    VrFacialExpression.eyebrowsRaised => 'Abrir / Cerrar Menú Sutil',
    VrFacialExpression.leftWink => 'Opción anterior',
    VrFacialExpression.rightWink => 'Siguiente opción',
    VrFacialExpression.headNod => 'Entrar / Aceptar',
    VrFacialExpression.headShake => 'Cerrar / Volver atrás',
    VrFacialExpression.headTiltLeft => 'Mover foco izquierda',
    VrFacialExpression.headTiltRight => 'Mover foco derecha',
  };

  static VrFacialExpression fromWire(String? raw) {
    if (raw == null || raw.isEmpty) return VrFacialExpression.neutral;
    for (final v in VrFacialExpression.values) {
      if (v.name == raw) return v;
    }
    return VrFacialExpression.neutral;
  }
}

/// Normalized 2D keypoint `[0..1]` in top-left image coordinates (`+u` right,
/// `+v` down) emitted by the Desktop AI pose/hand vision pipeline.
class VrDesktopKeypoint2D {
  const VrDesktopKeypoint2D(this.u, this.v, [this.confidence = 1.0]);

  final double u;
  final double v;
  final double confidence;

  bool get isValid =>
      u.isFinite && v.isFinite && confidence.isFinite && confidence >= 0.25;

  Map<String, double> toJson() => {'u': u, 'v': v, 'c': confidence};

  static VrDesktopKeypoint2D? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final u = (raw['u'] as num?)?.toDouble();
    final v = (raw['v'] as num?)?.toDouble();
    final c = (raw['c'] as num?)?.toDouble() ?? 0.0;
    if (u == null || v == null || !u.isFinite || !v.isFinite || !c.isFinite) {
      return null;
    }
    return VrDesktopKeypoint2D(u.clamp(0.0, 1.0), v.clamp(0.0, 1.0), c);
  }
}

/// Single AI vision observation captured by the computer's webcam.
///
/// Coordinates are normalized `[0..1]` in an unmirrored camera frame looking
/// out from the monitor into the room (`u=0` camera-left / user-right when
/// facing the screen; `v=0` top, `v=1` bottom). Anatomical labels (`left*`,
/// `right*`) always refer to the user's own left and right sides.
class VrDesktopVisionFrame {
  const VrDesktopVisionFrame({
    required this.timestampMicros,
    this.mirrored = false,
    this.eyesFromFaceLandmarks = false,
    this.nose,
    this.leftEye,
    this.rightEye,
    this.mouthCenter,
    this.facialExpression = VrFacialExpression.neutral,
    this.facialConfidence = 0.0,
    this.mouthOpenRatio,
    this.smileRatio,
    this.eyebrowRaiseRatio,
    this.leftShoulder,
    this.rightShoulder,
    this.leftElbow,
    this.rightElbow,
    this.leftWrist,
    this.rightWrist,
    this.leftIndexTip,
    this.leftThumbTip,
    this.rightIndexTip,
    this.rightThumbTip,
    this.leftPalmSpanNorm,
    this.rightPalmSpanNorm,
    this.leftExtendedFingers,
    this.rightExtendedFingers,
    this.leftHip,
    this.rightHip,
    this.qrPayload,
    this.fiducialTags = const [],
    this.frameWidth = 640,
    this.frameHeight = 480,
    this.miniFrameGray32x24,
    this.inferenceMs,
  });

  static const int miniWidth = 32;
  static const int miniHeight = 24;

  final int timestampMicros;
  final bool mirrored;
  final bool eyesFromFaceLandmarks;
  final VrDesktopKeypoint2D? nose;
  final VrDesktopKeypoint2D? leftEye;
  final VrDesktopKeypoint2D? rightEye;
  final VrDesktopKeypoint2D? mouthCenter;
  final VrFacialExpression facialExpression;
  final double facialConfidence;
  final double? mouthOpenRatio;
  final double? smileRatio;
  final double? eyebrowRaiseRatio;
  final VrDesktopKeypoint2D? leftShoulder;
  final VrDesktopKeypoint2D? rightShoulder;
  final VrDesktopKeypoint2D? leftElbow;
  final VrDesktopKeypoint2D? rightElbow;
  final VrDesktopKeypoint2D? leftWrist;
  final VrDesktopKeypoint2D? rightWrist;
  final VrDesktopKeypoint2D? leftIndexTip;
  final VrDesktopKeypoint2D? leftThumbTip;
  final VrDesktopKeypoint2D? rightIndexTip;
  final VrDesktopKeypoint2D? rightThumbTip;
  final double? leftPalmSpanNorm;
  final double? rightPalmSpanNorm;
  final int? leftExtendedFingers;
  final int? rightExtendedFingers;
  final VrDesktopKeypoint2D? leftHip;
  final VrDesktopKeypoint2D? rightHip;
  final String? qrPayload;
  final List<VrFiducialMarkerObservation> fiducialTags;
  final int frameWidth;
  final int frameHeight;
  final Uint8List? miniFrameGray32x24;
  final double? inferenceMs;

  bool get hasUpperBody =>
      (nose?.isValid ?? false) ||
      ((leftShoulder?.isValid ?? false) && (rightShoulder?.isValid ?? false));

  bool get hasLeftHand =>
      (leftWrist?.isValid ?? false) ||
      (leftIndexTip?.isValid ?? false) ||
      (leftThumbTip?.isValid ?? false);

  bool get hasRightHand =>
      (rightWrist?.isValid ?? false) ||
      (rightIndexTip?.isValid ?? false) ||
      (rightThumbTip?.isValid ?? false);

  bool get hasFiducialTag => fiducialTags.any((t) => t.isValid);

  static VrDesktopVisionFrame? fromPlatformMap(Map<dynamic, dynamic>? map) {
    if (map == null || map['status'] != 'ok') return null;
    final ts = (map['timestampMicros'] as num?)?.toInt() ?? 0;
    final fw = ((map['frameWidth'] as num?)?.toInt() ?? 640).clamp(64, 8192);
    final fh = ((map['frameHeight'] as num?)?.toInt() ?? 480).clamp(64, 8192);
    final rawMini = map['miniFrame'];
    Uint8List? mini;
    if (rawMini is Uint8List && rawMini.length == miniWidth * miniHeight) {
      mini = rawMini;
    }
    final parsedTags = <VrFiducialMarkerObservation>[];
    final rawTags = map['fiducialTags'];
    if (rawTags is List) {
      for (final rawTag in rawTags) {
        final obs = VrFiducialMarkerObservation.fromMap(
          rawTag,
          defaultWidth: fw,
          defaultHeight: fh,
        );
        if (obs != null && obs.isValid) parsedTags.add(obs);
      }
    }
    return VrDesktopVisionFrame(
      timestampMicros: ts,
      mirrored: map['mirrored'] == true,
      eyesFromFaceLandmarks: map['eyesFromFaceLandmarks'] == true,
      nose: VrDesktopKeypoint2D.fromMap(map['nose']),
      leftEye: VrDesktopKeypoint2D.fromMap(map['leftEye']),
      rightEye: VrDesktopKeypoint2D.fromMap(map['rightEye']),
      mouthCenter: VrDesktopKeypoint2D.fromMap(map['mouthCenter']),
      facialExpression: VrFacialExpression.fromWire(
        map['facialExpression'] as String?,
      ),
      facialConfidence:
          ((map['facialConfidence'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 1.0),
      mouthOpenRatio: (map['mouthOpenRatio'] as num?)?.toDouble(),
      smileRatio: (map['smileRatio'] as num?)?.toDouble(),
      eyebrowRaiseRatio: (map['eyebrowRaiseRatio'] as num?)?.toDouble(),
      leftShoulder: VrDesktopKeypoint2D.fromMap(map['leftShoulder']),
      rightShoulder: VrDesktopKeypoint2D.fromMap(map['rightShoulder']),
      leftElbow: VrDesktopKeypoint2D.fromMap(map['leftElbow']),
      rightElbow: VrDesktopKeypoint2D.fromMap(map['rightElbow']),
      leftWrist: VrDesktopKeypoint2D.fromMap(map['leftWrist']),
      rightWrist: VrDesktopKeypoint2D.fromMap(map['rightWrist']),
      leftIndexTip: VrDesktopKeypoint2D.fromMap(map['leftIndexTip']),
      leftThumbTip: VrDesktopKeypoint2D.fromMap(map['leftThumbTip']),
      rightIndexTip: VrDesktopKeypoint2D.fromMap(map['rightIndexTip']),
      rightThumbTip: VrDesktopKeypoint2D.fromMap(map['rightThumbTip']),
      leftPalmSpanNorm: (map['leftPalmSpan'] as num?)?.toDouble(),
      rightPalmSpanNorm: (map['rightPalmSpan'] as num?)?.toDouble(),
      leftExtendedFingers: (map['leftExtendedFingers'] as num?)?.toInt(),
      rightExtendedFingers: (map['rightExtendedFingers'] as num?)?.toInt(),
      leftHip: VrDesktopKeypoint2D.fromMap(map['leftHip']),
      rightHip: VrDesktopKeypoint2D.fromMap(map['rightHip']),
      qrPayload: map['qrPayload'] as String?,
      fiducialTags: List.unmodifiable(parsedTags),
      frameWidth: fw,
      frameHeight: fh,
      miniFrameGray32x24: mini,
      inferenceMs: (map['inferenceMs'] as num?)?.toDouble(),
    );
  }
}

/// Lightweight telemetry reported by the Visor back to VRlizate Desktop so the
/// computer can close the 3-node kinematic triangle (`PC ↔ Visor ↔ Joystick`)
/// while the Visor autonomously runs the `.vrlz` experience.
class VrVisorBeaconFeedback {
  VrVisorBeaconFeedback({
    required this.timestampMicros,
    vm.Quaternion? visorOrientation,
    vm.Quaternion? joystickOrientation,
    this.visorToJoystickMeters,
    this.desktopBleRssiDbm,
    this.desktopSonarAzimuthRad,
    this.joystickConnected = false,
    this.activeExperience = 'Virtual Home',
    this.visorFps = 60.0,
    this.castViewerUri,
    this.rttMs,
    this.visorCapabilities,
    this.joystickCapabilities,
  }) : visorOrientation = visorOrientation?.clone() ?? vm.Quaternion.identity(),
       joystickOrientation =
           joystickOrientation?.clone() ?? vm.Quaternion.identity();

  final int timestampMicros;
  final vm.Quaternion visorOrientation;
  final vm.Quaternion joystickOrientation;
  final double? visorToJoystickMeters;
  final double? desktopBleRssiDbm;
  final double? desktopSonarAzimuthRad;
  final bool joystickConnected;
  final String activeExperience;
  final double visorFps;

  /// Authenticated LAN viewer URL of the Visor's active [VrCastHost] session so
  /// VRlizate Desktop can render the `.vrlz` experience on the computer screen
  /// while freeing the Joystick smartphone from video decoding.
  final String? castViewerUri;

  /// Measured round-trip network latency between Visor and Desktop in ms.
  final double? rttMs;

  /// Hardware capabilities of the Smartphone Visor (`RAM`, `Hz`, `Wi-Fi`, etc.).
  final VrMobileNodeCapabilities? visorCapabilities;

  /// Hardware capabilities of the attached Smartphone Joystick (`gyro`, `BLE`, etc.).
  final VrMobileNodeCapabilities? joystickCapabilities;

  static String? _sanitizeCastUri(Object? raw) {
    if (raw is! String || raw.isEmpty || raw.length > 512) return null;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      return null;
    }
    return uri.toString();
  }

  static double _round5(double v) =>
      v.isFinite ? (v * 100000.0).round() / 100000.0 : 0.0;

  static double _round3(double v) =>
      v.isFinite ? (v * 1000.0).round() / 1000.0 : 0.0;

  VrVisorBeaconFeedback withFallbackCapabilities({
    VrMobileNodeCapabilities? fallbackVisorCapabilities,
    VrMobileNodeCapabilities? fallbackJoystickCapabilities,
  }) {
    final nextVc = visorCapabilities ?? fallbackVisorCapabilities;
    final nextJc = joystickCapabilities ?? fallbackJoystickCapabilities;
    if (identical(nextVc, visorCapabilities) &&
        identical(nextJc, joystickCapabilities)) {
      return this;
    }
    return VrVisorBeaconFeedback(
      timestampMicros: timestampMicros,
      visorOrientation: visorOrientation,
      joystickOrientation: joystickOrientation,
      visorToJoystickMeters: visorToJoystickMeters,
      desktopBleRssiDbm: desktopBleRssiDbm,
      desktopSonarAzimuthRad: desktopSonarAzimuthRad,
      joystickConnected: joystickConnected,
      activeExperience: activeExperience,
      visorFps: visorFps,
      castViewerUri: castViewerUri,
      rttMs: rttMs,
      visorCapabilities: nextVc,
      joystickCapabilities: nextJc,
    );
  }

  Map<String, Object?> toJson({bool includeCapabilities = true}) => {
    'ts': timestampMicros,
    'vq': [
      _round5(visorOrientation.x),
      _round5(visorOrientation.y),
      _round5(visorOrientation.z),
      _round5(visorOrientation.w),
    ],
    'jq': [
      _round5(joystickOrientation.x),
      _round5(joystickOrientation.y),
      _round5(joystickOrientation.z),
      _round5(joystickOrientation.w),
    ],
    if (visorToJoystickMeters != null && visorToJoystickMeters!.isFinite)
      'dvj': _round3(visorToJoystickMeters!),
    if (desktopBleRssiDbm != null && desktopBleRssiDbm!.isFinite)
      'rssi': double.parse(desktopBleRssiDbm!.toStringAsFixed(1)),
    if (desktopSonarAzimuthRad != null && desktopSonarAzimuthRad!.isFinite)
      'az': _round3(desktopSonarAzimuthRad!),
    'joy': joystickConnected,
    'exp': activeExperience.length > 48
        ? activeExperience.substring(0, 48)
        : activeExperience,
    'fps': double.parse(visorFps.clamp(1.0, 240.0).toStringAsFixed(1)),
    if (_sanitizeCastUri(castViewerUri) case final cleanUri?) 'cast': cleanUri,
    if (rttMs != null && rttMs!.isFinite)
      'rtt': double.parse(rttMs!.clamp(0.0, 2000.0).toStringAsFixed(1)),
    if (includeCapabilities && visorCapabilities != null)
      'vc': visorCapabilities!.toJson(),
    if (includeCapabilities && joystickCapabilities != null)
      'jc': joystickCapabilities!.toJson(),
  };

  static VrVisorBeaconFeedback? fromJson(Map<String, dynamic> map) {
    final ts = (map['ts'] as num?)?.toInt();
    if (ts == null || ts < 0) return null;
    vm.Quaternion? parseQ(Object? raw) {
      if (raw is! List || raw.length != 4) return null;
      final vals = raw.map((e) => (e as num?)?.toDouble()).toList();
      if (vals.any((v) => v == null || !v.isFinite)) return null;
      final q = vm.Quaternion(vals[0]!, vals[1]!, vals[2]!, vals[3]!);
      if (q.length2 < 1e-9) return null;
      return q..normalize();
    }

    return VrVisorBeaconFeedback(
      timestampMicros: ts,
      visorOrientation: parseQ(map['vq']),
      joystickOrientation: parseQ(map['jq']),
      visorToJoystickMeters: (map['dvj'] as num?)?.toDouble(),
      desktopBleRssiDbm: (map['rssi'] as num?)?.toDouble(),
      desktopSonarAzimuthRad: (map['az'] as num?)?.toDouble(),
      joystickConnected: map['joy'] == true,
      activeExperience: (map['exp'] as String?) ?? 'VRlizate',
      visorFps: ((map['fps'] as num?)?.toDouble() ?? 60.0).clamp(1.0, 240.0),
      castViewerUri: _sanitizeCastUri(map['cast']),
      rttMs: (map['rtt'] as num?)?.toDouble(),
      visorCapabilities: VrMobileNodeCapabilities.fromJson(map['vc']),
      joystickCapabilities: VrMobileNodeCapabilities.fromJson(map['jc']),
    );
  }
}

/// Complete 3-node triangulation (`Computadora ↔ Visor ↔ Joystick`) + AI 3D
/// hand/arm tracking state solved by VRlizate Desktop Estación Faro.
///
/// Frame convention for `visorRoomPosition` and `joystickRoomPosition`:
/// - Origin `(0, 0, 0)` is the Desktop monitor/webcam center at desk height.
/// - When the user stands in front of the desk facing the screen, their local
///   VR room coordinates place the desk ahead at `-Z`, so stepping backward
///   away from the desk increases `+Z` (`visorRoomPosition.z` is negative when
///   expressed from user origin, or `computerToVisorMeters` along the ray).
///   Specifically, `visorRoomPosition` is expressed in gravity-aligned viewer
///   world meters centered on the calibrated standing spot `1.50 m` in front of
///   the desk: `(0, 1.60, 0)` = standing `1.50 m` from the PC; leaning `0.30 m`
///   closer to the monitor moves `z` to `-0.30 m`; stepping right moves `+x`.
class VrTriNodeDepthSolution {
  VrTriNodeDepthSolution({
    required this.timestampMicros,
    required this.sequence,
    required this.computerToVisorMeters,
    required this.computerToJoystickMeters,
    required this.visorToJoystickMeters,
    required vm.Vector3 visorRoomPosition,
    required vm.Vector3 joystickRoomPosition,
    required this.deskClearanceMeters,
    required this.visorAzimuthRadians,
    required this.yawAnchorCorrectionRadians,
    required vm.Vector3 leftHandRelHead,
    required vm.Vector3 rightHandRelHead,
    vm.Vector3? leftHandVelocity,
    vm.Vector3? rightHandVelocity,
    required this.leftHandConfidence,
    required this.rightHandConfidence,
    required this.leftHandRaised,
    required this.rightHandRaised,
    required this.leftPinchStrength,
    required this.rightPinchStrength,
    required this.gesture,
    required this.confidence,
    this.activeModalitiesMask = 0,
    this.visorFiducialLocked = false,
    this.joystickFiducialLocked = false,
    this.visorFiducialReprojectionRmsPx,
    this.estimatedUserIpdMeters,
    this.facialExpression = VrFacialExpression.neutral,
    this.facialConfidence = 0.0,
  }) : _visorRoomPosition = visorRoomPosition.clone(),
       _joystickRoomPosition = joystickRoomPosition.clone(),
       _leftHandRelHead = leftHandRelHead.clone(),
       _rightHandRelHead = rightHandRelHead.clone(),
       _leftHandVelocity = leftHandVelocity?.clone() ?? vm.Vector3.zero(),
       _rightHandVelocity = rightHandVelocity?.clone() ?? vm.Vector3.zero();

  static const int modalityWebcamAi = 1 << 0;
  static const int modalityBleBeacon = 1 << 1;
  static const int modalityWifiUdp = 1 << 2;
  static const int modalityStereoSonar = 1 << 3;
  static const int modalityMonitorFiducial = 1 << 4;
  static const int modalityFiducialPnp = 1 << 5;

  final int timestampMicros;
  final int sequence;

  /// Metric distance $d_{CV}$ from Computer `(0,0,0)` to Visor smartphone.
  final double computerToVisorMeters;

  /// Metric distance $d_{CJ}$ from Computer `(0,0,0)` to Joystick / Hands.
  final double computerToJoystickMeters;

  /// Triangulated 3D distance $d_{VJ}$ between Visor and Joystick smartphones.
  final double visorToJoystickMeters;

  final vm.Vector3 _visorRoomPosition;
  final vm.Vector3 _joystickRoomPosition;
  final double deskClearanceMeters;
  final double visorAzimuthRadians;
  final double yawAnchorCorrectionRadians;

  final vm.Vector3 _leftHandRelHead;
  final vm.Vector3 _rightHandRelHead;
  final vm.Vector3 _leftHandVelocity;
  final vm.Vector3 _rightHandVelocity;

  final double leftHandConfidence;
  final double rightHandConfidence;
  final bool leftHandRaised;
  final bool rightHandRaised;
  final double leftPinchStrength;
  final double rightPinchStrength;
  final VrBeaconHandGesture gesture;
  final double confidence;
  final int activeModalitiesMask;
  final bool visorFiducialLocked;
  final bool joystickFiducialLocked;
  final double? visorFiducialReprojectionRmsPx;
  final double? estimatedUserIpdMeters;
  final VrFacialExpression facialExpression;
  final double facialConfidence;

  vm.Vector3 get visorRoomPosition => _visorRoomPosition.clone();
  vm.Vector3 get joystickRoomPosition => _joystickRoomPosition.clone();
  vm.Vector3 get leftHandRelHead => _leftHandRelHead.clone();
  vm.Vector3 get rightHandRelHead => _rightHandRelHead.clone();
  vm.Vector3 get leftHandVelocity => _leftHandVelocity.clone();
  vm.Vector3 get rightHandVelocity => _rightHandVelocity.clone();

  bool get anyHandRaised => leftHandRaised || rightHandRaised;

  VrTrackedHandsSnapshot toTrackedHandsSnapshot() => VrTrackedHandsSnapshot(
    timestampMicros: timestampMicros,
    sourceLabel: 'Estación Faro Desktop IA',
    left: leftHandConfidence >= 0.25
        ? VrTrackedHandSample(
            headRelativeMeters: _leftHandRelHead,
            velocityMetersPerSec: _leftHandVelocity,
            confidence: leftHandConfidence,
            raised: leftHandRaised,
            pinchStrength: leftPinchStrength,
          )
        : null,
    right: rightHandConfidence >= 0.25
        ? VrTrackedHandSample(
            headRelativeMeters: _rightHandRelHead,
            velocityMetersPerSec: _rightHandVelocity,
            confidence: rightHandConfidence,
            raised: rightHandRaised,
            pinchStrength: rightPinchStrength,
          )
        : null,
  );
}

/// Summary of a VRlizate Desktop Estación Faro discovered on the local LAN.
class VrDiscoveredDesktopBeacon {
  const VrDiscoveredDesktopBeacon({
    required this.stationId,
    required this.stationName,
    required this.host,
    required this.port,
    required this.capabilitiesMask,
    required this.lastSeenMicros,
    this.monitorWidthMm = 344,
    this.monitorHeightMm = 215,
  });

  final String stationId;
  final String stationName;
  final String host;
  final int port;
  final int capabilitiesMask;
  final int lastSeenMicros;
  final int monitorWidthMm;
  final int monitorHeightMm;
}

/// Authenticated spoken command relayed from Estación Faro Desktop mic/console
/// to the paired Smartphone Visor (`VRB1` `voiceCommandKind = 11`).
class VrBeaconVoiceCommandPacket {
  const VrBeaconVoiceCommandPacket({
    required this.sequence,
    required this.timestampMicros,
    required this.transcript,
    this.source = 'desktop_mic',
  });

  final int sequence;
  final int timestampMicros;
  final String transcript;
  final String source;

  Map<String, Object?> toJson() => {
    'seq': sequence,
    'ts': timestampMicros,
    'txt': transcript.length > 240
        ? transcript.substring(0, 240)
        : transcript,
    'src': source.length > 32 ? source.substring(0, 32) : source,
  };

  static VrBeaconVoiceCommandPacket? fromJson(Map<String, dynamic> map) {
    final seq = (map['seq'] as num?)?.toInt();
    final ts = (map['ts'] as num?)?.toInt();
    final txt = (map['txt'] as String?)?.trim() ?? '';
    if (seq == null || seq < 0 || ts == null || ts < 0 || txt.isEmpty) {
      return null;
    }
    return VrBeaconVoiceCommandPacket(
      sequence: seq,
      timestampMicros: ts,
      transcript: txt,
      source: (map['src'] as String?)?.trim() ?? 'desktop_mic',
    );
  }
}
