import 'dart:math';
import 'package:flutter/material.dart';
import 'package:vrlizate/vrlizate.dart';

/// Motor VR 360 reactivo al audio construido sobre sint_vr/vrlizate.
///
/// Administra partículas, anillos, constelaciones y el estado del audio.
/// Delega la proyección y el renderizado estereoscópico a la librería vrlizate.
class NeomVR360Engine extends ChangeNotifier {
  final Random _random = Random();

  /// La escena VR subyacente que almacena los elementos visuales.
  final VRScene scene = VRScene();

  /// La cámara VR para la simulación del punto de vista 3D.
  final VRCamera camera = VRCamera();

  /// Proyección estereoscópica para visualización side-by-side en cascos VR.
  final StereoscopicProjection projection = StereoscopicProjection();

  /// Lista de partículas reactivas al audio (estrellas flotantes).
  List<AudioParticle> particles = [];

  /// Lista de partículas dispuestas en anillos concéntricos reactivos.
  List<AudioParticle> rings = [];

  /// Lista de partículas que forman constelaciones con líneas de conexión.
  List<AudioParticle> constellations = [];

  /// Amplitud de la señal de audio actual (rango de 0.0 a 1.0).
  double audioAmplitude = 0.0;

  /// Frecuencia principal de la señal de audio en Hertz (ej. 432 Hz).
  double audioFrequency = 432.0;

  /// Pulso o tempo del audio utilizado para efectos de latido.
  double audioBeat = 0.0;

  /// Fase actual de la onda de audio para animaciones continuas.
  double audioPhase = 0.0;

  /// Nivel de coherencia o sincronía hemisférica del audio (rango 0.0 a 1.0).
  double audioCoherence = 0.5;

  /// Longitud de onda multiplicadora para alterar el radio de las órbitas visuales.
  double wavelength = 1.0;

  // Animation
  double _time = 0.0;

  /// Cantidad máxima de partículas estelares flotantes a generar.
  int particleCount = 200;

  /// Cantidad de anillos concéntricos a generar en la inicialización.
  int ringCount = 8;

  /// Define si se deben pintar los anillos reactivos concéntricos.
  bool showRings = true;

  /// Define si se deben pintar las constelaciones estelares y sus uniones.
  bool showConstellations = true;

  /// Define si se debe pintar el efecto difuminado de la nebulosa cósmica.
  bool showNebula = true;

  /// Color principal o primario de la paleta temática actual.
  Color primaryColor = const Color(0xFF00CED1);

  /// Color secundario de la paleta temática actual.
  Color secondaryColor = const Color(0xFF6A5ACD);

  /// Color de acento de la paleta temática actual.
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

      final p = AudioParticle(
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
        final p = AudioParticle(
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
      final groupParticles = <AudioParticle>[];

      for (int s = 0; s < starCount; s++) {
        final theta = centerTheta + (_random.nextDouble() - 0.5) * 0.3;
        final phi = centerPhi + (_random.nextDouble() - 0.5) * 0.2;
        final p = AudioParticle(
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

  /// Actualiza los parámetros de estado de audio para modular los gráficos reactivos.
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

  /// Delega la actualización de todos los elementos visuales basándose en el paso del tiempo.
  void update(double dt) {
    _time += dt;
    camera.update(dt);

    for (final p in particles) {
      final freqFactor = 1.0 + normalizedFrequency * 0.5;
      p.energy = 0.3 + 0.7 * ((sin(_time * 2 * freqFactor + p.pulsePhase) + 1) / 2) * audioAmplitude;
      final newRadius = p.baseRadius * wavelength;
      final oldElement = p.vrElement as VRParticle;
      final newColor = Color.lerp(_getRandomStarColor(), frequencyModulatedColor, normalizedFrequency * 0.3)!
          .withValues(alpha: 0.5 + 0.5 * p.energy);
      final newElement = VRParticle(
        position: Offset3D.fromSpherical(p.theta, p.phi, newRadius),
        radius: oldElement.radius,
        color: newColor,
        glowRadius: oldElement.glowRadius,
        visible: oldElement.visible,
      );
      final idx = scene.elements.indexOf(oldElement);
      if (idx != -1) {
        scene.elements[idx] = newElement;
      }
      p.vrElement = newElement;
    }

    for (final r in rings) {
      final freqSpeed = 0.5 + normalizedFrequency * 1.5;
      final pulse = sin(_time * audioBeat * freqSpeed + r.pulsePhase) * audioAmplitude * 0.1;
      final newRadius = (r.baseRadius + pulse) * wavelength;
      final oldElement = r.vrElement as VRParticle;
      final newColor = Color.lerp(secondaryColor, frequencyModulatedColor, normalizedFrequency * 0.5)!
          .withValues(alpha: 0.6 + audioAmplitude * 0.4);
      final newElement = VRParticle(
        position: Offset3D.fromSpherical(r.theta, r.phi, newRadius),
        radius: oldElement.radius,
        color: newColor,
        glowRadius: oldElement.glowRadius,
        visible: oldElement.visible,
      );
      final idx = scene.elements.indexOf(oldElement);
      if (idx != -1) {
        scene.elements[idx] = newElement;
      }
      r.vrElement = newElement;
    }

    for (final c in constellations) {
      c.energy = 0.5 + 0.5 * sin(_time * 1.5 + c.pulsePhase) * audioCoherence;
      final oldElement = c.vrElement as VRParticle;
      final newColor = Colors.white.withValues(alpha: 0.5 + 0.5 * c.energy);
      final newElement = VRParticle(
        position: oldElement.position,
        radius: oldElement.radius,
        color: newColor,
        glowRadius: oldElement.glowRadius,
        visible: oldElement.visible,
      );
      final idx = scene.elements.indexOf(oldElement);
      if (idx != -1) {
        scene.elements[idx] = newElement;
      }
      c.vrElement = newElement;
    }

    notifyListeners();
  }

  /// Delega la rotación de la cámara basándose en deltas de entrada del giroscopio o táctiles.
  void updateCamera(double deltaTheta, double deltaPhi) {
    camera.rotate(deltaTheta, deltaPhi);
  }

  /// Cambia la paleta cromática visual activa del universo VR basándose en un tema.
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

/// Estructura de soporte para partículas animadas y reactivas al audio.
class AudioParticle {
  /// Referencia al elemento visual renderizado en el espacio 3D de vrlizate.
  VRElement vrElement;

  /// Nivel de energía de vibración/pulsación de la partícula.
  double energy;

  /// Fase individual para desfasar la pulsación respecto a otras partículas.
  double pulsePhase;

  /// Ángulo esférico horizontal (Theta) en radianes.
  double theta;

  /// Ángulo esférico vertical (Phi) en radianes.
  double phi;

  /// Radio orbital base desde el centro de la escena 3D.
  double baseRadius;

  /// Constructor base para crear una partícula de audio interactiva.
  AudioParticle({
    required this.vrElement,
    required this.energy,
    required this.pulsePhase,
    required this.theta,
    required this.phi,
    required this.baseRadius,
  });
}
