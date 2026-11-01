import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'vr_desktop_beacon_models.dart';
import 'vr_fiducial_tag_codec.dart';

/// Platform abstraction for Desktop webcam + AI body/hand pose extraction.
abstract interface class VrDesktopVisionPlatform {
  Future<bool> isSupported();
  Future<Map<String, dynamic>?> readCapabilities() async => null;
  Future<bool> startCapture();
  Future<void> stopCapture();
  Stream<VrDesktopVisionFrame> get frames;
}

/// Native MethodChannel / EventChannel implementation (`vrlizate/desktop_beacon_vision`).
///
/// On macOS, backed by `AVCaptureSession` + Apple `Vision`
/// (`VNDetectHumanBodyPoseRequest` + `VNDetectHumanHandPoseRequest`).
class MethodChannelVrDesktopVisionPlatform implements VrDesktopVisionPlatform {
  static const _methods = MethodChannel('vrlizate/desktop_beacon_vision');
  static const _events = EventChannel('vrlizate/desktop_beacon_vision/frames');

  @override
  Future<bool> isSupported() async {
    if (kIsWeb) return false;
    try {
      final res = await _methods
          .invokeMapMethod<String, dynamic>('availability')
          .timeout(const Duration(seconds: 2));
      return res?['supported'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>?> readCapabilities() async {
    if (kIsWeb) return null;
    try {
      return await _methods
          .invokeMapMethod<String, dynamic>('capabilities')
          .timeout(const Duration(milliseconds: 800));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> startCapture() async {
    if (kIsWeb) return false;
    try {
      // Allow up to 60s on first launch so macOS/Windows camera permission
      // prompt does not time out before the user clicks Allow.
      final res = await _methods
          .invokeMapMethod<String, dynamic>('start')
          .timeout(const Duration(seconds: 60));
      return res?['started'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> stopCapture() async {
    if (kIsWeb) return;
    try {
      await _methods
          .invokeMethod<void>('stop')
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  @override
  Stream<VrDesktopVisionFrame> get frames => _events
      .receiveBroadcastStream()
      .map((raw) => raw is Map ? VrDesktopVisionFrame.fromPlatformMap(raw) : null)
      .where((frame) => frame != null)
      .cast<VrDesktopVisionFrame>();
}

/// Deterministic interactive vision generator used when testing on headless
/// desktops or exercising specific hand-raise/depth gestures from the Faro UI.
class VrSyntheticDesktopVisionGenerator {
  double simulatedDistanceMeters = 1.48;
  double simulatedLateralMeters = 0.0;
  bool simulateLeftRaised = false;
  bool simulateRightRaised = false;
  bool simulateRightPinch = false;
  bool simulateWave = false;
  bool simulateFiducialTag = false;
  VrFacialExpression simulatedFacialExpression = VrFacialExpression.neutral;

  VrDesktopVisionFrame sample(int nowMicros) {
    final t = nowMicros / 1e6;
    // Shoulder span scales inversely with distance (w ~ 0.25 at 1.50m)
    final span = (0.375 / simulatedDistanceMeters.clamp(0.55, 3.5)).clamp(
      0.08,
      0.62,
    );
    final centerU = (0.5 + simulatedLateralMeters * 0.22).clamp(0.20, 0.80);
    final shoulderV = 0.48;
    final headV = (shoulderV - span * 0.45).clamp(0.12, 0.75);

    final waveOffset = simulateWave ? math.sin(t * 7.5) * 0.10 : 0.0;
    final leftU = (centerU - span * 0.5).clamp(0.08, 0.92);
    final rightU = (centerU + span * 0.5).clamp(0.08, 0.92);

    final lwU = (leftU - 0.04).clamp(0.05, 0.95);
    final lwV = simulateLeftRaised ? (shoulderV - 0.16) : (shoulderV + 0.18);

    final rwU = (rightU + 0.04 + waveOffset).clamp(0.05, 0.95);
    final rwV = (simulateRightRaised || simulateWave || simulateRightPinch)
        ? (shoulderV - 0.17)
        : (shoulderV + 0.18);

    final pinchGap = simulateRightPinch ? 0.008 : 0.085;

    final mini = Uint8List(
      VrDesktopVisionFrame.miniWidth * VrDesktopVisionFrame.miniHeight,
    );
    for (var y = 0; y < VrDesktopVisionFrame.miniHeight; y++) {
      for (var x = 0; x < VrDesktopVisionFrame.miniWidth; x++) {
        final u = x / VrDesktopVisionFrame.miniWidth;
        final v = y / VrDesktopVisionFrame.miniHeight;
        final dHead = (u - centerU) * (u - centerU) + (v - headV) * (v - headV);
        final dTorso =
            (u - centerU).abs() < span * 0.52 &&
            v >= shoulderV &&
            v <= shoulderV + 0.32;
        final dLeft = (u - lwU) * (u - lwU) + (v - lwV) * (v - lwV) < 0.006;
        final dRight = (u - rwU) * (u - rwU) + (v - rwV) * (v - rwV) < 0.006;
        mini[y * VrDesktopVisionFrame.miniWidth + x] = dHead < 0.008
            ? 235
            : (dLeft || dRight)
            ? 250
            : dTorso
            ? 145
            : ((x % 8 == 0 || y % 6 == 0) ? 38 : 22);
      }
    }

    final tags = <VrFiducialMarkerObservation>[];
    if (simulateFiducialTag) {
      const fw = 640;
      const fh = 480;
      final halfTanX = math.tan((68.0 * math.pi / 180.0) * 0.5);
      final fx = (fw * 0.5) / halfTanX;
      final zCam = simulatedDistanceMeters.clamp(0.55, 3.50);
      final xCam = -simulatedLateralMeters;
      const yCam = -0.42; // 1.60m standing eye height vs 1.18m desk camera
      const halfTag = 0.024; // 48 mm Visor fiducial tag
      final pts = <List<double>>[
        [xCam - halfTag, yCam - halfTag],
        [xCam + halfTag, yCam - halfTag],
        [xCam + halfTag, yCam + halfTag],
        [xCam - halfTag, yCam + halfTag],
      ];
      final corners = <VrDesktopKeypoint2D>[];
      for (final p in pts) {
        final px = fx * (p[0] / zCam) + fw * 0.5;
        final py = fx * (p[1] / zCam) + fh * 0.5;
        final uUnmirrored = (px / fw).clamp(0.0, 1.0);
        // Synthetic frame is mirrored: u_mirrored = 1.0 - u_unmirrored.
        corners.add(
          VrDesktopKeypoint2D(
            (1.0 - uUnmirrored).clamp(0.0, 1.0),
            (py / fh).clamp(0.0, 1.0),
            1.0,
          ),
        );
      }
      tags.add(
        VrFiducialMarkerObservation(
          payload: VrFiducialTagCodec.defaultVisorTag.toUri().toString(),
          node: VrFiducialNodeKind.visor,
          markerSizeMeters: 0.048,
          corners: corners,
          frameWidth: fw,
          frameHeight: fh,
        ),
      );
    }

    final halfTanX = math.tan((68.0 * math.pi / 180.0) * 0.5);
    final focalNormX = 0.5 / halfTanX;
    final halfEyeSpan =
        (0.5 * focalNormX * 0.064 / simulatedDistanceMeters.clamp(0.55, 3.50))
            .clamp(0.006, 0.055);

    return VrDesktopVisionFrame(
      timestampMicros: nowMicros,
      mirrored: true,
      nose: VrDesktopKeypoint2D(centerU, headV, 0.96),
      leftEye: VrDesktopKeypoint2D(centerU - halfEyeSpan, headV - 0.02, 0.95),
      rightEye: VrDesktopKeypoint2D(centerU + halfEyeSpan, headV - 0.02, 0.95),
      mouthCenter: VrDesktopKeypoint2D(centerU, headV + 0.032, 0.95),
      facialExpression: simulatedFacialExpression,
      facialConfidence:
          simulatedFacialExpression == VrFacialExpression.neutral ? 0.0 : 0.92,
      leftShoulder: VrDesktopKeypoint2D(leftU, shoulderV, 0.96),
      rightShoulder: VrDesktopKeypoint2D(rightU, shoulderV, 0.96),
      leftElbow: VrDesktopKeypoint2D(
        (leftU + lwU) * 0.5,
        (shoulderV + lwV) * 0.5 + 0.04,
        0.92,
      ),
      rightElbow: VrDesktopKeypoint2D(
        (rightU + rwU) * 0.5,
        (shoulderV + rwV) * 0.5 + 0.04,
        0.92,
      ),
      leftWrist: VrDesktopKeypoint2D(lwU, lwV, 0.94),
      rightWrist: VrDesktopKeypoint2D(rwU, rwV, 0.95),
      leftThumbTip: VrDesktopKeypoint2D(lwU + 0.042, lwV - 0.02, 0.90),
      leftIndexTip: VrDesktopKeypoint2D(lwU - 0.042, lwV - 0.05, 0.90),
      rightThumbTip: VrDesktopKeypoint2D(rwU - pinchGap * 0.5, rwV - 0.03, 0.94),
      rightIndexTip: VrDesktopKeypoint2D(rwU + pinchGap * 0.5, rwV - 0.04, 0.94),
      fiducialTags: tags,
      frameWidth: 640,
      frameHeight: 480,
      miniFrameGray32x24: mini,
      inferenceMs: 4.2,
      eyesFromFaceLandmarks: true,
    );
  }
}

/// Streaming speech recognition event emitted by the Desktop voice backend
/// (`vrlizate/desktop_beacon_voice/events`).
class VrDesktopVoiceEvent {
  const VrDesktopVoiceEvent({
    required this.kind,
    this.text = '',
    this.isFinal = false,
    this.listening = false,
    this.locale,
    this.error,
    this.timestampMicros = 0,
  });

  final String kind;
  final String text;
  final bool isFinal;
  final bool listening;
  final String? locale;
  final String? error;
  final int timestampMicros;

  static VrDesktopVoiceEvent? fromPlatformMap(Object? raw) {
    if (raw is! Map) return null;
    final kind = (raw['kind'] as String?) ?? 'status';
    return VrDesktopVoiceEvent(
      kind: kind,
      text: ((raw['text'] as String?) ?? '').trim(),
      isFinal: raw['isFinal'] == true,
      listening: raw['listening'] == true,
      locale: raw['locale'] as String?,
      error: raw['error'] as String?,
      timestampMicros: (raw['timestampMicros'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Platform abstraction for continuous Spanish voice recognition on Estación Faro.
abstract interface class VrDesktopVoicePlatform {
  Future<bool> isSupported();
  Future<bool> startListening({String locale = 'es-MX'});
  Future<void> stopListening();
  Stream<VrDesktopVoiceEvent> get events;
}

/// Native MethodChannel / EventChannel implementation (`vrlizate/desktop_beacon_voice`).
class MethodChannelVrDesktopVoicePlatform implements VrDesktopVoicePlatform {
  static const _methods = MethodChannel('vrlizate/desktop_beacon_voice');
  static const _events = EventChannel('vrlizate/desktop_beacon_voice/events');

  @override
  Future<bool> isSupported() async {
    if (kIsWeb) return false;
    try {
      final res = await _methods
          .invokeMapMethod<String, dynamic>('availability')
          .timeout(const Duration(seconds: 2));
      return res?['supported'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> startListening({String locale = 'es-MX'}) async {
    if (kIsWeb) return false;
    try {
      final res = await _methods
          .invokeMapMethod<String, dynamic>('startListening', {
            'locale': locale,
          })
          .timeout(const Duration(seconds: 30));
      return res?['started'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> stopListening() async {
    if (kIsWeb) return;
    try {
      await _methods
          .invokeMethod<void>('stopListening')
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  @override
  Stream<VrDesktopVoiceEvent> get events => _events
      .receiveBroadcastStream()
      .map(VrDesktopVoiceEvent.fromPlatformMap)
      .where((e) => e != null)
      .cast<VrDesktopVoiceEvent>();
}
