import 'package:flutter_test/flutter_test.dart';
import 'package:neom_vr/session/vr_visual_tracking_session.dart';
import 'package:neom_vr/session/vr_visual_marker_pose.dart';
import 'package:vrlizate_joystick/vrlizate_joystick.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'thermal pause is not absence and temporarily stops image analysis work',
    () {
      var now = 100000;
      final s = VrVisualTrackingSession(monotonicMicroseconds: () => now);
      addTearDown(s.dispose);
      s.setBodyDetectionEnabled(true);
      s.acceptResultForTesting({
        'status': 'thermal_backoff',
        'thermalStatus': 3,
        'retryAfterMs': 2000,
      });
      expect(s.inferenceCount, 0);
      expect(s.bodyResult!['status'], 'thermal_backoff');
      expect(s.hasAnalysisWork, isFalse);
      expect(s.pose, isNull);
      now += 1999999;
      expect(s.hasAnalysisWork, isFalse);
      now++;
      expect(s.hasAnalysisWork, isTrue);
      s.invalidateStream('camera closed');
      expect(s.bodyResult, isNull);
      expect(s.metricPoseReady, isFalse);
    },
  );
  test('QR and body consumers can be enabled independently', () {
    final s = VrVisualTrackingSession();
    addTearDown(s.dispose);
    s.setBodyDetectionEnabled(true);
    expect(s.enabled, isTrue);
    expect(s.markerDetectionEnabled, isFalse);
    expect(s.hasAnalysisWork, isTrue);
    s.setEnabled(true);
    s.setEnabled(false);
    expect(s.bodyDetectionEnabled, isTrue);
    expect(s.hasAnalysisWork, isTrue);
    s.setBodyDetectionEnabled(false);
    expect(s.enabled, isFalse);
    expect(s.hasAnalysisWork, isFalse);
  });
  test(
    'visor rejects raw weak landmarks and stops work without a consumer',
    () {
      var now = 0;
      final s = VrVisualTrackingSession(monotonicMicroseconds: () => now);
      addTearDown(s.dispose);
      s.setEnabled(true);
      expect(s.hasAnalysisWork, isFalse);
      s.setBodyDetectionEnabled(true);
      expect(s.hasAnalysisWork, isTrue);
      for (var frame = 0; frame < 4; frame++) {
        now = frame * 1000000;
        s.acceptResultForTesting({
          'status': 'ok',
          'imageWidth': 640,
          'imageHeight': 480,
          'pose': {
            'status': 'ok',
            'present': true,
            'landmarks': [
              for (var joint = 0; joint < 33; joint++)
                {
                  'type': joint,
                  'x': 320,
                  'y': 240,
                  'z': 0,
                  'inFrameLikelihood': .2,
                },
            ],
          },
        });
        expect(s.bodyResult!['present'], isFalse);
        expect(s.bodyResult!['landmarks'], isEmpty);
        expect(s.bodyResult!['rawLandmarkCount'], 33);
        expect(s.bodyResult!['acceptanceReason'], 'weak_torso');
      }
      expect(s.acceptedBodyProposals, 0);
      expect(s.rejectedBodyProposals, 4);
      s.setBodyDetectionEnabled(false);
      expect(s.hasAnalysisWork, isFalse);
      expect(s.bodyResult, isNull);
    },
  );
  test(
    'visor body inference exposes real absence and clears on camera loss',
    () {
      final s = VrVisualTrackingSession();
      addTearDown(s.dispose);
      s.setEnabled(true);
      s.setBodyDetectionEnabled(true);
      s.acceptResultForTesting({
        'status': 'ok',
        'imageWidth': 640,
        'imageHeight': 480,
        'markerStatus': 'ok',
        'markers': [],
        'pose': {'status': 'ok', 'present': false, 'landmarks': []},
      });
      expect(s.bodyResult!['present'], isFalse);
      expect(s.bodyResult!['landmarks'], isEmpty);
      s.invalidateStream('camera closed');
      expect(s.bodyResult, isNull);
      expect(s.metricPoseReady, isFalse);
    },
  );
  const id = 'vrlizate-marker-v1:0123456789abcdef';
  test(
    'metric QR output requires scale verification and a fresh observation',
    () {
      var now = 0;
      final session = VrVisualTrackingSession(monotonicMicroseconds: () => now);
      addTearDown(session.dispose);
      session.setMarkerConfiguration(
        const VrTrackingMarkerConfiguration(markerId: id, widthMeters: .2),
      );
      session.setEnabled(true);
      const k = VrMarkerFrameCalibration(
        fx: 800,
        fy: 830,
        cx: 635,
        cy: 475,
        skew: 2,
      );
      void observe(vm.Matrix4 transform) {
        final points = [
          vm.Vector3(-.1, -.1, 0),
          vm.Vector3(.1, -.1, 0),
          vm.Vector3(.1, .1, 0),
          vm.Vector3(-.1, .1, 0),
        ].map((point) => k.project(transform.transformed3(point))).toList();
        session.acceptResultForTesting({
          'status': 'ok',
          'imageWidth': 1280,
          'imageHeight': 960,
          'markers': [
            {
              'rawValue': id,
              'orientationVerified': true,
              'corners': points.map((p) => {'x': p.x, 'y': p.y}).toList(),
            },
          ],
        });
      }

      const ax = [-.4, .3, .45, -.25, .1, .35, -.3, .42, -.38, .2, -.15, .35];
      const ay = [-.3, .4, -.2, .35, .3, -.4, .45, .15, -.2, -.35, .35, -.3];
      for (var i = 0; i < ax.length; i++) {
        observe(
          vm.Matrix4.identity()
            ..translateByDouble(
              (i % 4 - 1.5) * .09,
              (i ~/ 4 - 1) * .09,
              .5 + (i % 3) * .07,
              1,
            )
            ..rotateZ((i % 3 - 1) * .15)
            ..rotateY(ay[i])
            ..rotateX(ax[i]),
        );
        session.captureCalibrationView();
      }
      session.calibrate();
      expect(session.metricCameraMarkerTranslation, isNull);
      observe(vm.Matrix4.identity()..translateByDouble(.02, .03, .7, 1));
      expect(session.metricCameraMarkerTranslation, isNull);
      session.validateMeasuredDistance(vm.Vector3(.02, .03, .7).length);
      final before = session.metricCameraMarkerTranslation!;
      expect(before.y, closeTo(.03, 1e-4));
      before.y = 50;
      expect(session.metricCameraMarkerTranslation!.y, closeTo(.03, 1e-4));
      // A 10 cm rise is -Y in the CV frame, not a change in visor eye height.
      observe(vm.Matrix4.identity()..translateByDouble(.02, -.07, .7, 1));
      expect(session.metricCameraMarkerTranslation!.y, closeTo(-.07, 1e-4));
      expect(
        session.controllerPositionStatus,
        contains('falta calibrar montaje'),
      );
      now += 1000000;
      expect(session.metricCameraMarkerTranslation, isNull);
      expect(session.controllerPositionStatus, contains('QR fuera de cámara'));
      session.invalidateStream('camera changed');
      expect(session.metricCameraMarkerTranslation, isNull);
      expect(session.profile, isNull);
      expect(session.lastCalibrationResetReason, 'camera changed');
      expect(session.calibrationResetCount, 1);
    },
  );
  Map<String, dynamic> frame(String markerId) => {
    'status': 'ok',
    'imageWidth': 640,
    'imageHeight': 480,
    'inferenceMs': 12.3,
    'markers': [
      {
        'rawValue': markerId,
        'corners': [
          {'x': 200, 'y': 150},
          {'x': 300, 'y': 150},
          {'x': 300, 'y': 250},
          {'x': 200, 'y': 250},
        ],
      },
    ],
  };
  test(
    'reset diagnostics retain actual loss instead of subsequent empty invalidations',
    () {
      final session = VrVisualTrackingSession(
        monotonicMicroseconds: () => 100000,
      );
      addTearDown(session.dispose);
      session.setEnabled(true);
      session.setMarkerConfiguration(
        const VrTrackingMarkerConfiguration(markerId: id),
      );
      session.invalidateStream('initial empty stream');
      session.resetCalibration();
      expect(session.lastCalibrationResetReason, isNull);
      expect(session.calibrationResetCount, 0);

      session.acceptResultForTesting(frame(id));
      session.captureCalibrationView();
      expect(session.calibrationViews, 1);
      session.invalidateStream('Cámara cerrada; requiere calibración');
      expect(session.calibrationViews, 0);
      expect(session.profile, isNull);
      expect(
        session.lastCalibrationResetReason,
        'Cámara cerrada; requiere calibración',
      );
      expect(session.calibrationResetCount, 1);

      // A reopened camera's first frame must not overwrite the true loss cause.
      session.invalidateStream('Geometría nueva; requiere calibración');
      expect(
        session.lastCalibrationResetReason,
        'Cámara cerrada; requiere calibración',
      );
      expect(session.calibrationResetCount, 1);
      session.acceptResultForTesting(frame(id));
      session.captureCalibrationView();
      expect(session.calibrationViews, 1);
      expect(session.calibrationResetCount, 1);
      expect(
        session.lastCalibrationResetReason,
        'Cámara cerrada; requiere calibración',
      );
      session.resetCalibration();
      expect(
        session.lastCalibrationResetReason,
        'Reinicio manual de calibración',
      );
      expect(session.calibrationResetCount, 2);
      expect(session.calibrationViews, 0);
      session.resetCalibration();
      expect(session.calibrationResetCount, 2);
      expect(
        session.lastCalibrationResetReason,
        'Reinicio manual de calibración',
      );
    },
  );

  test(
    'failed capture or K fit does not register or perform calibration loss',
    () {
      final session = VrVisualTrackingSession(
        monotonicMicroseconds: () => 100000,
      );
      addTearDown(session.dispose);
      session.setEnabled(true);
      session.setMarkerConfiguration(
        const VrTrackingMarkerConfiguration(markerId: id),
      );
      expect(
        session.captureCalibrationView,
        throwsA(isA<VrVisualMarkerPoseException>()),
      );
      session.acceptResultForTesting(frame(id));
      session.captureCalibrationView();
      expect(session.calibrate, throwsA(isA<VrVisualMarkerPoseException>()));
      expect(session.calibrationViews, 1);
      session.acceptResultForTesting({
        'status': 'ok',
        'imageWidth': 640,
        'imageHeight': 480,
        'markers': [],
      });
      expect(
        session.captureCalibrationView,
        throwsA(isA<VrVisualMarkerPoseException>()),
      );
      expect(session.calibrationViews, 1);
      expect(session.lastCalibrationResetReason, isNull);
      expect(session.calibrationResetCount, 0);
    },
  );

  test('QR TTL starts before inference and late replies cannot renew it', () {
    var now = 100;
    final session = VrVisualTrackingSession(monotonicMicroseconds: () => now);
    addTearDown(session.dispose);
    session.setEnabled(true);
    session.setMarkerConfiguration(
      const VrTrackingMarkerConfiguration(markerId: id),
    );
    final sampledAtUs = now;
    now += 900000;
    session.acceptResultForTesting(frame(id), sampledAtUs: sampledAtUs);
    expect(session.markerVisible, isTrue);
    now = sampledAtUs + 999999;
    expect(session.markerVisible, isTrue);
    now++;
    expect(session.markerVisible, isFalse);
    expect(session.metricCameraMarkerTranslation, isNull);
    // An older inference reply is not a newly captured observation.
    session.acceptResultForTesting(frame(id), sampledAtUs: sampledAtUs);
    expect(session.markerVisible, isFalse);
    expect(session.status, 'Observación QR caducada');
    session.acceptResultForTesting(frame(id), sampledAtUs: now + 1);
    expect(session.markerVisible, isFalse);
    // A genuinely new capture can recover without resetting the opt-in.
    session.acceptResultForTesting(frame(id), sampledAtUs: now);
    expect(session.markerVisible, isTrue);
    expect(session.hasAnalysisWork, isTrue);
  });

  test(
    'only a paired public marker is accepted; a detection cannot create metres',
    () {
      final s = VrVisualTrackingSession();
      addTearDown(s.dispose);
      s.acceptResultForTesting(frame(id));
      expect(s.markerVisible, isFalse);
      s.setMarkerConfiguration(
        const VrTrackingMarkerConfiguration(markerId: id),
      );
      s.acceptResultForTesting(frame('vrlizate-marker-v1:ffffffffffffffff'));
      expect(s.markerVisible, isFalse);
      s.acceptResultForTesting(frame(id));
      expect(s.markerVisible, isTrue);
      expect(s.metricPoseReady, isFalse);
      expect(s.pose, isNull);
      s.captureCalibrationView();
      expect(s.calibrationViews, 1);
      expect(s.calibrate, throwsA(isA<VrVisualMarkerPoseException>()));
      expect(
        () => s.validateMeasuredDistance(.5),
        throwsA(isA<VrVisualMarkerPoseException>()),
      );
      s.invalidateStream('closed');
      expect(s.markerVisible, isFalse);
      expect(s.calibrationViews, 0);
    },
  );
  test(
    'lost reference and replacement link invalidate current observations',
    () {
      final s = VrVisualTrackingSession();
      addTearDown(s.dispose);
      s.setMarkerConfiguration(
        const VrTrackingMarkerConfiguration(markerId: id, widthMeters: .07),
      );
      s.acceptResultForTesting(frame(id));
      expect(s.markerVisible, isTrue);
      s.acceptResultForTesting({
        'status': 'ok',
        'imageWidth': 640,
        'imageHeight': 480,
        'markers': [],
      });
      expect(s.markerVisible, isFalse);
      expect(s.pose, isNull);
      s.acceptResultForTesting(frame(id));
      s.setMarkerConfiguration(null);
      expect(s.markerVisible, isFalse);
      expect(s.metricPoseReady, isFalse);
    },
  );
  test(
    'mirrored front detections cannot certify orientation or calibration',
    () {
      final s = VrVisualTrackingSession();
      addTearDown(s.dispose);
      s.setMarkerConfiguration(
        const VrTrackingMarkerConfiguration(markerId: id, widthMeters: .07),
      );
      final result = frame(id);
      (result['markers'] as List).single['orientationVerified'] = true;
      result['mirrored'] = true;
      s.acceptResultForTesting(result);
      expect(s.markerVisible, isTrue);
      expect(s.orientationVerified, isFalse);
      expect(s.metricPoseReady, isFalse);
      expect(s.pose, isNull);
      expect(
        s.captureCalibrationView,
        throwsA(
          isA<VrVisualMarkerPoseException>().having(
            (e) => e.reason,
            'reason',
            'mirrored_frame_calibration_not_supported',
          ),
        ),
      );
      expect(s.calibrationViews, 0);
      s.acceptResultForTesting(frame(id));
      s.captureCalibrationView();
      expect(s.calibrationViews, 1);
    },
  );
}
