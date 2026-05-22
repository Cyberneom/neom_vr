import 'package:flutter/material.dart';
import 'package:vrlizate/vrlizate.dart';

import '../../engine/neom_vr_360_engine.dart';

/// Monoscopic (single-eye) painter for spatial 360 view.
/// Delegates rendering to sint_vr's VRMonoPainter + VRScene.
class NeomVR360Painter extends CustomPainter {
  final NeomVR360Engine engine;
  final bool showRings;
  final bool showConstellations;
  final bool showNebula;

  late final VRMonoPainter _monoPainter;

  NeomVR360Painter({
    required this.engine,
    this.showRings = true,
    this.showConstellations = true,
    this.showNebula = true,
  }) {
    for (final r in engine.rings) {
      r.vrElement.visible = showRings;
    }
    for (final c in engine.constellations) {
      c.vrElement.visible = showConstellations;
    }

    _monoPainter = VRMonoPainter(
      renderer: engine.scene,
      camera: engine.camera,
      projection: engine.projection,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    _monoPainter.paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant NeomVR360Painter oldDelegate) => true;
}
