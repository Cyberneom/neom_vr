import 'package:flutter/material.dart';
import 'package:vrlizate/vrlizate.dart';

import '../../engine/neom_vr_360_engine.dart';

/// Stereoscopic painter for neom_vr.
/// Delegates all rendering to sint_vr's VRStereoPainter + VRScene.
class NeomVR360StereoPainter extends CustomPainter {
  final NeomVR360Engine engine;
  final bool showRings;
  final bool showConstellations;
  final bool showNebula;

  late final VRStereoPainter _stereoPainter;

  NeomVR360StereoPainter({
    required this.engine,
    this.showRings = true,
    this.showConstellations = true,
    this.showNebula = true,
  }) {
    // Toggle visibility based on flags
    for (final r in engine.rings) {
      r.vrElement.visible = showRings;
    }
    for (final c in engine.constellations) {
      c.vrElement.visible = showConstellations;
    }

    _stereoPainter = VRStereoPainter(
      renderer: engine.scene,
      camera: engine.camera,
      projection: engine.projection,
      showLensVignette: true,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    _stereoPainter.paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant NeomVR360StereoPainter oldDelegate) => true;
}
