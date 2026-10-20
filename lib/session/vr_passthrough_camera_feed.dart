import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../utils/constants/vr_constants.dart';
import '../utils/constants/vr_translation_constants.dart';
import 'vr_spatial_tracking_service.dart';

/// Live physical camera preview used inside the Visor Passthrough ("Breakthrough")
/// curtain and in the 3-Camera Spatial Inspector.
///
/// Shares a single reference-counted [CameraController] per [CameraLensDirection]
/// so both the Left Eye and Right Eye viewports in stereoscopic VR render the
/// exact same hardware GPU texture (`CameraPreview`) simultaneously without
/// Android Camera2 device contention.
class VrPassthroughCameraFeed extends StatefulWidget {
  const VrPassthroughCameraFeed({
    super.key,
    this.lensDirection = CameraLensDirection.back,
    this.service,
    this.showLensBadge = false,
  });

  final CameraLensDirection lensDirection;
  final VrSpatialTrackingService? service;
  final bool showLensBadge;

  @override
  State<VrPassthroughCameraFeed> createState() =>
      _VrPassthroughCameraFeedState();
}

class _VrPassthroughCameraFeedState extends State<VrPassthroughCameraFeed> {
  // Shared reference-counted camera state across Left & Right stereo eyes
  static CameraController? _sharedController;
  static CameraLensDirection? _sharedLens;
  static Future<void>? _sharedInitFuture;
  static int _activeSubscribers = 0;
  static String? _sharedStatusMessage;
  static VrSpatialTrackingService? _suspendedTrackingService;
  static int _lastVisionFrameUs = 0;
  static final Stopwatch _visionClock = Stopwatch()..start();
  static final ValueNotifier<int> _sharedRevision = ValueNotifier<int>(0);

  bool _isSubscribed = false;

  @override
  void initState() {
    super.initState();
    _sharedRevision.addListener(_onSharedCameraChanged);
    _subscribeCamera();
  }

  @override
  void didUpdateWidget(VrPassthroughCameraFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lensDirection != widget.lensDirection) {
      unawaited(_switchLens(widget.lensDirection));
    }
  }

  void _onSharedCameraChanged() {
    if (mounted) setState(() {});
  }

  void _subscribeCamera() {
    if (_isSubscribed) return;
    _isSubscribed = true;
    _activeSubscribers++;
    unawaited(_ensureSharedCamera(widget.lensDirection, widget.service));
  }

  Future<void> _switchLens(CameraLensDirection newLens) async {
    if (_sharedLens == newLens &&
        _sharedController != null &&
        _sharedController!.value.isInitialized) {
      return;
    }
    await _disposeSharedController();
    if (mounted) {
      await _ensureSharedCamera(newLens, widget.service);
    }
  }

  static Future<void> _ensureSharedCamera(
    CameraLensDirection lensDirection,
    VrSpatialTrackingService? service,
  ) async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    if (_sharedController != null &&
        _sharedController!.value.isInitialized &&
        _sharedLens == lensDirection) {
      _sharedRevision.value++;
      return;
    }
    if (_sharedInitFuture != null) {
      await _sharedInitFuture;
      return;
    }
    final future = _openSharedCameraInternal(lensDirection, service);
    _sharedInitFuture = future;
    try {
      await future;
    } finally {
      if (identical(_sharedInitFuture, future)) {
        _sharedInitFuture = null;
      }
    }
  }

  static Future<void> _openSharedCameraInternal(
    CameraLensDirection lensDirection,
    VrSpatialTrackingService? service,
  ) async {
    try {
      final perm = await Permission.camera.request();
      if (!perm.isGranted) {
        _sharedStatusMessage = VrTranslationConstants.cameraPermissionPending;
        _sharedRevision.value++;
        return;
      }
      if (service != null && _suspendedTrackingService == null) {
        _suspendedTrackingService = service;
        await service.suspendForCamera();
      }
      final cameras = await availableCameras();
      if (_activeSubscribers <= 0 || cameras.isEmpty) {
        _sharedStatusMessage = VrTranslationConstants.cameraSyntheticFallback;
        _sharedRevision.value++;
        return;
      }
      final selected = cameras.firstWhere(
        (c) => c.lensDirection == lensDirection,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        selected,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (_activeSubscribers <= 0) {
        await controller.dispose();
        return;
      }
      // Attach real-time YUV420 CV analyzer stream (throttled to ~7 FPS)
      try {
        await controller.startImageStream((CameraImage image) {
          final nowUs = _visionClock.elapsedMicroseconds;
          if (nowUs - _lastVisionFrameUs <
              VrConstants.passthroughVisionFrameIntervalUs) {
            return;
          }
          _lastVisionFrameUs = nowUs;
          _suspendedTrackingService?.ingestLiveVisorCameraFrame(image);
        });
      } catch (_) {
        // Some emulators or devices may not support simultaneous image stream;
        // preview texture still works normally.
      }
      _sharedController = controller;
      _sharedLens = lensDirection;
      _sharedStatusMessage = null;
      _sharedRevision.value++;
    } catch (_) {
      _sharedStatusMessage =
          VrTranslationConstants.cameraSyntheticWireframeFallback;
      _sharedRevision.value++;
    }
  }

  static Future<void> _disposeSharedController() async {
    final ctrl = _sharedController;
    _sharedController = null;
    _sharedLens = null;
    if (ctrl != null) {
      try {
        if (ctrl.value.isStreamingImages) {
          await ctrl.stopImageStream();
        }
      } catch (_) {}
      try {
        await ctrl.dispose();
      } catch (_) {}
    }
    final suspended = _suspendedTrackingService;
    _suspendedTrackingService = null;
    if (suspended != null) {
      unawaited(suspended.resumeAfterCamera());
    }
  }

  @override
  void dispose() {
    _sharedRevision.removeListener(_onSharedCameraChanged);
    if (_isSubscribed) {
      _isSubscribed = false;
      _activeSubscribers = (_activeSubscribers - 1).clamp(0, 1000);
      if (_activeSubscribers == 0) {
        unawaited(_disposeSharedController());
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _sharedController;
    final hasPreview = ctrl != null && ctrl.value.isInitialized;
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 0.95,
          colors: [
            Color(0xCC061826),
            Color(0xE6040B14),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasPreview)
            ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: ctrl.value.previewSize?.height ?? 640,
                  height: ctrl.value.previewSize?.width ?? 480,
                  child: CameraPreview(ctrl),
                ),
              ),
            ),
          if (widget.showLensBadge || _sharedStatusMessage != null)
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
                      : (_sharedStatusMessage ??
                            VrTranslationConstants.cameraInitializingBadge),
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
