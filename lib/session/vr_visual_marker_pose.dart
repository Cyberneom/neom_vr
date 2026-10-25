import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

/// Intrinsics for the exact, undistorted pixel frame supplying the corners.
/// Vendor static K, resized screenshots, mirrored/cropped previews and guessed
/// focal lengths must leave [verifiedForFrame] false.
class VrMarkerFrameCalibration {
  const VrMarkerFrameCalibration({
    required this.fx,
    required this.fy,
    required this.cx,
    required this.cy,
    this.skew = 0,
    this.verifiedForFrame = false,
  });
  final double fx, fy, cx, cy, skew;
  final bool verifiedForFrame;

  vm.Vector2 _normalize(vm.Vector2 p) {
    final y = (p.y - cy) / fy;
    return vm.Vector2((p.x - cx - skew * y) / fx, y);
  }

  vm.Vector2 project(vm.Vector3 p) =>
      vm.Vector2(fx * p.x / p.z + skew * p.y / p.z + cx, fy * p.y / p.z + cy);

  void _validate() {
    if (![fx, fy, cx, cy, skew].every((n) => n.isFinite) ||
        fx <= 0 ||
        fy <= 0) {
      throw const VrVisualMarkerPoseException('invalid_frame_intrinsics');
    }
  }
}

class VrVisualMarkerPoseException implements Exception {
  const VrVisualMarkerPoseException(this.reason);
  final String reason;
  @override
  String toString() => 'VrVisualMarkerPoseException: $reason';
}

/// T_camera_marker maps marker-local meters into CV camera coordinates:
/// +X right, +Y down, +Z forward. It is not a VR/world/body pose.
class VrVisualMarkerPose {
  VrVisualMarkerPose._({
    required vm.Matrix4 cameraFromMarkerMatrix,
    required this.reprojectionRmsPixels,
    required this.rawAxisOrthogonalityError,
    required this.relativeAxisScaleMismatch,
    required this.linearSystemPivotRatio,
    required this.minimumCornerDepthMeters,
    required this.confidence,
    required this.metricPoseReady,
  }) : _cameraFromMarkerMatrix = cameraFromMarkerMatrix.clone();
  final vm.Matrix4 _cameraFromMarkerMatrix;
  vm.Matrix4 get cameraFromMarkerMatrix => _cameraFromMarkerMatrix.clone();
  vm.Vector3 get translationMeters => _cameraFromMarkerMatrix.getTranslation();

  /// Rodrigues axis-angle vector in camera axes; magnitude is radians.
  vm.Vector3 get rotationVectorRadians {
    final q = vm.Quaternion.fromRotation(_cameraFromMarkerMatrix.getRotation())
      ..normalize();
    if (q.w < 0) q.scale(-1);
    final length = math.sqrt(q.x * q.x + q.y * q.y + q.z * q.z);
    if (length < 1e-10) return vm.Vector3.zero();
    final scale = 2 * math.atan2(length, q.w) / length;
    return vm.Vector3(q.x * scale, q.y * scale, q.z * scale);
  }

  final double reprojectionRmsPixels;
  final double rawAxisOrthogonalityError;
  final double relativeAxisScaleMismatch;

  /// Ratio of Gaussian pivots, a numerical warning, not an SVD condition number.
  final double linearSystemPivotRatio;
  final double minimumCornerDepthMeters;

  /// Geometric quality heuristic; not a learned detection probability.
  final double confidence;
  final bool metricPoseReady;
  bool get allCornersInFront => minimumCornerDepthMeters > 0;
}

class VrVisualMarkerPoseSolver {
  const VrVisualMarkerPoseSolver({
    this.maxReprojectionRmsPixels = 3,
    this.maxRawAxisOrthogonalityError = .20,
    this.maxRelativeAxisScaleMismatch = .25,
    this.minimumQuadAreaPixels = 36,
    this.minimumEdgePixels = 3,
  });
  final double maxReprojectionRmsPixels;
  final double maxRawAxisOrthogonalityError;
  final double maxRelativeAxisScaleMismatch;
  final double minimumQuadAreaPixels;
  final double minimumEdgePixels;

  /// Corners are marker-semantic TL,TR,BR,BL, clockwise in image Y-down axes.
  /// A unique oriented marker ID is the caller's responsibility. A plain
  /// rectangle cannot resolve its 180-degree identity or planar ambiguity.
  VrVisualMarkerPose solve({
    required List<vm.Vector2> corners,
    required double markerWidthMeters,
    required double markerHeightMeters,
    required VrMarkerFrameCalibration calibration,
  }) {
    calibration._validate();
    if (![
      markerWidthMeters,
      markerHeightMeters,
    ].every((n) => n.isFinite && n > 0)) {
      throw const VrVisualMarkerPoseException('invalid_marker_dimensions');
    }
    if (![
      maxReprojectionRmsPixels,
      maxRawAxisOrthogonalityError,
      maxRelativeAxisScaleMismatch,
      minimumQuadAreaPixels,
      minimumEdgePixels,
    ].every((n) => n.isFinite && n > 0)) {
      throw const VrVisualMarkerPoseException('invalid_quality_thresholds');
    }
    _validateCorners(corners, minimumQuadAreaPixels, minimumEdgePixels);
    final h = _homography(corners.map(calibration._normalize).toList());
    final a = vm.Vector3(h.values[0], h.values[3], h.values[6])
      ..scale(2 / markerWidthMeters);
    final b = vm.Vector3(h.values[1], h.values[4], h.values[7])
      ..scale(2 / markerHeightMeters);
    final na = a.length, nb = b.length;
    if (!na.isFinite || !nb.isFinite || na <= 1e-12 || nb <= 1e-12) {
      throw const VrVisualMarkerPoseException('degenerate_rotation_axes');
    }
    final ortho = (a.dot(b) / (na * nb)).abs();
    final mismatch = (na - nb).abs() / ((na + nb) / 2);
    if (ortho > maxRawAxisOrthogonalityError ||
        mismatch > maxRelativeAxisScaleMismatch) {
      throw const VrVisualMarkerPoseException(
        'inconsistent_euclidean_homography',
      );
    }
    final scale = 2 / (na + nb);
    final t = vm.Vector3(h.values[2], h.values[5], 1)..scale(scale);
    final r1 = a / na;
    final r2 = b - r1 * r1.dot(b);
    if (r2.length < 1e-10) {
      throw const VrVisualMarkerPoseException('degenerate_rotation_axes');
    }
    r2.normalize();
    final r3 = r1.cross(r2)..normalize();
    final transform = vm.Matrix4.identity()
      ..setColumn(0, vm.Vector4(r1.x, r1.y, r1.z, 0))
      ..setColumn(1, vm.Vector4(r2.x, r2.y, r2.z, 0))
      ..setColumn(2, vm.Vector4(r3.x, r3.y, r3.z, 0))
      ..setColumn(3, vm.Vector4(t.x, t.y, t.z, 1));
    final objectPoints = _objectCorners(markerWidthMeters, markerHeightMeters);
    double squaredError = 0, minDepth = double.infinity;
    for (var i = 0; i < 4; i++) {
      final point = transform.transformed3(objectPoints[i]);
      if (!point.z.isFinite || point.z <= 1e-8) {
        throw const VrVisualMarkerPoseException('failed_cheirality');
      }
      minDepth = math.min(minDepth, point.z);
      final projected = calibration.project(point);
      squaredError += projected.distanceToSquared(corners[i]);
    }
    final rms = math.sqrt(squaredError / 4);
    if (!rms.isFinite || rms > maxReprojectionRmsPixels) {
      throw const VrVisualMarkerPoseException('reprojection_error_too_large');
    }
    final confidence =
        (1 -
                math.max(
                  rms / maxReprojectionRmsPixels,
                  math.max(
                    ortho / maxRawAxisOrthogonalityError,
                    mismatch / maxRelativeAxisScaleMismatch,
                  ),
                ))
            .clamp(0.0, 1.0);
    return VrVisualMarkerPose._(
      cameraFromMarkerMatrix: transform,
      reprojectionRmsPixels: rms,
      rawAxisOrthogonalityError: ortho,
      relativeAxisScaleMismatch: mismatch,
      linearSystemPivotRatio: h.pivotRatio,
      minimumCornerDepthMeters: minDepth,
      confidence: confidence.toDouble(),
      metricPoseReady: calibration.verifiedForFrame,
    );
  }
}

List<vm.Vector3> _objectCorners(double width, double height) => [
  vm.Vector3(-width / 2, -height / 2, 0),
  vm.Vector3(width / 2, -height / 2, 0),
  vm.Vector3(width / 2, height / 2, 0),
  vm.Vector3(-width / 2, height / 2, 0),
];

void _validateCorners(
  List<vm.Vector2> corners,
  double minArea,
  double minEdge,
) {
  if (corners.length != 4 ||
      corners.any((p) => !p.x.isFinite || !p.y.isFinite)) {
    throw const VrVisualMarkerPoseException('four_finite_corners_required');
  }
  double area = 0;
  for (var i = 0; i < 4; i++) {
    final a = corners[i], b = corners[(i + 1) % 4], c = corners[(i + 2) % 4];
    final cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
    if (!cross.isFinite || cross <= 1e-8) {
      throw const VrVisualMarkerPoseException(
        'nonconvex_reversed_or_collinear_corners',
      );
    }
    if (a.distanceTo(b) < minEdge) {
      throw const VrVisualMarkerPoseException('marker_edge_too_small');
    }
    area += a.x * b.y - a.y * b.x;
  }
  if (!area.isFinite || area / 2 < minArea) {
    throw const VrVisualMarkerPoseException('marker_area_too_small');
  }
}

class _Homography {
  _Homography(this.values, this.pivotRatio);
  final List<double> values;
  final double pivotRatio;
}

/// Unit-square DLT with H33=1. Scaling the marker keeps the 8x8 solve small.
_Homography _homography(List<vm.Vector2> image) {
  const world = [
    [-1.0, -1.0],
    [1.0, -1.0],
    [1.0, 1.0],
    [-1.0, 1.0],
  ];
  final rows = <List<double>>[];
  for (var i = 0; i < 4; i++) {
    final x = world[i][0], y = world[i][1], u = image[i].x, v = image[i].y;
    rows.add([x, y, 1, 0, 0, 0, -u * x, -u * y, u]);
    rows.add([0, 0, 0, x, y, 1, -v * x, -v * y, v]);
  }
  double minPivot = double.infinity, maxPivot = 0;
  for (var column = 0; column < 8; column++) {
    var pivot = column;
    for (var row = column + 1; row < 8; row++) {
      if (rows[row][column].abs() > rows[pivot][column].abs()) pivot = row;
    }
    final value = rows[pivot][column].abs();
    if (!value.isFinite || value < 1e-12) {
      throw const VrVisualMarkerPoseException('singular_homography');
    }
    minPivot = math.min(minPivot, value);
    maxPivot = math.max(maxPivot, value);
    final swap = rows[column];
    rows[column] = rows[pivot];
    rows[pivot] = swap;
    final divisor = rows[column][column];
    for (var j = column; j < 9; j++) {
      rows[column][j] /= divisor;
    }
    for (var row = 0; row < 8; row++) {
      if (row == column) continue;
      final factor = rows[row][column];
      for (var j = column; j < 9; j++) {
        rows[row][j] -= factor * rows[column][j];
      }
    }
  }
  final ratio = minPivot / maxPivot;
  if (!ratio.isFinite || ratio < 1e-10) {
    throw const VrVisualMarkerPoseException('ill_conditioned_homography');
  }
  final result = [for (var i = 0; i < 8; i++) rows[i][8], 1.0];
  if (result.any((v) => !v.isFinite)) {
    throw const VrVisualMarkerPoseException('nonfinite_homography');
  }
  return _Homography(result, ratio);
}

/// Empirical pinhole calibration from >=6 views of one square planar marker.
/// All samples must be from the same undistorted stream geometry. This does not
/// estimate distortion, sensor-to-preview mapping or a phone's mounting offset.
class VrPlanarCameraCalibrator {
  VrPlanarCameraCalibrator({
    this.minimumViews = 6,
    this.maxReprojectionRmsPixels = 2,
  });
  final int minimumViews;
  final double maxReprojectionRmsPixels;
  final List<List<vm.Vector2>> _views = [];
  int? _width, _height;
  int get viewCount => _views.length;
  void clear() {
    _views.clear();
    _width = null;
    _height = null;
  }

  void addView(List<vm.Vector2> corners, int widthPx, int heightPx) {
    if (widthPx <= 0 || heightPx <= 0 || _views.length >= 64) {
      throw const VrVisualMarkerPoseException(
        'invalid_calibration_frame_size_or_view_limit',
      );
    }
    if (_width != null && (_width != widthPx || _height != heightPx)) {
      throw const VrVisualMarkerPoseException(
        'calibration_stream_size_changed',
      );
    }
    _validateCorners(corners, 36, 3);
    if (corners.any(
      (p) => p.x < 0 || p.y < 0 || p.x >= widthPx || p.y >= heightPx,
    )) {
      throw const VrVisualMarkerPoseException(
        'calibration_corners_outside_frame',
      );
    }
    _width = widthPx;
    _height = heightPx;
    _views.add(corners.map((p) => p.clone()).toList());
  }

  VrPlanarCameraCalibrationResult calibrate() {
    if (minimumViews < 6 ||
        _views.length < minimumViews ||
        !maxReprojectionRmsPixels.isFinite ||
        maxReprojectionRmsPixels <= 0) {
      throw const VrVisualMarkerPoseException(
        'at_least_six_calibration_views_required',
      );
    }
    final width = _width!,
        height = _height!,
        scale = math.max(width, height).toDouble();
    final center = vm.Vector2(width / 2, height / 2);
    final normal = List.generate(6, (_) => List<double>.filled(6, 0));
    for (final corners in _views) {
      final h = _homography(
        corners.map((p) => (p - center) / scale).toList(),
      ).values;
      final a = [h[0], h[3], h[6]], b = [h[1], h[4], h[7]];
      final constraints = [
        _vij(a, b),
        List.generate(6, (i) => _vij(a, a)[i] - _vij(b, b)[i]),
      ];
      for (final row in constraints) {
        final norm = math.sqrt(row.fold<double>(0, (sum, v) => sum + v * v));
        if (norm < 1e-12) {
          throw const VrVisualMarkerPoseException(
            'degenerate_calibration_view',
          );
        }
        for (var i = 0; i < 6; i++) {
          for (var j = 0; j < 6; j++) {
            normal[i][j] += row[i] * row[j] / (norm * norm);
          }
        }
      }
    }
    final eigen = _symmetricEigen(normal);
    final order = List.generate(6, (i) => i)
      ..sort((a, b) => eigen.values[a].compareTo(eigen.values[b]));
    final smallest = eigen.values[order[0]].abs(),
        second = eigen.values[order[1]],
        largest = eigen.values[order[5]];
    final condition = second / largest;
    if (!condition.isFinite ||
        condition < 1e-6 ||
        second <= 0 ||
        smallest / second > .1) {
      throw const VrVisualMarkerPoseException(
        'calibration_views_lack_orientation_diversity',
      );
    }
    var b = List.generate(6, (i) => eigen.vectors[i][order[0]]);
    if (b[0] < 0) b = b.map((v) => -v).toList();
    final denominator = b[0] * b[2] - b[1] * b[1];
    if (b[0] <= 0 || denominator <= 1e-14) {
      throw const VrVisualMarkerPoseException('nonphysical_intrinsic_conic');
    }
    final v0 = (b[1] * b[3] - b[0] * b[4]) / denominator;
    final lambda =
        b[5] - (b[3] * b[3] + v0 * (b[1] * b[3] - b[0] * b[4])) / b[0];
    if (lambda <= 0) {
      throw const VrVisualMarkerPoseException('nonphysical_intrinsic_conic');
    }
    final alpha = math.sqrt(lambda / b[0]);
    final beta = math.sqrt(lambda * b[0] / denominator);
    final skew = -b[1] * alpha * alpha * beta / lambda;
    final u0 = skew * v0 / beta - b[3] * alpha * alpha / lambda;
    final calibration = VrMarkerFrameCalibration(
      fx: alpha * scale,
      fy: beta * scale,
      cx: u0 * scale + center.x,
      cy: v0 * scale + center.y,
      skew: skew * scale,
      verifiedForFrame: false,
    );
    calibration._validate();
    if (calibration.cx < 0 ||
        calibration.cx >= width ||
        calibration.cy < 0 ||
        calibration.cy >= height ||
        calibration.fx < width * .1 ||
        calibration.fx > width * 10 ||
        calibration.fy < height * .1 ||
        calibration.fy > height * 10) {
      throw const VrVisualMarkerPoseException(
        'implausible_empirical_intrinsics',
      );
    }
    final solver = VrVisualMarkerPoseSolver(
      maxReprojectionRmsPixels: maxReprojectionRmsPixels,
    );
    double errorSum = 0, maxTilt = 0, maxNormalSeparation = 0;
    double minX = double.infinity, minY = double.infinity, maxX = 0, maxY = 0;
    final normals = <vm.Vector3>[];
    for (final corners in _views) {
      final pose = solver.solve(
        corners: corners,
        markerWidthMeters: 1,
        markerHeightMeters: 1,
        calibration: calibration,
      );
      errorSum += pose.reprojectionRmsPixels * pose.reprojectionRmsPixels;
      final matrix = pose.cameraFromMarkerMatrix;
      final normal = vm.Vector3(
        matrix.entry(0, 2),
        matrix.entry(1, 2),
        matrix.entry(2, 2),
      );
      maxTilt = math.max(maxTilt, math.acos(normal.z.clamp(-1.0, 1.0)));
      for (final previous in normals) {
        maxNormalSeparation = math.max(
          maxNormalSeparation,
          math.acos(previous.dot(normal).clamp(-1.0, 1.0)),
        );
      }
      normals.add(normal);
      for (final p in corners) {
        minX = math.min(minX, p.x);
        minY = math.min(minY, p.y);
        maxX = math.max(maxX, p.x);
        maxY = math.max(maxY, p.y);
      }
    }
    final coverage = (maxX - minX) * (maxY - minY) / (width * height);
    if (maxTilt < .25 || maxNormalSeparation < .25 || coverage < .10) {
      throw const VrVisualMarkerPoseException(
        'calibration_needs_tilted_diverse_well_spread_views',
      );
    }
    final rms = math.sqrt(errorSum / _views.length);
    if (!rms.isFinite || rms > maxReprojectionRmsPixels) {
      throw const VrVisualMarkerPoseException(
        'calibration_reprojection_error_too_large',
      );
    }
    return VrPlanarCameraCalibrationResult(
      calibration: calibration,
      widthPixels: width,
      heightPixels: height,
      viewCount: _views.length,
      reprojectionRmsPixels: rms,
      coverageFraction: coverage,
      constraintRankRatio: condition,
      maximumNormalSeparationRadians: maxNormalSeparation,
    );
  }
}

class VrPlanarCameraCalibrationResult {
  const VrPlanarCameraCalibrationResult({
    required this.calibration,
    required this.widthPixels,
    required this.heightPixels,
    required this.viewCount,
    required this.reprojectionRmsPixels,
    required this.coverageFraction,
    required this.constraintRankRatio,
    required this.maximumNormalSeparationRadians,
  });

  /// Experimental pinhole fit, deliberately unverified. Callers must verify
  /// camera/size/crop/rotation/zoom/distortion and an independent physical
  /// measurement before promoting this K to verified frame calibration.
  final VrMarkerFrameCalibration calibration;
  final int widthPixels, heightPixels, viewCount;
  final double reprojectionRmsPixels, coverageFraction, constraintRankRatio;
  final double maximumNormalSeparationRadians;
  String get source => 'empirical_planar_zhang_pinhole';
  bool get distortionEstimated => false;
}

List<double> _vij(List<double> a, List<double> b) => [
  a[0] * b[0],
  a[0] * b[1] + a[1] * b[0],
  a[1] * b[1],
  a[2] * b[0] + a[0] * b[2],
  a[2] * b[1] + a[1] * b[2],
  a[2] * b[2],
];

class _Eigen {
  _Eigen(this.values, this.vectors);
  final List<double> values;
  final List<List<double>> vectors;
}

/// Jacobi rotations for a real symmetric 6x6 matrix; eigenvectors are columns.
_Eigen _symmetricEigen(List<List<double>> input) {
  final a = input.map((row) => row.toList()).toList();
  final vectors = List.generate(
    6,
    (i) => List.generate(6, (j) => i == j ? 1.0 : 0.0),
  );
  var converged = false;
  for (var iteration = 0; iteration < 200; iteration++) {
    var p = 0, q = 1;
    for (var i = 0; i < 6; i++) {
      for (var j = i + 1; j < 6; j++) {
        if (a[i][j].abs() > a[p][q].abs()) {
          p = i;
          q = j;
        }
      }
    }
    if (a[p][q].abs() < 1e-14) {
      converged = true;
      break;
    }
    final angle = .5 * math.atan2(2 * a[p][q], a[q][q] - a[p][p]);
    final c = math.cos(angle), s = math.sin(angle);
    final app = a[p][p], aqq = a[q][q], apq = a[p][q];
    for (var i = 0; i < 6; i++) {
      if (i == p || i == q) continue;
      final aip = a[i][p], aiq = a[i][q];
      a[i][p] = a[p][i] = c * aip - s * aiq;
      a[i][q] = a[q][i] = s * aip + c * aiq;
    }
    a[p][p] = c * c * app - 2 * s * c * apq + s * s * aqq;
    a[q][q] = s * s * app + 2 * s * c * apq + c * c * aqq;
    a[p][q] = a[q][p] = 0;
    for (var i = 0; i < 6; i++) {
      final vip = vectors[i][p], viq = vectors[i][q];
      vectors[i][p] = c * vip - s * viq;
      vectors[i][q] = s * vip + c * viq;
    }
  }
  if (!converged) {
    throw const VrVisualMarkerPoseException(
      'intrinsic_eigensolver_not_converged',
    );
  }
  return _Eigen(List.generate(6, (i) => a[i][i]), vectors);
}
