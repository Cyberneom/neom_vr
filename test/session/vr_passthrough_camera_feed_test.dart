// ignore_for_file: must_call_super

import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:neom_vr/session/vr_passthrough_camera_feed.dart';
import 'package:neom_vr/session/vr_spatial_tracking_service.dart';
import 'package:vrlizate_joystick/vrlizate_joystick.dart';

const rear = CameraDescription(
  name: '0',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 90,
);
const front = CameraDescription(
  name: '1',
  lensDirection: CameraLensDirection.front,
  sensorOrientation: 270,
);

class FakePreviewCamera extends CameraController {
  FakePreviewCamera(CameraDescription camera)
    : super(camera, ResolutionPreset.low);
  Completer<void>? initialization;
  bool fails = false;
  bool failsAnalysis = false;
  int disposals = 0;
  int analysisStarts = 0, analysisStops = 0;
  void Function(CameraImage)? analysis;
  @override
  Future<void> initialize() async {
    await initialization?.future;
    if (fails) throw StateError('native initialize failed');
    value = value.copyWith(isInitialized: true);
  }

  @override
  Future<void> startImageStream(void Function(CameraImage) onAvailable) async {
    analysisStarts++;
    if (failsAnalysis) throw StateError('native analyzer unavailable');
    analysis = onAvailable;
    value = value.copyWith(isStreamingImages: true);
  }

  @override
  Future<void> stopImageStream() async {
    analysisStops++;
    analysis = null;
    value = value.copyWith(isStreamingImages: false);
  }

  // The fake allocates no plugin resources to dispose through the superclass.
  @override
  Future<void> dispose() async {
    disposals++;
    analysis = null;
    value = value.copyWith(isStreamingImages: false, isInitialized: false);
  }
}

class FakeTrackingService extends VrSpatialTrackingService {
  FakeTrackingService() : super(observeLifecycle: false);
  int suspensions = 0;
  int resumptions = 0;
  Completer<void>? suspension;
  @override
  Future<void> suspendForCamera() async {
    suspensions++;
    await suspension?.future;
  }

  @override
  Future<void> resumeAfterCamera() async {
    resumptions++;
  }
}

class CountingOpticalSession extends Fake
    implements VrPassthroughCameraSession {
  int acquisitions = 0, releases = 0;
  VrSpatialTrackingService? lastService;

  @override
  Future<void> acquire(
    Object owner, {
    required CameraLensDirection lens,
    VrSpatialTrackingService? service,
  }) async {
    acquisitions++;
    lastService = service;
  }

  @override
  Future<void> release(Object owner) async {
    releases++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'preview dimensions follow camera landscape and portrait orientation',
    () {
      final base = CameraValue.uninitialized(
        rear,
      ).copyWith(isInitialized: true, previewSize: const Size(640, 480));
      for (final orientation in [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]) {
        expect(
          vrPassthroughPreviewSize(
            base.copyWith(deviceOrientation: orientation),
          ),
          const Size(640, 480),
        );
      }
      for (final orientation in [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]) {
        expect(
          vrPassthroughPreviewSize(
            base.copyWith(deviceOrientation: orientation),
          ),
          const Size(480, 640),
        );
      }
    },
  );

  test('stereo eyes share one camera; final lease releases hardware', () async {
    final created = <FakePreviewCamera>[];
    final session = VrPassthroughCameraSession(
      observeLifecycle: false,
      permissionGranted: () async => true,
      camerasProvider: () async => [rear],
      controllerFactory: (camera) {
        final controller = FakePreviewCamera(camera);
        created.add(controller);
        return controller;
      },
    );
    final left = Object(), right = Object();
    await Future.wait([
      session.acquire(left, lens: CameraLensDirection.back),
      session.acquire(right, lens: CameraLensDirection.back),
    ]);
    expect(created, hasLength(1));
    await session.release(left);
    expect(created.single.disposals, 0);
    await session.release(right);
    expect(created.single.disposals, 1);
    expect(session.controllerFor(CameraLensDirection.back), isNull);
    await session.close();
    session.dispose();
  });

  testWidgets(
    'hidden tracking shares preview camera and releases on private route',
    (tester) async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const budgetChannel = MethodChannel('vrlizate/camera_analysis_budget');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            budgetChannel,
            (_) async => {'configured': true},
          );
      final tracking = FakeTrackingService();
      final created = <FakePreviewCamera>[];
      final session = VrPassthroughCameraSession(
        observeLifecycle: false,
        permissionGranted: () async => true,
        camerasProvider: () async => [rear],
        controllerFactory: (description) {
          final camera = FakePreviewCamera(description);
          created.add(camera);
          return camera;
        },
      );
      try {
        tracking.visualTracking.setMarkerConfiguration(
          const VrTrackingMarkerConfiguration(
            markerId: 'vrlizate-marker-v1:0123456789abcdef',
          ),
        );
        tracking.setControllerOpticalTrackingEnabled(true);
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            home: VrOpticalTrackingCameraLease(
              session: session,
              service: tracking,
              enabled: true,
              child: const Scaffold(body: Text('VR without camera pixels')),
            ),
          ),
        );
        await tester.pump();
        // Await the session operation, including native analysis admission. A
        // single widget pump does not promise the asynchronous open is complete.
        final previewOwner = Object();
        await session.acquire(
          previewOwner,
          lens: CameraLensDirection.back,
          service: tracking,
        );
        expect(created, hasLength(1));
        expect(created.single.analysisStarts, 1);
        expect(find.byType(CameraPreview), findsNothing);
        expect(tracking.passthroughMix, 0);
        expect(tracking.visorCameraPreviewEnabled, isFalse);

        await session.release(previewOwner);
        expect(created.single.disposals, 0);

        unawaited(
          navigator.currentState!.push<void>(
            MaterialPageRoute(
              builder: (_) => const Scaffold(body: Text('Private')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(created.single.disposals, 1);
        expect(session.controllerFor(CameraLensDirection.back), isNull);
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        expect(created, hasLength(2));
        expect(tracking.visualTracking.metricCameraMarkerTranslation, isNull);
        await session.setForeground(false);
        expect(created.last.disposals, 1);
        // The shared session retains the lease while backgrounded. Resuming
        // must reopen even though the widget's request has not changed.
        await session.setForeground(true);
        expect(created, hasLength(3));
        expect(created.last.analysisStarts, 1);
      } finally {
        // Finish async camera work in this test's live FakeAsync zone. An
        // addTearDown outside that zone cannot flush its pending continuations.
        try {
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
          await session.close();
        } finally {
          session.dispose();
          tracking.dispose();
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(budgetChannel, null);
          debugDefaultTargetPlatformOverride = previousPlatform;
        }
      }
    },
  );

  testWidgets('optical lease only reacquires for a changed request or route', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final first = FakeTrackingService(), second = FakeTrackingService();
    final session = CountingOpticalSession();
    final navigator = GlobalKey<NavigatorState>();
    Widget tree(VrSpatialTrackingService service, bool enabled, String label) =>
        MaterialApp(
          navigatorKey: navigator,
          home: VrOpticalTrackingCameraLease(
            session: session,
            service: service,
            enabled: enabled,
            child: Scaffold(body: Text(label)),
          ),
        );
    try {
      await tester.pumpWidget(tree(first, true, 'first'));
      expect(session.acquisitions, 1);
      await tester.pumpWidget(tree(first, true, 'unrelated rebuild'));
      expect(session.acquisitions, 1);
      await tester.pumpWidget(tree(second, true, 'new service'));
      expect(session.acquisitions, 2);
      expect(session.lastService, same(second));
      await tester.pumpWidget(tree(second, false, 'disabled'));
      expect(session.releases, 1);
      await tester.pumpWidget(tree(second, false, 'still disabled'));
      expect(session.releases, 1);
      await tester.pumpWidget(tree(second, true, 'enabled again'));
      expect(session.acquisitions, 3);
      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('Private')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(session.releases, 2);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(session.acquisitions, 4);
    } finally {
      try {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      } finally {
        first.dispose();
        second.dispose();
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    }
  });

  test(
    'analysis opt-in borrows stereo owner and final release invalidates it',
    () async {
      const markerId = 'vrlizate-marker-v1:0123456789abcdef';
      const channel = MethodChannel('vrlizate/vision_inference');
      var nativeRequests = 0;
      final tracking = FakeTrackingService();
      final created = <FakePreviewCamera>[];
      final session = VrPassthroughCameraSession(
        observeLifecycle: false,
        permissionGranted: () async => true,
        camerasProvider: () async => [rear],
        controllerFactory: (camera) {
          final fake = FakePreviewCamera(camera);
          created.add(fake);
          return fake;
        },
      );
      Map<String, dynamic> fixture() => {
        'status': 'ok',
        'imageWidth': 18,
        'imageHeight': 24,
        'inferenceMs': 1.5,
        'markers': [
          {
            'rawValue': markerId,
            'corners': [
              {'x': 2, 'y': 2},
              {'x': 14, 'y': 2},
              {'x': 14, 'y': 14},
              {'x': 2, 'y': 14},
            ],
          },
        ],
      };
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'capabilities') {
              return {'supportsYuv420Planes': false};
            }
            expect(call.method, 'analyze');
            final args = call.arguments as Map;
            expect(args['detectPose'], isFalse);
            expect(args['detectMarker'], isTrue);
            expect(args['sourceId'], 'visor:0');
            expect((args['bytes'] as Uint8List).length, 24 * 18 * 3 ~/ 2);
            nativeRequests++;
            return fixture();
          });
      addTearDown(() async {
        await session.close();
        session.dispose();
        tracking.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      tracking.visualTracking.setMarkerConfiguration(
        const VrTrackingMarkerConfiguration(
          markerId: markerId,
          widthMeters: .07,
        ),
      );
      final left = Object(), right = Object();
      await session.acquire(
        left,
        lens: CameraLensDirection.back,
        service: tracking,
      );
      await session.acquire(
        right,
        lens: CameraLensDirection.back,
        service: tracking,
      );
      expect(created, hasLength(1));
      expect(created.single.analysisStarts, 0);
      expect(nativeRequests, 0);

      tracking.visualTracking.setEnabled(true);
      await session.acquire(
        left,
        lens: CameraLensDirection.back,
        service: tracking,
      );
      expect(created, hasLength(1));
      expect(created.single.analysisStarts, 1);
      expect(created.single.value.isStreamingImages, isTrue);
      final observed = Completer<void>();
      void onObservation() {
        if (tracking.visualTracking.markerVisible && !observed.isCompleted) {
          observed.complete();
        }
      }

      tracking.visualTracking.addListener(onObservation);
      // A synthetic camera-plane fixture tests ownership/dispatch only; it is
      // never evidence of physical ML recognition or metric calibration.
      created.single.analysis!(
        // ignore: deprecated_member_use
        CameraImage.fromPlatformData({
          'width': 24,
          'height': 18,
          'format': 35,
          'planes': [
            {'bytes': Uint8List(432), 'bytesPerRow': 24, 'bytesPerPixel': 1},
            {'bytes': Uint8List(108), 'bytesPerRow': 12, 'bytesPerPixel': 1},
            {'bytes': Uint8List(108), 'bytesPerRow': 12, 'bytesPerPixel': 1},
          ],
        }),
      );
      await observed.future.timeout(const Duration(seconds: 5));
      tracking.visualTracking.removeListener(onObservation);
      expect(nativeRequests, 1);
      expect(tracking.visualTracking.metricPoseReady, isFalse);

      tracking.visualTracking.setEnabled(false);
      await session.acquire(
        left,
        lens: CameraLensDirection.back,
        service: tracking,
      );
      expect(created.single.analysisStops, 1);
      expect(created.single.disposals, 0);
      expect(created.single.value.isInitialized, isTrue);
      expect(
        session.controllerFor(CameraLensDirection.back),
        same(created.single),
      );

      tracking.visualTracking.setEnabled(true);
      await session.acquire(
        left,
        lens: CameraLensDirection.back,
        service: tracking,
      );
      tracking.visualTracking.acceptResultForTesting(fixture());
      tracking.visualTracking.captureCalibrationView();
      expect(tracking.visualTracking.calibrationViews, 1);
      await session.release(left);
      expect(created.single.disposals, 0);
      expect(tracking.visualTracking.markerVisible, isTrue);
      await session.release(right);
      expect(created.single.disposals, 1);
      expect(tracking.visualTracking.markerVisible, isFalse);
      expect(tracking.visualTracking.calibrationViews, 0);
      expect(tracking.visualTracking.profile, isNull);

      await session.acquire(
        left,
        lens: CameraLensDirection.back,
        service: tracking,
      );
      expect(created, hasLength(2));
      expect(created.last.description.name, created.first.description.name);
      expect(tracking.visualTracking.markerVisible, isFalse);
      expect(tracking.visualTracking.calibrationViews, 0);
      expect(tracking.visualTracking.metricPoseReady, isFalse);
    },
  );

  test('analyzer startup failure preserves GPU camera preview', () async {
    final tracking = FakeTrackingService();
    final camera = FakePreviewCamera(rear)..failsAnalysis = true;
    final session = VrPassthroughCameraSession(
      observeLifecycle: false,
      permissionGranted: () async => true,
      camerasProvider: () async => [rear],
      controllerFactory: (_) => camera,
    );
    addTearDown(() async {
      await session.close();
      session.dispose();
      tracking.dispose();
    });
    tracking.visualTracking.setEnabled(true);
    tracking.visualTracking.setBodyDetectionEnabled(true);
    final owner = Object();
    await session.acquire(
      owner,
      lens: CameraLensDirection.back,
      service: tracking,
    );
    expect(camera.analysisStarts, 1);
    expect(camera.value.isInitialized, isTrue);
    expect(camera.value.isStreamingImages, isFalse);
    expect(camera.disposals, 0);
    expect(session.controllerFor(CameraLensDirection.back), same(camera));
    expect(
      session.statusFor(CameraLensDirection.back),
      VrPassthroughCameraStatus.ready,
    );
    expect(tracking.visualTracking.status, contains('Análisis no disponible'));
    expect(tracking.visualTracking.metricPoseReady, isFalse);
    await session.release(owner);
    expect(camera.disposals, 1);
  });

  test(
    'release during initialize disposes pending controller without publishing it',
    () async {
      final camera = FakePreviewCamera(rear)
        ..initialization = Completer<void>();
      final session = VrPassthroughCameraSession(
        observeLifecycle: false,
        permissionGranted: () async => true,
        camerasProvider: () async => [rear],
        controllerFactory: (_) => camera,
      );
      final owner = Object();
      final opening = session.acquire(owner, lens: CameraLensDirection.back);
      await Future<void>.delayed(Duration.zero);
      final closing = session.release(owner);
      camera.initialization!.complete();
      await opening;
      await closing;
      expect(camera.disposals, 1);
      expect(session.controllerFor(CameraLensDirection.back), isNull);
      expect(
        session.statusFor(CameraLensDirection.back),
        VrPassthroughCameraStatus.disabled,
      );
      await session.close();
      session.dispose();
    },
  );

  test(
    'lifecycle closes hardware and reacquires only for retained leases',
    () async {
      final created = <FakePreviewCamera>[];
      final session = VrPassthroughCameraSession(
        observeLifecycle: false,
        permissionGranted: () async => true,
        camerasProvider: () async => [rear],
        controllerFactory: (description) {
          final camera = FakePreviewCamera(description);
          created.add(camera);
          return camera;
        },
      );
      final owner = Object();
      await session.acquire(owner, lens: CameraLensDirection.back);
      await session.setForeground(false);
      expect(created.single.disposals, 1);
      expect(
        session.statusFor(CameraLensDirection.back),
        VrPassthroughCameraStatus.paused,
      );
      await session.setForeground(true);
      expect(created, hasLength(2));
      await session.release(owner);
      await session.setForeground(false);
      await session.setForeground(true);
      expect(created, hasLength(2));
      await session.close();
      session.dispose();
    },
  );

  test(
    'second lens reports contention, then opens when first lease leaves',
    () async {
      final created = <FakePreviewCamera>[];
      final session = VrPassthroughCameraSession(
        observeLifecycle: false,
        permissionGranted: () async => true,
        camerasProvider: () async => [rear, front],
        controllerFactory: (description) {
          final camera = FakePreviewCamera(description);
          created.add(camera);
          return camera;
        },
      );
      final visor = Object(), inspector = Object();
      await session.acquire(visor, lens: CameraLensDirection.back);
      await session.acquire(inspector, lens: CameraLensDirection.front);
      expect(created, hasLength(1));
      expect(session.controllerFor(CameraLensDirection.front), isNull);
      expect(
        session.statusFor(CameraLensDirection.front),
        VrPassthroughCameraStatus.busy,
      );
      await session.release(visor);
      expect(created, hasLength(2));
      expect(created.first.disposals, 1);
      expect(
        session.controllerFor(CameraLensDirection.front),
        same(created.last),
      );
      await session.close();
      session.dispose();
    },
  );

  test('same owner can change lens without leaking previous camera', () async {
    final created = <FakePreviewCamera>[];
    final session = VrPassthroughCameraSession(
      observeLifecycle: false,
      permissionGranted: () async => true,
      camerasProvider: () async => [rear, front],
      controllerFactory: (description) {
        final camera = FakePreviewCamera(description);
        created.add(camera);
        return camera;
      },
    );
    final owner = Object();
    await session.acquire(owner, lens: CameraLensDirection.back);
    await session.acquire(owner, lens: CameraLensDirection.front);
    expect(created, hasLength(2));
    expect(created.first.disposals, 1);
    expect(session.controllerFor(CameraLensDirection.back), isNull);
    await session.close();
    session.dispose();
  });

  test(
    'unavailable requested lens never falls back to a wrongly labeled camera',
    () async {
      var factories = 0;
      final session = VrPassthroughCameraSession(
        observeLifecycle: false,
        permissionGranted: () async => true,
        camerasProvider: () async => [rear],
        controllerFactory: (description) {
          factories++;
          return FakePreviewCamera(description);
        },
      );
      await session.acquire(Object(), lens: CameraLensDirection.front);
      expect(factories, 0);
      expect(
        session.statusFor(CameraLensDirection.front),
        VrPassthroughCameraStatus.unavailable,
      );
      await session.close();
      session.dispose();
    },
  );

  test(
    'awaits VIO suspension and balances changed services after camera release',
    () async {
      final first = FakeTrackingService()..suspension = Completer<void>();
      final second = FakeTrackingService();
      final camera = FakePreviewCamera(rear);
      var factories = 0;
      final session = VrPassthroughCameraSession(
        observeLifecycle: false,
        permissionGranted: () async => true,
        camerasProvider: () async => [rear],
        controllerFactory: (_) {
          factories++;
          return camera;
        },
      );
      final owner = Object();
      final opening = session.acquire(
        owner,
        lens: CameraLensDirection.back,
        service: first,
      );
      await Future<void>.delayed(Duration.zero);
      expect(first.suspensions, 1);
      expect(factories, 0);
      first.suspension!.complete();
      await opening;
      await session.acquire(
        owner,
        lens: CameraLensDirection.back,
        service: second,
      );
      expect(factories, 1);
      expect(second.suspensions, 1);
      expect(first.resumptions, 0);
      await session.release(owner);
      expect(camera.disposals, 1);
      expect(first.resumptions, 1);
      expect(second.resumptions, 1);
      await session.close();
      session.dispose();
      first.dispose();
      second.dispose();
    },
  );

  test(
    'failed initialization releases partial camera; denial never opens it',
    () async {
      final camera = FakePreviewCamera(rear)..fails = true;
      final session = VrPassthroughCameraSession(
        observeLifecycle: false,
        permissionGranted: () async => true,
        camerasProvider: () async => [rear],
        controllerFactory: (_) => camera,
      );
      await session.acquire(Object(), lens: CameraLensDirection.back);
      expect(camera.disposals, 1);
      expect(
        session.statusFor(CameraLensDirection.back),
        VrPassthroughCameraStatus.unavailable,
      );
      await session.close();
      session.dispose();
      final denied = VrPassthroughCameraSession(
        observeLifecycle: false,
        permissionGranted: () async => false,
        camerasProvider: () async => throw StateError('should not discover'),
      );
      await denied.acquire(Object(), lens: CameraLensDirection.back);
      expect(
        denied.statusFor(CameraLensDirection.back),
        VrPassthroughCameraStatus.permissionDenied,
      );
      await denied.close();
      denied.dispose();
    },
  );
}
