import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:neom_commons/utils/constants/app_page_id_constants.dart';
import 'package:neom_commons/utils/vr_utilities.dart';
import 'package:sint/sint.dart';
import 'package:vrlizate/vrlizate.dart';

import '../../engine/neom_vr_360_engine.dart';
import '../../engine/neom_vr_painter_engine.dart';

/// Controlador para modo VR estereoscópico (visor con smartphone).
/// Usa HeadTracker de vrlizate para giroscopio y touch fallback.
class NeomVR360StereoController extends SintController {

  late NeomVR360Engine vrEngine;
  late HeadTracker headTracker;
  NeomVrPainterEngine? vrPainterEngine;

  Timer? _animationTimer;

  // Estado de UI
  final RxBool isRunning = true.obs;
  static bool get _defaultUseGyroscope =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  late final RxBool useGyroscope = _defaultUseGyroscope.obs;
  final RxBool showRings = true.obs;
  final RxBool showConstellations = true.obs;
  final RxBool showNebula = true.obs;
  final RxString colorMode = 'default'.obs;

  // Control de frecuencia directo
  final RxDouble frequency = 432.0.obs;
  final RxDouble wavelength = 1.0.obs;
  final RxDouble eyeSeparation = 0.065.obs;
  final RxDouble gyroSensitivity = 0.04.obs;

  static NeomVrPainterEngine? _resolvePainterEngine() {
    try {
      final args = Sint.arguments;
      if (args is NeomVrPainterEngine) return args;
    } catch (_) {
      // SintRoot may not be mounted when embedded in standard MaterialApp or headless tests.
    }
    if (Sint.isRegistered<NeomVrPainterEngine>()) {
      return Sint.find<NeomVrPainterEngine>();
    }
    return null;
  }

  @override
  void onInit() {
    super.onInit();

    try {
      VrUtilities.enableVrMode();
    } catch (_) {}

    vrEngine = NeomVR360Engine();

    // Recibir el painter engine del generador
    vrPainterEngine ??= _resolvePainterEngine();

    // Inicializar universo OPTIMIZADO para VR
    vrEngine.particleCount = 120;
    vrEngine.ringCount = 5;
    vrEngine.initialize();
    vrEngine.camera.autoRotateSpeed = 0; // Solo giroscopio en VR

    // Head tracking via vrlizate
    headTracker = HeadTracker.forCamera(
      vrEngine.camera,
      sensitivity: gyroSensitivity.value,
    );

    if (useGyroscope.value) {
      _startHeadTrackerSafely();
    }

    _startAnimation();
  }

  void _startHeadTrackerSafely() {
    runZonedGuarded(
      () {
        headTracker.start();
      },
      (Object error, StackTrace stack) {
        useGyroscope.value = false;
      },
    );
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

  bool _didClose = false;

  @override
  void onClose() {
    if (_didClose) return;
    _didClose = true;
    _animationTimer?.cancel();
    _animationTimer = null;
    try {
      headTracker.dispose();
    } catch (_) {}
    try {
      vrEngine.dispose();
    } catch (_) {}

    isRunning.close();
    useGyroscope.close();
    showRings.close();
    showConstellations.close();
    showNebula.close();
    colorMode.close();
    frequency.close();
    wavelength.close();
    eyeSeparation.close();
    gyroSensitivity.close();

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
      _startHeadTrackerSafely();
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
    if (!value.isFinite) return;
    frequency.value = value.clamp(20.0, 2000.0);
    update([AppPageIdConstants.vr360]);
  }

  void setWavelength(double value) {
    if (!value.isFinite) return;
    wavelength.value = value.clamp(0.5, 2.0);
    update([AppPageIdConstants.vr360]);
  }

  void setEyeSeparation(double value) {
    if (!value.isFinite) return;
    eyeSeparation.value = value.clamp(0.04, 0.08);
    update([AppPageIdConstants.vr360]);
  }

  void setGyroSensitivity(double value) {
    if (!value.isFinite) return;
    final clamped = value.clamp(0.01, 0.1);
    gyroSensitivity.value = clamped;
    try {
      headTracker.sensitivity = clamped;
    } catch (_) {}
  }

  // Touch fallback — delegates to vrlizate HeadTracker
  void onPanUpdate(double dx, double dy) {
    if (useGyroscope.value || !dx.isFinite || !dy.isFinite) return;
    headTracker.applyTouchDelta(dx, dy);
  }

  void resetCamera() {
    vrEngine.camera.reset();
    headTracker.calibrate();
    update([AppPageIdConstants.vr360]);
  }

  void exitFullscreen() {
    try {
      Sint.back();
    } catch (_) {}
  }
}
