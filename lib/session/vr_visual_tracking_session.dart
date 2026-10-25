import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_joystick/vrlizate_joystick.dart';

import 'vr_visual_marker_pose.dart';
import 'vr_marker_orientation_resolver.dart';

/// Experimental registration of a paired public marker in the actual ML frame.
/// Borrows the shared camera capture, including hidden tracking with visual
/// passthrough off. This object never opens camera hardware itself.
class VrVisualTrackingSession extends ChangeNotifier {
  VrVisualTrackingSession({
    VrVisionInferenceClient? client,
    @visibleForTesting int Function()? monotonicMicroseconds,
  }) : _client = client ?? VrVisionInferenceClient() {
    _nowUs = monotonicMicroseconds ?? () => _clock.elapsedMicroseconds;
  }

  static const _markerFreshnessUs = 1000000;

  final VrVisionInferenceClient _client;
  final _clock = Stopwatch()..start();
  late final int Function() _nowUs;
  final _bodyGate = VrBodyPoseGate();
  final _budget = VrVisionInferenceBudget();
  final _calibrator = VrPlanarCameraCalibrator();
  final _orientationResolver = VrMarkerOrientationResolver();
  bool _orientationVerified = false;
  bool _frameMirrored = false;
  bool _enabled = false, _disposed = false, _distanceValidated = false;
  bool _bodyDetectionEnabled = false;
  bool _markerDetectionEnabled = false;
  Map<dynamic, dynamic>? _bodyResult;
  int _lastBodyUs = -2000000;
  int _lastMarkerUs = -1000000, _sequence = 0;
  int _thermalRetryUs = 0;
  int _epoch = 0;
  Timer? _watchdog;
  String? _signature;
  int _width = 0, _height = 0;
  List<vm.Vector2>? _corners;
  VrTrackingMarkerConfiguration? _marker;
  VrPlanarCameraCalibrationResult? _profile;
  VrVisualMarkerPose? _pose;
  String _status = 'Desactivado';
  String? _lastCalibrationResetReason;
  int _calibrationResetCount = 0;
  int _inferences = 0, _dropped = 0;
  int _bodyAccepted = 0, _bodyRejected = 0;
  int _lastDiagnosticsUs = -5000000;
  double? _inferenceMs;

  bool get enabled => _enabled;
  bool get bodyDetectionEnabled => _bodyDetectionEnabled;
  bool get markerDetectionEnabled => _markerDetectionEnabled;
  bool get hasAnalysisWork =>
      _enabled &&
      _nowUs() >= _thermalRetryUs &&
      (_bodyDetectionEnabled || (_markerDetectionEnabled && _marker != null));
  int get acceptedBodyProposals => _bodyAccepted;
  int get rejectedBodyProposals => _bodyRejected;
  double get analysisMaxHz => _budget.effectiveMaxHz;
  Map<dynamic, dynamic>? get bodyResult =>
      _enabled &&
          _bodyDetectionEnabled &&
          (_nowUs() - _lastBodyUs < 2000000 ||
              (_bodyResult?['status'] == 'thermal_backoff' &&
                  _nowUs() < _thermalRetryUs))
      ? _bodyResult
      : null;
  String get status => _status;
  int get inferenceCount => _inferences;
  int get droppedFrames => _dropped;
  double? get inferenceMs => _inferenceMs;
  int get calibrationViews => _calibrator.viewCount;

  /// Historical cause of the last loss of saved views/profile. Empty-stream
  /// invalidations never replace it. A new capture retains this history;
  /// interfaces should show the warning only while [calibrationViews] is zero.
  String? get lastCalibrationResetReason => _lastCalibrationResetReason;
  int get calibrationResetCount => _calibrationResetCount;
  VrPlanarCameraCalibrationResult? get profile => _profile;
  VrTrackingMarkerConfiguration? get marker => _marker;
  bool get markerVisible =>
      _corners != null && _nowUs() - _lastMarkerUs < _markerFreshnessUs;
  VrVisualMarkerPose? get pose => markerVisible ? _pose : null;
  bool get metricPoseReady => pose?.metricPoseReady ?? false;

  /// Fresh, ruler-validated QR-center position in the analyzed CV frame:
  /// +X right, +Y down, +Z forward. This is not controller-center/world/eye
  /// position; those require a measured camera-to-eye and marker mount profile.
  /// Missing calibration, stale frames or lost orientation return no position.
  vm.Vector3? get metricCameraMarkerTranslation {
    final current = pose;
    return _enabled && current?.metricPoseReady == true
        ? current!.translationMeters
        : null;
  }

  String get controllerPositionStatus {
    if (!_markerDetectionEnabled) return 'Mando 3DoF · seguimiento QR apagado';
    if (_marker == null) return 'Mando 3DoF · falta vincular el marcador QR';
    if (!markerVisible) return 'Mando 3DoF · QR fuera de cámara';
    if (metricCameraMarkerTranslation == null) {
      return 'Mando 3DoF · QR visible; falta calibrar y contrastar escala';
    }
    return 'QR medido respecto a cámara · falta calibrar montaje para posición VR';
  }

  bool get orientationVerified => markerVisible && _orientationVerified;
  String? get frameSignature => _signature;

  void setBodyDetectionEnabled(bool value) {
    if (_disposed || value == _bodyDetectionEnabled) return;
    _bodyDetectionEnabled = value;
    _bodyResult = null;
    _bodyGate.reset();
    _budget.reset();
    _epoch++;
    _client.cancelPendingResults();
    _setProcessingEnabled(_bodyDetectionEnabled || _markerDetectionEnabled);
    notifyListeners();
  }

  /// Marker and body consumers are independent; switching QR off must not
  /// silently disable body detection or leave an unrequested QR scan running.
  void setEnabled(bool value) {
    if (_disposed || value == _markerDetectionEnabled) return;
    _markerDetectionEnabled = value;
    _pose = null;
    _corners = null;
    _frameMirrored = false;
    _epoch++;
    _client.cancelPendingResults();
    _setProcessingEnabled(_bodyDetectionEnabled || _markerDetectionEnabled);
    notifyListeners();
  }

  void _setProcessingEnabled(bool value) {
    if (_disposed || value == _enabled) return;
    _enabled = value;
    invalidateStream(value ? 'Esperando cámara del visor' : 'Desactivado');
    _watchdog?.cancel();
    _watchdog = value
        ? Timer.periodic(const Duration(milliseconds: 250), (_) {
            if (_thermalRetryUs != 0 && _nowUs() >= _thermalRetryUs) {
              _thermalRetryUs = 0;
              notifyListeners();
            }
            if (_bodyResult != null && bodyResult == null) {
              _bodyResult = null;
              _bodyGate.reset();
              notifyListeners();
            }
            if (_corners != null && !markerVisible) {
              _corners = null;
              _pose = null;
              _status = 'Referencia perdida';
              notifyListeners();
            }
          })
        : null;
  }

  void setMarkerConfiguration(VrTrackingMarkerConfiguration? value) {
    if (_disposed ||
        (_marker?.markerId == value?.markerId &&
            _marker?.widthMeters == value?.widthMeters)) {
      return;
    }
    _marker = value;
    _pose = null;
    _corners = null;
    _distanceValidated = false;
    _status = value == null
        ? 'Sin marcador del mando vinculado'
        : 'Marcador registrado; esperando verlo';
    notifyListeners();
  }

  void _recordCalibrationReset(String reason) {
    if (_calibrator.viewCount == 0 && _profile == null) return;
    _lastCalibrationResetReason = reason;
    _calibrationResetCount++;
  }

  /// A close, lens/orientation change or background transition invalidates the
  /// empirical profile. It is deliberately not persisted across unknown crops.
  void invalidateStream(String reason) {
    if (_disposed) return;
    _recordCalibrationReset(reason);
    _epoch++;
    _client.cancelPendingResults();
    _bodyGate.reset();
    _budget.reset();
    _thermalRetryUs = 0;
    _pose = null;
    _corners = null;
    _bodyResult = null;
    _frameMirrored = false;
    _thermalRetryUs = 0;
    _signature = null;
    _profile = null;
    _distanceValidated = false;
    _calibrator.clear();
    _status = reason;
    notifyListeners();
  }

  void ingestFrame(
    CameraImage image,
    CameraDescription camera,
    DeviceOrientation orientation,
  ) {
    if (!hasAnalysisWork || _disposed) return;
    final now = _nowUs();
    if (_client.isBusy) {
      _dropped++;
      return;
    }
    final rotation = VrVisionInferenceClient.rotationDegreesFor(
      camera,
      orientation,
    );
    // iOS pixels are already rotated, so rotation=0 alone cannot distinguish
    // landscape-left/right buffers with different principal-point mapping.
    final signature =
        '${camera.name}:${camera.lensDirection.name}:'
        '${image.width}x${image.height}:$rotation:${orientation.name}';
    if (_signature != signature) {
      invalidateStream('Geometría nueva; requiere calibración');
      _signature = signature;
    }
    if (!_budget.tryStart(now)) {
      _dropped++;
      return;
    }
    final epoch = _epoch;
    final sequence = ++_sequence;
    unawaited(() async {
      try {
        final result = await _client.analyzeFrame(
          image,
          camera: camera,
          orientation: orientation,
          sourceId: 'visor:${camera.name}',
          sequence: sequence,
          detectPose: _bodyDetectionEnabled,
          detectMarker: _markerDetectionEnabled && _marker != null,
        );
        if (_disposed || !_enabled || epoch != _epoch) return;
        _acceptResult(
          _resolveOrientation(result, image, rotation),
          sampledAtUs: now,
        );
      } finally {
        _budget.recordCompletion(
          startedUs: now,
          finishedUs: _nowUs(),
          confirmedBody: _bodyResult?['present'] == true || markerVisible,
        );
      }
    }());
  }

  @visibleForTesting
  void acceptResultForTesting(
    Map<String, dynamic> result, {
    int? sampledAtUs,
  }) => _acceptResult(result, sampledAtUs: sampledAtUs);

  Map<String, dynamic> _resolveOrientation(
    Map<String, dynamic> result,
    CameraImage image,
    int rotation,
  ) {
    final markers = result['markers'];
    if (markers is! List || _marker == null) return result;
    final updated = <Map<String, dynamic>>[];
    for (final value in markers.whereType<Map>()) {
      final marker = Map<String, dynamic>.from(value);
      if (result['mirrored'] == true) {
        marker['orientationVerified'] = false;
        marker['orientationReason'] = 'mirrored_frame_not_supported';
        updated.add(marker);
        continue;
      }
      final raw = marker['corners'];
      if (marker['rawValue'] == _marker!.markerId &&
          raw is List &&
          raw.length == 4) {
        final corners = <vm.Vector2>[];
        for (final p in raw) {
          if (p is Map && p['x'] is num && p['y'] is num) {
            corners.add(
              vm.Vector2(
                (p['x'] as num).toDouble(),
                (p['y'] as num).toDouble(),
              ),
            );
          }
        }
        if (corners.length == 4) {
          final orientation = _orientationResolver.resolve(
            image: image,
            rotationDegrees: rotation,
            corners: corners,
            markerId: _marker!.markerId,
          );
          marker['orientationVerified'] = orientation.verified;
          marker['orientationReason'] = orientation.reason;
          if (orientation.verified) {
            marker['corners'] = orientation.orderedCorners
                .map((p) => {'x': p.x, 'y': p.y})
                .toList();
          }
        }
      }
      updated.add(marker);
    }
    return {...result, 'markers': updated};
  }

  void _acceptResult(Map<String, dynamic> result, {int? sampledAtUs}) {
    if (result['status'] == 'thermal_backoff') {
      final delay = result['retryAfterMs'];
      final retryMs = delay is num && delay.isFinite
          ? delay.toInt().clamp(2000, 10000)
          : 2000;
      _thermalRetryUs = _nowUs() + retryMs * 1000;
      _bodyGate.reset();
      _corners = null;
      _pose = null;
      _bodyResult = _bodyDetectionEnabled
          ? Map.unmodifiable({
              'status': 'thermal_backoff',
              'present': false,
              'landmarks': const [],
            })
          : null;
      _lastBodyUs = _nowUs();
      _status =
          'IA en pausa por temperatura; la vista de cámara puede continuar';
      notifyListeners();
      return;
    }
    _thermalRetryUs = 0;
    _frameMirrored = result['mirrored'] == true;
    if (_frameMirrored) _distanceValidated = false;
    _inferences++;
    final latency = result['inferenceMs'];
    _inferenceMs = latency is num && latency.isFinite
        ? latency.toDouble()
        : null;
    final width = result['imageWidth'], height = result['imageHeight'];
    final body = result['pose'];
    _bodyResult = null;
    if (_bodyDetectionEnabled && body is Map) {
      final landmarks = VrBodyLandmark.fromNative(
        body['landmarks'],
        imageWidth: width is int ? width : 0,
        imageHeight: height is int ? height : 0,
      );
      final gate = _bodyGate.evaluate(
        landmarks: landmarks,
        sourceId: result['sourceId'] as String? ?? _signature ?? 'visor',
        rotationDegrees: result['rotationDegrees'] as int? ?? 0,
        capturedAtUs: sampledAtUs ?? _nowUs(),
        imageWidth: width is int ? width : 0,
        imageHeight: height is int ? height : 0,
        present:
            body['present'] == true &&
            body['status'] == 'ok' &&
            _nowUs() - (sampledAtUs ?? _nowUs()) < 2000000,
      );
      gate.accepted ? _bodyAccepted++ : _bodyRejected++;
      _bodyResult = Map.unmodifiable({
        ...body,
        'present': gate.accepted,
        'landmarks': gate.accepted ? body['landmarks'] : const [],
        'rawLandmarkCount': gate.rawCount,
        'acceptanceReason': gate.reason,
        'stableFrames': gate.stableFrames,
      });
      _lastBodyUs = _nowUs();
      if (!kReleaseMode && _nowUs() - _lastDiagnosticsUs >= 5000000) {
        _lastDiagnosticsUs = _nowUs();
        debugPrint(
          '[VisorInference] count=$_inferences raw=${gate.rawCount} '
          'accepted=${gate.accepted} reason=${gate.reason} '
          'acceptedTotal=$_bodyAccepted rejectedTotal=$_bodyRejected '
          'nativeMs=$_inferenceMs intervalUs=${_budget.intervalUs}',
        );
      }
    } else {
      _bodyGate.reset();
    }
    _pose = null;
    _corners = null;
    _orientationVerified = false;
    // Same-device monotonic time captured before the inference request. Native
    // timestamps and the other phone's clock are not comparable to this one.
    final observedAtUs = sampledAtUs ?? _nowUs();
    final markerAgeUs = _nowUs() - observedAtUs;
    if (markerAgeUs < 0 || markerAgeUs >= _markerFreshnessUs) {
      _status = 'Observación QR caducada';
      notifyListeners();
      return;
    }
    if ((result['status'] != 'ok' && result['markerStatus'] != 'ok') ||
        width is! int ||
        height is! int) {
      _status = 'Detector: ${result['status'] ?? 'sin respuesta'}';
      notifyListeners();
      return;
    }
    _width = width;
    _height = height;
    final markers = result['markers'];
    final matching = markers is List
        ? markers
              .whereType<Map>()
              .where((m) => m['rawValue'] == _marker?.markerId)
              .toList()
        : <Map>[];
    if (_marker == null || matching.length != 1) {
      _status = _marker == null
          ? 'Sin marcador del mando vinculado'
          : 'No se ve el marcador vinculado';
      notifyListeners();
      return;
    }
    final raw = matching.single['corners'];
    void rejectCorners() {
      _status = 'Esquinas del marcador inválidas';
      notifyListeners();
    }

    if (raw is! List || raw.length != 4) {
      rejectCorners();
      return;
    }
    final corners = <vm.Vector2>[];
    for (final p in raw) {
      if (p is! Map || p['x'] is! num || p['y'] is! num) {
        rejectCorners();
        return;
      }
      final x = (p['x'] as num).toDouble(), y = (p['y'] as num).toDouble();
      if (!x.isFinite ||
          !y.isFinite ||
          x < 0 ||
          x >= width ||
          y < 0 ||
          y >= height) {
        rejectCorners();
        return;
      }
      corners.add(vm.Vector2(x, y));
    }
    _corners = corners;
    _orientationVerified =
        !_frameMirrored && matching.single['orientationVerified'] == true;
    _lastMarkerUs = observedAtUs;
    _status =
        'Marcador visible · ${_profile == null ? 'sin calibración' : 'K experimental disponible'}';
    _solvePose();
    if (!const bool.fromEnvironment('dart.vm.product') &&
        _inferences % 10 == 0) {
      debugPrint(
        '[VrVisualTracking] frames=$_inferences status=$_status '
        'metric=$metricPoseReady latencyMs=$_inferenceMs',
      );
    }
    notifyListeners();
  }

  void captureCalibrationView() {
    if (_frameMirrored) {
      throw const VrVisualMarkerPoseException(
        'mirrored_frame_calibration_not_supported',
      );
    }
    if (!markerVisible) {
      throw const VrVisualMarkerPoseException('marker_not_visible');
    }
    _calibrator.addView(_corners!, _width, _height);
    _profile = null;
    _distanceValidated = false;
    _pose = null;
    _status =
        '${_calibrator.viewCount} vistas guardadas; inclina el marcador antes de otra';
    notifyListeners();
  }

  void calibrate() {
    _profile = _calibrator.calibrate();
    _distanceValidated = false;
    _solvePose();
    _status =
        'Ajuste pinhole experimental · falta contrastar distancia con regla';
    notifyListeners();
  }

  void resetCalibration() {
    _recordCalibrationReset('Reinicio manual de calibración');
    _calibrator.clear();
    _profile = null;
    _distanceValidated = false;
    _pose = null;
    _status = 'Calibración eliminada';
    notifyListeners();
  }

  void validateMeasuredDistance(double measuredMeters) {
    final estimate = pose?.translationMeters.length;
    if (estimate == null ||
        !measuredMeters.isFinite ||
        measuredMeters < .1 ||
        measuredMeters > 5) {
      throw const VrVisualMarkerPoseException(
        'fresh_pose_and_measured_distance_required',
      );
    }
    if ((estimate - measuredMeters).abs() >
        math.max(.03, measuredMeters * .1)) {
      _distanceValidated = false;
      _solvePose();
      throw const VrVisualMarkerPoseException(
        'independent_distance_check_failed',
      );
    }
    _distanceValidated = true;
    _solvePose();
    _status = 'Escala contrastada; pose del centro QR respecto a cámara';
    notifyListeners();
  }

  void _solvePose() {
    _pose = null;
    // A reflected frame is not a physical pinhole camera coordinate frame.
    // Keep its 2D detection visible without inventing an unmirrored transform.
    if (_frameMirrored) return;
    final k = _profile?.calibration, side = _marker?.widthMeters;
    if (!markerVisible || k == null || side == null) return;
    try {
      _pose = const VrVisualMarkerPoseSolver().solve(
        corners: _corners!,
        markerWidthMeters: side,
        markerHeightMeters: side,
        calibration: VrMarkerFrameCalibration(
          fx: k.fx,
          fy: k.fy,
          cx: k.cx,
          cy: k.cy,
          skew: k.skew,
          verifiedForFrame: _distanceValidated && _orientationVerified,
        ),
      );
    } on VrVisualMarkerPoseException catch (error) {
      _status = 'Pose rechazada: ${error.reason}';
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _watchdog?.cancel();
    _client.dispose();
    _clock.stop();
    super.dispose();
  }
}
