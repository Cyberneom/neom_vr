import 'dart:math';
import 'package:flutter/material.dart';

/// Representa una partícula/estrella en el espacio 3D esférico
class VRParticle {
  double theta;     // Ángulo horizontal (0 - 2π)
  double phi;       // Ángulo vertical (-π/2 - π/2)
  double radius;    // Distancia del centro
  double size;
  Color color;
  double energy;
  double pulsePhase;

  VRParticle({
    required this.theta,
    required this.phi,
    this.radius = 1.0,
    this.size = 2.0,
    this.color = Colors.white,
    this.energy = 1.0,
    this.pulsePhase = 0.0,
  });

  /// Convierte coordenadas esféricas a cartesianas
  Offset3D toCartesian() {
    final x = radius * cos(phi) * cos(theta);
    final y = radius * cos(phi) * sin(theta);
    final z = radius * sin(phi);
    return Offset3D(x, y, z);
  }
}

class Offset3D {
  final double x, y, z;
  Offset3D(this.x, this.y, this.z);

  Offset3D operator +(Offset3D other) => Offset3D(x + other.x, y + other.y, z + other.z);
  Offset3D operator -(Offset3D other) => Offset3D(x - other.x, y - other.y, z - other.z);
  Offset3D operator *(double scalar) => Offset3D(x * scalar, y * scalar, z * scalar);

  double get length => sqrt(x * x + y * y + z * z);

  Offset3D normalize() {
    final len = length;
    if (len == 0) return Offset3D(0, 0, 0);
    return Offset3D(x / len, y / len, z / len);
  }
}

/// Motor de visualización VR 360 reactivo al audio
class NeomVR360Engine extends ChangeNotifier {
  final Random _random = Random();

  List<VRParticle> particles = [];
  List<VRParticle> rings = [];       // Anillos de frecuencia
  List<VRParticle> constellations = []; // Puntos conectados

  // Cámara / Vista
  double cameraTheta = 0.0;  // Rotación horizontal
  double cameraPhi = 0.0;    // Rotación vertical
  double cameraFOV = 90.0;   // Campo de visión en grados

  // Audio reactivo
  double audioAmplitude = 0.0;
  double audioFrequency = 432.0;
  double audioBeat = 0.0;
  double audioPhase = 0.0;
  double audioCoherence = 0.5;

  // Wavelength (longitud de onda) - afecta escala del espacio
  double wavelength = 1.0; // 0.5 - 2.0 (corta a larga)

  // Separación interpupilar para estereoscópico (en unidades de espacio virtual)
  double eyeSeparation = 0.065; // ~6.5cm promedio humano escalado

  // Animación
  double _time = 0.0;
  double rotationSpeed = 0.002;

  // Configuración visual
  int particleCount = 200;
  int ringCount = 8;
  bool showRings = true;
  bool showConstellations = true;
  bool showNebula = true;
  bool autoRotate = true;

  // Colores base (cambian según estado)
  Color primaryColor = const Color(0xFF00CED1);
  Color secondaryColor = const Color(0xFF6A5ACD);
  Color accentColor = const Color(0xFFFF6B6B);

  /// Inicializa el universo VR
  void initialize() {
    particles.clear();
    rings.clear();
    constellations.clear();

    // Crear partículas/estrellas distribuidas en esfera
    for (int i = 0; i < particleCount; i++) {
      particles.add(VRParticle(
        theta: _random.nextDouble() * 2 * pi,
        phi: ((_random.nextDouble() * 2) - 1) * pi / 2, // -90° a +90°
        radius: 0.8 + _random.nextDouble() * 0.4,
        size: 1.0 + _random.nextDouble() * 3.0,
        color: _getRandomStarColor(),
        energy: 0.3 + _random.nextDouble() * 0.7,
        pulsePhase: _random.nextDouble() * 2 * pi,
      ));
    }

    // Crear anillos de frecuencia (como ondas expandiéndose)
    for (int i = 0; i < ringCount; i++) {
      final ringRadius = 0.3 + (i / ringCount) * 0.6;
      final pointsInRing = 60 + i * 10;

      for (int j = 0; j < pointsInRing; j++) {
        rings.add(VRParticle(
          theta: (j / pointsInRing) * 2 * pi,
          phi: 0.0, // En el ecuador
          radius: ringRadius,
          size: 1.5,
          color: primaryColor,
          energy: 1.0,
          pulsePhase: i * 0.5, // Fase diferente por anillo
        ));
      }
    }

    // Crear constelaciones (grupos de puntos conectados)
    _generateConstellations();
  }

  void _generateConstellations() {
    // Crear 5-8 constelaciones aleatorias
    final numConstellations = 5 + _random.nextInt(4);

    for (int c = 0; c < numConstellations; c++) {
      final centerTheta = _random.nextDouble() * 2 * pi;
      final centerPhi = ((_random.nextDouble() * 2) - 1) * pi / 3;
      final starCount = 3 + _random.nextInt(5);

      for (int s = 0; s < starCount; s++) {
        constellations.add(VRParticle(
          theta: centerTheta + (_random.nextDouble() - 0.5) * 0.3,
          phi: centerPhi + (_random.nextDouble() - 0.5) * 0.2,
          radius: 0.95,
          size: 2.0 + _random.nextDouble() * 2.0,
          color: Colors.white,
          energy: 0.8,
          pulsePhase: c.toDouble(), // Agrupar por constelación
        ));
      }
    }
  }

  Color _getRandomStarColor() {
    final colors = [
      Colors.white,
      const Color(0xFFFFE4B5), // Moccasin (amarillento)
      const Color(0xFFADD8E6), // Light blue
      const Color(0xFFFFB6C1), // Light pink
      primaryColor.withOpacity(0.8),
    ];
    return colors[_random.nextInt(colors.length)];
  }

  /// Actualiza el estado del audio
  void updateAudio({
    required double amplitude,
    required double frequency,
    required double beat,
    required double phase,
    required double coherence,
    double? waveLen,
  }) {
    audioAmplitude = amplitude.clamp(0.0, 1.0);
    audioFrequency = frequency;
    audioBeat = beat.clamp(0.0, 40.0);
    audioPhase = phase;
    audioCoherence = coherence.clamp(0.0, 1.0);

    // Wavelength afecta la escala visual del espacio
    if (waveLen != null) {
      wavelength = waveLen.clamp(0.5, 2.0);
    }
  }

  /// Calcula la frecuencia normalizada (0-1) para mapear a visual
  double get normalizedFrequency {
    // Rango típico: 40Hz - 1500Hz
    const minF = 40.0;
    const maxF = 1500.0;
    final logNorm = (log(audioFrequency.clamp(minF, maxF)) - log(minF)) /
        (log(maxF) - log(minF));
    return logNorm.clamp(0.0, 1.0);
  }

  /// Obtiene el color primario modulado por la frecuencia
  Color get frequencyModulatedColor {
    // Mapear frecuencia a hue: bajo (rojo/naranja) a alto (azul/violeta)
    final hue = 240 - (normalizedFrequency * 180); // 240° (azul) a 60° (amarillo)
    return HSLColor.fromAHSL(1.0, hue, 0.8, 0.5 + audioAmplitude * 0.2).toColor();
  }

  /// Tick principal de animación
  void update(double dt) {
    _time += dt;

    // Auto-rotación suave
    if (autoRotate) {
      cameraTheta += rotationSpeed * (1.0 + audioAmplitude * 0.5);
      if (cameraTheta > 2 * pi) cameraTheta -= 2 * pi;
    }

    // Actualizar partículas - ahora reactivas a la frecuencia
    for (var p in particles) {
      // Pulso de energía sincronizado con audio y frecuencia
      final freqFactor = 1.0 + normalizedFrequency * 0.5;
      p.energy = 0.3 + 0.7 * ((sin(_time * 2 * freqFactor + p.pulsePhase) + 1) / 2) * audioAmplitude;

      // Tamaño reactivo al beat y wavelength
      p.size = (1.0 + _random.nextDouble() * 2.0) * (1.0 + audioAmplitude * 0.5) * wavelength;

      // Color modulado por frecuencia (gradual)
      if (_time.toInt() % 60 == 0) { // Actualizar color ocasionalmente para performance
        final baseColor = _getRandomStarColor();
        p.color = Color.lerp(baseColor, frequencyModulatedColor, normalizedFrequency * 0.3)!;
      }
    }

    // Actualizar anillos - expandirse con el beat y frecuencia
    for (int i = 0; i < rings.length; i++) {
      final ring = rings[i];
      final baseRadius = 0.3 + ((i ~/ 70) / ringCount) * 0.6;
      // Frecuencia afecta velocidad de pulsación, wavelength afecta tamaño
      final freqSpeed = 0.5 + normalizedFrequency * 1.5;
      final pulse = sin(_time * audioBeat * freqSpeed + ring.pulsePhase) * audioAmplitude * 0.1;
      ring.radius = (baseRadius + pulse) * wavelength;

      // Color basado en coherencia y frecuencia
      ring.color = Color.lerp(
        Color.lerp(secondaryColor, frequencyModulatedColor, normalizedFrequency * 0.5)!,
        primaryColor,
        audioCoherence,
      )!.withOpacity(0.6 + audioAmplitude * 0.4);
    }

    // Actualizar constelaciones - brillo pulsante
    for (var c in constellations) {
      c.energy = 0.5 + 0.5 * sin(_time * 1.5 + c.pulsePhase) * audioCoherence;
    }

    notifyListeners();
  }

  /// Mueve la cámara con el giroscopio
  void updateCamera(double deltaTheta, double deltaPhi) {
    cameraTheta += deltaTheta;
    cameraPhi = (cameraPhi + deltaPhi).clamp(-pi / 2 + 0.1, pi / 2 - 0.1);

    // Normalizar theta
    if (cameraTheta > 2 * pi) cameraTheta -= 2 * pi;
    if (cameraTheta < 0) cameraTheta += 2 * pi;
  }

  /// Proyecta un punto 3D esférico a coordenadas 2D de pantalla
  Offset? projectToScreen(VRParticle particle, Size screenSize, {double eyeOffset = 0.0}) {
    final cart = particle.toCartesian();

    // Aplicar wavelength como escala del espacio
    final scaledCart = Offset3D(
      cart.x * wavelength,
      cart.y * wavelength,
      cart.z * wavelength,
    );

    // Aplicar offset del ojo (para estereoscópico)
    final eyeAdjusted = Offset3D(
      scaledCart.x,
      scaledCart.y - eyeOffset, // Desplazamiento lateral
      scaledCart.z,
    );

    // Rotar según la cámara
    final rotated = _rotatePoint(eyeAdjusted, -cameraTheta, -cameraPhi);

    // Si está detrás de la cámara, no dibujar
    if (rotated.x < 0.01) return null;

    // Proyección perspectiva
    final fovRad = cameraFOV * pi / 180;
    final scale = screenSize.width / (2 * tan(fovRad / 2));

    final screenX = screenSize.width / 2 + (rotated.y / rotated.x) * scale;
    final screenY = screenSize.height / 2 - (rotated.z / rotated.x) * scale;

    // Verificar si está dentro de la pantalla (con margen)
    if (screenX < -50 || screenX > screenSize.width + 50) return null;
    if (screenY < -50 || screenY > screenSize.height + 50) return null;

    return Offset(screenX, screenY);
  }

  /// Proyecta para ojo izquierdo (estereoscópico)
  Offset? projectToScreenLeft(VRParticle particle, Size screenSize) {
    return projectToScreen(particle, screenSize, eyeOffset: -eyeSeparation / 2);
  }

  /// Proyecta para ojo derecho (estereoscópico)
  Offset? projectToScreenRight(VRParticle particle, Size screenSize) {
    return projectToScreen(particle, screenSize, eyeOffset: eyeSeparation / 2);
  }

  /// Calcula la profundidad (para ordenar z-order)
  double getDepth(VRParticle particle, {double eyeOffset = 0.0}) {
    final cart = particle.toCartesian();
    final scaledCart = Offset3D(
      cart.x * wavelength,
      cart.y * wavelength - eyeOffset,
      cart.z * wavelength,
    );
    final rotated = _rotatePoint(scaledCart, -cameraTheta, -cameraPhi);
    return rotated.x;
  }

  Offset3D _rotatePoint(Offset3D p, double theta, double phi) {
    // Rotación horizontal (theta)
    double x1 = p.x * cos(theta) - p.y * sin(theta);
    double y1 = p.x * sin(theta) + p.y * cos(theta);
    double z1 = p.z;

    // Rotación vertical (phi)
    double x2 = x1 * cos(phi) - z1 * sin(phi);
    double y2 = y1;
    double z2 = x1 * sin(phi) + z1 * cos(phi);

    return Offset3D(x2, y2, z2);
  }

  /// Cambia el tema de colores según estado neuronal
  void setColorTheme(String mode) {
    switch (mode) {
      case 'calm':
        primaryColor = const Color(0xFF4B0082);
        secondaryColor = const Color(0xFF9370DB);
        accentColor = const Color(0xFFE6E6FA);
        break;
      case 'focus':
        primaryColor = const Color(0xFFFFA500);
        secondaryColor = const Color(0xFFFF6347);
        accentColor = const Color(0xFFFFD700);
        break;
      case 'sleep':
        primaryColor = const Color(0xFF191970);
        secondaryColor = const Color(0xFF000080);
        accentColor = const Color(0xFF4169E1);
        break;
      case 'creativity':
        primaryColor = const Color(0xFFFF1493);
        secondaryColor = const Color(0xFF00CED1);
        accentColor = const Color(0xFF7B68EE);
        break;
      default:
        primaryColor = const Color(0xFF00CED1);
        secondaryColor = const Color(0xFF6A5ACD);
        accentColor = const Color(0xFFFF6B6B);
    }

    // Actualizar colores de anillos
    for (var ring in rings) {
      ring.color = primaryColor;
    }
  }
}
