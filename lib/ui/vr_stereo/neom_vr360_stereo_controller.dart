import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:sint/sint.dart';
import 'package:neom_commons/utils/constants/app_page_id_constants.dart';
import 'package:neom_commons/utils/vr_utilities.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../../engine/neom_vr_360_engine.dart';
import '../../engine/neom_vr_painter_engine.dart';

/// Controlador para modo VR estereoscópico (visor con smartphone)
class NeomVR360StereoController extends SintController {

  late NeomVR360Engine vrEngine;
  NeomVrPainterEngine? vrPainterEngine;

  Timer? _animationTimer;
  StreamSubscription? _gyroSubscription;

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
  final RxDouble eyeSeparation = 0.065.obs; // Separación interpupilar

  // Sensibilidad del giroscopio
  final RxDouble gyroSensitivity = 0.04.obs;

  // Para control táctil cuando no hay giroscopio
  double _lastTouchX = 0;
  double _lastTouchY = 0;

  // Calibración del giroscopio
  double _gyroOffsetX = 0;
  double _gyroOffsetY = 0;
  bool _isCalibrating = false;
  final List<double> _calibrationSamplesX = [];
  final List<double> _calibrationSamplesY = [];

  @override
  void onInit() {
    super.onInit();

    VrUtilities.enableVrMode();

    // Inicializar engine VR
    vrEngine = NeomVR360Engine();

    // Recibir el painter engine del generador
    if (Sint.arguments != null && Sint.arguments is NeomVrPainterEngine) {
      vrPainterEngine = Sint.arguments;
    } else if (Sint.isRegistered<NeomVrPainterEngine>()) {
      vrPainterEngine = Sint.find<NeomVrPainterEngine>();
    }

    // Inicializar universo OPTIMIZADO para VR (menos partículas = más fluido)
    vrEngine.particleCount = 120;
    vrEngine.ringCount = 5;
    vrEngine.initialize();

    // Desactivar auto-rotate para VR (solo giroscopio)
    vrEngine.autoRotate = false;

    // Iniciar calibración del giroscopio
    _calibrateGyroscope();

    // Iniciar giroscopio
    _initGyroscope();

    // Iniciar loop de animación a 60fps
    _startAnimation();
  }

  void _calibrateGyroscope() {
    _isCalibrating = true;
    _calibrationSamplesX.clear();
    _calibrationSamplesY.clear();

    // Calibrar durante 1 segundo
    Future.delayed(const Duration(seconds: 1), () {
      if (_calibrationSamplesX.isNotEmpty) {
        _gyroOffsetX = _calibrationSamplesX.reduce((a, b) => a + b) / _calibrationSamplesX.length;
        _gyroOffsetY = _calibrationSamplesY.reduce((a, b) => a + b) / _calibrationSamplesY.length;
      }
      _isCalibrating = false;
    });
  }

  void _initGyroscope() {
    // En web no hay giroscopio disponible
    if (kIsWeb) {
      useGyroscope.value = false;
      return;
    }

    try {
      _gyroSubscription = gyroscopeEventStream().listen((GyroscopeEvent event) {
        if (_isCalibrating) {
          _calibrationSamplesX.add(event.x);
          _calibrationSamplesY.add(event.y);
          return;
        }

        if (!useGyroscope.value || !isRunning.value) return;

        // Aplicar offset de calibración
        final adjustedX = event.x - _gyroOffsetX;
        final adjustedY = event.y - _gyroOffsetY;

        // El giroscopio da velocidades angulares en rad/s
        vrEngine.updateCamera(
          adjustedY * gyroSensitivity.value,  // Rotación horizontal
          -adjustedX * gyroSensitivity.value, // Rotación vertical
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

    // 60 FPS constantes
    _animationTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!isRunning.value) return;

      final now = DateTime.now();
      final dt = (now.difference(lastTime).inMicroseconds) / 1000000.0;
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
        // Sin painterEngine, usar valores por defecto con variación
        vrEngine.updateAudio(
          amplitude: 0.5 + 0.3 * (DateTime.now().millisecondsSinceEpoch % 1000) / 1000,
          frequency: frequency.value,
          beat: 10.0,
          phase: (DateTime.now().millisecondsSinceEpoch % 10000) / 10000 * 3.14159 * 2,
          coherence: 0.7,
          waveLen: wavelength.value,
        );
      }

      // Actualizar separación de ojos
      vrEngine.eyeSeparation = eyeSeparation.value;

      // Actualizar configuración visual
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
    if (useGyroscope.value) {
      _calibrateGyroscope();
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
  }

  // Control táctil para mover la cámara (cuando no hay giroscopio)
  void onPanStart(double x, double y) {
    _lastTouchX = x;
    _lastTouchY = y;
  }

  void onPanUpdate(double x, double y) {
    if (useGyroscope.value) return;

    final deltaX = (x - _lastTouchX) * 0.005;
    final deltaY = (y - _lastTouchY) * 0.005;

    vrEngine.updateCamera(-deltaX, deltaY);

    _lastTouchX = x;
    _lastTouchY = y;
  }

  void resetCamera() {
    vrEngine.cameraTheta = 0.0;
    vrEngine.cameraPhi = 0.0;
    _calibrateGyroscope();
    update([AppPageIdConstants.vr360]);
  }

  void exitFullscreen() {
    Sint.back();
  }
}
