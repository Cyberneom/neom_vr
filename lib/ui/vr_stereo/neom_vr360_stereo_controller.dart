import 'dart:async';

import 'package:flutter/services.dart';
import 'package:neom_commons/utils/constants/app_page_id_constants.dart';
import 'package:neom_commons/utils/vr_utilities.dart';
import 'package:sint/sint.dart';
import 'package:vrlizate/vrlizate.dart';

import '../../engine/neom_vr_360_engine.dart';
import '../../engine/neom_vr_painter_engine.dart';

/// Controlador para modo VR estereoscópico (visor con smartphone).
/// Usa HeadTracker de sint_vr para giroscopio y touch fallback.
class NeomVR360StereoController extends SintController {

  late NeomVR360Engine vrEngine;
  late HeadTracker headTracker;
  NeomVrPainterEngine? vrPainterEngine;

  Timer? _animationTimer;

  // Estado de UI
  final RxBool isRunning = true.obs;
  final RxBool useGyroscope = true.obs;
  final RxBool showRings = true.obs;
  final RxBool showConstellations = true.obs;
  final RxBool showNebula = true.obs;
  final RxString colorMode = 'default'.obs;

  // Control de frecuencia directo
  final RxDouble frequency = 432.0.obs;
  final RxDouble wavelength = 1.0.obs;
  final RxDouble eyeSeparation = 0.065.obs;
  final RxDouble gyroSensitivity = 0.04.obs;

  @override
  void onInit() {
    super.onInit();

    VrUtilities.enableVrMode();

    vrEngine = NeomVR360Engine();

    // Recibir el painter engine del generador
    if (Sint.arguments != null && Sint.arguments is NeomVrPainterEngine) {
      vrPainterEngine = Sint.arguments;
    } else if (Sint.isRegistered<NeomVrPainterEngine>()) {
      vrPainterEngine = Sint.find<NeomVrPainterEngine>();
    }

    // Inicializar universo OPTIMIZADO para VR
    vrEngine.particleCount = 120;
    vrEngine.ringCount = 5;
    vrEngine.initialize();
    vrEngine.camera.autoRotateSpeed = 0; // Solo giroscopio en VR

    // Head tracking via sint_vr
    headTracker = HeadTracker.forCamera(
      vrEngine.camera,
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

      // Sincronizar con audio del painterEngine
      if (vrPainterEngine != null) {
        vrEngine.updateAudio(
          amplitude: vrPainterEngine!.waveHeight,
          frequency: frequency.value,
          beat: vrPainterEngine!.binauralPhase * 10,
          phase: vrPainterEngine!.visualPhase,
          coherence: vrPainterEngine!.hemisphericCoherence,
          waveLen: wavelength.value,
        );
      } else {
        vrEngine.updateAudio(
          amplitude: 0.5 + 0.3 * (DateTime.now().millisecondsSinceEpoch % 1000) / 1000,
          frequency: frequency.value,
          beat: 10.0,
          phase: (DateTime.now().millisecondsSinceEpoch % 10000) / 10000 * 3.14159 * 2,
          coherence: 0.7,
          waveLen: wavelength.value,
        );
      }

      vrEngine.eyeSeparation = eyeSeparation.value;
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

  // --- Acciones de usuario ---

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

  void setFrequency(double value) {
    frequency.value = value.clamp(20.0, 2000.0);
    update([AppPageIdConstants.vr360]);
  }

  void setWavelength(double value) {
    wavelength.value = value.clamp(0.5, 2.0);
    update([AppPageIdConstants.vr360]);
  }

  void setEyeSeparation(double value) {
    eyeSeparation.value = value.clamp(0.04, 0.08);
    update([AppPageIdConstants.vr360]);
  }

  void setGyroSensitivity(double value) {
    gyroSensitivity.value = value.clamp(0.01, 0.1);
    headTracker.sensitivity = value;
  }

  // Touch fallback — delegates to sint_vr HeadTracker
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
