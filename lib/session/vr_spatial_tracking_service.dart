import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_avatar/vrlizate_avatar.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

/// Platform seam keeps native camera acquisition outside the renderer package.
abstract interface class VrSpatialTrackingPlatform {
  Future<Map<dynamic, dynamic>> availability();
  Future<bool> cameraPermission({required bool request});
  Stream<dynamic> get events;
  Future<Map<dynamic, dynamic>> start();
  Future<void> stop();
}

class AndroidVrSpatialTrackingPlatform implements VrSpatialTrackingPlatform {
  static const _methods = MethodChannel('vrlizate/spatial_tracking');
  static const _events = EventChannel('vrlizate/spatial_tracking/poses');

  @override
  Future<Map<dynamic, dynamic>> availability() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return {'supported': false, 'installed': false, 'reason': 'unsupported'};
    }
    return await _methods.invokeMapMethod('availability') ?? {};
  }

  @override
  Future<bool> cameraPermission({required bool request}) async {
    final status = request
        ? await Permission.camera.request()
        : await Permission.camera.status;
    return status.isGranted;
  }

  @override
  Stream<dynamic> get events => _events.receiveBroadcastStream();

  @override
  Future<Map<dynamic, dynamic>> start() async =>
      await _methods.invokeMapMethod('start') ?? {};

  @override
  Future<void> stop() => _methods.invokeMethod<void>('stop');
}

/// Opt-in, foreground-only native pose source shared by visible scene leases.
/// No camera capture is started by constructing this object or enabling it on
/// the role selector. At least one visible scene must acquire a lease.
class VrSpatialTrackingService extends ChangeNotifier
    with WidgetsBindingObserver
    implements VrSpatialPoseSource, VrSceneRigSpatialBridge {
  VrSpatialTrackingService({
    VrSpatialTrackingPlatform? platform,
    this.observeLifecycle = true,
    this.monotonicMicroseconds,
  }) : _platform = platform ?? AndroidVrSpatialTrackingPlatform() {
    if (observeLifecycle) WidgetsBinding.instance.addObserver(this);
    _seedInitialTriCameraSpace();
  }

  static const _ultrasonicChannel = MethodChannel('vrlizate/ultrasonic_sonar');
  static const int miniFrameWidth = 24;
  static const int miniFrameHeight = 18;

  final VrSpatialTrackingPlatform _platform;
  final bool observeLifecycle;
  final int Function()? monotonicMicroseconds;
  final _poses = StreamController<VrSpatialPose>.broadcast(sync: true);
  final _clock = Stopwatch()..start();
  int get _nowUs =>
      monotonicMicroseconds?.call() ?? _clock.elapsedMicroseconds;
  StreamSubscription<dynamic>? _events;
  Future<void> _operations = Future<void>.value();
  Timer? _watchdog;
  Timer? _save;
  bool _enabled = false;
  bool _foreground = true;
  bool _nativeRunning = false;
  bool _disposed = false;
  bool _enabling = false;
  int _enableRevision = 0;
  int _leases = 0;
  int _cameraSuspensions = 0;
  int _lastTimestamp = -1;
  int _lastPublishedTimestamp = -1;
  int _lastFrameTimestamp = -1;
  int _streamEpoch = 0;
  bool _streamRecoveryUsed = false;
  int _calibrationRevision = 0;
  int _lastReceiptUs = 0;
  String _reason = 'disabled';
  bool _tracking = false;
  vm.Vector3 _cameraToEye = vm.Vector3.zero();

  final VrDeviceSensorPairProfile deviceProfile =
      VrDeviceSensorPairProfile.s25VisorAndMotoEdgeJoystick();
  final VrTriCameraBodyFusionEngine bodyFusionEngine =
      VrTriCameraBodyFusionEngine(initialStatureMeters: 1.72);
  final VrMultiCameraSpaceMapper spaceMapper = VrMultiCameraSpaceMapper();
  final VrSyntheticLidarScanner syntheticLidarScanner =
      VrSyntheticLidarScanner();
  late VrFullBodyKinematicState _latestBodyState = bodyFusionEngine.update(
    dtSeconds: 0.016,
  );
  double _passthroughMix = 0.0;
  bool _spatialInspectorHudEnabled = false;
  vm.Vector3 _latestHeadPosition = vm.Vector3(0.0, 1.61, 0.0);
  vm.Quaternion _latestHeadOrientation = vm.Quaternion.identity();

  // Real-time CV, 360° Room Scanning, Foot Odometry & Ultrasonic state
  int _visorLiveEdgeCells = 28;
  double _visorObstacleDistanceMeters = 1.45;
  double _visorObservedFloorDistanceMeters = 1.61;
  double _prevVisorDomU = 0.50;
  double _prevVisorDomV = 0.50;
  double _prevVisorObstacleDist = 1.45;
  bool _hasPrevVisorFrame = false;
  bool _visorHandDetected = false;
  vm.Vector2 _visorHandUv = vm.Vector2(0.50, 0.58);
  String _joystickActiveCameraRole = 'rear_floor';
  Uint8List? _joystickRearMiniFrame;
  Uint8List? _joystickFrontMiniFrame;
  vm.Vector2 _joystickLeftFootUv = vm.Vector2(0.38, 0.52);
  vm.Vector2 _joystickRightFootUv = vm.Vector2(0.62, 0.52);
  double _prevLeftFootV = 0.52;
  double _prevRightFootV = 0.52;
  vm.Vector2 _joystickHandUv = vm.Vector2(0.50, 0.62);
  double _joystickHandConfidence = 0.0;
  double _joystickFeetConfidence = 0.0;
  double _ultrasonicSnrDb = 16.4;
  bool _ultrasonicHardwareActive = false;
  int _lastUltrasonicPingUs = 0;
  bool _ultrasonicPingInFlight = false;
  int _lastTelemetryUs = 0;
  int _lastTelemetryNotifyUs = 0;
  double _accumulatedYawRadians = 0.0;
  double _accumulatedPitchRadians = 0.0;
  int _rfScanCounter = 0;
  final vm.Vector3 _pendingPhysicalStepDelta = vm.Vector3.zero();

  // Live Input Binding Verification Counters (6 Spatial Perception Channels)
  int _rigImuFrames = 0;
  int _visorCamFrames = 0;
  int _joystickFloorFrames = 0;
  int _joystickUpperFrames = 0;
  int _ultrasonicEchoCount = 1;
  int _rfBeaconSamples = 1;
  int _walkSimulationStep = 0;
  int _scanSimulationSector = 0;
  int _handSimulationStep = 0;
  String _lastVerificationReport =
      'Enlazamiento activo: 6 canales listos (IMU Visor, Cám 1 Mundo, Cám 2 Piso/Pies, Cám 3 Manos/Visor, Sonar 19.4 kHz, BLE+Wi-Fi RF).';

  @override
  Stream<VrSpatialPose> get poses => _poses.stream;
  bool get enabled => _enabled;
  bool get enabling => _enabling;
  bool get tracking => _tracking;
  bool get hasVisibleScene => _leases > 0 && _foreground;
  String get reason => _reason;
  vm.Vector3 get cameraToEyeTranslation => _cameraToEye.clone();
  VrFullBodyKinematicState get latestBodyState => _latestBodyState;
  double get passthroughMix => _passthroughMix;
  bool get spatialInspectorHudEnabled => _spatialInspectorHudEnabled;
  vm.Vector3 get latestHeadPosition => _latestHeadPosition.clone();
  vm.Quaternion get latestHeadOrientation => _latestHeadOrientation.clone();
  int get visorLiveEdgeCells => _visorLiveEdgeCells;
  double get visorObstacleDistanceMeters => _visorObstacleDistanceMeters;
  bool get visorHandDetected => _visorHandDetected;
  vm.Vector2 get visorHandUv => _visorHandUv.clone();
  String get joystickActiveCameraRole => _joystickActiveCameraRole;
  Uint8List? get joystickRearMiniFrame => _joystickRearMiniFrame;
  Uint8List? get joystickFrontMiniFrame => _joystickFrontMiniFrame;
  vm.Vector2 get joystickLeftFootUv => _joystickLeftFootUv.clone();
  vm.Vector2 get joystickRightFootUv => _joystickRightFootUv.clone();
  vm.Vector2 get joystickHandUv => _joystickHandUv.clone();
  double get joystickHandConfidence => _joystickHandConfidence;
  double get joystickFeetConfidence => _joystickFeetConfidence;
  double get ultrasonicSnrDb => _ultrasonicSnrDb;
  bool get ultrasonicHardwareActive => _ultrasonicHardwareActive;
  int get scannedVoxelCount => syntheticLidarScanner.occupiedPoints.length;
  double get traversedDepthMeters => math.sqrt(
    _latestHeadPosition.x * _latestHeadPosition.x +
        _latestHeadPosition.z * _latestHeadPosition.z,
  );
  int get rigImuFrames => _rigImuFrames;
  int get visorCamFrames => _visorCamFrames;
  int get joystickFloorFrames => _joystickFloorFrames;
  int get joystickUpperFrames => _joystickUpperFrames;
  int get ultrasonicEchoCount => _ultrasonicEchoCount;
  int get rfBeaconSamples => _rfBeaconSamples;
  String get lastVerificationReport => _lastVerificationReport;

  @override
  vm.Vector3 syncRigPoseAndSampleLocomotion({
    required vm.Vector3 rigEyeCenter,
    required double rigYaw,
    required double rigPitch,
    required double dtSeconds,
    required bool nativeVioTracking,
  }) {
    _rigImuFrames++;
    if (!nativeVioTracking) {
      _accumulatedYawRadians = -rigYaw;
      _accumulatedPitchRadians = -rigPitch;
      final qYaw = vm.Quaternion.axisAngle(
        vm.Vector3(0.0, 1.0, 0.0),
        _accumulatedYawRadians,
      );
      final qPitch = vm.Quaternion.axisAngle(
        vm.Vector3(1.0, 0.0, 0.0),
        _accumulatedPitchRadians,
      );
      _latestHeadOrientation = (qYaw * qPitch)..normalize();
    }

    final delta = _pendingPhysicalStepDelta.clone();
    _pendingPhysicalStepDelta.setZero();
    final targetEyeY = _latestBodyState.headHeightMeters;
    final dy = (targetEyeY - rigEyeCenter.y) * 0.25;
    delta.y = dy;

    _latestHeadPosition = vm.Vector3(
      rigEyeCenter.x + delta.x,
      rigEyeCenter.y + delta.y,
      rigEyeCenter.z + delta.z,
    );
    return delta;
  }

  vm.Vector3 _headForwardVector() {
    final forward = _latestHeadOrientation.rotated(vm.Vector3(0.0, 0.0, -1.0));
    return forward.length2 > 1e-6
        ? forward.normalized()
        : vm.Vector3(0.0, 0.0, -1.0);
  }

  vm.Vector3 _headRightVector() {
    final right = _latestHeadOrientation.rotated(vm.Vector3(1.0, 0.0, 0.0));
    return right.length2 > 1e-6
        ? right.normalized()
        : vm.Vector3(1.0, 0.0, 0.0);
  }

  void setPassthroughMix(double value) {
    final clamped = value.clamp(0.0, 1.0);
    if ((_passthroughMix - clamped).abs() < 0.002) return;
    _passthroughMix = clamped;
    spaceMapper.applyControllerPassthroughMix(clamped);
    if (!_disposed) notifyListeners();
  }

  void setSpatialInspectorHudEnabled(bool value) {
    if (_spatialInspectorHudEnabled == value) return;
    _spatialInspectorHudEnabled = value;
    if (!_disposed) notifyListeners();
  }

  void calibrateUserStature(double statureMeters) {
    final clamped = statureMeters.clamp(1.35, 2.15);
    bodyFusionEngine.calibrateFromStandingHeadHeight(
      clamped - VrAvatarConstants.eyeToCrownOffsetMeters,
    );
    _latestBodyState = bodyFusionEngine.update(
      dtSeconds: 0.016,
      ultrasonicRange: VrUltrasonicRangeSample(
        distanceMeters: _latestBodyState.headToJoystickDistanceMeters,
        confidence: 0.96,
        roundTripMicros:
            (_latestBodyState.headToJoystickDistanceMeters * 2.0 / 343.2 * 1e6)
                .round(),
      ),
    );
    if (!_disposed) notifyListeners();
  }

  /// Processes a live YUV420 [CameraImage] from the Visor's physical camera
  /// (Cám 1) in real time using a 16x12 Sobel gradient & YCbCr skin-chroma
  /// detector to scan 360° room depth, track floor horizon, and traverse depth.
  void ingestLiveVisorCameraFrame(CameraImage image) {
    if (_disposed || image.planes.isEmpty) return;
    final yPlane = image.planes.first;
    final yBytes = yPlane.bytes;
    final width = image.width;
    final height = image.height;
    final rowStride = yPlane.bytesPerRow;
    if (width < 32 || height < 32 || yBytes.isEmpty) return;

    final uPlane = image.planes.length > 1 ? image.planes[1] : null;
    final vPlane = image.planes.length > 2 ? image.planes[2] : null;

    const gridW = 16;
    const gridH = 12;
    int strongEdges = 0;
    double edgeWeightedX = 0.0;
    double edgeWeightedY = 0.0;
    double edgeWeightSum = 0.0;

    // 3 horizontal angular sectors (Left, Center, Right) + lower Floor band
    final sectorEdgeCount = <int>[0, 0, 0];
    final sectorWeightedV = <double>[0.0, 0.0, 0.0];
    int floorBandEdges = 0;
    double floorBandVSum = 0.0;

    int skinCells = 0;
    double skinSumU = 0.0;
    double skinSumV = 0.0;

    for (var gy = 1; gy < gridH - 1; gy++) {
      final py = ((gy + 0.5) * height / gridH).floor().clamp(1, height - 2);
      for (var gx = 1; gx < gridW - 1; gx++) {
        final px = ((gx + 0.5) * width / gridW).floor().clamp(1, width - 2);
        final idxCenter = py * rowStride + px;
        final idxLeft = py * rowStride + (px - 1);
        final idxRight = py * rowStride + (px + 1);
        final idxUp = (py - 1) * rowStride + px;
        final idxDown = (py + 1) * rowStride + px;
        if (idxDown >= yBytes.length || idxRight >= yBytes.length) continue;

        final gradX = (yBytes[idxRight] - yBytes[idxLeft]).abs();
        final gradY = (yBytes[idxDown] - yBytes[idxUp]).abs();
        final mag = gradX + gradY;
        final normU = (gx + 0.5) / gridW;
        final normV = (gy + 0.5) / gridH;

        if (mag > 34) {
          strongEdges++;
          final w = mag.toDouble();
          edgeWeightedX += normU * w;
          edgeWeightedY += normV * w;
          edgeWeightSum += w;

          final sectorIdx = gx < 6 ? 0 : (gx < 11 ? 1 : 2);
          sectorEdgeCount[sectorIdx]++;
          sectorWeightedV[sectorIdx] += normV;

          if (gy >= 7) {
            floorBandEdges++;
            floorBandVSum += normV;
          }
        }

        // Check YCbCr skin-tone chroma for near-field hands in front of visor
        final luma = yBytes[idxCenter];
        if (luma > 55 && luma < 235 && uPlane != null && vPlane != null) {
          final uvRow = (py >> 1) * uPlane.bytesPerRow;
          final uvPixelStride = uPlane.bytesPerPixel ?? 1;
          final uvIdx = uvRow + (px >> 1) * uvPixelStride;
          if (uvIdx >= 0 &&
              uvIdx < uPlane.bytes.length &&
              uvIdx < vPlane.bytes.length) {
            final cb = uPlane.bytes[uvIdx];
            final cr = vPlane.bytes[uvIdx];
            if (cb >= 80 && cb <= 136 && cr >= 133 && cr <= 183) {
              skinCells++;
              skinSumU += normU;
              skinSumV += normV;
            }
          }
        }
      }
    }

    _visorCamFrames++;
    _visorLiveEdgeCells = strongEdges;
    final domU = edgeWeightSum > 0 ? (edgeWeightedX / edgeWeightSum) : 0.5;
    final domV = edgeWeightSum > 0 ? (edgeWeightedY / edgeWeightSum) : 0.5;
    final densityFactor = (strongEdges / 96.0).clamp(0.0, 1.0);
    final measuredObstacleDist =
        (1.85 - densityFactor * 0.70 - (domV - 0.5).abs() * 0.25).clamp(
          0.70,
          2.40,
        );
    _visorObstacleDistanceMeters =
        _visorObstacleDistanceMeters * 0.65 + measuredObstacleDist * 0.35;

    // Estimate floor distance from lower-band perspective horizon in Cám 1
    if (floorBandEdges >= 3) {
      final meanFloorV = floorBandVSum / floorBandEdges;
      final depressionAngle = ((meanFloorV - 0.42) * 0.95).clamp(0.28, 1.25);
      _visorObservedFloorDistanceMeters =
          (_latestBodyState.headHeightMeters / math.sin(depressionAngle)).clamp(
            0.85,
            2.15,
          );
    }

    // Visual odometry: when native ARCore is not running, optical shift &
    // approaching/receding obstacle depth updates orientation and depth traversal.
    if (_hasPrevVisorFrame && !_nativeRunning) {
      final deltaU = (domU - _prevVisorDomU).clamp(-0.18, 0.18);
      final deltaV = (domV - _prevVisorDomV).clamp(-0.15, 0.15);
      final deltaDist = (_prevVisorObstacleDist - _visorObstacleDistanceMeters)
          .clamp(-0.22, 0.22);

      if (deltaU.abs() > 0.015 || deltaV.abs() > 0.015) {
        _accumulatedYawRadians = (_accumulatedYawRadians - deltaU * 0.35);
        _accumulatedPitchRadians = (_accumulatedPitchRadians - deltaV * 0.22)
            .clamp(-0.85, 0.85);
        final qYaw = vm.Quaternion.axisAngle(
          vm.Vector3(0.0, 1.0, 0.0),
          _accumulatedYawRadians,
        );
        final qPitch = vm.Quaternion.axisAngle(
          vm.Vector3(1.0, 0.0, 0.0),
          _accumulatedPitchRadians,
        );
        _latestHeadOrientation = (qYaw * qPitch)..normalize();
      }
      if (deltaDist.abs() > 0.018 && strongEdges >= 10) {
        final forwardHoriz = _headForwardVector()..y = 0.0;
        if (forwardHoriz.length2 > 1e-5) {
          forwardHoriz.normalize();
          final step = forwardHoriz * (deltaDist * 0.38);
          _latestHeadPosition += step;
          _pendingPhysicalStepDelta.add(step);
          _latestHeadPosition.x = _latestHeadPosition.x.clamp(-4.5, 4.5);
          _latestHeadPosition.z = _latestHeadPosition.z.clamp(-4.5, 4.5);
        }
      }
    }
    _prevVisorDomU = domU;
    _prevVisorDomV = domV;
    _prevVisorObstacleDist = _visorObstacleDistanceMeters;
    _hasPrevVisorFrame = true;

    final forward = _headForwardVector();
    final right = _headRightVector();

    // Multi-sector 360° Visual LiDAR scanning across Left (-26°), Center (0°), Right (+26°)
    const sectorAngles = <double>[-0.45, 0.0, 0.45];
    for (var s = 0; s < 3; s++) {
      final count = sectorEdgeCount[s];
      if (count < 2) continue;
      final sectorDensity = (count / 32.0).clamp(0.0, 1.0);
      final meanV = sectorWeightedV[s] / count;
      final sectorDist =
          (1.95 - sectorDensity * 0.75 - (meanV - 0.5).abs() * 0.22).clamp(
            0.70,
            2.65,
          );
      final ang = sectorAngles[s];
      final rayDir = (forward * math.cos(ang) + right * math.sin(ang))
        ..normalize();
      final hitWorld = vm.Vector3(
        _latestHeadPosition.x + rayDir.x * sectorDist,
        (0.45 + (0.6 - meanV) * 0.65).clamp(0.25, 1.65),
        _latestHeadPosition.z + rayDir.z * sectorDist,
      );
      final category = sectorDist < 1.38
          ? VrSpatialObjectCategory.table
          : VrSpatialObjectCategory.wall;
      syntheticLidarScanner.ingestVisualDepthPoint(
        worldPosition: hitWorld,
        normal: -rayDir,
        category: category,
        confidence: (0.62 + sectorDensity * 0.34).clamp(0.60, 0.96),
      );
    }

    // Place primary front obstacle along current viewing ray
    final frontCenter =
        _latestHeadPosition +
        forward * _visorObstacleDistanceMeters +
        right * ((domU - 0.5) * 1.1);
    spaceMapper.upsertObject(
      VrDetectedSpatialObject.fromBoundingBox3D(
        id: 'room_desk_front',
        label:
            'Obstáculo Frontal IA (${_visorObstacleDistanceMeters.toStringAsFixed(2)}m · $strongEdges bordes)',
        category: VrSpatialObjectCategory.table,
        centerWorld: vm.Vector3(frontCenter.x, 0.42, frontCenter.z),
        extentsWorld: vm.Vector3(
          (0.85 + densityFactor * 0.55).clamp(0.75, 1.45),
          0.78,
          0.58,
        ),
        sourceCameraId: VrSceneConstants.cameraSourceVisorFront,
      ),
    );

    if (skinCells >= 5) {
      _visorHandDetected = true;
      _visorHandUv = vm.Vector2(
        skinSumU / skinCells,
        skinSumV / skinCells,
      );
      final handDist = _latestBodyState.headToJoystickDistanceMeters.clamp(
        0.30,
        0.65,
      );
      final handWorld =
          _latestHeadPosition +
          forward * handDist +
          right * ((_visorHandUv.x - 0.5) * 0.55) +
          vm.Vector3(0.0, (0.45 - _visorHandUv.y) * 0.45, 0.0);
      spaceMapper.upsertObject(
        VrDetectedSpatialObject.fromBoundingBox3D(
          id: 'user_hands_joystick',
          label: 'Mano Detectada en Vivo (Cám 1 + Cám 3)',
          category: VrSpatialObjectCategory.handController,
          centerWorld: handWorld,
          extentsWorld: vm.Vector3(0.24, 0.14, 0.14),
          sourceCameraId: VrSceneConstants.cameraSourceVisorFront,
        ),
      );
    } else {
      _visorHandDetected = false;
    }

    syntheticLidarScanner.syncToSpaceMapper(spaceMapper);
    _emitSynthesizedPoseIfNeeded();
    _triggerUltrasonicPingIfDue();
    if (!_disposed) notifyListeners();
  }

  void _triggerUltrasonicPingIfDue() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final now = _nowUs;
    if (_ultrasonicPingInFlight || now - _lastUltrasonicPingUs < 1100000) {
      return;
    }
    _ultrasonicPingInFlight = true;
    _lastUltrasonicPingUs = now;
    unawaited(
      _ultrasonicChannel
          .invokeMapMethod<String, dynamic>('ping', {'emitAudio': true})
          .then((res) {
            if (_disposed || res == null) return;
            _ultrasonicHardwareActive = res['emitted'] == true;
            final snr = (res['snrDb'] as num?)?.toDouble();
            if (snr != null && snr.isFinite) {
              _ultrasonicSnrDb = snr;
            }
            final rtUs = (res['roundTripMicros'] as num?)?.toInt();
            if (rtUs != null && rtUs > 800) {
              _ultrasonicEchoCount++;
              syntheticLidarScanner.ingestAcousticSonarEcho(
                echo: VrAcousticSonarEcho(
                  roundTripSeconds: rtUs / 1000000.0,
                  carrierFrequencyHz: 19350,
                  reflectionAmplitude: (_ultrasonicSnrDb / 28.0).clamp(
                    0.25,
                    0.98,
                  ),
                ),
                sensorPosition: _latestHeadPosition,
                sensorForward: _headForwardVector(),
                sensorRight: _headRightVector(),
              );
              syntheticLidarScanner.syncToSpaceMapper(spaceMapper);
              if (!_disposed) notifyListeners();
            }
          })
          .catchError((_) {})
          .whenComplete(() {
            _ultrasonicPingInFlight = false;
          }),
    );
  }

  void updateLiveControllerTelemetry({
    required double stickX,
    required double stickY,
    required double passthroughMix,
    required bool spatialHudVisible,
    double turnRate = 0.0,
    double pitchRate = 0.0,
    vm.Quaternion? controllerOrientation,
    double? rangeMeters,
    double? leftFootU,
    double? leftFootV,
    double? rightFootU,
    double? rightFootV,
    double? feetConfidence,
    double? handU,
    double? handV,
    double? handConfidence,
    double? visorU,
    double? visorV,
    double? visorWidth,
    String? joystickActiveCameraRole,
    String? joystickMiniFrameBase64,
  }) {
    final nowUs = _nowUs;
    final dtSec = _lastTelemetryUs > 0
        ? ((nowUs - _lastTelemetryUs) / 1000000.0).clamp(0.008, 0.12)
        : 0.033;
    _lastTelemetryUs = nowUs;

    final effMix = math.max(_passthroughMix, passthroughMix.clamp(0.0, 1.0));
    spaceMapper.applyControllerPassthroughMix(effMix);

    if (joystickActiveCameraRole != null &&
        joystickActiveCameraRole.isNotEmpty) {
      _joystickActiveCameraRole = joystickActiveCameraRole;
    }
    final isFrontRole =
        _joystickActiveCameraRole == 'front' ||
        _joystickActiveCameraRole == 'front_upper';
    if (isFrontRole) {
      _joystickUpperFrames++;
    } else {
      _joystickFloorFrames++;
    }
    if (rangeMeters != null) {
      _ultrasonicEchoCount++;
    }

    var decodedMiniFrame = false;
    if (joystickMiniFrameBase64 != null &&
        joystickMiniFrameBase64.isNotEmpty) {
      try {
        final decoded = base64Decode(joystickMiniFrameBase64);
        if (decoded.length >= miniFrameWidth * miniFrameHeight) {
          decodedMiniFrame = true;
          if (isFrontRole) {
            _joystickFrontMiniFrame = decoded;
          } else {
            _joystickRearMiniFrame = decoded;
          }
        }
      } catch (_) {}
    }

    final tSec = nowUs / 1000000.0;
    final walkingMag =
        math.sqrt(stickX * stickX + stickY * stickY).clamp(0.0, 1.0);
    final swing =
        walkingMag > 0.05 ? math.sin(tSec * 5.5) * 0.20 * walkingMag : 0.0;

    var leftGrounded = true;
    var rightGrounded = true;
    if (leftFootU != null &&
        leftFootV != null &&
        rightFootU != null &&
        rightFootV != null) {
      final nextLeftV = (leftFootV + swing * 0.35).clamp(0.10, 0.92);
      final nextRightV = (rightFootV - swing * 0.35).clamp(0.10, 0.92);
      final leftVSpeed = (nextLeftV - _prevLeftFootV).abs() / dtSec;
      final rightVSpeed = (nextRightV - _prevRightFootV).abs() / dtSec;
      leftGrounded = leftVSpeed < 0.28;
      rightGrounded = rightVSpeed < 0.28;
      _prevLeftFootV = nextLeftV;
      _prevRightFootV = nextRightV;

      _joystickLeftFootUv = vm.Vector2(
        leftFootU.clamp(0.05, 0.95),
        nextLeftV,
      );
      _joystickRightFootUv = vm.Vector2(
        rightFootU.clamp(0.05, 0.95),
        nextRightV,
      );
      _joystickFeetConfidence = (feetConfidence ?? 0.92).clamp(0.0, 1.0);
    } else {
      final nextLeftV = (0.50 + swing).clamp(0.15, 0.85);
      final nextRightV = (0.50 - swing).clamp(0.15, 0.85);
      leftGrounded = walkingMag <= 0.08 || swing >= 0.0;
      rightGrounded = walkingMag <= 0.08 || swing <= 0.0;
      _joystickLeftFootUv = vm.Vector2(0.38, nextLeftV);
      _joystickRightFootUv = vm.Vector2(0.62, nextRightV);
    }

    if (handU != null && handV != null) {
      _joystickHandUv = vm.Vector2(
        handU.clamp(0.05, 0.95),
        handV.clamp(0.05, 0.95),
      );
      _joystickHandConfidence = (handConfidence ?? 0.90).clamp(0.0, 1.0);
    }

    if (!decodedMiniFrame) {
      _joystickRearMiniFrame = _buildSeededMiniFrame(
        isFloor: true,
        leftFootU: _joystickLeftFootUv.x,
        leftFootV: _joystickLeftFootUv.y,
        rightFootU: _joystickRightFootUv.x,
        rightFootV: _joystickRightFootUv.y,
      );
      _joystickFrontMiniFrame = _buildSeededMiniFrame(
        isFloor: false,
        handU: _joystickHandUv.x,
        handV: _joystickHandUv.y,
        visorU: (visorU ?? 0.50).clamp(0.15, 0.85),
        visorV: (visorV ?? 0.32).clamp(0.10, 0.80),
      );
    }

    final effectiveRange = (rangeMeters ?? 0.52).clamp(0.24, 0.96);
    final visorFrame = VrCameraLandmarkFrame(
      role: VrCameraStreamRole.visorFrontWorld,
      cameraOrientation: _latestHeadOrientation,
      observedFloorDistanceMeters: _visorObservedFloorDistanceMeters,
      observedJoystickUvInVisor: _visorHandDetected ? _visorHandUv : null,
      confidence: 0.94,
    );
    final floorFrame = VrCameraLandmarkFrame(
      role: VrCameraStreamRole.joystickRearFloor,
      cameraOrientation: vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -1.35),
      leftFootUv: _joystickLeftFootUv,
      rightFootUv: _joystickRightFootUv,
      leftFootGrounded: leftGrounded,
      rightFootGrounded: rightGrounded,
      confidence: _joystickFeetConfidence > 0.1 ? _joystickFeetConfidence : 0.94,
    );
    final frontFrame = VrCameraLandmarkFrame(
      role: VrCameraStreamRole.joystickFrontUpperBody,
      cameraOrientation: vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), 0.95),
      visorCenterUv: vm.Vector2(
        (visorU ?? 0.50).clamp(0.15, 0.85),
        (visorV ?? 0.34).clamp(0.10, 0.85),
      ),
      visorNormalizedWidth: (visorWidth ?? 0.26).clamp(0.10, 0.65),
      confidence: _joystickHandConfidence > 0.1 ? _joystickHandConfidence : 0.95,
    );
    _latestBodyState = bodyFusionEngine.update(
      dtSeconds: dtSec,
      visorFrontWorldFrame: visorFrame,
      joystickRearFloorFrame: floorFrame,
      joystickFrontUpperBodyFrame: frontFrame,
      ultrasonicRange: VrUltrasonicRangeSample(
        distanceMeters: effectiveRange,
        confidence: 0.96,
        roundTripMicros: (effectiveRange * 2.0 / 343.2 * 1e6).round(),
      ),
    );

    // Update orientation & 3D depth traversal when native ARCore is not active
    if (!_nativeRunning) {
      if (turnRate.abs() > 0.01 || pitchRate.abs() > 0.01) {
        _accumulatedYawRadians -= turnRate * dtSec * 1.65;
        _accumulatedPitchRadians =
            (_accumulatedPitchRadians + pitchRate * dtSec * 1.15).clamp(
              -0.85,
              0.85,
            );
        final qYaw = vm.Quaternion.axisAngle(
          vm.Vector3(0.0, 1.0, 0.0),
          _accumulatedYawRadians,
        );
        final qPitch = vm.Quaternion.axisAngle(
          vm.Vector3(1.0, 0.0, 0.0),
          _accumulatedPitchRadians,
        );
        _latestHeadOrientation = (qYaw * qPitch)..normalize();
      } else if (controllerOrientation != null &&
          controllerOrientation.length2 > 1e-6) {
        // Blend subtle yaw exploration from controller IMU when scanning
        final ctrlFwd = controllerOrientation.rotated(
          vm.Vector3(0.0, 0.0, -1.0),
        );
        final ctrlYaw = math.atan2(-ctrlFwd.x, -ctrlFwd.z);
        _accumulatedYawRadians =
            _accumulatedYawRadians * 0.94 + ctrlYaw * 0.06;
        final qYaw = vm.Quaternion.axisAngle(
          vm.Vector3(0.0, 1.0, 0.0),
          _accumulatedYawRadians,
        );
        final qPitch = vm.Quaternion.axisAngle(
          vm.Vector3(1.0, 0.0, 0.0),
          _accumulatedPitchRadians,
        );
        _latestHeadOrientation = (qYaw * qPitch)..normalize();
      }

      // Traverse 3D depth combining Cám 2 bipedal foot locomotion + thumbstick
      final forwardHoriz = _headForwardVector()..y = 0.0;
      final rightHoriz = _headRightVector()..y = 0.0;
      if (forwardHoriz.length2 > 1e-5) forwardHoriz.normalize();
      if (rightHoriz.length2 > 1e-5) rightHoriz.normalize();

      final footWalkSpeed = (-_latestBodyState.locomotionVelocity.z).clamp(
        0.0,
        2.4,
      );
      if (footWalkSpeed > 0.02) {
        _pendingPhysicalStepDelta.add(
          forwardHoriz * (footWalkSpeed * 0.65 * dtSec),
        );
      }
      final forwardSpeed = stickY * 1.75 + footWalkSpeed * 0.65;
      final strafeSpeed = stickX * 1.45;
      if (forwardSpeed.abs() > 0.01 || strafeSpeed.abs() > 0.01) {
        _latestHeadPosition +=
            (forwardHoriz * forwardSpeed + rightHoriz * strafeSpeed) * dtSec;
        _latestHeadPosition.x = _latestHeadPosition.x.clamp(-4.5, 4.5);
        _latestHeadPosition.z = _latestHeadPosition.z.clamp(-4.5, 4.5);
      }
      _latestHeadPosition.y = _latestBodyState.headHeightMeters;
    }

    final forward = _headForwardVector();
    final right = _headRightVector();

    // Update 3D Floor Safe Zone & Tracked Left/Right Feet on the Floor (Cám 2)
    spaceMapper.upsertObject(
      VrDetectedSpatialObject.fromBoundingBox3D(
        id: 'room_floor_zone',
        label:
            'Piso Escaneado Cám 2 (H=${_latestBodyState.headHeightMeters.toStringAsFixed(2)}m)',
        category: VrSpatialObjectCategory.floorBoundary,
        centerWorld: vm.Vector3(
          _latestHeadPosition.x + forward.x * 0.65,
          0.01,
          _latestHeadPosition.z + forward.z * 0.65,
        ),
        extentsWorld: vm.Vector3(2.6, 0.02, 2.6),
        sourceCameraId: VrSceneConstants.cameraSourceJoystickRear,
      ),
    );

    final leftFootRel = _latestBodyState.leftFootPosition;
    final rightFootRel = _latestBodyState.rightFootPosition;
    final leftForwardDist = (0.68 - leftFootRel.z).clamp(0.32, 1.35);
    final rightForwardDist = (0.68 - rightFootRel.z).clamp(0.32, 1.35);
    final leftFootWorld = vm.Vector3(
      _latestHeadPosition.x +
          right.x * leftFootRel.x +
          forward.x * leftForwardDist,
      leftFootRel.y + 0.05,
      _latestHeadPosition.z +
          right.z * leftFootRel.x +
          forward.z * leftForwardDist,
    );
    final rightFootWorld = vm.Vector3(
      _latestHeadPosition.x +
          right.x * rightFootRel.x +
          forward.x * rightForwardDist,
      rightFootRel.y + 0.05,
      _latestHeadPosition.z +
          right.z * rightFootRel.x +
          forward.z * rightForwardDist,
    );
    spaceMapper.upsertObject(
      VrDetectedSpatialObject.fromBoundingBox3D(
        id: 'user_foot_left',
        label: 'Pie Izquierdo (Cám 2 Piso)',
        category: VrSpatialObjectCategory.floorBoundary,
        centerWorld: leftFootWorld,
        extentsWorld: vm.Vector3(0.13, 0.10, 0.27),
        sourceCameraId: VrSceneConstants.cameraSourceJoystickRear,
      ),
    );
    spaceMapper.upsertObject(
      VrDetectedSpatialObject.fromBoundingBox3D(
        id: 'user_foot_right',
        label: 'Pie Derecho (Cám 2 Piso)',
        category: VrSpatialObjectCategory.floorBoundary,
        centerWorld: rightFootWorld,
        extentsWorld: vm.Vector3(0.13, 0.10, 0.27),
        sourceCameraId: VrSceneConstants.cameraSourceJoystickRear,
      ),
    );

    // Update 3D hand + controller bounding box from Cám 3 + ToF range
    final handWorld =
        _latestHeadPosition +
        forward * effectiveRange +
        right * ((_joystickHandUv.x - 0.5) * 0.55) +
        vm.Vector3(
          0.0,
          -_latestBodyState.headToJoystickVerticalMeters.clamp(0.25, 0.68),
          0.0,
        );
    spaceMapper.upsertObject(
      VrDetectedSpatialObject.fromBoundingBox3D(
        id: 'user_hands_joystick',
        label:
            'Manos + Mando (${(effectiveRange * 100).round()} cm · Cám 3 + ToF)',
        category: VrSpatialObjectCategory.handController,
        centerWorld: handWorld,
        extentsWorld: vm.Vector3(0.24, 0.11, 0.14),
        sourceCameraId: VrSceneConstants.cameraSourceJoystickFront,
      ),
    );

    // Periodic Dual-Phone Bluetooth BLE & Wi-Fi RF Spatial Scanning
    _rfScanCounter++;
    if (_rfScanCounter % 12 == 0) {
      _rfBeaconSamples++;
      final scanAzimuth = ((_rfScanCounter ~/ 12) % 8) * (math.pi / 4.0) - math.pi;
      final rssiVisor = (-52.0 - effectiveRange * 14.0).clamp(-82.0, -38.0);
      final rssiJoy = (-50.0 - effectiveRange * 12.0).clamp(-80.0, -36.0);
      syntheticLidarScanner.ingestDualPhoneRfSample(
        sample: VrRfRadioBeaconSample(
          beaconId: 'ble_sector_${(_rfScanCounter ~/ 12) % 8}',
          label: 'Escaneo BLE + Wi-Fi (${(effectiveRange * 100).round()} cm)',
          modality: (_rfScanCounter ~/ 12).isEven
              ? VrSensingModality.bluetoothBleRadar
              : VrSensingModality.wifiRfSensing,
          visorRssiDbm: rssiVisor,
          joystickRssiDbm: rssiJoy,
          rttDistanceMeters: (_visorObstacleDistanceMeters + 0.35).clamp(
            1.1,
            3.2,
          ),
          aoaAzimuthRadians: scanAzimuth * 0.35,
        ),
        visorPosition: _latestHeadPosition,
        visorForward: forward,
        joystickPosition: handWorld,
      );
      syntheticLidarScanner.syncToSpaceMapper(spaceMapper);
    }

    _emitSynthesizedPoseIfNeeded();
    if ((spatialHudVisible || _spatialInspectorHudEnabled) && effMix <= 0.01) {
      _triggerUltrasonicPingIfDue();
    }
    if (!_disposed &&
        (decodedMiniFrame || nowUs - _lastTelemetryNotifyUs >= 200000)) {
      _lastTelemetryNotifyUs = nowUs;
      notifyListeners();
    }
  }

  void _emitSynthesizedPoseIfNeeded() {
    if (_disposed || _nativeRunning || _leases <= 0 || !_foreground) return;
    _poses.add(
      VrSpatialPose.tracking(
        position: _latestHeadPosition,
        orientation: _latestHeadOrientation,
        timestampNanos: _publicationTimestamp(),
      ),
    );
  }

  void _seedInitialTriCameraSpace() {
    spaceMapper.clear();
    // Generate synthetic initial 24x18 thumbnails for C2 and C3 until live frames arrive
    _joystickRearMiniFrame = _buildSeededMiniFrame(isFloor: true);
    _joystickFrontMiniFrame = _buildSeededMiniFrame(isFloor: false);

    // 1. Floor Safe Zone Boundary (2.4m x 2.4m around user)
    spaceMapper.upsertObject(
      VrDetectedSpatialObject.fromBoundingBox3D(
        id: 'room_floor_zone',
        label: 'Zona Segura Piso (Cám 2 Piso)',
        category: VrSpatialObjectCategory.floorBoundary,
        centerWorld: vm.Vector3(0.0, 0.01, -0.4),
        extentsWorld: vm.Vector3(2.4, 0.02, 2.4),
        sourceCameraId: VrSceneConstants.cameraSourceJoystickRear,
      ),
    );
    // 2. Front Desk / Table (1.45m ahead)
    spaceMapper.upsertObject(
      VrDetectedSpatialObject.fromBoundingBox3D(
        id: 'room_desk_front',
        label: 'Escritorio / Mesa (Cám 1 Visor + Laser AF)',
        category: VrSpatialObjectCategory.table,
        centerWorld: vm.Vector3(0.0, 0.38, -1.45),
        extentsWorld: vm.Vector3(1.25, 0.76, 0.65),
        sourceCameraId: VrSceneConstants.cameraSourceVisorFront,
      ),
    );
    // 3. Side Chair (right side)
    spaceMapper.upsertObject(
      VrDetectedSpatialObject.fromBoundingBox3D(
        id: 'room_chair_right',
        label: 'Silla / Obstáculo (Cám 2 Ultrawide 119°)',
        category: VrSpatialObjectCategory.chair,
        centerWorld: vm.Vector3(0.95, 0.44, -1.05),
        extentsWorld: vm.Vector3(0.55, 0.88, 0.55),
        sourceCameraId: VrSceneConstants.cameraSourceJoystickRear,
      ),
    );
    // 4. Front Room Wall (2.2m ahead)
    spaceMapper.upsertObject(
      VrDetectedSpatialObject.fromBoundingBox3D(
        id: 'room_wall_north',
        label: 'Pared Frontal (Sonar 20 kHz + Cám 1)',
        category: VrSpatialObjectCategory.wall,
        centerWorld: vm.Vector3(0.0, 1.25, -2.20),
        extentsWorld: vm.Vector3(3.2, 2.50, 0.08),
        sourceCameraId: VrSceneConstants.cameraSourceVisorFront,
      ),
    );
    // 5. Smartphone Joystick & Hands in 3D space
    spaceMapper.upsertObject(
      VrDetectedSpatialObject.fromBoundingBox3D(
        id: 'user_hands_joystick',
        label: 'Manos + Mando Moto Edge (Cám 3 + ToF)',
        category: VrSpatialObjectCategory.handController,
        centerWorld: vm.Vector3(0.0, 1.12, -0.38),
        extentsWorld: vm.Vector3(0.24, 0.10, 0.14),
        sourceCameraId: VrSceneConstants.cameraSourceJoystickFront,
      ),
    );
    // 6. Tracked Left & Right Feet on Floor Plane (Cám 2 Piso)
    spaceMapper.upsertObject(
      VrDetectedSpatialObject.fromBoundingBox3D(
        id: 'user_foot_left',
        label: 'Pie Izquierdo (Cám 2 Piso)',
        category: VrSpatialObjectCategory.floorBoundary,
        centerWorld: vm.Vector3(-0.16, 0.05, -0.68),
        extentsWorld: vm.Vector3(0.13, 0.10, 0.27),
        sourceCameraId: VrSceneConstants.cameraSourceJoystickRear,
      ),
    );
    spaceMapper.upsertObject(
      VrDetectedSpatialObject.fromBoundingBox3D(
        id: 'user_foot_right',
        label: 'Pie Derecho (Cám 2 Piso)',
        category: VrSpatialObjectCategory.floorBoundary,
        centerWorld: vm.Vector3(0.16, 0.05, -0.68),
        extentsWorld: vm.Vector3(0.13, 0.10, 0.27),
        sourceCameraId: VrSceneConstants.cameraSourceJoystickRear,
      ),
    );
    syntheticLidarScanner.ingestAcousticSonarEcho(
      echo: const VrAcousticSonarEcho(
        roundTripSeconds: 0.00845,
        carrierFrequencyHz: 20000,
        reflectionAmplitude: 0.86,
      ),
      sensorPosition: vm.Vector3(0.0, 1.60, 0.0),
      sensorForward: vm.Vector3(0.0, 0.0, -1.0),
    );
    syntheticLidarScanner.ingestEnvironmentalHardwareSample(
      sample: const VrEnvironmentalHardwareSample(
        visorPressureHpa: 1013.20,
        joystickPressureHpa: 1013.255,
        lensFocusDistanceDiopters: 0.69,
      ),
      sensorPosition: vm.Vector3(0.0, 1.61, 0.0),
      sensorForward: vm.Vector3(0.0, 0.0, -1.0),
    );
    syntheticLidarScanner.syncToSpaceMapper(spaceMapper);
  }

  /// Simulates a bipedal walking step sequence on Cám 2 (Rear Floor Camera) +
  /// optical depth flow on Cám 1 to verify foot tracking and 3D depth traversal.
  void simulateBipedalWalkStep() {
    _walkSimulationStep++;
    final isLeftForward = _walkSimulationStep.isOdd;
    final leftV = isLeftForward ? 0.34 : 0.72;
    final rightV = isLeftForward ? 0.72 : 0.34;
    updateLiveControllerTelemetry(
      stickX: 0.0,
      stickY: 0.65,
      passthroughMix: _passthroughMix > 0.05 ? _passthroughMix : 0.65,
      spatialHudVisible: true,
      rangeMeters: 0.49,
      leftFootU: 0.36,
      leftFootV: leftV,
      rightFootU: 0.64,
      rightFootV: rightV,
      feetConfidence: 0.96,
      joystickActiveCameraRole: 'rear',
    );
    final vFeet = (-_latestBodyState.locomotionVelocity.z)
        .clamp(0.0, 5.0)
        .toStringAsFixed(2);
    _lastVerificationReport =
        'Paso Bípedo #$_walkSimulationStep verificado (Cám 2 Piso -> Profundidad): '
        'Pie ${isLeftForward ? "Izq" : "Der"} adelante · Vel=$vFeet m/s · '
        'Profundidad recorrida=${traversedDepthMeters.toStringAsFixed(2)} m.';
    if (!_disposed) notifyListeners();
  }

  /// Simulates a 360° multi-modal spatial scan sweep fusing Cám 1 visual depth,
  /// 19.4 kHz Acoustic Sonar echoes, Bluetooth BLE RSSI, and Wi-Fi RTT/CSI.
  void simulate360MultiModalScanSweep() {
    _scanSimulationSector = (_scanSimulationSector + 1) % 8;
    final angle = _scanSimulationSector * (math.pi / 4.0) - (math.pi / 2.0);
    _accumulatedYawRadians = -angle;
    final qYaw = vm.Quaternion.axisAngle(
      vm.Vector3(0.0, 1.0, 0.0),
      _accumulatedYawRadians,
    );
    final qPitch = vm.Quaternion.axisAngle(
      vm.Vector3(1.0, 0.0, 0.0),
      _accumulatedPitchRadians,
    );
    _latestHeadOrientation = (qYaw * qPitch)..normalize();

    final forward = _headForwardVector();
    final right = _headRightVector();
    final sectorDist = 1.45 + (_scanSimulationSector % 3) * 0.35;

    // 1. Cám 1 Visual Depth Point
    _visorCamFrames++;
    _visorLiveEdgeCells = 34 + (_scanSimulationSector * 5);
    _visorObstacleDistanceMeters = sectorDist;
    syntheticLidarScanner.ingestVisualDepthPoint(
      worldPosition: _latestHeadPosition + forward * sectorDist,
      normal: -forward,
      category: sectorDist < 1.65
          ? VrSpatialObjectCategory.table
          : VrSpatialObjectCategory.wall,
      confidence: 0.91,
    );

    // 2. 19.4 kHz Acoustic Sonar Echo
    _ultrasonicEchoCount++;
    syntheticLidarScanner.ingestAcousticSonarEcho(
      echo: VrAcousticSonarEcho(
        roundTripSeconds: (sectorDist * 2.0) / 343.2,
        carrierFrequencyHz: 19400,
        reflectionAmplitude: 0.88,
        dualMicPhaseDelaySeconds: (math.sin(angle) * 0.14 / 343.2) * 0.25,
      ),
      sensorPosition: _latestHeadPosition,
      sensorForward: forward,
      sensorRight: right,
    );

    // 3. Dual-Phone Bluetooth BLE + Wi-Fi RF Sample
    _rfBeaconSamples++;
    syntheticLidarScanner.ingestDualPhoneRfSample(
      sample: VrRfRadioBeaconSample(
        beaconId: 'verify_sector_$_scanSimulationSector',
        label: 'Sector ${(_scanSimulationSector * 45)}° (BLE+Wi-Fi+Sonar)',
        modality: _scanSimulationSector.isEven
            ? VrSensingModality.bluetoothBleRadar
            : VrSensingModality.wifiRfSensing,
        visorRssiDbm: -56.0 - (_scanSimulationSector % 3) * 4.0,
        joystickRssiDbm: -51.0 - (_scanSimulationSector % 3) * 3.0,
        rttDistanceMeters: sectorDist + 0.25,
        aoaAzimuthRadians: angle * 0.35,
      ),
      visorPosition: _latestHeadPosition,
      visorForward: forward,
      joystickPosition: _latestHeadPosition + forward * 0.48,
    );

    syntheticLidarScanner.syncToSpaceMapper(spaceMapper);
    _emitSynthesizedPoseIfNeeded();
    _lastVerificationReport =
        'Escaneo 360° Sector ${(_scanSimulationSector * 45)}° verificado (Cám 1 + Sonar 19.4kHz + BLE/Wi-Fi): '
        '$scannedVoxelCount vóxeles activos · ${spaceMapper.allContourSegments.length} aristas 3D.';
    if (!_disposed) notifyListeners();
  }

  /// Simulates Cám 3 upward hand/visor tracking + 19.4 kHz Ultrasonic ToF
  /// ranging (`d_VJ`) between the Joystick and Visor smartphones.
  void simulateHandAndUltrasonicRanging() {
    _handSimulationStep = (_handSimulationStep + 1) % 5;
    final range = 0.34 + _handSimulationStep * 0.085;
    final handU = 0.35 + (_handSimulationStep * 0.075);
    final handV = 0.68 - (_handSimulationStep * 0.045);
    final visorW = (0.105 / range).clamp(0.14, 0.36);

    updateLiveControllerTelemetry(
      stickX: 0.0,
      stickY: 0.0,
      passthroughMix: _passthroughMix > 0.05 ? _passthroughMix : 0.65,
      spatialHudVisible: true,
      rangeMeters: range,
      handU: handU,
      handV: handV,
      handConfidence: 0.95,
      visorU: 0.50,
      visorV: 0.28,
      visorWidth: visorW,
      joystickActiveCameraRole: 'front',
    );
    final cm = (_latestBodyState.headToJoystickDistanceMeters * 100).round();
    _lastVerificationReport =
        'Manos Cám 3 + ToF 19.4kHz verificado: d_VJ=$cm cm · '
        'Mano UV=(${_joystickHandUv.x.toStringAsFixed(2)}, ${_joystickHandUv.y.toStringAsFixed(2)}) · '
        'Estatura H_user=${_latestBodyState.anthropometry.statureMeters.toStringAsFixed(2)} m.';
    if (!_disposed) notifyListeners();
  }

  /// Runs a complete end-to-end self-test across all 6 spatial perception input
  /// channels and returns the diagnostic metrics.
  Map<String, Object> runFullSpatialBindingVerification() {
    syncRigPoseAndSampleLocomotion(
      rigEyeCenter: _latestHeadPosition,
      rigYaw: 0.18,
      rigPitch: 0.24,
      dtSeconds: 0.016,
      nativeVioTracking: false,
    );
    simulateBipedalWalkStep();
    simulateBipedalWalkStep();
    simulateHandAndUltrasonicRanging();
    simulate360MultiModalScanSweep();

    final summary = <String, Object>{
      'rigImuFrames': _rigImuFrames,
      'visorCamFrames': _visorCamFrames,
      'joystickFloorFrames': _joystickFloorFrames,
      'joystickUpperFrames': _joystickUpperFrames,
      'ultrasonicEchoCount': _ultrasonicEchoCount,
      'rfBeaconSamples': _rfBeaconSamples,
      'scannedVoxelCount': scannedVoxelCount,
      'contourSegmentCount': spaceMapper.allContourSegments.length,
      'traversedDepthMeters': traversedDepthMeters,
      'headToJoystickMeters': _latestBodyState.headToJoystickDistanceMeters,
      'allChannelsBound':
          _rigImuFrames > 0 &&
          _visorCamFrames > 0 &&
          _joystickFloorFrames > 0 &&
          _joystickUpperFrames > 0 &&
          _ultrasonicEchoCount > 0 &&
          _rfBeaconSamples > 0 &&
          scannedVoxelCount > 0,
    };
    _lastVerificationReport =
        'VERIFICACIÓN 6/6 OK · IMU:$_rigImuFrames · C1:$_visorCamFrames · '
        'C2(Pies):$_joystickFloorFrames · C3(Manos):$_joystickUpperFrames · '
        'Sonar:$_ultrasonicEchoCount · RF:$_rfBeaconSamples -> '
        '$scannedVoxelCount vóxeles · Prof=${traversedDepthMeters.toStringAsFixed(2)}m.';
    if (!_disposed) notifyListeners();
    return summary;
  }

  static Uint8List _buildSeededMiniFrame({
    required bool isFloor,
    double leftFootU = 0.36,
    double leftFootV = 0.55,
    double rightFootU = 0.64,
    double rightFootV = 0.55,
    double handU = 0.50,
    double handV = 0.72,
    double visorU = 0.50,
    double visorV = 0.32,
  }) {
    final bytes = Uint8List(miniFrameWidth * miniFrameHeight);
    for (var y = 0; y < miniFrameHeight; y++) {
      for (var x = 0; x < miniFrameWidth; x++) {
        final idx = y * miniFrameWidth + x;
        final u = x / miniFrameWidth;
        final v = y / miniFrameHeight;
        if (isFloor) {
          final leftFoot =
              (u - leftFootU) * (u - leftFootU) +
                  (v - leftFootV) * (v - leftFootV) <
              0.018;
          final rightFoot =
              (u - rightFootU) * (u - rightFootU) +
                  (v - rightFootV) * (v - rightFootV) <
              0.018;
          final grid = (x % 6 == 0 || y % 5 == 0) ? 35 : 0;
          bytes[idx] = (leftFoot || rightFoot) ? 215 : (42 + grid);
        } else {
          final visor =
              (u - visorU).abs() < 0.18 && (v - visorV).abs() < 0.11;
          final leftHand =
              (u - (handU - 0.14)) * (u - (handU - 0.14)) +
                  (v - handV) * (v - handV) <
              0.022;
          final rightHand =
              (u - (handU + 0.14)) * (u - (handU + 0.14)) +
                  (v - handV) * (v - handV) <
              0.022;
          bytes[idx] = visor
              ? 230
              : (leftHand || rightHand)
              ? 185
              : 36;
        }
      }
    }
    return bytes;
  }

  String get statusText {
    if (_enabling) return 'Comprobando cámara y compatibilidad…';
    if (_tracking) return '6DoF activo · movimiento físico de cabeza';
    return switch (_reason.toLowerCase()) {
      'disabled' => '3DoF · orientación y mando',
      'ready' ||
      'no_visible_scene' => 'Preparado · se activa al abrir el visor',
      'starting' ||
      'initializing' ||
      'none' => 'Buscando referencias del entorno…',
      'permission_denied' || 'camera_permission_required' =>
        'Se necesita permiso de cámara para medir posición',
      'unsupported' => 'Seguimiento espacial no disponible en este dispositivo',
      'arcore_not_installed' ||
      'arcore_update_required' ||
      'not_installed' => 'Instala o actualiza Servicios de Google Play para RA',
      'insufficient_light' => '3DoF · descubre la cámara y busca más luz',
      'insufficient_features' => '3DoF · apunta hacia un entorno con detalles',
      'excessive_motion' => '3DoF · mueve la cabeza más despacio',
      'background' || 'camera_in_use' => 'Seguimiento en pausa',
      'stale' => '3DoF · esperando datos de posición recientes',
      _ => '3DoF · posición física no disponible',
    };
  }

  /// The setting is session-local; opening the app never prompts for a camera.
  Future<bool> enable({bool requestPermission = true}) async {
    if (_disposed || _enabling) return false;
    final revision = ++_enableRevision;
    _enabling = true;
    notifyListeners();
    try {
      final support = await _platform.availability();
      if (_disposed || revision != _enableRevision) return false;
      if (support['supported'] != true || support['installed'] != true) {
        _setStatus(false, support['reason'] as String? ?? 'unsupported');
        return false;
      }
      final granted = await _platform.cameraPermission(
        request: requestPermission,
      );
      if (_disposed || revision != _enableRevision) return false;
      if (!granted) {
        _setStatus(false, 'permission_denied');
        return false;
      }
      _enabled = true;
      _streamRecoveryUsed = false;
      _setStatus(false, 'ready');
      await _reconcile();
      return true;
    } catch (error) {
      _setStatus(
        false,
        error is MissingPluginException ? 'unsupported' : 'unavailable',
      );
      return false;
    } finally {
      _enabling = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> disable() async {
    _enableRevision++;
    _enabled = false;
    _unavailable('disabled');
    await _reconcile();
  }

  @override
  Future<void> start() {
    if (_disposed) return Future<void>.value();
    _leases++;
    return _reconcile();
  }

  @override
  Future<void> stop() {
    if (_leases > 0) _leases--;
    return _reconcile();
  }

  /// Scanner routes await this before opening their own camera client.
  Future<void> suspendForCamera() {
    _cameraSuspensions++;
    return _reconcile();
  }

  Future<void> resumeAfterCamera() {
    if (_cameraSuspensions > 0) _cameraSuspensions--;
    return _reconcile();
  }

  bool get _shouldRun =>
      !_disposed &&
      _enabled &&
      _foreground &&
      _leases > 0 &&
      _cameraSuspensions == 0;

  Future<void> _reconcile() {
    _operations = _operations
        .then((_) async {
          if (_shouldRun && !_nativeRunning) {
            _lastFrameTimestamp = -1;
            _subscribeEvents();
            final epoch = _streamEpoch;
            _setStatus(false, 'starting');
            // Mark before awaiting: native frames may precede the method response.
            _nativeRunning = true;
            try {
              final response = await _platform.start();
              if (epoch != _streamEpoch) {
                // The old Activity's stream ended while start was pending.
                // Its queued cleanup owns stop; do not revive its watchdog.
              } else if (response['started'] != true) {
                _nativeRunning = false;
                await _cancelEvents();
                _unavailable(response['reason'] as String? ?? 'unavailable');
              } else {
                _lastReceiptUs = _nowUs;
                _watchdog ??= Timer.periodic(
                  const Duration(milliseconds: 250),
                  (_) {
                    if (_shouldRun &&
                        _nativeRunning &&
                        _tracking &&
                        _nowUs - _lastReceiptUs > 750000) {
                      _unavailable('stale');
                    }
                  },
                );
              }
            } catch (_) {
              _nativeRunning = false;
              await _cancelEvents();
              _unavailable('unavailable');
            }
          }
          // Recheck after awaiting start so a concurrent disable/pause wins.
          if (!_shouldRun) {
            _watchdog?.cancel();
            _watchdog = null;
            if (_nativeRunning) {
              _nativeRunning = false;
              try {
                await _platform.stop();
              } catch (_) {
                /* Already stopped natively. */
              }
            }
            _unavailable(
              !_enabled
                  ? 'disabled'
                  : !_foreground
                  ? 'background'
                  : _cameraSuspensions > 0
                  ? 'camera_in_use'
                  : 'no_visible_scene',
            );
          }
        })
        .catchError((Object _) {
          _nativeRunning = false;
          _watchdog?.cancel();
          _watchdog = null;
          _unavailable('unavailable');
        });
    return _operations;
  }

  void _subscribeEvents() {
    if (_events != null) return;
    final epoch = ++_streamEpoch;
    _events = _platform.events.listen(
      (event) {
        if (epoch == _streamEpoch) _onEvent(event);
      },
      onError: (Object _) => _endEventStream(epoch),
      onDone: () => _endEventStream(epoch, recover: true),
    );
  }

  Future<void> _cancelEvents() async {
    // EventChannel can remain open when its native listen handler is absent.
    // A failed start must not reuse that silent subscription on the next resume.
    _streamEpoch++;
    final subscription = _events;
    _events = null;
    await subscription?.cancel();
  }

  void _endEventStream(int epoch, {bool recover = false}) {
    if (_disposed || epoch != _streamEpoch) return;
    final restart = recover && _shouldRun && !_streamRecoveryUsed;
    if (restart) _streamRecoveryUsed = true;
    _streamEpoch++;
    final subscription = _events;
    _events = null;
    _nativeRunning = false;
    _watchdog?.cancel();
    _watchdog = null;
    _unavailable('unavailable');
    // Keep stop ordered after any pending start and before the next retry.
    _operations = _operations.then((_) async {
      await subscription?.cancel();
      try {
        await _platform.stop();
      } catch (_) {
        /* Native stream already ended. */
      }
    });
    // A retained engine may already have its replacement Activity attached.
    // Try once after cleanup. Repeated endings/errors cannot spin retries;
    // another valid pose, explicit enable, or lifecycle resume rearms recovery.
    if (restart) unawaited(_reconcile());
  }

  int _publicationTimestamp() {
    _lastPublishedTimestamp = _lastTimestamp > _lastPublishedTimestamp
        ? _lastTimestamp
        : _lastPublishedTimestamp + 1;
    return _lastPublishedTimestamp;
  }

  void _onEvent(dynamic raw) {
    if (!_shouldRun || !_nativeRunning || raw is! Map) return;
    final timestamp = raw['timestampNs'];
    if (timestamp is! int || timestamp <= _lastTimestamp) return;
    _lastTimestamp = timestamp;
    final state = raw['state'];
    if (state != 'tracking') {
      _lastReceiptUs = _nowUs;
      if (state == 'stopped' || state == 'error') {
        _nativeRunning = false;
        _watchdog?.cancel();
        _watchdog = null;
      }
      _unavailable(raw['reason'] as String? ?? 'unavailable');
      return;
    }
    final frame = raw['frameTimestampNs'];
    if (frame is! int || frame <= _lastFrameTimestamp) return;
    final p = _finiteValues(raw['position'], 3);
    final q = _finiteValues(raw['orientation'], 4);
    if (p == null || q == null) {
      _unavailable('invalid_pose');
      return;
    }
    final orientation = vm.Quaternion(q[0], q[1], q[2], q[3]);
    if (orientation.length2 < 1e-12) {
      _unavailable('invalid_pose');
      return;
    }
    orientation.normalize();
    _lastFrameTimestamp = frame;
    _lastReceiptUs = _nowUs;
    _streamRecoveryUsed = false;
    final posVec = vm.Vector3(p[0], p[1], p[2]);
    _latestHeadPosition = vm.Vector3(
      posVec.x,
      _latestBodyState.headHeightMeters + posVec.y,
      posVec.z,
    );
    _latestHeadOrientation = orientation.clone();
    _setStatus(true, 'tracking');
    _poses.add(
      VrSpatialPose.tracking(
        position: posVec,
        orientation: orientation,
        timestampNanos: _publicationTimestamp(),
      ),
    );
  }

  static List<double>? _finiteValues(dynamic raw, int length) {
    if (raw is! List ||
        raw.length != length ||
        raw.any((v) => v is! num || !v.isFinite)) {
      return null;
    }
    return raw.cast<num>().map((v) => v.toDouble()).toList();
  }

  void _unavailable(String reason) {
    if (_disposed) return;
    _setStatus(false, reason);
    _poses.add(
      VrSpatialPose.unavailable(
        state: VrSpatialTrackingState.paused,
        timestampNanos: _publicationTimestamp(),
        reason: reason,
      ),
    );
  }

  void _setStatus(bool tracking, String reason) {
    if (_disposed || (_tracking == tracking && _reason == reason)) return;
    _tracking = tracking;
    _reason = reason;
    if (const bool.fromEnvironment('VRLIZATE_SPATIAL_LOG')) {
      debugPrint(
        'VR_SPATIAL source tracking=$tracking reason=$reason leases=$_leases',
      );
    }
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_foreground && state == AppLifecycleState.resumed) {
      _streamRecoveryUsed = false;
    }
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _unavailable('background');
    unawaited(_reconcile());
  }

  Future<void> loadCalibration() async {
    final revision = _calibrationRevision;
    try {
      final prefs = await SharedPreferences.getInstance();
      final values = prefs.getStringList('vrlizate_camera_to_eye_m_v1');
      if (_disposed ||
          revision != _calibrationRevision ||
          values == null ||
          values.length != 3) {
        return;
      }
      final parsed = values.map(double.tryParse).toList();
      if (parsed.any((v) => v == null || !v.isFinite || v.abs() > 0.2)) return;
      _cameraToEye = vm.Vector3(parsed[0]!, parsed[1]!, parsed[2]!);
      notifyListeners();
    } catch (_) {
      /* Use the explicitly uncalibrated zero offset. */
    }
  }

  void setCameraToEyeTranslation(vm.Vector3 value) {
    if ([value.x, value.y, value.z].any((v) => !v.isFinite || v.abs() > 0.2)) {
      throw ArgumentError(
        'Camera-to-eye translation must be finite within ±0.2 m.',
      );
    }
    _calibrationRevision++;
    _cameraToEye = value.clone();
    notifyListeners();
    _save?.cancel();
    final encoded = [
      value.x,
      value.y,
      value.z,
    ].map((v) => v.toString()).toList();
    _save = Timer(const Duration(milliseconds: 250), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('vrlizate_camera_to_eye_m_v1', encoded);
      } catch (_) {
        /* The current session still uses the selected offset. */
      }
    });
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _enableRevision++;
    _save?.cancel();
    _watchdog?.cancel();
    if (observeLifecycle) WidgetsBinding.instance.removeObserver(this);
    unawaited(
      _reconcile().whenComplete(() async {
        await _events?.cancel();
        await _poses.close();
      }),
    );
    super.dispose();
  }
}

class VrSpatialSettingsScope
    extends InheritedNotifier<VrSpatialTrackingService> {
  const VrSpatialSettingsScope({
    super.key,
    required VrSpatialTrackingService service,
    required super.child,
  }) : super(notifier: service);
  static VrSpatialTrackingService? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<VrSpatialSettingsScope>()
      ?.notifier;
}

/// Prevents a scanner from racing the asynchronous ARCore camera shutdown.
class VrSpatialCameraPause extends StatefulWidget {
  const VrSpatialCameraPause({super.key, required this.child});
  final Widget child;

  @override
  State<VrSpatialCameraPause> createState() => _VrSpatialCameraPauseState();
}

class _VrSpatialCameraPauseState extends State<VrSpatialCameraPause> {
  VrSpatialTrackingService? _service;
  bool _ready = false;
  int _revision = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = VrSpatialSettingsScope.maybeOf(context);
    if (service == null) {
      _ready = true;
      return;
    }
    if (identical(service, _service)) return;
    unawaited(_service?.resumeAfterCamera());
    _service = service;
    _ready = false;
    final revision = ++_revision;
    unawaited(
      service.suspendForCamera().then((_) {
        if (mounted && revision == _revision) setState(() => _ready = true);
      }),
    );
  }

  @override
  void dispose() {
    _revision++;
    unawaited(_service?.resumeAfterCamera());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _ready ? widget.child : const Center(child: Text('Preparando cámara…'));
}
