import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:neom_commons/utils/constants/app_page_id_constants.dart';
import 'package:neom_commons/utils/vr_utilities.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:sint/sint.dart';

import '../../engine/neom_vr_360_engine.dart';
import '../../engine/neom_vr_painter_engine.dart';

class NeomSpatial360Controller extends SintController {

  late NeomVR360Engine vrEngine;
  NeomVrPainterEngine? painterEngine;

  Timer? _animationTimer;
  StreamSubscription? _gyroSubscription;

  // Estado de UI
  final RxBool isRunning = true.obs;
  final RxBool useGyroscope = true.obs;
  final RxBool showRings = true.obs;
  final RxBool showConstellations = true.obs;
  final RxBool showNebula = true.obs;
  final RxBool autoRotate = true.obs;
  final RxString colorMode = 'default'.obs;

  // Sensibilidad del giroscopio
  final RxDouble gyroSensitivity = 0.03.obs;

  // Para control táctil cuando no hay giroscopio
  double _lastTouchX = 0;
  double _lastTouchY = 0;

  @override
  void onInit() {
    super.onInit();

    VrUtilities.enableVrMode();

    // Inicializar engine VR
    vrEngine = NeomVR360Engine();

    // Recibir el painter engine del generador
    if (Sint.arguments != null && Sint.arguments is NeomVrPainterEngine) {
      painterEngine = Sint.arguments;
    } else if (Sint.isRegistered<NeomVrPainterEngine>()) {
      painterEngine = Sint.find<NeomVrPainterEngine>();
    }

    // Inicializar universo
    vrEngine.initialize();

    // Iniciar giroscopio
    _initGyroscope();

    // Iniciar loop de animación
    _startAnimation();
  }

  void _initGyroscope() {
    // En web no hay giroscopio disponible
    if (kIsWeb) {
      useGyroscope.value = false;
      return;
    }

    try {
      _gyroSubscription = gyroscopeEventStream().listen((GyroscopeEvent event) {
        if (!useGyroscope.value || !isRunning.value) return;

        // El giroscopio da velocidades angulares en rad/s
        // Invertimos Y para que sea intuitivo (mirar arriba = hacia arriba)
        vrEngine.updateCamera(
          event.y * gyroSensitivity.value,  // Rotación horizontal
          -event.x * gyroSensitivity.value, // Rotación vertical
        );
      });
    } catch (e) {
      // Si no hay giroscopio, usar solo touch
      useGyroscope.value = false;
    }
  }

  void _startAnimation() {
    _animationTimer?.cancel();

    DateTime lastTime = DateTime.now();

    // 60 FPS
    _animationTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!isRunning.value) return;

      final now = DateTime.now();
      final dt = (now.difference(lastTime).inMicroseconds) / 1000000.0;
      lastTime = now;

      // Sincronizar con audio
      if (painterEngine != null) {
        vrEngine.updateAudio(
          amplitude: painterEngine!.waveHeight,
          frequency: 432.0, // Podrías obtener la frecuencia real
          beat: painterEngine!.binauralPhase * 10,
          phase: painterEngine!.visualPhase,
          coherence: painterEngine!.hemisphericCoherence,
        );
      }

      // Actualizar configuración
      vrEngine.autoRotate = autoRotate.value;
      vrEngine.showRings = showRings.value;
      vrEngine.showConstellations = showConstellations.value;
      vrEngine.showNebula = showNebula.value;

      // Tick de animación
      vrEngine.update(dt);

      update([AppPageIdConstants.vr360]);
    });
  }

  @override
  void onClose() {
    _animationTimer?.cancel();
    _gyroSubscription?.cancel();

    // Restaurar orientación
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    // Restaurar UI
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
  }

  // Control táctil para mover la cámara (cuando no hay giroscopio)
  void onPanStart(double x, double y) {
    _lastTouchX = x;
    _lastTouchY = y;
  }

  void onPanUpdate(double x, double y) {
    if (useGyroscope.value) return; // Si hay giroscopio, ignorar touch

    final deltaX = (x - _lastTouchX) * 0.005;
    final deltaY = (y - _lastTouchY) * 0.005;

    vrEngine.updateCamera(-deltaX, deltaY);

    _lastTouchX = x;
    _lastTouchY = y;
  }

  void resetCamera() {
    vrEngine.cameraTheta = 0.0;
    vrEngine.cameraPhi = 0.0;
    update([AppPageIdConstants.vr360]);
  }

  void exitFullscreen() {
    Sint.back();
  }
}
