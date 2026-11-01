import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vrlizate_joystick/vrlizate_joystick.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart' show VrOpticalZoomCurve;

import '../utils/constants/vr_translation_constants.dart';
import 'vr_spatial_tracking_service.dart';

/// One camera owner shared by the two stereo eyes. Different physical lenses
/// are not opened concurrently: a requested second lens reports [busy] instead
/// of showing another camera's texture under the wrong lens badge.
enum VrPassthroughCameraStatus {
  disabled,
  initializing,
  ready,
  permissionDenied,
  unavailable,
  busy,
  paused,
}

class _CameraLease {
  const _CameraLease(this.lens, this.service);
  final CameraLensDirection lens;
  final VrSpatialTrackingService? service;
}

VrPassthroughCameraSession? _sharedCameraSession;
VrPassthroughCameraSession get _sharedSession =>
    _sharedCameraSession ??= VrPassthroughCameraSession();
VrPassthroughCameraSession? get activeSharedPassthroughCameraSession =>
    _sharedCameraSession;

/// Serializes camera acquisition, lifecycle shutdown and ARCore exclusion.
/// Preview remains a native texture. Optional marker analysis borrows frames
/// from this same controller; it never acquires a second physical camera.
class VrPassthroughCameraSession extends ChangeNotifier
    with WidgetsBindingObserver {
  VrPassthroughCameraSession({
    this.observeLifecycle = true,
    Future<bool> Function()? permissionGranted,
    Future<List<CameraDescription>> Function()? camerasProvider,
    CameraController Function(CameraDescription)? controllerFactory,
  }) : _permissionGranted = permissionGranted ?? _requestPermission,
       _camerasProvider = camerasProvider ?? availableCameras,
       _controllerFactory = controllerFactory ?? _createController {
    if (observeLifecycle) {
      final binding = WidgetsBinding.instance;
      _foreground =
          binding.lifecycleState == null ||
          binding.lifecycleState == AppLifecycleState.resumed;
      binding.addObserver(this);
    }
  }

  final bool observeLifecycle;
  final Future<bool> Function() _permissionGranted;
  final Future<List<CameraDescription>> Function() _camerasProvider;
  final CameraController Function(CameraDescription) _controllerFactory;
  final Map<Object, _CameraLease> _leases = {};
  final Set<VrSpatialTrackingService> _suspendedServices = {};
  final Set<VrSpatialTrackingService> _analysisServices = {};
  Future<void> _operations = Future<void>.value();
  CameraController? _controller;
  CameraLensDirection? _lens;
  bool _foreground = true;
  bool _disposed = false;
  Future<void>? _closing;
  VrPassthroughCameraStatus _status = VrPassthroughCameraStatus.disabled;
  double _minZoomLevel = 1.0;
  double _maxZoomLevel = 1.0;
  double _currentZoomLevel = 1.0;
  double _desiredDisplayZoomLevel = 1.0;
  bool _zoomOperationInFlight = false;
  double? _queuedZoomRatio;
  int _lastConfiguredIntervalMs = -1;

  double get minZoomLevel => _minZoomLevel;
  double get maxZoomLevel => _maxZoomLevel;
  double get currentZoomLevel => _currentZoomLevel;
  double get desiredDisplayZoomLevel => _desiredDisplayZoomLevel;

  /// Zero-latency GPU residual zoom factor (`desired / committedHardware`) so
  /// continuous `eMudra` sweeps from `0.6x` to `100x` render smoothly at 120 Hz
  /// while the hardware Camera2 ISP catches up asynchronously.
  double get gpuResidualZoomScale {
    if (_currentZoomLevel <= 0.01 || !_desiredDisplayZoomLevel.isFinite) {
      return 1.0;
    }
    return (_desiredDisplayZoomLevel / _currentZoomLevel).clamp(0.82, 1.35);
  }

  /// Re-evaluates whether the Visor's CV `ImageStream` should hibernate (`0 Hz`)
  /// or wake up (`66 ms` low-latency ROI) after zoom or Desktop Faro state changes.
  Future<void> reconcileSensingSchedule() {
    if (_disposed || _controller == null) return Future<void>.value();
    return _reconcile();
  }

  /// Selects the optimal rear [CameraDescription] when [preferUltraWide] is
  /// requested:
  /// 1. Prefers a public logical multi-camera that spans Ultra-Wide (`< 1.0x`,
  ///    e.g. `0.5x–0.6x` `eyefish` ~120° FOV) up to telephoto (`100x` on
  ///    Galaxy S25 Ultra) so zoom transitions require no camera reopen.
  /// 2. Otherwise selects the public camera with the widest horizontal FOV /
  ///    shortest focal length reported by Camera2 metadata.
  @visibleForTesting
  static CameraDescription selectPreferredCamera(
    Iterable<CameraDescription> matching, {
    required bool preferUltraWide,
    List<Map<dynamic, dynamic>>? calibratedCameras,
  }) {
    final list = matching.toList(growable: false);
    if (list.length <= 1 || !preferUltraWide) return list.first;

    if (calibratedCameras != null && calibratedCameras.isNotEmpty) {
      final byId = <String, Map<dynamic, dynamic>>{};
      for (final cam in calibratedCameras) {
        final id = cam['id']?.toString() ?? cam['cameraId']?.toString();
        if (id != null && cam['isPublicCameraId'] != false) {
          byId[id] = cam;
        }
      }
      // Priority 1: Logical multi-camera supporting < 1.0x Ultra-Wide AND optical zoom
      CameraDescription? bestLogical;
      double bestMaxZoom = -1.0;
      for (final desc in list) {
        final meta = byId[desc.name];
        final minZ = (meta?['minZoomRatio'] as num?)?.toDouble();
        final maxZ = (meta?['maxZoomRatio'] as num?)?.toDouble() ?? 1.0;
        if (minZ != null && minZ < 0.95 && maxZ > bestMaxZoom) {
          bestMaxZoom = maxZ;
          bestLogical = desc;
        }
      }
      if (bestLogical != null) return bestLogical;

      // Priority 2: Widest horizontal FOV / shortest focal length physical public camera
      CameraDescription? widest;
      double bestFov = -1.0;
      for (final desc in list) {
        final meta = byId[desc.name];
        final fov = (meta?['estimatedHorizontalFovDeg'] as num?)?.toDouble();
        if (fov != null && fov > bestFov) {
          bestFov = fov;
          widest = desc;
        }
      }
      if (widest != null) return widest;
    }

    // Heuristic fallback when static metadata was not queried yet: check name hints
    for (final desc in list) {
      final lower = desc.name.toLowerCase();
      if (lower.contains('ultra') ||
          lower.contains('wide') ||
          lower.contains('fisheye')) {
        return desc;
      }
    }
    return list.first;
  }

  /// Smoothly updates hardware optical/digital zoom on the active camera
  /// (`[minZoomLevel .. maxZoomLevel]`, e.g. `0.6x .. 100.0x` on S25 Ultra),
  /// applying immediate GPU micro-zoom (`gpuResidualZoomScale`) while hardware
  /// Camera2 ISP catches up in `>= 2.2%` relative steps.
  Future<void> setZoomRatio(double requestedZoom) async {
    if (_disposed || !requestedZoom.isFinite) return;
    final clamped = requestedZoom
        .clamp(math.min(_minZoomLevel, 1.0), math.max(_maxZoomLevel, 1.0))
        .toDouble();
    final boundedDisplay = clamped
        .clamp(_minZoomLevel, _maxZoomLevel)
        .toDouble();
    if ((_desiredDisplayZoomLevel - boundedDisplay).abs() > 0.001) {
      _desiredDisplayZoomLevel = boundedDisplay;
      if (!_disposed) notifyListeners();
    }
    _queuedZoomRatio = clamped;
    if (_zoomOperationInFlight) return;
    _zoomOperationInFlight = true;
    try {
      while (_queuedZoomRatio != null && !_disposed) {
        final next = _queuedZoomRatio!;
        _queuedZoomRatio = null;
        final ctrl = _controller;
        if (ctrl == null || !ctrl.value.isInitialized) break;
        final target = next.clamp(_minZoomLevel, _maxZoomLevel).toDouble();
        final relativeDelta =
            (target - _currentZoomLevel).abs() /
            math.max(0.5, _currentZoomLevel);
        // Quantize IPC calls to >= 2.0% relative step unless landing on exact bounds
        final atBound =
            (target - _minZoomLevel).abs() < 0.01 ||
            (target - _maxZoomLevel).abs() < 0.05 ||
            (target - 1.0).abs() < 0.01;
        if (!atBound && relativeDelta < 0.020) continue;
        if ((target - _currentZoomLevel).abs() < 0.004) continue;
        try {
          final wasTelephoto = _currentZoomLevel > 1.80;
          await ctrl.setZoomLevel(target);
          _currentZoomLevel = target;
          _desiredDisplayZoomLevel = _queuedZoomRatio != null
              ? _queuedZoomRatio!.clamp(_minZoomLevel, _maxZoomLevel).toDouble()
              : target;
          for (final lease in _leases.values) {
            lease.service?.syncHardwareCameraZoomBounds(
              minZoom: _minZoomLevel,
              maxZoom: _maxZoomLevel,
              currentZoom: _currentZoomLevel,
            );
          }
          final nowTelephoto = _currentZoomLevel > 1.80;
          if (wasTelephoto != nowTelephoto) {
            await _syncImageAnalysis();
          }
          if (!_disposed) notifyListeners();
        } catch (error) {
          debugPrint('[VrPassthroughCamera] setZoomLevel failed: $error');
          break;
        }
      }
    } finally {
      _zoomOperationInFlight = false;
    }
  }

  static Future<bool> _requestPermission() async {
    var permission = await Permission.camera.status;
    if (!permission.isGranted) permission = await Permission.camera.request();
    return permission.isGranted;
  }

  static CameraController _createController(CameraDescription camera) =>
      CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        fps: 30,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

  CameraController? controllerFor(CameraLensDirection lens) =>
      _lens == lens ? _controller : null;

  VrPassthroughCameraStatus statusFor(CameraLensDirection lens) {
    if (_controller != null && _lens != lens) {
      return VrPassthroughCameraStatus.busy;
    }
    return _status;
  }

  Future<void> acquire(
    Object owner, {
    required CameraLensDirection lens,
    VrSpatialTrackingService? service,
  }) {
    if (_disposed) return Future<void>.value();
    _leases[owner] = _CameraLease(lens, service);
    return _reconcile();
  }

  Future<void> release(Object owner) {
    _leases.remove(owner);
    return _reconcile();
  }

  /// Public for tests and integrations with their own foreground lease.
  Future<void> setForeground(bool foreground) {
    if (_foreground == foreground) return _operations;
    _foreground = foreground;
    return _reconcile();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(setForeground(state == AppLifecycleState.resumed));
  }

  CameraLensDirection? get _desiredLens {
    if (_disposed || !_foreground || _leases.isEmpty) return null;
    // Retain the current lens while any eye still uses it. An inspector asking
    // for another lens must not steal/reset the camera on every widget rebuild.
    if (_lens != null && _leases.values.any((lease) => lease.lens == _lens)) {
      return _lens;
    }
    return _leases.values.first.lens;
  }

  Future<void> _reconcile() {
    _operations = _operations.then((_) => _reconcileInternal()).catchError((
      Object error,
      StackTrace stack,
    ) {
      debugPrint('[VrPassthroughCamera] Reconcile failed: $error');
    });
    return _operations;
  }

  void _publish(VrPassthroughCameraStatus status) {
    _status = status;
    if (!_disposed) notifyListeners();
  }

  Future<void> _reconcileInternal() async {
    _updateAnalysisListeners();
    final target = _desiredLens;
    if (target == null) {
      await _releaseHardware();
      _publish(
        _foreground
            ? VrPassthroughCameraStatus.disabled
            : VrPassthroughCameraStatus.paused,
      );
      return;
    }
    if (_controller != null && _lens != target) await _releaseHardware();
    if (_controller != null) {
      await _suspendRequestedTracking();
      await _syncImageAnalysis();
      _publish(VrPassthroughCameraStatus.ready);
      return;
    }
    _publish(VrPassthroughCameraStatus.initializing);
    CameraController? pending;
    try {
      if (!await _permissionGranted()) {
        _publish(VrPassthroughCameraStatus.permissionDenied);
        return;
      }
      if (_desiredLens != target) return;
      final cameras = await _camerasProvider();
      if (_desiredLens != target) return;
      final matching = cameras.where(
        (camera) => camera.lensDirection == target,
      );
      if (matching.isEmpty) {
        _publish(VrPassthroughCameraStatus.unavailable);
        return;
      }
      // Native VIO and Flutter CameraController are exclusive camera clients.
      // Await ARCore release before initialize, and resume only after disposal.
      await _suspendRequestedTracking();
      if (_desiredLens != target) {
        await _releaseHardware();
        return;
      }
      final primaryService = _leases.values
          .map((lease) => lease.service)
          .whereType<VrSpatialTrackingService>()
          .firstOrNull;
      final preferUltraWide =
          target == CameraLensDirection.back &&
          (primaryService?.preferUltraWideCamera ?? true);
      List<Map<dynamic, dynamic>>? calibratedCameras;
      if (preferUltraWide && matching.length > 1 && primaryService != null) {
        try {
          final diag = await primaryService.readCameraCalibrationDiagnostics();
          final rawList = diag['cameras'];
          if (rawList is List) {
            calibratedCameras = rawList
                .whereType<Map>()
                .map((m) => Map<dynamic, dynamic>.from(m))
                .toList();
          }
        } catch (_) {}
      }
      final chosen = selectPreferredCamera(
        matching,
        preferUltraWide: preferUltraWide,
        calibratedCameras: calibratedCameras,
      );
      pending = _controllerFactory(chosen);
      await pending.initialize();
      if (_desiredLens != target) {
        await pending.dispose();
        pending = null;
        await _releaseHardware();
        return;
      }
      var minZ = 1.0;
      var maxZ = 1.0;
      if (pending.cameraId >= 0) {
        try {
          minZ = await pending.getMinZoomLevel();
          maxZ = await pending.getMaxZoomLevel();
        } catch (_) {}
      }
      if (!minZ.isFinite || minZ <= 0) minZ = 1.0;
      if (!maxZ.isFinite || maxZ < minZ) maxZ = math.max(1.0, minZ);
      _minZoomLevel = minZ;
      _maxZoomLevel = maxZ;

      final requestedZoom = primaryService?.requestedCameraZoomRatio;
      final initialZoom = requestedZoom != null
          ? requestedZoom.clamp(minZ, maxZ)
          : (preferUltraWide && minZ < 1.0 ? minZ : 1.0.clamp(minZ, maxZ));
      _currentZoomLevel = initialZoom;
      _desiredDisplayZoomLevel = initialZoom;
      if (pending.cameraId >= 0 && (initialZoom - 1.0).abs() > 0.01) {
        try {
          await pending.setZoomLevel(initialZoom);
        } catch (_) {
          _currentZoomLevel = 1.0;
          _desiredDisplayZoomLevel = 1.0;
        }
      }
      for (final lease in _leases.values) {
        lease.service?.syncHardwareCameraZoomBounds(
          minZoom: _minZoomLevel,
          maxZoom: _maxZoomLevel,
          currentZoom: _currentZoomLevel,
        );
      }

      _controller = pending;
      pending = null;
      _lens = target;
      await _syncImageAnalysis();
      _publish(VrPassthroughCameraStatus.ready);
    } catch (error) {
      // A failed initialization can still own a native CameraDevice.
      try {
        await pending?.dispose();
      } catch (_) {}
      await _releaseHardware();
      debugPrint('[VrPassthroughCamera] Camera unavailable: $error');
      _publish(VrPassthroughCameraStatus.unavailable);
    }
  }

  Future<void> _suspendRequestedTracking() async {
    final services = _leases.values
        .map((lease) => lease.service)
        .whereType<VrSpatialTrackingService>()
        .toSet();
    for (final service in services) {
      if (_suspendedServices.add(service)) await service.suspendForCamera();
    }
  }

  void _updateAnalysisListeners() {
    final desired = _leases.values
        .map((lease) => lease.service)
        .whereType<VrSpatialTrackingService>()
        .toSet();
    for (final service in _analysisServices.difference(desired)) {
      service.visualTracking.removeListener(_onAnalysisSettingsChanged);
      service.visualTracking.invalidateStream(
        'Consumidor de cámara cerrado; requiere calibración',
      );
    }
    for (final service in desired.difference(_analysisServices)) {
      service.visualTracking.addListener(_onAnalysisSettingsChanged);
    }
    _analysisServices
      ..clear()
      ..addAll(desired);
  }

  bool _lastAnalysisEnabled = false;
  void _onAnalysisSettingsChanged() {
    final desired =
        !_disposed &&
        _foreground &&
        _desiredLens != null &&
        _analysisServices.any((s) => s.shouldRunVisorImageStream);
    if (desired != _lastAnalysisEnabled) unawaited(_reconcile());
  }

  Future<void> _syncImageAnalysis() async {
    final camera = _controller;
    if (camera == null) return;
    final enabled =
        _foreground &&
        _analysisServices.any((s) => s.shouldRunVisorImageStream);
    _lastAnalysisEnabled = enabled;
    const activeIntervalMs = 66; // ~15 Hz low-latency ROI (4.5x faster than legacy 300 ms)
    try {
      if (enabled && !camera.value.isStreamingImages) {
        final bounded = await VrCameraAnalysisBudget.configure(
          camera,
          intervalMs: activeIntervalMs,
        );
        _lastConfiguredIntervalMs = activeIntervalMs;
        debugPrint(
          '[VrCameraAnalysisBudget] visor nativeAdmission=$bounded intervalMs=$activeIntervalMs',
        );
        await camera.startImageStream((image) {
          for (final service in _analysisServices) {
            if (service.shouldRunVisorImageStream) {
              service.visualTracking.ingestFrame(
                image,
                camera.description,
                camera.value.deviceOrientation,
              );
              break;
            }
          }
        });
      } else if (enabled &&
          camera.value.isStreamingImages &&
          _lastConfiguredIntervalMs != activeIntervalMs) {
        await VrCameraAnalysisBudget.configure(
          camera,
          intervalMs: activeIntervalMs,
        );
        _lastConfiguredIntervalMs = activeIntervalMs;
      } else if (!enabled && camera.value.isStreamingImages) {
        await camera.stopImageStream();
        await VrCameraAnalysisBudget.configure(camera, intervalMs: 0);
        _lastConfiguredIntervalMs = 0;
      }
    } catch (error) {
      // A failed analyzer must leave the physical passthrough texture alive.
      for (final service in _analysisServices) {
        service.visualTracking.invalidateStream(
          'Análisis no disponible: ${error.runtimeType}',
        );
      }
      debugPrint('[VrPassthroughCamera] Analysis unavailable: $error');
    }
  }

  Future<void> _releaseHardware() async {
    final camera = _controller;
    _controller = null;
    _lens = null;
    _lastAnalysisEnabled = false;
    for (final service in _analysisServices) {
      service.visualTracking.invalidateStream(
        'Cámara cerrada; requiere calibración',
      );
    }
    if (camera != null) {
      try {
        await camera.dispose();
      } catch (error) {
        debugPrint('[VrPassthroughCamera] Dispose failed: $error');
      }
    }
    final suspended = _suspendedServices.toList();
    _suspendedServices.clear();
    for (final service in suspended) {
      try {
        await service.resumeAfterCamera();
      } catch (error) {
        debugPrint('[VrPassthroughCamera] Resume VIO failed: $error');
      }
    }
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _disposed = true;
    _leases.clear();
    if (observeLifecycle) WidgetsBinding.instance.removeObserver(this);
    await _reconcile();
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}

/// Uses the same applicable orientation as camera's CameraPreview widget.
/// A forced portrait-sized parent in landscape would stretch the native image
/// before BoxFit.cover applies its crop.
@visibleForTesting
Size vrPassthroughPreviewSize(CameraValue value) {
  final orientation = value.isRecordingVideo
      ? (value.recordingOrientation ?? value.deviceOrientation)
      : (value.previewPauseOrientation ??
            value.lockedCaptureOrientation ??
            value.deviceOrientation);
  final landscape =
      orientation == DeviceOrientation.landscapeLeft ||
      orientation == DeviceOrientation.landscapeRight;
  final preview = value.previewSize ?? const Size(640, 480);
  return landscape ? preview : Size(preview.height, preview.width);
}

/// Physical camera texture shared by stereo eyes. This is a single camera
/// session, not a guarantee of simultaneous front/rear/ARCore camera support.
class VrPassthroughCameraFeed extends StatefulWidget {
  const VrPassthroughCameraFeed({
    super.key,
    this.lensDirection = CameraLensDirection.back,
    this.service,
    this.showLensBadge = false,
    this.enableHardwareCamera = false,
    this.fit = BoxFit.cover,
  });

  final CameraLensDirection lensDirection;
  final VrSpatialTrackingService? service;
  final bool showLensBadge;
  final bool enableHardwareCamera;

  /// Calibration uses contain to retain the entire frame; stereo keeps cover.
  final BoxFit fit;

  @override
  State<VrPassthroughCameraFeed> createState() =>
      _VrPassthroughCameraFeedState();
}

class _VrPassthroughCameraFeedState extends State<VrPassthroughCameraFeed> {
  final Object _owner = Object();
  VrPassthroughCameraSession? _session;

  @override
  void initState() {
    super.initState();
    _synchronizeLease();
  }

  @override
  void didUpdateWidget(VrPassthroughCameraFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enableHardwareCamera != widget.enableHardwareCamera ||
        oldWidget.lensDirection != widget.lensDirection ||
        !identical(oldWidget.service, widget.service)) {
      _synchronizeLease();
    }
  }

  void _synchronizeLease() {
    final supported =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    if (!supported || !widget.enableHardwareCamera) {
      final session = _session;
      _session = null;
      session?.removeListener(_onCameraChanged);
      if (session != null) unawaited(session.release(_owner));
      return;
    }
    if (_session == null) {
      _session = _sharedSession;
      _session!.addListener(_onCameraChanged);
    }
    unawaited(
      _session!.acquire(
        _owner,
        lens: widget.lensDirection,
        service: widget.service,
      ),
    );
  }

  void _onCameraChanged() {
    if (mounted) setState(() {});
  }

  String? get _statusMessage {
    if (!widget.enableHardwareCamera) return null;
    final status = _session?.statusFor(widget.lensDirection);
    return switch (status) {
      VrPassthroughCameraStatus.ready => null,
      VrPassthroughCameraStatus.permissionDenied =>
        VrTranslationConstants.cameraPermissionPending,
      VrPassthroughCameraStatus.busy => 'Otra lente está utilizando la cámara',
      VrPassthroughCameraStatus.paused => 'Cámara pausada',
      VrPassthroughCameraStatus.unavailable => 'Cámara física no disponible',
      _ => VrTranslationConstants.cameraInitializingBadge,
    };
  }

  @override
  void dispose() {
    final session = _session;
    _session = null;
    session?.removeListener(_onCameraChanged);
    if (session != null) unawaited(session.release(_owner));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _session?.controllerFor(widget.lensDirection);
    final hasPreview = ctrl != null && ctrl.value.isInitialized;
    final statusMessage = _statusMessage;
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 0.95,
          colors: [Color(0xCC061826), Color(0xE6040B14)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasPreview)
            ClipRect(
              child: ValueListenableBuilder<CameraValue>(
                valueListenable: ctrl,
                child: CameraPreview(ctrl),
                builder: (context, value, preview) {
                  final size = vrPassthroughPreviewSize(value);
                  final residual = _session?.gpuResidualZoomScale ?? 1.0;
                  final scaledPreview = (residual - 1.0).abs() > 0.005
                      ? Transform.scale(
                          scale: residual,
                          alignment: Alignment.center,
                          child: preview,
                        )
                      : preview;
                  return FittedBox(
                    fit: widget.fit,
                    child: SizedBox(
                      width: size.width,
                      height: size.height,
                      child: scaledPreview,
                    ),
                  );
                },
              ),
            ),
          if (widget.showLensBadge || statusMessage != null)
            Positioned(
              left: 8,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xCC07101E),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0x6600E5FF)),
                ),
                child: Text(
                  hasPreview
                      ? (widget.lensDirection == CameraLensDirection.front
                            ? VrTranslationConstants.lensFrontLiveBadge
                            : '${VrTranslationConstants.lensBackLiveBadge} · '
                                  '${VrOpticalZoomCurve.lensStageLabel(_session?.currentZoomLevel ?? 1.0)}')
                      : (statusMessage ??
                            (widget.enableHardwareCamera
                                ? VrTranslationConstants.cameraInitializingBadge
                                : 'Cámara física desactivada')),
                  style: const TextStyle(
                    color: Color(0xFF80DEEA),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Captures analysis frames without rendering any camera pixels. Uses the same
/// physical session as [VrPassthroughCameraFeed], so turning visual passthrough
/// on adds preview consumers instead of opening another camera. A covered
/// route releases its lease; a visible calibration panel can acquire its own.
class VrOpticalTrackingCameraLease extends StatefulWidget {
  const VrOpticalTrackingCameraLease({
    super.key,
    required this.service,
    required this.enabled,
    this.child = const SizedBox.shrink(),
    @visibleForTesting this.session,
  });

  final VrSpatialTrackingService service;
  final bool enabled;
  final Widget child;
  final VrPassthroughCameraSession? session;

  @override
  State<VrOpticalTrackingCameraLease> createState() =>
      _VrOpticalTrackingCameraLeaseState();
}

class _VrOpticalTrackingCameraLeaseState
    extends State<VrOpticalTrackingCameraLease> {
  final Object _owner = Object();
  VrPassthroughCameraSession? _session;
  VrSpatialTrackingService? _leasedService;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _synchronize();
  }

  @override
  void didUpdateWidget(VrOpticalTrackingCameraLease oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled ||
        !identical(oldWidget.service, widget.service) ||
        !identical(oldWidget.session, widget.session)) {
      _synchronize();
    }
  }

  void _synchronize() {
    final visible = ModalRoute.isCurrentOf(context) ?? true;
    final supported =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final next = widget.enabled && visible && supported
        ? (widget.session ?? _sharedSession)
        : null;
    if (identical(_session, next) &&
        (next == null || identical(_leasedService, widget.service))) {
      return;
    }
    final old = _session;
    _session = next;
    _leasedService = next == null ? null : widget.service;
    if (old != null && !identical(old, next)) {
      unawaited(old.release(_owner));
    }
    if (next != null) {
      unawaited(
        next.acquire(
          _owner,
          lens: CameraLensDirection.back,
          service: widget.service,
        ),
      );
    }
  }

  @override
  void dispose() {
    final session = _session;
    _session = null;
    if (session != null) unawaited(session.release(_owner));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
