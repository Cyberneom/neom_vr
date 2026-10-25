import 'dart:typed_data';

import 'package:camera/camera.dart';
// CameraImage's supported test constructor uses platform image data.
// ignore: depend_on_referenced_packages
import 'package:camera_platform_interface/camera_platform_interface.dart'
    show CameraImageData, CameraImageFormat, CameraImagePlane;
import 'package:flutter_test/flutter_test.dart';
import 'package:neom_vr/session/vr_marker_orientation_resolver.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:vector_math/vector_math.dart' as vm;

const _id = 'vrlizate-marker-test-12345';

class _Frame {
  _Frame(this.image, this.detectorCorners, this.semanticCorners);
  final CameraImage image;
  final List<vm.Vector2> detectorCorners, semanticCorners;
}

_Frame _frame({
  int physicalTurns = 0,
  int rotation = 0,
  bool yuv = false,
  bool blank = false,
  int dark = 20,
  int light = 235,
}) {
  final qr = QrImage(
    QrCode.fromData(data: _id, errorCorrectLevel: QrErrorCorrectLevel.M),
  );
  final count = qr.moduleCount, side = count * 6;
  final width = side + 48, height = side + 80;
  final stride = yuv ? width * 2 + 12 : width;
  final pixelStride = yuv ? 2 : 1;
  final bytes = Uint8List(stride * height + (yuv ? 0 : width * height ~/ 2))
    ..fillRange(0, stride * height, light);
  for (var py = 0; py < side; py++) {
    for (var px = 0; px < side; px++) {
      final row = py ~/ 6, col = px ~/ 6;
      final isDark = switch (physicalTurns) {
        0 => qr.isDark(row, col),
        1 => qr.isDark(count - 1 - col, row),
        2 => qr.isDark(count - 1 - row, count - 1 - col),
        _ => qr.isDark(col, count - 1 - row),
      };
      bytes[(py + 16) * stride + (px + 24) * pixelStride] = !blank && isDark
          ? dark
          : light;
    }
  }
  vm.Vector2 rotate(vm.Vector2 p) => switch (rotation) {
    90 => vm.Vector2(height - 1 - p.y, p.x),
    180 => vm.Vector2(width - 1 - p.x, height - 1 - p.y),
    270 => vm.Vector2(p.y, width - 1 - p.x),
    _ => p.clone(),
  };
  final geometric = [
    vm.Vector2(24, 16),
    vm.Vector2(24 + side.toDouble(), 16),
    vm.Vector2(24 + side.toDouble(), 16 + side.toDouble()),
    vm.Vector2(24, 16 + side.toDouble()),
  ].map(rotate).toList();
  final semantic = List.generate(4, (i) => geometric[(i + physicalTurns) % 4]);
  // Intentionally start at an arbitrary detector corner.
  final detector = List.generate(4, (i) => geometric[(i + 2) % 4]);
  final image = CameraImage.fromPlatformInterface(
    CameraImageData(
      format: CameraImageFormat(
        yuv ? ImageFormatGroup.yuv420 : ImageFormatGroup.nv21,
        raw: yuv ? 35 : 17,
      ),
      height: height,
      width: width,
      planes: [
        CameraImagePlane(
          bytes: bytes,
          bytesPerRow: stride,
          bytesPerPixel: pixelStride,
        ),
        if (yuv) ...[
          CameraImagePlane(
            bytes: Uint8List(width * height ~/ 4),
            bytesPerRow: width ~/ 2,
            bytesPerPixel: 1,
          ),
          CameraImagePlane(
            bytes: Uint8List(width * height ~/ 4),
            bytesPerRow: width ~/ 2,
            bytesPerPixel: 1,
          ),
        ],
      ],
    ),
  );
  return _Frame(image, detector, semantic);
}

void main() {
  for (final rotation in [0, 90, 180, 270]) {
    for (var turns = 0; turns < 4; turns++) {
      test('NV21 physical QR turn $turns with ML Kit rotation $rotation', () {
        final f = _frame(physicalTurns: turns, rotation: rotation);
        final r = VrMarkerOrientationResolver().resolve(
          image: f.image,
          rotationDegrees: rotation,
          corners: f.detectorCorners,
          markerId: _id,
        );
        expect(r.verified, isTrue, reason: r.reason);
        expect(r.binaryError, 0);
        expect(r.runnerUpError - r.binaryError, greaterThan(.12));
        expect(r.contrast, 215);
        expect(r.score, 1);
        for (var i = 0; i < 4; i++) {
          expect(
            r.orderedCorners[i].distanceTo(f.semanticCorners[i]),
            lessThan(.001),
          );
        }
      });
    }
  }

  test('YUV luminance honors row padding and pixel stride', () {
    final f = _frame(yuv: true, physicalTurns: 3, rotation: 90);
    final r = VrMarkerOrientationResolver().resolve(
      image: f.image,
      rotationDegrees: 90,
      corners: f.detectorCorners,
      markerId: _id,
    );
    expect(r.verified, isTrue, reason: r.reason);
    expect(r.binaryError, 0);
  });

  test('blank and low contrast frames never certify orientation', () {
    for (final f in [_frame(blank: true), _frame(dark: 120, light: 150)]) {
      final r = VrMarkerOrientationResolver().resolve(
        image: f.image,
        rotationDegrees: 0,
        corners: f.detectorCorners,
        markerId: _id,
      );
      expect(r.verified, isFalse);
      expect(r.reason, 'insufficient_marker_contrast');
    }
  });

  test('another marker payload cannot certify this code', () {
    final f = _frame();
    final r = VrMarkerOrientationResolver().resolve(
      image: f.image,
      rotationDegrees: 0,
      corners: f.detectorCorners,
      markerId: 'vrlizate-other-marker-67890',
    );
    expect(r.verified, isFalse);
  });

  test(
    'unsupported rotation, reversed corners and bad buffers fail honestly',
    () {
      final resolver = VrMarkerOrientationResolver(), f = _frame();
      expect(
        resolver
            .resolve(
              image: f.image,
              rotationDegrees: 45,
              corners: f.detectorCorners,
              markerId: _id,
            )
            .reason,
        'unsupported_frame_rotation',
      );
      expect(
        resolver
            .resolve(
              image: f.image,
              rotationDegrees: 0,
              corners: f.detectorCorners.reversed.toList(),
              markerId: _id,
            )
            .verified,
        isFalse,
      );
      final bad = CameraImage.fromPlatformInterface(
        CameraImageData(
          format: const CameraImageFormat(ImageFormatGroup.nv21, raw: 17),
          width: f.image.width,
          height: f.image.height,
          planes: [
            CameraImagePlane(bytes: Uint8List(5), bytesPerRow: f.image.width),
          ],
        ),
      );
      expect(
        resolver
            .resolve(
              image: bad,
              rotationDegrees: 0,
              corners: f.detectorCorners,
              markerId: _id,
            )
            .reason,
        'invalid_luminance_layout',
      );
    },
  );

  test('returned corners cannot mutate a stored verification', () {
    final f = _frame();
    final r = VrMarkerOrientationResolver().resolve(
      image: f.image,
      rotationDegrees: 0,
      corners: f.detectorCorners,
      markerId: _id,
    );
    final x = r.orderedCorners.first.x;
    r.orderedCorners.first.x = -100;
    expect(r.orderedCorners.first.x, x);
    expect(r.verified, isTrue);
  });
}
