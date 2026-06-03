import 'dart:async';

import 'package:flutter/services.dart';
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
  final RxBool useGyroscope = true.obs;

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

  /// Alterna el estado de reproducción de la simulación VR (Pausa/Reanudar).
  void toggleSimulation() {
    isRunning.toggle();
    update([AppPageIdConstants.vr360]);
  }

  /// Activa o desactiva el uso del giroscopio del dispositivo.
  void toggleGyroscope() {
    useGyroscope.toggle();
    if (useGyroscope.value) {
      headTracker.start();
    } else {
      headTracker.stop();
    }
    update([AppPageIdConstants.vr360]);
  }

  /// Activa o desactiva la auto-rotación de la cámara.
  void toggleAutoRotate() {
    autoRotate.toggle();
    update([AppPageIdConstants.vr360]);
  }

  /// Activa o desactiva el renderizado de anillos concéntricos.
  void toggleRings() {
    showRings.toggle();
    update([AppPageIdConstants.vr360]);
  }

  /// Activa o desactiva el renderizado de constelaciones y sus enlaces.
  void toggleConstellations() {
    showConstellations.toggle();
    update([AppPageIdConstants.vr360]);
  }

  /// Activa o desactiva el efecto visual difuminado de la nebulosa.
  void toggleNebula() {
    showNebula.toggle();
    update([AppPageIdConstants.vr360]);
  }

  /// Modifica el esquema cromático visual de acuerdo con un modo o tema.
  void setColorMode(String mode) {
    colorMode.value = mode;
    vrEngine.setColorTheme(mode);
    update([AppPageIdConstants.vr360]);
  }

  /// Ajusta el factor de sensibilidad del giroscopio físico.
  void setGyroSensitivity(double value) {
    gyroSensitivity.value = value.clamp(0.01, 0.1);
    headTracker.sensitivity = value;
  }

  /// Se ejecuta al deslizar el dedo en pantalla para rotar manualmente la cámara cuando el giroscopio está apagado.
  void onPanUpdate(double dx, double dy) {
    if (useGyroscope.value) return;
    headTracker.applyTouchDelta(dx, dy);
  }

  /// Calibra la cámara a su punto frontal de inicio y resetea el giroscopio.
  void resetCamera() {
    vrEngine.camera.reset();
    headTracker.calibrate();
    update([AppPageIdConstants.vr360]);
  }

  /// Sale de la vista de pantalla completa y retorna a la página previa.
  void exitFullscreen() {
    Sint.back();
  }
}
