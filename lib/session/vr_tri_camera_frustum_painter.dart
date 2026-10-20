import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vrlizate_avatar/vrlizate_avatar.dart';

import '../utils/constants/vr_translation_constants.dart';

/// Paints a real-time schematic of the 3 synchronized cameras
/// (`visor_front`, `joystick_rear` floor, `joystick_front` torso/visor),
/// the 20 kHz ultrasonic ToF link ($d_{VJ}$), the 3.63 m floor coverage,
/// and the user's calibrated kinematic skeleton ($H_{\text{user}}$).
class VrTriCameraFrustumPainter extends CustomPainter {
  const VrTriCameraFrustumPainter({
    required this.bodyState,
    required this.passthroughMix,
    this.compact = false,
  });

  final VrFullBodyKinematicState bodyState;
  final double passthroughMix;
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..color = const Color(0xFF070D19)
      ..style = PaintingStyle.fill;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(compact ? 10 : 14),
    );
    canvas.drawRRect(rrect, bgPaint);

    // Subtle spatial grid
    final gridPaint = Paint()
      ..color = const Color(0x1800E5FF)
      ..strokeWidth = 1.0;
    final stepX = size.width / 8;
    final stepY = size.height / 5;
    for (var i = 1; i < 8; i++) {
      canvas.drawLine(
        Offset(stepX * i, 0),
        Offset(stepX * i, size.height),
        gridPaint,
      );
    }
    for (var j = 1; j < 5; j++) {
      canvas.drawLine(
        Offset(0, stepY * j),
        Offset(size.width, stepY * j),
        gridPaint,
      );
    }

    final floorY = size.height * 0.84;
    final userX = size.width * 0.30;
    final headY = size.height * 0.20;
    final shoulderY = size.height * 0.31;
    final chestJoystickY = size.height * 0.46;
    final hipY = size.height * 0.56;
    final joystickX = userX + size.width * 0.11;

    // Floor plane line (3.63m Ultrawide coverage)
    final floorPaint = Paint()
      ..color = const Color(0xFF10B981)
      ..strokeWidth = compact ? 1.8 : 2.4;
    canvas.drawLine(
      Offset(size.width * 0.08, floorY),
      Offset(size.width * 0.94, floorY),
      floorPaint,
    );

    // 1. Camera 1 Frustum: Visor Front Camera (Cyan) -> World & Horizon SLAM
    final cam1Path = Path()
      ..moveTo(userX + 4, headY)
      ..lineTo(size.width * 0.94, size.height * 0.06)
      ..lineTo(size.width * 0.94, size.height * 0.52)
      ..close();
    canvas.drawPath(
      cam1Path,
      Paint()
        ..color = const Color(0x2E00E5FF)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      cam1Path,
      Paint()
        ..color = const Color(0xAA00E5FF)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke,
    );

    // 2. Camera 2 Frustum: Joystick Rear Ultrawide (Emerald) -> Floor & Feet
    final cam2Path = Path()
      ..moveTo(joystickX, chestJoystickY + 2)
      ..lineTo(userX - size.width * 0.14, floorY)
      ..lineTo(size.width * 0.78, floorY)
      ..close();
    canvas.drawPath(
      cam2Path,
      Paint()
        ..color = const Color(0x2E10B981)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      cam2Path,
      Paint()
        ..color = const Color(0xAA10B981)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke,
    );

    // 3. Camera 3 Frustum: Joystick Front Camera (Violet) -> Hands, Torso & Visor
    final cam3Path = Path()
      ..moveTo(joystickX, chestJoystickY - 2)
      ..lineTo(userX - size.width * 0.05, headY - 8)
      ..lineTo(userX + size.width * 0.18, headY - 4)
      ..close();
    canvas.drawPath(
      cam3Path,
      Paint()
        ..color = const Color(0x2EA855F7)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      cam3Path,
      Paint()
        ..color = const Color(0xAAA855F7)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke,
    );

    // Ultrasonic 20 kHz ToF Acoustic Wave Link between Visor & Joystick (Amber)
    final sonarPaint = Paint()
      ..color = const Color(0xFFF59E0B)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(userX + 3, headY + 3),
      Offset(joystickX, chestJoystickY),
      sonarPaint,
    );
    final midSonar = Offset(
      (userX + joystickX) * 0.5,
      (headY + chestJoystickY) * 0.5,
    );
    canvas.drawCircle(midSonar, compact ? 4 : 6, sonarPaint);

    // User 3D Kinematic Skeleton
    final bonePaint = Paint()
      ..color = const Color(0xFFE0F2FE)
      ..strokeWidth = compact ? 2.0 : 2.6
      ..strokeCap = StrokeCap.round;

    // Spine (head -> shoulder -> hip)
    canvas.drawLine(Offset(userX, headY), Offset(userX, hipY), bonePaint);
    // Arm (shoulder -> joystick in hands)
    canvas.drawLine(
      Offset(userX, shoulderY),
      Offset(joystickX, chestJoystickY),
      bonePaint,
    );

    // Left & Right Legs animated by foot vectors
    final leftFootOffset =
        (bodyState.leftFootPosition.z * 28.0).clamp(-16.0, 16.0);
    final rightFootOffset =
        (bodyState.rightFootPosition.z * 28.0).clamp(-16.0, 16.0);
    final leftFootPt = Offset(userX - 8 + leftFootOffset, floorY);
    final rightFootPt = Offset(userX + 10 + rightFootOffset, floorY);

    canvas.drawLine(Offset(userX, hipY), leftFootPt, bonePaint);
    canvas.drawLine(Offset(userX, hipY), rightFootPt, bonePaint);

    // Visor S25 Node on Head
    canvas.drawCircle(
      Offset(userX, headY),
      compact ? 5.0 : 6.5,
      Paint()..color = const Color(0xFF00E5FF),
    );
    // Joystick Moto Edge Node in Hands
    canvas.drawCircle(
      Offset(joystickX, chestJoystickY),
      compact ? 4.5 : 5.5,
      Paint()..color = const Color(0xFFA855F7),
    );
    // Feet Nodes on Floor
    canvas.drawCircle(
      leftFootPt,
      compact ? 3.5 : 4.5,
      Paint()..color = const Color(0xFF10B981),
    );
    canvas.drawCircle(
      rightFootPt,
      compact ? 3.5 : 4.5,
      Paint()..color = const Color(0xFF34D399),
    );

    // Detected Room Obstacle Wireframe Box on right side (Desk / Wall)
    final deskRect = Rect.fromLTWH(
      size.width * 0.68,
      floorY - size.height * 0.28,
      size.width * 0.18,
      size.height * 0.28,
    );
    canvas.drawRect(
      deskRect,
      Paint()
        ..color = Color.lerp(
          const Color(0x66F59E0B),
          const Color(0xFFF59E0B),
          math.max(0.35, passthroughMix),
        )!
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );

    if (!compact) {
      _drawLabel(
        canvas,
        VrTranslationConstants.frustumCam1Label,
        Offset(size.width * 0.50, size.height * 0.08),
        const Color(0xFF00E5FF),
      );
      _drawLabel(
        canvas,
        'CÁM 3 Torso + ToF ${(bodyState.headToJoystickDistanceMeters * 100).round()} cm',
        Offset(userX + 14, headY + 12),
        const Color(0xFFD8B4FE),
      );
      _drawLabel(
        canvas,
        VrTranslationConstants.frustumCam2Label,
        Offset(size.width * 0.34, floorY - 18),
        const Color(0xFF34D399),
      );
      _drawLabel(
        canvas,
        'H=${bodyState.anthropometry.statureMeters.toStringAsFixed(2)}m',
        Offset(6, headY - 4),
        const Color(0xFFE0F2FE),
      );
    }
  }

  void _drawLabel(Canvas canvas, String text, Offset offset, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant VrTriCameraFrustumPainter oldDelegate) =>
      oldDelegate.bodyState != bodyState ||
      oldDelegate.passthroughMix != passthroughMix ||
      oldDelegate.compact != compact;
}
