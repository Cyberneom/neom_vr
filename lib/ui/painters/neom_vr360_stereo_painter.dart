import 'dart:math';
import 'package:flutter/material.dart';

import '../../engine/neom_vr_360_engine.dart';

/// Painter estereoscópico para VR headset (split-screen dual view)
/// Renderiza la misma escena dos veces con separación interpupilar
class NeomVR360StereoPainter extends CustomPainter {
  final NeomVR360Engine engine;
  final bool showRings;
  final bool showConstellations;
  final bool showNebula;

  NeomVR360StereoPainter({
    required this.engine,
    this.showRings = true,
    this.showConstellations = true,
    this.showNebula = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final halfWidth = size.width / 2;
    final eyeSize = Size(halfWidth, size.height);

    // Dibujar separador central (para alinear con el visor)
    _drawCenterDivider(canvas, size);

    // === OJO IZQUIERDO ===
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, halfWidth, size.height));
    _paintEye(canvas, eyeSize, Offset.zero, isLeftEye: true);
    canvas.restore();

    // === OJO DERECHO ===
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(halfWidth, 0, halfWidth, size.height));
    canvas.translate(halfWidth, 0);
    _paintEye(canvas, eyeSize, Offset(halfWidth, 0), isLeftEye: false);
    canvas.restore();

    // Dibujar frame de visor VR
    _drawVRFrame(canvas, size);
  }

  void _paintEye(Canvas canvas, Size size, Offset offset, {required bool isLeftEye}) {
    final eyeOffset = isLeftEye ? -engine.eyeSeparation / 2 : engine.eyeSeparation / 2;

    _drawBackground(canvas, size);

    if (showNebula) {
      _drawNebula(canvas, size);
    }

    // Recopilar todos los elementos con profundidad para z-sorting
    List<_DrawableElement> elements = [];

    // Agregar partículas
    for (var p in engine.particles) {
      final screenPos = engine.projectToScreen(p, size, eyeOffset: eyeOffset);
      if (screenPos != null) {
        elements.add(_DrawableElement(
          type: _ElementType.star,
          particle: p,
          screenPos: screenPos,
          depth: engine.getDepth(p, eyeOffset: eyeOffset),
        ));
      }
    }

    // Agregar anillos
    if (showRings) {
      for (var r in engine.rings) {
        final screenPos = engine.projectToScreen(r, size, eyeOffset: eyeOffset);
        if (screenPos != null) {
          elements.add(_DrawableElement(
            type: _ElementType.ring,
            particle: r,
            screenPos: screenPos,
            depth: engine.getDepth(r, eyeOffset: eyeOffset),
          ));
        }
      }
    }

    // Agregar constelaciones
    if (showConstellations) {
      for (var c in engine.constellations) {
        final screenPos = engine.projectToScreen(c, size, eyeOffset: eyeOffset);
        if (screenPos != null) {
          elements.add(_DrawableElement(
            type: _ElementType.constellation,
            particle: c,
            screenPos: screenPos,
            depth: engine.getDepth(c, eyeOffset: eyeOffset),
          ));
        }
      }
    }

    // Ordenar por profundidad (más lejano primero)
    elements.sort((a, b) => a.depth.compareTo(b.depth));

    // Dibujar elementos ordenados
    for (var elem in elements) {
      switch (elem.type) {
        case _ElementType.star:
          _drawStar(canvas, elem);
          break;
        case _ElementType.ring:
          _drawRingPoint(canvas, elem);
          break;
        case _ElementType.constellation:
          _drawConstellationStar(canvas, elem);
          break;
      }
    }

    // Dibujar líneas de constelación
    if (showConstellations) {
      _drawConstellationLines(canvas, size, eyeOffset);
    }

    // Dibujar centro de frecuencia (el "core" reactivo)
    _drawFrequencyCore(canvas, size);

    // Viñeta circular para efecto de lente VR
    _drawLensVignette(canvas, size);
  }

  void _drawCenterDivider(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 4;

    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      paint,
    );
  }

  void _drawVRFrame(Canvas canvas, Size size) {
    final halfWidth = size.width / 2;
    final centerY = size.height / 2;

    // Marcos circulares para simular lentes
    final framePaint = Paint()
      ..color = Colors.black.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    // Radio del lente (ajustado para pantalla)
    final lensRadius = min(halfWidth, size.height) * 0.48;

    // Lente izquierdo
    canvas.drawCircle(
      Offset(halfWidth / 2, centerY),
      lensRadius,
      framePaint,
    );

    // Lente derecho
    canvas.drawCircle(
      Offset(halfWidth + halfWidth / 2, centerY),
      lensRadius,
      framePaint,
    );
  }

  void _drawBackground(Canvas canvas, Size size) {
    // Gradiente radial oscuro - más profundo para VR
    final paint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.5,
        colors: [
          Color.lerp(const Color(0xFF0A0A1A), engine.frequencyModulatedColor, 0.1)!,
          const Color(0xFF050510),
          Colors.black,
        ],
      ).createShader(Offset.zero & size);

    canvas.drawRect(Offset.zero & size, paint);
  }

  void _drawNebula(Canvas canvas, Size size) {
    // Nebulosa 1 - modulada por frecuencia
    final nebula1 = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.2),
        radius: 0.8 * engine.wavelength,
        colors: [
          Color.lerp(engine.primaryColor, engine.frequencyModulatedColor, 0.5)!
              .withOpacity(0.2 * engine.audioAmplitude.clamp(0.3, 1.0)),
          engine.primaryColor.withOpacity(0.05),
          Colors.transparent,
        ],
      ).createShader(Offset.zero & size)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40);

    canvas.drawCircle(
      Offset(size.width * 0.35, size.height * 0.4),
      size.width * 0.35 * engine.wavelength,
      nebula1,
    );

    // Nebulosa 2
    final nebula2 = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.4, 0.3),
        radius: 0.6 * engine.wavelength,
        colors: [
          Color.lerp(engine.secondaryColor, engine.frequencyModulatedColor, 0.3)!
              .withOpacity(0.15 * engine.audioAmplitude.clamp(0.3, 1.0)),
          engine.secondaryColor.withOpacity(0.04),
          Colors.transparent,
        ],
      ).createShader(Offset.zero & size)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 50);

    canvas.drawCircle(
      Offset(size.width * 0.65, size.height * 0.6),
      size.width * 0.3 * engine.wavelength,
      nebula2,
    );
  }

  void _drawStar(Canvas canvas, _DrawableElement elem) {
    final p = elem.particle;
    final pos = elem.screenPos;

    // Escalar tamaño por profundidad
    final depthScale = (elem.depth + 1) / 2;
    final scaledSize = p.size * depthScale.clamp(0.3, 1.0);

    // Glow modulado por frecuencia
    final glowColor = Color.lerp(p.color, engine.frequencyModulatedColor, engine.normalizedFrequency * 0.3)!;

    final glowPaint = Paint()
      ..color = glowColor.withOpacity(0.35 * p.energy)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, scaledSize * 2.5);

    canvas.drawCircle(pos, scaledSize * 2.5, glowPaint);

    // Core
    final corePaint = Paint()
      ..color = p.color.withOpacity(0.5 + 0.5 * p.energy);

    canvas.drawCircle(pos, scaledSize, corePaint);

    // Centro brillante
    final centerPaint = Paint()
      ..color = Colors.white.withOpacity(0.7 * p.energy);

    canvas.drawCircle(pos, scaledSize * 0.3, centerPaint);
  }

  void _drawRingPoint(Canvas canvas, _DrawableElement elem) {
    final p = elem.particle;
    final pos = elem.screenPos;

    final depthScale = (elem.depth + 1) / 2;
    final scaledSize = p.size * depthScale.clamp(0.2, 1.0);

    // Punto del anillo con glow - color modulado por frecuencia
    final ringColor = Color.lerp(p.color, engine.frequencyModulatedColor, 0.4)!;

    final paint = Paint()
      ..color = ringColor.withOpacity(0.7 * engine.audioAmplitude.clamp(0.3, 1.0))
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, scaledSize * 1.5);

    canvas.drawCircle(pos, scaledSize * 1.2, paint);
  }

  void _drawConstellationStar(Canvas canvas, _DrawableElement elem) {
    final p = elem.particle;
    final pos = elem.screenPos;

    final depthScale = (elem.depth + 1) / 2;
    final scaledSize = p.size * depthScale.clamp(0.4, 1.0);

    // Glow especial para constelaciones
    final glowPaint = Paint()
      ..color = engine.accentColor.withOpacity(0.5 * p.energy)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, scaledSize * 3);

    canvas.drawCircle(pos, scaledSize * 2.5, glowPaint);

    // Core brillante
    final corePaint = Paint()
      ..color = Colors.white.withOpacity(0.85 * p.energy);

    canvas.drawCircle(pos, scaledSize, corePaint);
  }

  void _drawConstellationLines(Canvas canvas, Size size, double eyeOffset) {
    // Agrupar constelaciones por pulsePhase (ID de grupo)
    Map<double, List<Offset>> groups = {};

    for (var c in engine.constellations) {
      final pos = engine.projectToScreen(c, size, eyeOffset: eyeOffset);
      if (pos != null) {
        groups.putIfAbsent(c.pulsePhase, () => []);
        groups[c.pulsePhase]!.add(pos);
      }
    }

    // Dibujar líneas entre puntos de cada constelación
    final linePaint = Paint()
      ..color = engine.accentColor.withOpacity(0.4 * engine.audioCoherence)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    for (var points in groups.values) {
      if (points.length < 2) continue;

      for (int i = 0; i < points.length - 1; i++) {
        canvas.drawLine(points[i], points[i + 1], linePaint);
      }
    }
  }

  void _drawFrequencyCore(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Core pulsante central - tamaño reactivo a frecuencia y amplitude
    final baseRadius = 15.0 + engine.normalizedFrequency * 20;
    final coreRadius = baseRadius + engine.audioAmplitude * 25;

    // Glow exterior - color por frecuencia
    final outerGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          engine.frequencyModulatedColor.withOpacity(0.5 * engine.audioAmplitude.clamp(0.2, 1.0)),
          engine.primaryColor.withOpacity(0.15),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: coreRadius * 3))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 25);

    canvas.drawCircle(center, coreRadius * 2.5, outerGlow);

    // Core interno
    final innerCore = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withOpacity(0.9),
          engine.frequencyModulatedColor.withOpacity(0.7),
          engine.frequencyModulatedColor.withOpacity(0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: coreRadius));

    canvas.drawCircle(center, coreRadius, innerCore);

    // Anillos de onda expansiva - velocidad por frecuencia
    final waveSpeed = 1.0 + engine.normalizedFrequency * 2.0;
    for (int i = 0; i < 4; i++) {
      final wavePhase = (engine.audioPhase * waveSpeed + i * 0.4) % (2 * pi);
      final waveRadius = coreRadius + 30 + (wavePhase / (2 * pi)) * 120 * engine.wavelength;
      final waveOpacity = (1 - wavePhase / (2 * pi)) * 0.4 * engine.audioAmplitude;

      if (waveOpacity > 0.02) {
        final wavePaint = Paint()
          ..color = engine.frequencyModulatedColor.withOpacity(waveOpacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 + engine.audioAmplitude;

        canvas.drawCircle(center, waveRadius, wavePaint);
      }
    }
  }

  void _drawLensVignette(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) * 0.5;

    // Viñeta circular más pronunciada para efecto de lente
    final vignettePaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.85,
        colors: [
          Colors.transparent,
          Colors.transparent,
          Colors.black.withOpacity(0.5),
          Colors.black.withOpacity(0.95),
        ],
        stops: const [0.0, 0.5, 0.75, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawRect(Offset.zero & size, vignettePaint);
  }

  @override
  bool shouldRepaint(covariant NeomVR360StereoPainter oldDelegate) => true;
}

enum _ElementType { star, ring, constellation }

class _DrawableElement {
  final _ElementType type;
  final VRParticle particle;
  final Offset screenPos;
  final double depth;

  _DrawableElement({
    required this.type,
    required this.particle,
    required this.screenPos,
    required this.depth,
  });
}
