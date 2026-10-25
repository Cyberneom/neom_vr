import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Renders a live 24x18 luminance frame captured from the Joystick smartphone's
/// physical cameras (`Cám 2 Piso` or `Cám 3 Frontal/Manos`) along with the
/// real-time AI/CV detected landmarks (feet centroids or hand/visor centroids).
class VrJoystickMiniFramePainter extends CustomPainter {
  const VrJoystickMiniFramePainter({
    required this.lumaBytes,
    required this.isFloorCamera,
    required this.isLiveActive,
    this.leftFootUv,
    this.rightFootUv,
    this.handUv,
    this.showEstimates = false,
    this.frameWidth = 24,
    this.frameHeight = 18,
  });

  /// Only for explicitly labeled simulation/heuristic overlays.
  final bool showEstimates;
  final Uint8List? lumaBytes;
  final bool isFloorCamera;
  final bool isLiveActive;
  final vm.Vector2? leftFootUv;
  final vm.Vector2? rightFootUv;
  final vm.Vector2? handUv;
  final int frameWidth;
  final int frameHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFF050B14);
    canvas.drawRect(Offset.zero & size, bgPaint);

    final bytes = lumaBytes;
    if (bytes != null && bytes.length >= frameWidth * frameHeight) {
      final cellW = size.width / frameWidth;
      final cellH = size.height / frameHeight;
      final pixelPaint = Paint()..style = PaintingStyle.fill;

      for (var y = 0; y < frameHeight; y++) {
        for (var x = 0; x < frameWidth; x++) {
          final luma = bytes[y * frameWidth + x];
          // Tint floor camera with emerald-cyan night-vision hue and front camera with violet-cyan hue
          if (isFloorCamera) {
            final r = (luma * 0.25).round().clamp(0, 255);
            final g = (luma * 0.95).round().clamp(0, 255);
            final b = (luma * 0.72).round().clamp(0, 255);
            pixelPaint.color = Color.fromARGB(255, r, g, b);
          } else {
            final r = (luma * 0.75).round().clamp(0, 255);
            final g = (luma * 0.48).round().clamp(0, 255);
            final b = (luma * 0.98).round().clamp(0, 255);
            pixelPaint.color = Color.fromARGB(255, r, g, b);
          }
          canvas.drawRect(
            Rect.fromLTWH(x * cellW, y * cellH, cellW + 0.6, cellH + 0.6),
            pixelPaint,
          );
        }
      }
    }

    // Draw subtle optical grid
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeWidth = 0.6;
    canvas.drawLine(
      Offset(size.width * 0.5, 0),
      Offset(size.width * 0.5, size.height),
      gridPaint,
    );
    canvas.drawLine(
      Offset(0, size.height * 0.5),
      Offset(size.width, size.height * 0.5),
      gridPaint,
    );

    // Draw real-time AI/CV detection markers
    if (showEstimates && isFloorCamera) {
      final footPaint = Paint()
        ..color = const Color(0xFF34D399)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      final fillPaint = Paint()
        ..color = const Color(0x5510B981)
        ..style = PaintingStyle.fill;

      for (final uv in [leftFootUv, rightFootUv]) {
        if (uv == null) continue;
        final cx = (uv.x.clamp(0.08, 0.92)) * size.width;
        final cy = (uv.y.clamp(0.10, 0.90)) * size.height;
        final rect = Rect.fromCenter(
          center: Offset(cx, cy),
          width: size.width * 0.20,
          height: size.height * 0.26,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)),
          fillPaint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)),
          footPaint,
        );
      }
    } else if (showEstimates) {
      // Upper-body / Hand detection box (bottom-up hand + top visor)
      final visorRect = Rect.fromCenter(
        center: Offset(size.width * 0.50, size.height * 0.30),
        width: size.width * 0.34,
        height: size.height * 0.22,
      );
      final visorPaint = Paint()
        ..color = const Color(0xFF38BDF8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1;
      canvas.drawRect(visorRect, visorPaint);

      final huv = handUv ?? vm.Vector2(0.50, 0.68);
      final hx = (huv.x.clamp(0.10, 0.90)) * size.width;
      final hy = (huv.y.clamp(0.15, 0.90)) * size.height;
      final handRect = Rect.fromCenter(
        center: Offset(hx, hy),
        width: size.width * 0.36,
        height: size.height * 0.30,
      );
      final handFill = Paint()
        ..color = const Color(0x55A855F7)
        ..style = PaintingStyle.fill;
      final handStroke = Paint()
        ..color = const Color(0xFFD8B4FE)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      canvas.drawRRect(
        RRect.fromRectAndRadius(handRect, const Radius.circular(3)),
        handFill,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(handRect, const Radius.circular(3)),
        handStroke,
      );
    }

    // Active status border
    final borderPaint = Paint()
      ..color = isLiveActive
          ? (isFloorCamera ? const Color(0xFF10B981) : const Color(0xFFA855F7))
          : Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = isLiveActive ? 1.4 : 0.8;
    canvas.drawRect(Offset.zero & size, borderPaint);
  }

  @override
  bool shouldRepaint(covariant VrJoystickMiniFramePainter oldDelegate) {
    return oldDelegate.showEstimates != showEstimates ||
        !identical(oldDelegate.lumaBytes, lumaBytes) ||
        oldDelegate.isFloorCamera != isFloorCamera ||
        oldDelegate.isLiveActive != isLiveActive ||
        oldDelegate.leftFootUv != leftFootUv ||
        oldDelegate.rightFootUv != rightFootUv ||
        oldDelegate.handUv != handUv;
  }
}
