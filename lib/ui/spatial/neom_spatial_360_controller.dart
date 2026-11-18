import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:neom_commons/utils/constants/app_page_id_constants.dart';
import 'package:neom_commons/utils/vr_utilities.dart';
import 'package:sint/sint.dart';
import 'package:vrlizate/vrlizate.dart';

import '../../engine/neom_vr_360_engine.dart';
import '../../engine/neom_vr_painter_engine.dart';

/// Controlador Sint que gestiona la escena espacial de realidad virtual 360 grados.
///
/// Encargado de coordinar el giroscopio mediante `HeadTracker`, alimentar el motor
/// visual `NeomVR360Engine` con ciclos de animación de tiempo y gestionar interacciones.
class NeomSpatial360Controller extends SintController {

  /// Motor de simulación 3D que almacena y actualiza el espacio VR.
  late NeomVR360Engine vrEngine;

  /// Controlador de seguimiento predictivo de cabeza mediante fusión de sensores.
  late HeadTracker headTracker;

  /// Motor opcional para suavizado y modulación de respuesta sonora/visual.
  NeomVrPainterEngine? painterEngine;

  Timer? _animationTimer;

  /// Define si la simulación y animación gráfica está actualmente corriendo.
  final RxBool isRunning = true.obs;

  /// Define si se debe utilizar el giroscopio físico del dispositivo móvil.
  /// Deshabilitado por defecto en Web y Escritorio (`macOS`/`Windows`/`Linux`).
  static bool get _defaultUseGyroscope =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  late final RxBool useGyroscope = _defaultUseGyroscope.obs;

  /// Control reactivo para activar o desactivar la pintura de anillos concéntricos.
  final RxBool showRings = true.obs;

  /// Control reactivo para activar o desactivar la pintura de constelaciones.
  final RxBool showConstellations = true.obs;

  /// Control reactivo para activar o desactivar la pintura de la nebulosa cósmica.
  final RxBool showNebula = true.obs;

  /// Define si la cámara espacial debe rotar suavemente de manera automática.
  final RxBool autoRotate = true.obs;

  /// Temática cromática visual activa (ej. 'default', 'calm', etc.).
  final RxString colorMode = 'default'.obs;

  /// Sensibilidad de movimiento del giroscopio físico.
  final RxDouble gyroSensitivity = 0.03.obs;

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
    painterEngine ??= _resolvePainterEngine();

    vrEngine.initialize();

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
      update([AppPageIdConstants.spatial360]);
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
    autoRotate.close();
    colorMode.close();
    gyroSensitivity.close();

    super.onClose();
  }

  /// Alterna el estado de reproducción de la simulación VR (Pausa/Reanudar).
  void toggleSimulation() {
    isRunning.toggle();
    update([AppPageIdConstants.spatial360]);
  }

  /// Activa o desactiva el uso del giroscopio del dispositivo.
  void toggleGyroscope() {
    useGyroscope.toggle();
    if (useGyroscope.value) {
      _startHeadTrackerSafely();
    } else {
      headTracker.stop();
    }
    update([AppPageIdConstants.spatial360]);
  }

  /// Activa o desactiva la auto-rotación de la cámara.
  void toggleAutoRotate() {
    autoRotate.toggle();
    update([AppPageIdConstants.spatial360]);
  }

  /// Activa o desactiva el renderizado de anillos concéntricos.
  void toggleRings() {
    showRings.toggle();
    update([AppPageIdConstants.spatial360]);
  }

  /// Activa o desactiva el renderizado de constelaciones y sus enlaces.
  void toggleConstellations() {
    showConstellations.toggle();
    update([AppPageIdConstants.spatial360]);
  }

  /// Activa o desactiva el efecto visual difuminado de la nebulosa.
  void toggleNebula() {
    showNebula.toggle();
    update([AppPageIdConstants.spatial360]);
  }

  /// Modifica el esquema cromático visual de acuerdo con un modo o tema.
  void setColorMode(String mode) {
    colorMode.value = mode;
    vrEngine.setColorTheme(mode);
    update([AppPageIdConstants.spatial360]);
  }

  /// Ajusta el factor de sensibilidad del giroscopio físico.
  void setGyroSensitivity(double value) {
    if (!value.isFinite) return;
    final clamped = value.clamp(0.01, 0.1);
    gyroSensitivity.value = clamped;
    try {
      headTracker.sensitivity = clamped;
    } catch (_) {}
  }

  /// Se ejecuta al deslizar el dedo en pantalla para rotar manualmente la cámara cuando el giroscopio está apagado.
  void onPanUpdate(double dx, double dy) {
    if (useGyroscope.value || !dx.isFinite || !dy.isFinite) return;
    headTracker.applyTouchDelta(dx, dy);
  }

  /// Calibra la cámara a su punto frontal de inicio y resetea el giroscopio.
  void resetCamera() {
    vrEngine.camera.reset();
    headTracker.calibrate();
    update([AppPageIdConstants.spatial360]);
  }

  /// Sale de la vista de pantalla completa y retorna a la página previa.
  void exitFullscreen() {
    try {
      Sint.back();
    } catch (_) {}
  }
}
