import 'dart:math';
import 'package:flutter/material.dart';

import '../../engine/neom_vr_360_engine.dart';

class NeomVR360Painter extends CustomPainter {
  final NeomVR360Engine engine;
  final bool showRings;
  final bool showConstellations;
  final bool showNebula;

  NeomVR360Painter({
    required this.engine,
    this.showRings = true,
    this.showConstellations = true,
    this.showNebula = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);

    if (showNebula) {
      _drawNebula(canvas, size);
    }

    // Recopilar todos los elementos con profundidad para z-sorting
    List<_DrawableElement> elements = [];

    // Agregar partículas
    for (var p in engine.particles) {
      final screenPos = engine.projectToScreen(p, size);
      if (screenPos != null) {
        elements.add(_DrawableElement(
          type: _ElementType.star,
          particle: p,
          screenPos: screenPos,
          depth: engine.getDepth(p),
        ));
      }
    }

    // Agregar anillos
    if (showRings) {
      for (var r in engine.rings) {
        final screenPos = engine.projectToScreen(r, size);
        if (screenPos != null) {
          elements.add(_DrawableElement(
            type: _ElementType.ring,
            particle: r,
            screenPos: screenPos,
            depth: engine.getDepth(r),
          ));
        }
      }
    }

    // Agregar constelaciones
    if (showConstellations) {
      for (var c in engine.constellations) {
        final screenPos = engine.projectToScreen(c, size);
        if (screenPos != null) {
          elements.add(_DrawableElement(
            type: _ElementType.constellation,
            particle: c,
            screenPos: screenPos,
            depth: engine.getDepth(c),
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

    // Dibujar líneas de constelación (después de estrellas para que estén encima)
    if (showConstellations) {
      _drawConstellationLines(canvas, size);
    }

    // Dibujar centro de frecuencia
    _drawFrequencyCore(canvas, size);

    _drawVignette(canvas, size);
  }

  void _drawBackground(Canvas canvas, Size size) {
    // Gradiente radial oscuro
    final paint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.5,
        colors: [
          const Color(0xFF0A0A1A),
          const Color(0xFF050510),
          Colors.black,
        ],
      ).createShader(Offset.zero & size);

    canvas.drawRect(Offset.zero & size, paint);
  }

  void _drawNebula(Canvas canvas, Size size) {
    // final center = Offset(size.width / 2, size.height / 2);

    // Nebulosa 1
    final nebula1 = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.2),
        radius: 0.8,
        colors: [
          engine.primaryColor.withOpacity(0.15 * engine.audioAmplitude.clamp(0.3, 1.0)),
          engine.primaryColor.withOpacity(0.05),
          Colors.transparent,
        ],
      ).createShader(Offset.zero & size)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 50);

    canvas.drawCircle(
      Offset(size.width * 0.35, size.height * 0.4),
      size.width * 0.4,
      nebula1,
    );

    // Nebulosa 2
    final nebula2 = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.4, 0.3),
        radius: 0.7,
        colors: [
          engine.secondaryColor.withOpacity(0.12 * engine.audioAmplitude.clamp(0.3, 1.0)),
          engine.secondaryColor.withOpacity(0.04),
          Colors.transparent,
        ],
      ).createShader(Offset.zero & size)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60);

    canvas.drawCircle(
      Offset(size.width * 0.65, size.height * 0.6),
      size.width * 0.35,
      nebula2,
    );
  }

  void _drawStar(Canvas canvas, _DrawableElement elem) {
    final p = elem.particle;
    final pos = elem.screenPos;

    // Escalar tamaño por profundidad
    final depthScale = (elem.depth + 1) / 2;
    final scaledSize = p.size * depthScale.clamp(0.3, 1.0);

    // Glow
    final glowPaint = Paint()
      ..color = p.color.withOpacity(0.3 * p.energy)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, scaledSize * 2);

    canvas.drawCircle(pos, scaledSize * 2, glowPaint);

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

    // Punto del anillo con glow
    final paint = Paint()
      ..color = p.color.withOpacity(0.6 * engine.audioAmplitude.clamp(0.3, 1.0))
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, scaledSize);

    canvas.drawCircle(pos, scaledSize, paint);
  }

  void _drawConstellationStar(Canvas canvas, _DrawableElement elem) {
    final p = elem.particle;
    final pos = elem.screenPos;

    final depthScale = (elem.depth + 1) / 2;
    final scaledSize = p.size * depthScale.clamp(0.4, 1.0);

    // Glow especial para constelaciones
    final glowPaint = Paint()
      ..color = engine.accentColor.withOpacity(0.4 * p.energy)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, scaledSize * 3);

    canvas.drawCircle(pos, scaledSize * 2.5, glowPaint);

    // Core brillante
    final corePaint = Paint()
      ..color = Colors.white.withOpacity(0.8 * p.energy);

    canvas.drawCircle(pos, scaledSize, corePaint);
  }

  void _drawConstellationLines(Canvas canvas, Size size) {
    // Agrupar constelaciones por pulsePhase (que usamos como ID de grupo)
    Map<double, List<Offset>> groups = {};

    for (var c in engine.constellations) {
      final pos = engine.projectToScreen(c, size);
      if (pos != null) {
        groups.putIfAbsent(c.pulsePhase, () => []);
        groups[c.pulsePhase]!.add(pos);
      }
    }

    // Dibujar líneas entre puntos de cada constelación
    final linePaint = Paint()
      ..color = engine.accentColor.withOpacity(0.3 * engine.audioCoherence)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    for (var points in groups.values) {
      if (points.length < 2) continue;

      // Conectar puntos secuencialmente
      for (int i = 0; i < points.length - 1; i++) {
        canvas.drawLine(points[i], points[i + 1], linePaint);
      }
    }
  }

  void _drawFrequencyCore(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Solo mostrar si hay audio
    if (engine.audioAmplitude < 0.1) return;

    // Core pulsante central
    final coreRadius = 20.0 + engine.audioAmplitude * 30;

    // Glow exterior
    final outerGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          engine.primaryColor.withOpacity(0.4 * engine.audioAmplitude),
          engine.primaryColor.withOpacity(0.1),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: coreRadius * 3))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);

    canvas.drawCircle(center, coreRadius * 2, outerGlow);

    // Core interno
    final innerCore = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withOpacity(0.8),
          engine.primaryColor.withOpacity(0.6),
          engine.primaryColor.withOpacity(0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: coreRadius));

    canvas.drawCircle(center, coreRadius, innerCore);

    // Anillos de onda expansiva (sincronizados con beat)
    for (int i = 0; i < 3; i++) {
      final wavePhase = (engine.audioPhase + i * 0.5) % (2 * pi);
      final waveRadius = coreRadius + 50 + (wavePhase / (2 * pi)) * 100;
      final waveOpacity = (1 - wavePhase / (2 * pi)) * 0.3 * engine.audioAmplitude;

      if (waveOpacity > 0.01) {
        final wavePaint = Paint()
          ..color = engine.primaryColor.withOpacity(waveOpacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;

        canvas.drawCircle(center, waveRadius, wavePaint);
      }
    }
  }

  void _drawVignette(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = max(size.width, size.height);

    final vignettePaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.8,
        colors: [
          Colors.transparent,
          Colors.black.withOpacity(0.4),
          Colors.black.withOpacity(0.8),
        ],
        stops: const [0.4, 0.75, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawRect(Offset.zero & size, vignettePaint);
  }

  @override
  bool shouldRepaint(covariant NeomVR360Painter oldDelegate) => true;
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
