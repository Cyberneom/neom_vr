import 'dart:math';

import 'package:flutter/material.dart';
import 'package:vrlizate/vrlizate.dart';

export 'package:vrlizate/vrlizate.dart'
    show AudioParticle, VrAudioReactive360Engine;

/// Open Neom wrapper around [VrAudioReactive360Engine] in `vrlizate` with
/// finite/range guards on stereoscopic, audio, time-step, and camera inputs.
class NeomVR360Engine extends VrAudioReactive360Engine {
  @override
  set eyeSeparation(double v) {
    if (!v.isFinite) return;
    super.eyeSeparation = v.clamp(0.0, 0.25);
  }

  @override
  void initialize() {
    particleCount = particleCount.isFinite ? particleCount.clamp(0, 4000) : 200;
    ringCount = ringCount.isFinite ? ringCount.clamp(0, 64) : 8;
    super.initialize();
  }

  @override
  double get normalizedFrequency {
    const minF = 40.0, maxF = 1500.0;
    final safeFreq = audioFrequency.isFinite
        ? audioFrequency.clamp(minF, maxF)
        : 432.0;
    return ((log(safeFreq) - log(minF)) / (log(maxF) - log(minF))).clamp(
      0.0,
      1.0,
    );
  }

  @override
  Color get frequencyModulatedColor {
    final hue = (240 - (normalizedFrequency * 180)).clamp(0.0, 360.0);
    final safeAmp = audioAmplitude.isFinite
        ? audioAmplitude.clamp(0.0, 1.0)
        : 0.0;
    final lightness = (0.5 + safeAmp * 0.2).clamp(0.0, 1.0);
    return HSLColor.fromAHSL(1.0, hue, 0.8, lightness).toColor();
  }

  @override
  void updateAudio({
    required double amplitude,
    required double frequency,
    required double beat,
    required double phase,
    required double coherence,
    double? waveLen,
  }) {
    if (amplitude.isFinite) audioAmplitude = amplitude.clamp(0.0, 1.0);
    if (frequency.isFinite) audioFrequency = frequency.clamp(20.0, 20000.0);
    if (beat.isFinite) audioBeat = beat.clamp(0.0, 40.0);
    if (phase.isFinite) audioPhase = phase.remainder(2 * pi);
    if (coherence.isFinite) audioCoherence = coherence.clamp(0.0, 1.0);
    if (waveLen != null && waveLen.isFinite) {
      wavelength = waveLen.clamp(0.5, 2.0);
    }
  }

  /// Alias for [updateAudio] preserving finite/clamped audio modulation.
  void setAudioState({
    required double amplitude,
    required double frequency,
    required double beat,
    required double phase,
    required double coherence,
    double? waveLen,
  }) => updateAudio(
    amplitude: amplitude,
    frequency: frequency,
    beat: beat,
    phase: phase,
    coherence: coherence,
    waveLen: waveLen,
  );

  @override
  void update(double dt) {
    if (!dt.isFinite || dt < 0) return;
    final clampedDt = dt.clamp(0.0, 1.0);
    audioAmplitude = audioAmplitude.isFinite
        ? audioAmplitude.clamp(0.0, 1.0)
        : 0.0;
    audioFrequency = audioFrequency.isFinite
        ? audioFrequency.clamp(20.0, 20000.0)
        : 432.0;
    audioBeat = audioBeat.isFinite ? audioBeat.clamp(0.0, 40.0) : 0.0;
    audioPhase = audioPhase.isFinite ? audioPhase.remainder(2 * pi) : 0.0;
    audioCoherence = audioCoherence.isFinite
        ? audioCoherence.clamp(0.0, 1.0)
        : 0.5;
    wavelength = wavelength.isFinite ? wavelength.clamp(0.5, 2.0) : 1.0;
    super.update(clampedDt);
  }

  @override
  void updateCamera(double deltaTheta, double deltaPhi) {
    if (!deltaTheta.isFinite || !deltaPhi.isFinite) return;
    super.updateCamera(deltaTheta, deltaPhi);
  }
}
