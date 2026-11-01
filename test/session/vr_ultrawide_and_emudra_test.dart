// ignore_for_file: must_call_super

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neom_vr/session/vr_passthrough_camera_feed.dart';
import 'package:neom_vr/session/vr_spatial_tracking_service.dart';

class _ZoomCapableFakeCamera extends CameraController {
  _ZoomCapableFakeCamera(
    CameraDescription camera, {
    required this.minZoom,
    required this.maxZoom,
  }) : super(camera, ResolutionPreset.low);

  final double minZoom;
  final double maxZoom;
  double appliedZoom = 1.0;

  @override
  int get cameraId => 0;

  @override
  Future<void> initialize() async {
    value = value.copyWith(isInitialized: true);
  }

  @override
  Future<double> getMinZoomLevel() async => minZoom;

  @override
  Future<double> getMaxZoomLevel() async => maxZoom;

  @override
  Future<void> setZoomLevel(double zoom) async {
    appliedZoom = zoom;
  }

  @override
  Future<void> dispose() async {
    value = value.copyWith(isInitialized: false);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const standardBack = CameraDescription(
    name: '0',
    lensDirection: CameraLensDirection.back,
    sensorOrientation: 90,
  );
  const ultraWideBack = CameraDescription(
    name: '2',
    lensDirection: CameraLensDirection.back,
    sensorOrientation: 90,
  );

  test('selectPreferredCamera prefers logical multi-camera spanning 0.6x..100x on S25 Ultra', () {
    final selected = VrPassthroughCameraSession.selectPreferredCamera(
      const [standardBack, ultraWideBack],
      preferUltraWide: true,
      calibratedCameras: const [
        {
          'id': '0',
          'isPublicCameraId': true,
          'estimatedHorizontalFovDeg': 78.0,
          'minZoomRatio': 0.6,
          'maxZoomRatio': 100.0,
        },
        {
          'id': '2',
          'isPublicCameraId': true,
          'estimatedHorizontalFovDeg': 120.0,
          'minZoomRatio': 1.0,
          'maxZoomRatio': 8.0,
        },
      ],
    );
    expect(selected.name, '0');
  });

  test('selectPreferredCamera falls back to dedicated widest-FOV eyefish camera when logical zoom >= 1.0', () {
    final selected = VrPassthroughCameraSession.selectPreferredCamera(
      const [standardBack, ultraWideBack],
      preferUltraWide: true,
      calibratedCameras: const [
        {
          'id': '0',
          'isPublicCameraId': true,
          'estimatedHorizontalFovDeg': 75.0,
          'minZoomRatio': 1.0,
          'maxZoomRatio': 10.0,
        },
        {
          'id': '2',
          'isPublicCameraId': true,
          'estimatedHorizontalFovDeg': 118.0,
          'minZoomRatio': 1.0,
          'maxZoomRatio': 4.0,
        },
      ],
    );
    expect(selected.name, '2');
  });

  test('initializes S25 Ultra camera at 0.6x Ultra-Wide and sweeps up to 100x zoom', () async {
    late _ZoomCapableFakeCamera created;
    final service = VrSpatialTrackingService(observeLifecycle: false);
    expect(service.showSpatialBoundingBoxes, isFalse);
    expect(service.preferUltraWideCamera, isTrue);

    final session = VrPassthroughCameraSession(
      observeLifecycle: false,
      permissionGranted: () async => true,
      camerasProvider: () async => const [standardBack],
      controllerFactory: (camera) {
        created = _ZoomCapableFakeCamera(camera, minZoom: 0.6, maxZoom: 100.0);
        return created;
      },
    );

    final owner = Object();
    await session.acquire(
      owner,
      lens: CameraLensDirection.back,
      service: service,
    );

    // Defaults automatically to 0.6x Ultra-Wide / Eyefish!
    expect(created.appliedZoom, closeTo(0.6, 1e-4));
    expect(service.minAvailableCameraZoom, closeTo(0.6, 1e-4));
    expect(service.maxAvailableCameraZoom, closeTo(100.0, 1e-4));
    expect(service.currentCameraZoomRatio, closeTo(0.6, 1e-4));

    // Smoothly zoom up to 100x Space Zoom
    await session.setZoomRatio(100.0);
    expect(created.appliedZoom, closeTo(100.0, 1e-4));
    expect(service.currentCameraZoomRatio, closeTo(100.0, 1e-4));
    // At 100x telephoto zoom, Visor CV stream is strictly shed (0 Hz)!
    expect(service.activeSensingSchedule.runVisorCvStream, isFalse);
    expect(service.shouldRunVisorImageStream, isFalse);

    // Sub-threshold micro-step (<2%) uses instant GPU residual zoom without Camera2 IPC spam
    await session.setZoomRatio(99.0);
    expect(created.appliedZoom, closeTo(100.0, 1e-4));
    expect(session.gpuResidualZoomScale, closeTo(0.99, 1e-3));

    await session.release(owner);
    await session.close();
    service.dispose();
  });
}
