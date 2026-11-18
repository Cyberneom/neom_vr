import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neom_commons/utils/constants/app_page_id_constants.dart';
import 'package:neom_vr/engine/neom_vr_360_engine.dart';
import 'package:neom_vr/state/vr_controller.dart';
import 'package:neom_vr/state/vr_scene_state.dart';
import 'package:neom_vr/ui/spatial/neom_spatial_360_controller.dart';
import 'package:neom_vr/ui/vr_stereo/neom_vr360_stereo_controller.dart';
import 'package:sint/sint.dart';
import 'package:vrlizate/vrlizate.dart';

class _TestVRController extends VRController {
  _TestVRController({super.engine, super.autoStart = false});
  double lastDt = -1;

  @override
  void onVRInit() {}

  @override
  void onVRUpdate(double dt) {
    lastDt = dt;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(Sint.resetInstance);

  group('neom_vr Lote 85 lifecycle & NaN/Infinity hardening', () {
    test('NeomVR360Engine guards eyeSeparation, audio inputs, dt, and camera', () {
      final engine = NeomVR360Engine();
      engine.particleCount = -10;
      engine.ringCount = 9999;
      engine.initialize();
      expect(engine.particles, isEmpty);
      expect(engine.rings, isNotEmpty);

      engine.eyeSeparation = double.nan;
      expect(engine.eyeSeparation.isFinite, isTrue);
      engine.eyeSeparation = 5.0;
      expect(engine.eyeSeparation, closeTo(0.25, 1e-6));

      engine.updateAudio(
        amplitude: double.nan,
        frequency: double.infinity,
        beat: double.negativeInfinity,
        phase: double.nan,
        coherence: double.nan,
        waveLen: double.nan,
      );
      expect(engine.normalizedFrequency.isFinite, isTrue);
      expect(() => engine.frequencyModulatedColor, returnsNormally);

      engine.update(double.nan);
      engine.update(-5.0);
      engine.update(10.0);
      engine.updateCamera(double.nan, double.infinity);
      expect(engine.camera.theta.isFinite, isTrue);
      expect(engine.camera.phi.isFinite, isTrue);
      engine.dispose();
    });

    test('VRSceneState.dispose and VRController.onClose release Rx observables cleanly', () {
      final rawEngine = VREngine();
      final sceneState = VRSceneState(rawEngine);
      sceneState.addNode(Node(name: 'cube'));
      expect(sceneState.nodeCount.value, greaterThanOrEqualTo(0));
      sceneState.dispose();

      final ctrl = _TestVRController(engine: rawEngine, autoStart: false);
      ctrl.onInit();
      ctrl.onClose();
      ctrl.onClose(); // idempotent
      rawEngine.dispose();
    });

    test('NeomSpatial360Controller & NeomVR360StereoController guard NaN inputs and idempotent onClose', () {
      final spatial = NeomSpatial360Controller();
      // Closing before onInit must not throw LateInitializationError
      expect(spatial.onClose, returnsNormally);

      final spatial2 = NeomSpatial360Controller()..onInit();
      spatial2.useGyroscope.value = false;
      spatial2.setGyroSensitivity(double.nan);
      expect(spatial2.gyroSensitivity.value.isFinite, isTrue);
      spatial2.onPanUpdate(double.nan, double.infinity);
      expect(spatial2.vrEngine.camera.theta.isFinite, isTrue);
      spatial2.onClose();
      spatial2.onClose();

      final stereo = NeomVR360StereoController();
      expect(stereo.onClose, returnsNormally);

      final stereo2 = NeomVR360StereoController()..onInit();
      stereo2.useGyroscope.value = false;
      stereo2.setFrequency(double.nan);
      stereo2.setWavelength(double.infinity);
      stereo2.setEyeSeparation(double.nan);
      stereo2.setGyroSensitivity(double.negativeInfinity);
      stereo2.onPanUpdate(double.nan, double.infinity);
      expect(stereo2.frequency.value.isFinite, isTrue);
      expect(stereo2.wavelength.value.isFinite, isTrue);
      expect(stereo2.eyeSeparation.value.isFinite, isTrue);
      expect(stereo2.gyroSensitivity.value.isFinite, isTrue);
      expect(stereo2.vrEngine.camera.theta.isFinite, isTrue);
      stereo2.onClose();
      stereo2.onClose();
    });

    testWidgets(
      'useGyroscope defaults to false on desktop and spatial360 SintBuilder rebuilds on controller updates',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          final spatialDesktop = NeomSpatial360Controller();
          final stereoDesktop = NeomVR360StereoController();
          expect(spatialDesktop.useGyroscope.value, isFalse);
          expect(stereoDesktop.useGyroscope.value, isFalse);

          int spatialBuilds = 0;
          await tester.pumpWidget(
            MaterialApp(
              home: SintBuilder<NeomSpatial360Controller>(
                id: AppPageIdConstants.spatial360,
                init: spatialDesktop,
                builder: (c) {
                  spatialBuilds++;
                  return Text('running:${c.isRunning.value}');
                },
              ),
            ),
          );
          final initialBuilds = spatialBuilds;
          spatialDesktop.toggleSimulation();
          await tester.pump();
          expect(spatialBuilds, greaterThan(initialBuilds));
          expect(find.text('running:false'), findsOneWidget);

          spatialDesktop.onClose();
          stereoDesktop.onClose();
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  });
}
