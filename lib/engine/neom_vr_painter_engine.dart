import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:neom_core/app_config.dart';
import 'package:neom_core/domain/model/neom_visual_state.dart';

/// Motor de dibujo y procesamiento visual VR de Neom.
///
/// Encargado de suavizar y transformar las señales de audio analizadas
/// en parámetros estéticos interpretables por los pintores de escena 3D y osciloscopio.
class NeomVrPainterEngine extends ChangeNotifier {

  NeomVisualState _state = NeomVisualState.zero();

  /// Nivel de amplitud visual base por defecto.
  double visualAmplitudeBase = 0.12;

  /// Nivel máximo permitido para la amplitud de la onda visual.
  double visualAmplitudeMax = 0.45;

  double _smooth({
    required double current,
    required double target,
    required double factor,
    double snapThreshold = 0.02,
  }) {
    if ((target - current).abs() < snapThreshold) {
      return target;
    }
    return current + (target - current) * factor;
  }


  /// Actualiza el estado visual a partir de los datos espectrales de audio recibidos.
  void updateFromAudio({
    required double phase,
    required double amplitude,
    required double pan,
    required double breath,
    required double modulation,
    required double neuro,
    required double frequency,
  }) {
    AppConfig.logger
        .t('NeomFrequencyPainterEngine.updateFromAudio: '
        'phase=$phase, amplitude=$amplitude, pan=$pan, '
        'breath=$breath, modulation=$modulation, neuro=$neuro');
    _state = NeomVisualState(
      frequency: _normalizeFrequency(frequency),
      phase: _smooth(current: _state.phase, target: phase, factor: 0.2),
      pan: _smooth(current: _state.pan, target: pan, factor: 0.25),
      modulation: _smooth(current: _state.modulation, target: modulation, factor: 0.2),
      amplitude: _smooth(
        current: _state.amplitude,
        target: amplitude,
        factor: smoothAmp,
      ),
      breath: _smooth(
        current: _state.breath,
        target: breath,
        factor: smoothBreath,
      ),
      neuro: _smooth(
        current: _state.neuro,
        target: neuro,
        factor: smoothNeuro,
      ),
    );

    notifyListeners();
  }

  /// -------- SALIDAS PARA EL PAINTER --------

  /// Obtiene la fase visual calculada a partir del estado de fase y modulación.
  double get visualPhase =>
      _state.phase + _state.modulation * pi * 0.5;

  /// Obtiene la intensidad de brillo (glow) combinando modulación y respuesta neuronal.
  double get glowIntensity =>
      _clamp01((_state.modulation + _state.neuro) * 0.5);

  /// Obtiene la altura de la onda basándose en amplitud, respiración y respuesta neuronal.
  double get waveHeight {
    final amp =
        (_state.amplitude * 0.75) +
            (_state.breath * 0.2) +
            (_state.neuro * 0.15);

    return amp.clamp(0.0, 1.0) * visualAmplitudeMax;
  }

  /// Obtiene el factor de estiramiento horizontal de la onda según la frecuencia.
  double get waveStretch {
    // Grave → ondas largas | Agudo → ondas cortas
    return lerpDouble(0.5, 5, _state.frequency)! +
        (_state.neuro * 0.3) +
        (_state.modulation * 0.2);
  }

  /// Obtiene el desplazamiento horizontal (drift) basándose en el paneo de audio.
  double get horizontalDrift =>
      _clamp01(_state.pan * 0.5);

  /// Obtiene la pulsación de respiración utilizando una función seno absoluta.
  double get breathPulse =>
      _clamp01(sin(_state.breath * pi).abs());

  double _clamp01(double v) {
    if (v.isNaN || v.isInfinite) return 0.0;
    return v.clamp(0.0, 1.0);
  }

  double _normalizeFrequency(double f) {
    const double minF = 40.0;
    const double maxF = 1500.0;

    final double norm =
        (log(f) - log(minF)) / (log(maxF) - log(minF));

    return norm.clamp(0.0, 1.0);
  }

  /// Factor de suavizado para la amplitud.
  double smoothAmp = 0.35;

  /// Factor de suavizado para la respiración (breath).
  double smoothBreath = 0.15;

  /// Factor de suavizado para la respuesta neuronal (neuro).
  double smoothNeuro = 0.12;

  /// Configura el perfil de suavizado de los filtros adaptativos.
  void setSmoothingProfile({
    required double amplitude,
    required double breath,
    required double neuro,
  }) {
    smoothAmp = amplitude;
    smoothBreath = breath;
    smoothNeuro = neuro;
  }

  double _binauralPhase = 0.0;
  double _binauralBeat = 0.0;

  /// Realiza un tick de animación para la simulación de tonos binaurales.
  void tickBinaural(double beatHz, double dt) {
    if (beatHz <= 0) return;

    _binauralBeat = beatHz;
    AppConfig.logger.d('NeomFrequencyPainterEngine.tickBinaural: beat=$_binauralBeat');

    _binauralPhase += dt * beatHz * 2 * pi * 0.25; // lento, perceptual
    _binauralPhase %= (2 * pi);

    notifyListeners();
  }

  /// Fase calculada de los tonos binaurales.
  double get binauralPhase => _binauralPhase;

  // =========================
  // 🔬 OSCILLOSCOPE BUFFER
  // =========================

  /// Tamaño constante del buffer de osciloscopio.
  static const int bufferSize = 512;
  final List<double> _samples =
  List.filled(bufferSize, 0.0, growable: false);
  int _writeIndex = 0;

  /// Obtiene la lista inmutable de muestras almacenadas en el buffer.
  List<double> get samples => _samples;

  /// Añade una nueva muestra analógica al buffer circular del osciloscopio.
  void pushSample(double value) {
    _samples[_writeIndex] = value.clamp(-1.0, 1.0);
    _writeIndex = (_writeIndex + 1) % bufferSize;
  }

  double _phaseL = 0.0;
  double _phaseR = 0.0;

  /// Actualiza las fases izquierda y derecha de las señales sinusoidales.
  void updatePhases({
    required double phaseL,
    required double phaseR,
  }) {
    _phaseL = phaseL;
    _phaseR = phaseR;
  }

  /// Obtiene la componente X para gráficos Lissajous.
  double get lissajousX => sin(_phaseL);

  /// Obtiene la componente Y para gráficos Lissajous.
  double get lissajousY => sin(_phaseR);

  /// Obtiene la coherencia hemisférica o desfase entre ambos canales.
  double get hemisphericCoherence {
    final diff = (_phaseL - _phaseR).abs();
    return cos(diff).abs().clamp(0.0, 1.0);
  }

}
