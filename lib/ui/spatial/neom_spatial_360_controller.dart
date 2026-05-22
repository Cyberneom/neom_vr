import 'dart:async';

import 'package:flutter/services.dart';
import 'package:neom_commons/utils/constants/app_page_id_constants.dart';
import 'package:neom_commons/utils/vr_utilities.dart';
import 'package:sint/sint.dart';
import 'package:vrlizate/vrlizate.dart';

import '../../engine/neom_vr_360_engine.dart';
import '../../engine/neom_vr_painter_engine.dart';

class NeomSpatial360Controller extends SintController {

  late NeomVR360Engine vrEngine;
  late HeadTracker headTracker;
  NeomVrPainterEngine? painterEngine;

  Timer? _animationTimer;

  final RxBool isRunning = true.obs;
  final RxBool useGyroscope = true.obs;
  final RxBool showRings = true.obs;
  final RxBool showConstellations = true.obs;
  final RxBool showNebula = true.obs;
  final RxBool autoRotate = true.obs;
  final RxString colorMode = 'default'.obs;
  final RxDouble gyroSensitivity = 0.03.obs;

  @override
  void onInit() {
    super.onInit();

    VrUtilities.enableVrMode();

    vrEngine = NeomVR360Engine();

    if (Sint.arguments != null && Sint.arguments is NeomVrPainterEngine) {
      painterEngine = Sint.arguments;
    } else if (Sint.isRegistered<NeomVrPainterEngine>()) {
      painterEngine = Sint.find<NeomVrPainterEngine>();
    }

    vrEngine.initialize();

    // Head tracking via sint_vr
    headTracker = HeadTracker(
      camera: vrEngine.camera,
      sensitivity: gyroSensitivity.value,
    );

    if (useGyroscope.value) {
      headTracker.start();
    }

    _startAnimation();
  }

  void _startAnimation() {
    _animationTimer?.cancel();
    DateTime lastTime = DateTime.now();

    _animationTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!isRunning.value) return;

      final now = DateTime.now();
      final dt = now.difference(lastTime).inMicroseconds / 1000000.0;
      lastTime = now;

      if (painterEngine != null) {
        vrEngine.updateAudio(
          amplitude: painterEngine!.waveHeight,
          frequency: 432.0,
          beat: painterEngine!.binauralPhase * 10,
          phase: painterEngine!.visualPhase,
          coherence: painterEngine!.hemisphericCoherence,
        );
      }

      vrEngine.camera.autoRotateSpeed = autoRotate.value ? 0.002 : 0;
      vrEngine.showRings = showRings.value;
      vrEngine.showConstellations = showConstellations.value;
      vrEngine.showNebula = showNebula.value;

      vrEngine.update(dt);
      update([AppPageIdConstants.vr360]);
    });
  }

  @override
  void onClose() {
    _animationTimer?.cancel();
    headTracker.dispose();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    super.onClose();
  }

  void toggleSimulation() {
    isRunning.toggle();
    update([AppPageIdConstants.vr360]);
  }

  void toggleGyroscope() {
    useGyroscope.toggle();
    if (useGyroscope.value) {
      headTracker.start();
    } else {
      headTracker.stop();
    }
    update([AppPageIdConstants.vr360]);
  }

  void toggleAutoRotate() {
    autoRotate.toggle();
    update([AppPageIdConstants.vr360]);
  }

  void toggleRings() {
    showRings.toggle();
    update([AppPageIdConstants.vr360]);
  }

  void toggleConstellations() {
    showConstellations.toggle();
    update([AppPageIdConstants.vr360]);
  }

  void toggleNebula() {
    showNebula.toggle();
    update([AppPageIdConstants.vr360]);
  }

  void setColorMode(String mode) {
    colorMode.value = mode;
    vrEngine.setColorTheme(mode);
    update([AppPageIdConstants.vr360]);
  }

  void setGyroSensitivity(double value) {
    gyroSensitivity.value = value.clamp(0.01, 0.1);
    headTracker.sensitivity = value;
  }

  void onPanUpdate(double dx, double dy) {
    if (useGyroscope.value) return;
    headTracker.applyTouchDelta(dx, dy);
  }

  void resetCamera() {
    vrEngine.camera.reset();
    headTracker.calibrate();
    update([AppPageIdConstants.vr360]);
  }

  void exitFullscreen() {
    Sint.back();
  }
}
