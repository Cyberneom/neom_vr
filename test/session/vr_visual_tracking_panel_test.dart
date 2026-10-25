import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neom_vr/session/vr_passthrough_camera_feed.dart';
import 'package:neom_vr/session/vr_spatial_tracking_service.dart';
import 'package:neom_vr/session/vr_visual_tracking_panel.dart';
import 'package:neom_vr/session/vr_tri_camera_live_inspector_card.dart';
import 'package:neom_vr/utils/constants/vr_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vrlizate_joystick/vrlizate_joystick.dart';

void main() {
  const marker = VrTrackingMarkerConfiguration(markerId: 'calibration-test');
  Map<String, dynamic> frame({bool visible = true}) => {
    'status': 'ok',
    'imageWidth': 640,
    'imageHeight': 480,
    'markers': [
      if (visible)
        {
          'rawValue': marker.markerId,
          'corners': [
            {'x': 200, 'y': 150},
            {'x': 300, 'y': 150},
            {'x': 300, 'y': 250},
            {'x': 200, 'y': 250},
          ],
        },
    ],
  };

  testWidgets(
    'capture feedback survives inference and reports loss separately',
    (tester) async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final service = VrSpatialTrackingService(observeLifecycle: false);
      final visual = service.visualTracking;
      final save = find.byKey(
        const ValueKey('capture-marker-calibration-view'),
      );
      final feedback = find.byKey(
        const ValueKey('marker-calibration-capture-confirmation'),
      );
      try {
        service.setControllerOpticalTrackingEnabled(true);
        visual.setMarkerConfiguration(marker);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: VrVisualTrackingPanel(service: service),
              ),
            ),
          ),
        );
        await tester.ensureVisible(save);
        visual.acceptResultForTesting(frame());
        await tester.pump();
        await tester.tap(save);
        await tester.pump();
        expect(visual.calibrationViews, 1);
        expect(find.text('Vistas guardadas: 1 / mínimo 6'), findsOneWidget);
        expect(feedback, findsOneWidget);
        visual.acceptResultForTesting(frame());
        await tester.pump();
        expect(feedback, findsOneWidget);

        visual.acceptResultForTesting(frame(visible: false));
        await tester.pump();
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pump();
        expect(visual.calibrationViews, 1);
        expect(find.textContaining('No se guardó la vista:'), findsOneWidget);
        expect(feedback, findsNothing);

        visual.acceptResultForTesting(frame());
        await tester.pump();
        await tester.tap(save);
        await tester.pump();
        expect(visual.calibrationViews, 2);
        expect(feedback, findsOneWidget);
        visual.invalidateStream('Cámara cerrada');
        await tester.pump();
        expect(find.text('Vistas guardadas: 0 / mínimo 6'), findsOneWidget);
        expect(feedback, findsNothing);
        expect(
          find.text('Se reinició la calibración: Cámara cerrada'),
          findsOneWidget,
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        service.dispose();
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    },
  );

  testWidgets('framing is explicit, contains full image, and leaves mix off', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final service = VrSpatialTrackingService(observeLifecycle: false);
    final navigation = GlobalKey<NavigatorState>();
    final framing = find.byKey(const ValueKey('calibration-framing-enabled'));
    try {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigation,
          home: Scaffold(
            body: SingleChildScrollView(
              child: VrVisualTrackingPanel(service: service),
            ),
          ),
        ),
      );
      expect(tester.widget<SwitchListTile>(framing).onChanged, isNull);
      expect(find.byType(VrPassthroughCameraFeed), findsNothing);
      service.setControllerOpticalTrackingEnabled(true);
      await tester.pump();
      await tester.ensureVisible(framing);
      await tester.tap(framing);
      await tester.pump();
      final feed = tester.widget<VrPassthroughCameraFeed>(
        find.byKey(const ValueKey('calibration-camera-framing')),
      );
      expect(feed.fit, BoxFit.contain);
      expect(feed.service, same(service));
      expect(service.passthroughMix, 0);
      expect(service.visorCameraPreviewEnabled, isFalse);
      expect(service.visualTracking.bodyDetectionEnabled, isFalse);

      navigation.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Other route')),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byType(VrPassthroughCameraFeed, skipOffstage: false),
        findsNothing,
      );
      navigation.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byType(VrPassthroughCameraFeed), findsOneWidget);
      service.setControllerOpticalTrackingEnabled(false);
      await tester.pump();
      expect(find.byType(VrPassthroughCameraFeed), findsNothing);
      expect(service.passthroughMix, 0);
    } finally {
      await tester.pumpWidget(const SizedBox());
      service.dispose();
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  testWidgets(
    'optical switch is expanded and reachable before camera monitors',
    (tester) async {
      final service = VrSpatialTrackingService(observeLifecycle: false);
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: VrTriCameraLiveInspectorCard(service: service),
              ),
            ),
          ),
        );
        final toggle = find.byKey(const ValueKey('visual-tracking-enabled'));
        expect(toggle.hitTestable(), findsOneWidget);
        expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
        expect(service.passthroughMix, 0);
        expect(service.controllerOpticalTrackingEnabled, isFalse);
        expect(find.byType(VrPassthroughCameraFeed), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        service.dispose();
      }
    },
  );

  testWidgets(
    'tapping optical ON then body and preview OFF preserves QR across rebuild',
    (tester) async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      SharedPreferences.setMockInitialValues({});
      final service = VrSpatialTrackingService(observeLifecycle: false);
      Widget inspector(String label) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                Text(label),
                VrTriCameraLiveInspectorCard(service: service),
              ],
            ),
          ),
        ),
      );
      final optical = find.byKey(const ValueKey('visual-tracking-enabled'));
      final body = find.byKey(const ValueKey('visor-body-detection-enabled'));
      final preview = find.byKey(
        const ValueKey(VrConstants.keyToggleLiveCameraInspectorBtn),
      );
      try {
        // Reproduce the reported initial state; subsequent changes must pass
        // through the actual SwitchListTile callbacks, not service setters.
        service.setPassthroughMix(.65);
        service.visualTracking.setBodyDetectionEnabled(true);
        await tester.pumpWidget(inspector('Initial'));
        await tester.pumpAndSettle();
        expect(tester.widget<SwitchListTile>(optical).value, isFalse);
        expect(tester.widget<SwitchListTile>(body).value, isTrue);
        expect(tester.widget<SwitchListTile>(preview).value, isTrue);

        await tester.ensureVisible(optical);
        await tester.tap(optical);
        await tester.pumpAndSettle();
        expect(service.controllerOpticalTrackingEnabled, isTrue);
        expect(service.visualTracking.markerDetectionEnabled, isTrue);

        await tester.ensureVisible(body);
        await tester.tap(body);
        await tester.pumpAndSettle();
        expect(service.visualTracking.bodyDetectionEnabled, isFalse);

        await tester.ensureVisible(preview);
        await tester.tap(preview);
        await tester.pumpAndSettle();
        await tester.pumpWidget(inspector('Rebuilt'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(optical);
        expect(tester.widget<SwitchListTile>(optical).value, isTrue);
        expect(tester.widget<SwitchListTile>(body).value, isFalse);
        expect(tester.widget<SwitchListTile>(preview).value, isFalse);
        expect(service.controllerOpticalTrackingEnabled, isTrue);
        expect(service.visualTracking.markerDetectionEnabled, isTrue);
        expect(service.visorCameraPreviewEnabled, isFalse);
        expect(service.passthroughMix, 0);
        expect(find.byType(VrPassthroughCameraFeed), findsNothing);
      } finally {
        try {
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
          await service.flushPassthroughPreferences();
        } finally {
          service.dispose();
          debugDefaultTargetPlatformOverride = previousPlatform;
        }
      }
    },
  );
}
