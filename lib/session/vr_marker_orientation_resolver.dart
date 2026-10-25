import 'package:camera/camera.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:vector_math/vector_math.dart' as vm;

class VrMarkerOrientationResult {
  VrMarkerOrientationResult({
    required List<vm.Vector2> orderedCorners,
    required this.verified,
    required this.score,
    required this.reason,
    this.binaryError = 1,
    this.runnerUpError = 1,
    this.contrast = 0,
  }) : _corners = orderedCorners.map((p) => p.clone()).toList();

  final List<vm.Vector2> _corners;
  List<vm.Vector2> get orderedCorners =>
      _corners.map((p) => p.clone()).toList();
  final bool verified;

  /// Fraction of matching module samples, not a detection probability.
  final double score;
  final String reason;
  final double binaryError, runnerUpError, contrast;
}

/// Verifies semantic QR corner identity against pixels from the SAME frame.
///
/// The displayed marker must use QrCode.fromData, correction M, auto version,
/// and QrImage's default mask. Corners enclose the code, excluding quiet zone.
/// Accepts ML Kit's clockwise corners in its rotated image coordinates; tests
/// all four cyclic starts. Reflection, another encoder/mask or low resolution
/// cannot silently certify orientation. This is not camera calibration.
class VrMarkerOrientationResolver {
  String? _cachedMarkerId;
  QrImage? _cachedSymbol;

  VrMarkerOrientationResult resolve({
    required CameraImage image,
    required int rotationDegrees,
    required List<vm.Vector2> corners,
    required String markerId,
  }) {
    VrMarkerOrientationResult fail(String reason) => VrMarkerOrientationResult(
      orderedCorners: corners,
      verified: false,
      score: 0,
      reason: reason,
    );
    if (![0, 90, 180, 270].contains(rotationDegrees)) {
      return fail('unsupported_frame_rotation');
    }
    if (image.width <= 0 ||
        image.height <= 0 ||
        image.planes.isEmpty ||
        ![
          ImageFormatGroup.nv21,
          ImageFormatGroup.yuv420,
        ].contains(image.format.group)) {
      return fail('unsupported_luminance_frame');
    }
    final y = image.planes.first;
    final pixelStride = y.bytesPerPixel ?? 1;
    if (pixelStride <= 0 ||
        y.bytesPerRow < (image.width - 1) * pixelStride + 1 ||
        y.bytes.length <=
            (image.height - 1) * y.bytesPerRow +
                (image.width - 1) * pixelStride) {
      return fail('invalid_luminance_layout');
    }
    final rotatedWidth = rotationDegrees % 180 == 0
        ? image.width
        : image.height;
    final rotatedHeight = rotationDegrees % 180 == 0
        ? image.height
        : image.width;
    if (corners.length != 4 ||
        corners.any(
          (p) =>
              !p.x.isFinite ||
              !p.y.isFinite ||
              p.x < 0 ||
              p.y < 0 ||
              p.x >= rotatedWidth ||
              p.y >= rotatedHeight,
        )) {
      return fail('four_in_frame_corners_required');
    }
    for (var i = 0; i < 4; i++) {
      final a = corners[i], b = corners[(i + 1) % 4], c = corners[(i + 2) % 4];
      if ((b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x) <= 1e-8 ||
          a.distanceTo(b) < 3) {
        return fail('nonconvex_reversed_or_small_quad');
      }
    }
    if (markerId.isEmpty || markerId.length > 512) {
      return fail('invalid_marker_id');
    }
    QrImage symbol;
    try {
      if (_cachedMarkerId != markerId) {
        _cachedSymbol = QrImage(
          QrCode.fromData(
            data: markerId,
            errorCorrectLevel: QrErrorCorrectLevel.M,
          ),
        );
        _cachedMarkerId = markerId;
      }
      symbol = _cachedSymbol!;
    } catch (_) {
      return fail('marker_encoding_failed');
    }
    final count = symbol.moduleCount;
    final candidates = <_Candidate>[];
    for (var start = 0; start < 4; start++) {
      final ordered = List.generate(4, (i) => corners[(i + start) % 4]);
      final h = _quadHomography(ordered);
      if (h == null) return fail('degenerate_marker_homography');
      final samples = <int>[];
      double darkSum = 0, lightSum = 0;
      var darkCount = 0, lightCount = 0;
      for (var row = 0; row < count; row++) {
        for (var col = 0; col < count; col++) {
          final u = (col + .5) / count, v = (row + .5) / count;
          final denominator = h[6] * u + h[7] * v + 1;
          if (!denominator.isFinite || denominator.abs() < 1e-10) {
            return fail('invalid_marker_projection');
          }
          final rx = (h[0] * u + h[1] * v + h[2]) / denominator;
          final ry = (h[3] * u + h[4] * v + h[5]) / denominator;
          late double sx, sy;
          switch (rotationDegrees) {
            case 0:
              sx = rx;
              sy = ry;
            case 90:
              sx = ry;
              sy = image.height - 1 - rx;
            case 180:
              sx = image.width - 1 - rx;
              sy = image.height - 1 - ry;
            case 270:
              sx = image.width - 1 - ry;
              sy = rx;
          }
          if (!sx.isFinite ||
              !sy.isFinite ||
              sx < 0 ||
              sy < 0 ||
              sx > image.width - 1 ||
              sy > image.height - 1) {
            return fail('marker_sample_outside_frame');
          }
          final value =
              y.bytes[sy.round() * y.bytesPerRow + sx.round() * pixelStride];
          samples.add(value);
          if (symbol.isDark(row, col)) {
            darkSum += value;
            darkCount++;
          } else {
            lightSum += value;
            lightCount++;
          }
        }
      }
      final darkMean = darkSum / darkCount, lightMean = lightSum / lightCount;
      final threshold = (darkMean + lightMean) / 2;
      var errors = 0;
      for (var row = 0; row < count; row++) {
        for (var col = 0; col < count; col++) {
          if ((samples[row * count + col] < threshold) !=
              symbol.isDark(row, col)) {
            errors++;
          }
        }
      }
      candidates.add(
        _Candidate(ordered, errors / samples.length, lightMean - darkMean),
      );
    }
    candidates.sort((a, b) => a.error.compareTo(b.error));
    final best = candidates[0], second = candidates[1];
    final reason = best.contrast <= 40
        ? 'insufficient_marker_contrast'
        : best.error >= .18
        ? 'marker_pattern_mismatch'
        : second.error - best.error <= .12
        ? 'ambiguous_marker_orientation'
        : 'orientation_verified';
    return VrMarkerOrientationResult(
      orderedCorners: best.corners,
      verified: reason == 'orientation_verified',
      score: (1 - best.error).clamp(0.0, 1.0),
      reason: reason,
      binaryError: best.error,
      runnerUpError: second.error,
      contrast: best.contrast,
    );
  }
}

class _Candidate {
  _Candidate(this.corners, this.error, this.contrast);
  final List<vm.Vector2> corners;
  final double error, contrast;
}

/// Four-point unit-square homography, H33=1, partial-pivot Gaussian solve.
List<double>? _quadHomography(List<vm.Vector2> image) {
  const points = [
    [0.0, 0.0],
    [1.0, 0.0],
    [1.0, 1.0],
    [0.0, 1.0],
  ];
  final rows = <List<double>>[];
  for (var i = 0; i < 4; i++) {
    final x = points[i][0], y = points[i][1], u = image[i].x, v = image[i].y;
    rows.add([x, y, 1, 0, 0, 0, -u * x, -u * y, u]);
    rows.add([0, 0, 0, x, y, 1, -v * x, -v * y, v]);
  }
  for (var c = 0; c < 8; c++) {
    var pivot = c;
    for (var r = c + 1; r < 8; r++) {
      if (rows[r][c].abs() > rows[pivot][c].abs()) pivot = r;
    }
    final magnitude = rows[pivot][c].abs();
    if (!magnitude.isFinite || magnitude < 1e-10) return null;
    final old = rows[c];
    rows[c] = rows[pivot];
    rows[pivot] = old;
    final divisor = rows[c][c];
    for (var j = c; j < 9; j++) {
      rows[c][j] /= divisor;
    }
    for (var r = 0; r < 8; r++) {
      if (r == c) continue;
      final factor = rows[r][c];
      for (var j = c; j < 9; j++) {
        rows[r][j] -= factor * rows[c][j];
      }
    }
  }
  final h = List.generate(8, (i) => rows[i][8]);
  return h.every((v) => v.isFinite) ? h : null;
}
