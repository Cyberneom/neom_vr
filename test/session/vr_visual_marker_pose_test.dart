import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:neom_vr/session/vr_visual_marker_pose.dart';
import 'package:vector_math/vector_math.dart' as vm;

const _k = VrMarkerFrameCalibration(
  fx: 800,
  fy: 830,
  cx: 635,
  cy: 475,
  skew: 2,
  verifiedForFrame: true,
);

vm.Matrix4 _transform({
  double ax = 0,
  double ay = 0,
  double az = 0,
  double x = 0,
  double y = 0,
  double z = .7,
}) => vm.Matrix4.identity()
  ..translateByDouble(x, y, z, 1)
  ..rotateZ(az)
  ..rotateY(ay)
  ..rotateX(ax);

List<vm.Vector2> _project(
  vm.Matrix4 transform, {
  double width = .2,
  double height = .2,
}) => [
  vm.Vector3(-width / 2, -height / 2, 0),
  vm.Vector3(width / 2, -height / 2, 0),
  vm.Vector3(width / 2, height / 2, 0),
  vm.Vector3(-width / 2, height / 2, 0),
].map((p) => _k.project(transform.transformed3(p))).toList();

VrVisualMarkerPose _solve(
  List<vm.Vector2> corners, {
  VrMarkerFrameCalibration calibration = _k,
  double width = .2,
  double height = .2,
}) => const VrVisualMarkerPoseSolver().solve(
  corners: corners,
  markerWidthMeters: width,
  markerHeightMeters: height,
  calibration: calibration,
);

Matcher _fails(String reason) => throwsA(
  isA<VrVisualMarkerPoseException>().having((e) => e.reason, 'reason', reason),
);

List<List<vm.Vector2>> _calibrationViews({double noise = 0}) {
  const ax = [-.4, .3, .45, -.25, .1, .35, -.3, .42, -.38, .2, -.15, .35];
  const ay = [-.3, .4, -.2, .35, .3, -.4, .45, .15, -.2, -.35, .35, -.3];
  return List.generate(12, (i) {
    final corners = _project(
      _transform(
        ax: ax[i],
        ay: ay[i],
        az: (i % 3 - 1) * .15,
        x: (i % 4 - 1.5) * .09,
        y: (i ~/ 4 - 1) * .09,
        z: .5 + (i % 3) * .07,
      ),
    );
    for (var j = 0; j < corners.length; j++) {
      corners[j].x += noise * math.sin(i * 3 + j * 5);
      corners[j].y += noise * math.cos(i * 7 + j * 2);
    }
    return corners;
  });
}

void main() {
  group('planar marker pose', () {
    test('frontal rectangular marker recovers camera-from-marker meters', () {
      final p = _solve(
        _project(_transform(x: .02, y: -.03, z: .8), width: .3, height: .1),
        width: .3,
        height: .1,
      );
      expect(p.translationMeters.x, closeTo(.02, 1e-5));
      expect(p.translationMeters.y, closeTo(-.03, 1e-5));
      expect(p.translationMeters.z, closeTo(.8, 1e-5));
      expect(p.reprojectionRmsPixels, lessThan(.001));
      expect(p.allCornersInFront, isTrue);
      expect(p.metricPoseReady, isTrue);
      expect(p.rotationVectorRadians.length, lessThan(1e-5));
    });

    test('tilted marker recovers orientation including skew', () {
      final expected = _transform(ax: .2, ay: .3, az: .1, x: .01, y: -.02);
      final p = _solve(_project(expected));
      for (var row = 0; row < 4; row++) {
        for (var col = 0; col < 4; col++) {
          expect(
            p.cameraFromMarkerMatrix.entry(row, col),
            closeTo(expected.entry(row, col), 1e-5),
          );
        }
      }
      expect(p.rawAxisOrthogonalityError, lessThan(1e-5));
      expect(p.relativeAxisScaleMismatch, lessThan(1e-5));
      expect(p.confidence, greaterThan(.99));
      expect(p.rotationVectorRadians.length, greaterThan(.3));
    });

    test('Rodrigues vector remains finite near a 180 degree in-plane roll', () {
      final p = _solve(_project(_transform(az: math.pi - .00001)));
      expect(p.rotationVectorRadians.z, closeTo(math.pi - .00001, 1e-4));
      expect(p.rotationVectorRadians.x.abs(), lessThan(1e-4));
      expect(p.rotationVectorRadians.y.abs(), lessThan(1e-4));
    });

    test('small noisy corners retain bounded reprojection and translation', () {
      final points = _project(_transform(ax: .2, ay: .3));
      for (var i = 0; i < 4; i++) {
        points[i] += vm.Vector2(i.isEven ? .15 : -.15, i < 2 ? -.1 : .1);
      }
      final p = _solve(points);
      expect(p.reprojectionRmsPixels, lessThan(1));
      expect(p.translationMeters.z, closeTo(.7, .01));
      expect(p.confidence, inInclusiveRange(0, 1));
    });

    test('unverified vendor or approximate K never becomes metric ready', () {
      final p = _solve(
        _project(_transform()),
        calibration: const VrMarkerFrameCalibration(
          fx: 800,
          fy: 830,
          cx: 635,
          cy: 475,
          skew: 2,
        ),
      );
      expect(p.metricPoseReady, isFalse);
      expect(p.reprojectionRmsPixels, lessThan(.001));
    });

    test('returned matrices and vectors cannot mutate the validated pose', () {
      final p = _solve(_project(_transform()));
      p.cameraFromMarkerMatrix.setEntry(2, 3, -20);
      p.translationMeters.z = -50;
      expect(p.translationMeters.z, closeTo(.7, 1e-5));
      expect(p.allCornersInFront, isTrue);
    });

    test('invalid intrinsics and marker dimensions fail explicitly', () {
      final corners = _project(_transform());
      for (final fx in [0.0, -1.0, double.nan, double.infinity]) {
        expect(
          () => _solve(
            corners,
            calibration: VrMarkerFrameCalibration(
              fx: fx,
              fy: 830,
              cx: 635,
              cy: 475,
            ),
          ),
          _fails('invalid_frame_intrinsics'),
        );
      }
      for (final width in [0.0, -1.0, double.nan, double.infinity]) {
        expect(
          () => _solve(corners, width: width),
          _fails('invalid_marker_dimensions'),
        );
      }
    });

    test('missing, nonfinite, reversed and nonconvex corners fail', () {
      final points = _project(_transform());
      expect(
        () => _solve(points.take(3).toList()),
        _fails('four_finite_corners_required'),
      );
      expect(
        () => _solve([vm.Vector2(double.nan, 0), ...points.skip(1)]),
        _fails('four_finite_corners_required'),
      );
      expect(
        () => _solve(points.reversed.toList()),
        _fails('nonconvex_reversed_or_collinear_corners'),
      );
      expect(
        () => _solve([points[0], points[2], points[1], points[3]]),
        _fails('nonconvex_reversed_or_collinear_corners'),
      );
    });

    test('collinear and extremely small markers fail', () {
      expect(
        () => _solve(List.generate(4, (i) => vm.Vector2(i * 10, 10))),
        _fails('nonconvex_reversed_or_collinear_corners'),
      );
      expect(
        () => _solve([
          vm.Vector2(0, 0),
          vm.Vector2(1, 0),
          vm.Vector2(1, 1),
          vm.Vector2(0, 1),
        ]),
        _fails('marker_edge_too_small'),
      );
    });

    test(
      'a geometrically inconsistent quad is not accepted as a rigid pose',
      () {
        final p = _project(_transform());
        p[2].x += 100;
        expect(() => _solve(p), throwsA(isA<VrVisualMarkerPoseException>()));
      },
    );
  });

  group('empirical planar camera calibration', () {
    test('diverse synthetic tilted views recover known pinhole K', () {
      final c = VrPlanarCameraCalibrator();
      for (final corners in _calibrationViews()) {
        c.addView(corners, 1280, 960);
      }
      final r = c.calibrate();
      expect(r.calibration.fx, closeTo(_k.fx, .001));
      expect(r.calibration.fy, closeTo(_k.fy, .001));
      expect(r.calibration.cx, closeTo(_k.cx, .001));
      expect(r.calibration.cy, closeTo(_k.cy, .001));
      expect(r.calibration.skew, closeTo(_k.skew, .001));
      expect(r.reprojectionRmsPixels, lessThan(.001));
      expect(r.coverageFraction, greaterThan(.4));
      expect(r.constraintRankRatio, greaterThan(1e-6));
      expect(r.maximumNormalSeparationRadians, greaterThan(.25));
      expect(r.widthPixels, 1280);
      expect(r.heightPixels, 960);
      expect(r.viewCount, 12);
      expect(r.source, 'empirical_planar_zhang_pinhole');
      expect(r.distortionEstimated, isFalse);
      expect(r.calibration.verifiedForFrame, isFalse);
      expect(
        _solve(
          _project(_transform()),
          calibration: r.calibration,
        ).metricPoseReady,
        isFalse,
      );
    });

    test('subpixel noise yields an experimental bounded fit', () {
      final c = VrPlanarCameraCalibrator();
      for (final corners in _calibrationViews(noise: .12)) {
        c.addView(corners, 1280, 960);
      }
      final r = c.calibrate();
      expect(r.calibration.fx, closeTo(_k.fx, _k.fx * .05));
      expect(r.calibration.fy, closeTo(_k.fy, _k.fy * .05));
      expect(r.reprojectionRmsPixels, lessThan(2));
      expect(r.calibration.verifiedForFrame, isFalse);
    });

    test(
      'six translated frontal views do not constrain camera calibration',
      () {
        final c = VrPlanarCameraCalibrator();
        for (var i = 0; i < 6; i++) {
          c.addView(_project(_transform(x: (i - 3) * .04)), 1280, 960);
        }
        expect(c.calibrate, throwsA(isA<VrVisualMarkerPoseException>()));
      },
    );

    test('repeated tilted views do not meet orientation diversity', () {
      final c = VrPlanarCameraCalibrator();
      for (var i = 0; i < 6; i++) {
        c.addView(_project(_transform(ax: .3, ay: .2)), 1280, 960);
      }
      expect(c.calibrate, throwsA(isA<VrVisualMarkerPoseException>()));
    });

    test('insufficient views, changed dimensions and out of bounds fail', () {
      final c = VrPlanarCameraCalibrator();
      expect(c.calibrate, _fails('at_least_six_calibration_views_required'));
      c.addView(_project(_transform()), 1280, 960);
      expect(
        () => c.addView(_project(_transform()), 640, 480),
        _fails('calibration_stream_size_changed'),
      );
      expect(
        () => c.addView(
          [
            vm.Vector2(-1, 20),
            vm.Vector2(30, 20),
            vm.Vector2(30, 60),
            vm.Vector2(-1, 60),
          ],
          1280,
          960,
        ),
        _fails('calibration_corners_outside_frame'),
      );
      expect(c.viewCount, 1);
    });

    test('views are copied and clear permits a different frame size', () {
      final c = VrPlanarCameraCalibrator();
      final corners = _project(_transform());
      c.addView(corners, 1280, 960);
      corners[0].x = double.nan;
      expect(c.viewCount, 1);
      c.clear();
      expect(c.viewCount, 0);
      c.addView(
        [
          vm.Vector2(10, 10),
          vm.Vector2(40, 10),
          vm.Vector2(40, 40),
          vm.Vector2(10, 40),
        ],
        640,
        480,
      );
      expect(c.viewCount, 1);
    });
  });
}
