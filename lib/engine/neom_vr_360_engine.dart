import 'dart:math';
import 'package:flutter/material.dart';
import 'package:vrlizate/vrlizate.dart';

/// Audio-reactive VR 360 engine built on sint_vr.
///
/// Manages particles, rings, constellations, and audio state.
/// Delegates projection and stereoscopic rendering to sint_vr.
class NeomVR360Engine extends ChangeNotifier {
  final Random _random = Random();

  /// The underlying VR scene (from sint_vr).
  final VRScene scene = VRScene();

  /// The VR camera (from sint_vr).
  final VRCamera camera = VRCamera();

  /// Stereoscopic projection (from sint_vr).
  final StereoscopicProjection projection = StereoscopicProjection();

  // Audio-reactive particles (neom-specific)
  List<_AudioParticle> particles = [];
  List<_AudioParticle> rings = [];
  List<_AudioParticle> constellations = [];

  // Audio state
  double audioAmplitude = 0.0;
  double audioFrequency = 432.0;
  double audioBeat = 0.0;
  double audioPhase = 0.0;
  double audioCoherence = 0.5;
  double wavelength = 1.0;

  // Animation
  double _time = 0.0;

  // Visual config
  int particleCount = 200;
  int ringCount = 8;
  bool showRings = true;
  bool showConstellations = true;
  bool showNebula = true;

  // Colors
  Color primaryColor = const Color(0xFF00CED1);
  Color secondaryColor = const Color(0xFF6A5ACD);
  Color accentColor = const Color(0xFFFF6B6B);

  /// Eye separation (delegates to projection).
  double get eyeSeparation => projection.eyeSeparation;
  set eyeSeparation(double v) => projection.eyeSeparation = v;

  /// Initializes the VR universe.
  void initialize() {
    particles.clear();
    rings.clear();
    constellations.clear();
    scene.clear();

    for (int i = 0; i < particleCount; i++) {
      final theta = _random.nextDouble() * 2 * pi;
      final phi = (_random.nextDouble() * 2 - 1) * pi / 2;
      final radius = 0.8 + _random.nextDouble() * 0.4;

      final p = _AudioParticle(
        vrElement: VRParticle(
          position: Offset3D.fromSpherical(theta, phi, radius),
          radius: 1.0 + _random.nextDouble() * 3.0,
          color: _getRandomStarColor(),
          glowRadius: 4,
        ),
        energy: 0.3 + _random.nextDouble() * 0.7,
        pulsePhase: _random.nextDouble() * 2 * pi,
        theta: theta, phi: phi, baseRadius: radius,
      );
      particles.add(p);
      scene.addElement(p.vrElement);
    }

    for (int i = 0; i < ringCount; i++) {
      final ringRadius = 0.3 + (i / ringCount) * 0.6;
      final pointsInRing = 60 + i * 10;
      for (int j = 0; j < pointsInRing; j++) {
        final theta = (j / pointsInRing) * 2 * pi;
        final p = _AudioParticle(
          vrElement: VRParticle(
            position: Offset3D.fromSpherical(theta, 0, ringRadius),
            radius: 1.5, color: primaryColor, glowRadius: 2,
          ),
          energy: 1.0, pulsePhase: i * 0.5,
          theta: theta, phi: 0, baseRadius: ringRadius,
        );
        rings.add(p);
        scene.addElement(p.vrElement);
      }
    }

    _generateConstellations();
  }

  void _generateConstellations() {
    final numConstellations = 5 + _random.nextInt(4);
    for (int c = 0; c < numConstellations; c++) {
      final centerTheta = _random.nextDouble() * 2 * pi;
      final centerPhi = (_random.nextDouble() * 2 - 1) * pi / 3;
      final starCount = 3 + _random.nextInt(5);
      final groupParticles = <_AudioParticle>[];

      for (int s = 0; s < starCount; s++) {
        final theta = centerTheta + (_random.nextDouble() - 0.5) * 0.3;
        final phi = centerPhi + (_random.nextDouble() - 0.5) * 0.2;
        final p = _AudioParticle(
          vrElement: VRParticle(
            position: Offset3D.fromSpherical(theta, phi, 0.95),
            radius: 2.0 + _random.nextDouble() * 2.0,
            color: Colors.white, glowRadius: 5,
          ),
          energy: 0.8, pulsePhase: c.toDouble(),
          theta: theta, phi: phi, baseRadius: 0.95,
        );
        constellations.add(p);
        groupParticles.add(p);
        scene.addElement(p.vrElement);
      }

      for (int i = 0; i < groupParticles.length - 1; i++) {
        scene.addConnection(VRConnection(
          a: groupParticles[i].vrElement,
          b: groupParticles[i + 1].vrElement,
          color: accentColor.withValues(alpha: 0.4),
          strokeWidth: 1.2,
        ));
      }
    }
  }

  Color _getRandomStarColor() {
    final colors = [
      Colors.white, const Color(0xFFFFE4B5), const Color(0xFFADD8E6),
      const Color(0xFFFFB6C1), primaryColor.withValues(alpha: 0.8),
    ];
    return colors[_random.nextInt(colors.length)];
  }

  double get normalizedFrequency {
    const minF = 40.0, maxF = 1500.0;
    return ((log(audioFrequency.clamp(minF, maxF)) - log(minF)) / (log(maxF) - log(minF))).clamp(0.0, 1.0);
  }

  Color get frequencyModulatedColor {
    final hue = 240 - (normalizedFrequency * 180);
    return HSLColor.fromAHSL(1.0, hue, 0.8, 0.5 + audioAmplitude * 0.2).toColor();
  }

  void updateAudio({
    required double amplitude, required double frequency,
    required double beat, required double phase,
    required double coherence, double? waveLen,
  }) {
    audioAmplitude = amplitude.clamp(0.0, 1.0);
    audioFrequency = frequency;
    audioBeat = beat.clamp(0.0, 40.0);
    audioPhase = phase;
    audioCoherence = coherence.clamp(0.0, 1.0);
    if (waveLen != null) wavelength = waveLen.clamp(0.5, 2.0);
  }

  void update(double dt) {
    _time += dt;
    camera.update(dt);

    for (final p in particles) {
      final freqFactor = 1.0 + normalizedFrequency * 0.5;
      p.energy = 0.3 + 0.7 * ((sin(_time * 2 * freqFactor + p.pulsePhase) + 1) / 2) * audioAmplitude;
      final newRadius = p.baseRadius * wavelength;
      (p.vrElement as VRParticle)
        ..position = Offset3D.fromSpherical(p.theta, p.phi, newRadius)
        ..color = Color.lerp(_getRandomStarColor(), frequencyModulatedColor, normalizedFrequency * 0.3)!
            .withValues(alpha: 0.5 + 0.5 * p.energy);
    }

    for (final r in rings) {
      final freqSpeed = 0.5 + normalizedFrequency * 1.5;
      final pulse = sin(_time * audioBeat * freqSpeed + r.pulsePhase) * audioAmplitude * 0.1;
      final newRadius = (r.baseRadius + pulse) * wavelength;
      (r.vrElement as VRParticle)
        ..position = Offset3D.fromSpherical(r.theta, r.phi, newRadius)
        ..color = Color.lerp(secondaryColor, frequencyModulatedColor, normalizedFrequency * 0.5)!
            .withValues(alpha: 0.6 + audioAmplitude * 0.4);
    }

    for (final c in constellations) {
      c.energy = 0.5 + 0.5 * sin(_time * 1.5 + c.pulsePhase) * audioCoherence;
      (c.vrElement as VRParticle).color = Colors.white.withValues(alpha: 0.5 + 0.5 * c.energy);
    }

    notifyListeners();
  }

  /// Delegates camera rotation to sint_vr VRCamera.
  void updateCamera(double deltaTheta, double deltaPhi) {
    camera.rotate(deltaTheta, deltaPhi);
  }

  void setColorTheme(String mode) {
    switch (mode) {
      case 'calm':
        primaryColor = const Color(0xFF4B0082);
        secondaryColor = const Color(0xFF9370DB);
        accentColor = const Color(0xFFE6E6FA);
      case 'focus':
        primaryColor = const Color(0xFFFFA500);
        secondaryColor = const Color(0xFFFF6347);
        accentColor = const Color(0xFFFFD700);
      case 'sleep':
        primaryColor = const Color(0xFF191970);
        secondaryColor = const Color(0xFF000080);
        accentColor = const Color(0xFF4169E1);
      case 'creativity':
        primaryColor = const Color(0xFFFF1493);
        secondaryColor = const Color(0xFF00CED1);
        accentColor = const Color(0xFF7B68EE);
      default:
        primaryColor = const Color(0xFF00CED1);
        secondaryColor = const Color(0xFF6A5ACD);
        accentColor = const Color(0xFFFF6B6B);
    }
  }
}

class _AudioParticle {
  final VRElement vrElement;
  double energy;
  double pulsePhase;
  double theta;
  double phi;
  double baseRadius;

  _AudioParticle({
    required this.vrElement,
    required this.energy,
    required this.pulsePhase,
    required this.theta,
    required this.phi,
    required this.baseRadius,
  });
}
