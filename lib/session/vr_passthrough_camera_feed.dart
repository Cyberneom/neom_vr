import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vrlizate_joystick/vrlizate_joystick.dart';

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
        fps: 15,
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
      pending = _controllerFactory(matching.first);
      await pending.initialize();
      if (_desiredLens != target) {
        await pending.dispose();
        pending = null;
        await _releaseHardware();
        return;
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
        _analysisServices.any((s) => s.visualTracking.hasAnalysisWork);
    if (desired != _lastAnalysisEnabled) unawaited(_reconcile());
  }

  Future<void> _syncImageAnalysis() async {
    final camera = _controller;
    if (camera == null) return;
    final enabled =
        _foreground &&
        _analysisServices.any((s) => s.visualTracking.hasAnalysisWork);
    _lastAnalysisEnabled = enabled;
    try {
      if (enabled && !camera.value.isStreamingImages) {
        final bounded = await VrCameraAnalysisBudget.configure(
          camera,
          intervalMs: 300,
        );
        debugPrint(
          '[VrCameraAnalysisBudget] visor nativeAdmission=$bounded intervalMs=300',
        );
        await camera.startImageStream((image) {
          for (final service in _analysisServices) {
            if (service.visualTracking.hasAnalysisWork) {
              service.visualTracking.ingestFrame(
                image,
                camera.description,
                camera.value.deviceOrientation,
              );
              break;
            }
          }
        });
      } else if (!enabled && camera.value.isStreamingImages) {
        await camera.stopImageStream();
        await VrCameraAnalysisBudget.configure(camera, intervalMs: 0);
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
                  return FittedBox(
                    fit: widget.fit,
                    child: SizedBox(
                      width: size.width,
                      height: size.height,
                      child: preview,
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
                            : VrTranslationConstants.lensBackLiveBadge)
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
