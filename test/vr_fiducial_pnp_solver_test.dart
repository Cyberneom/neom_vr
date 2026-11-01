import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:neom_vr/neom_vr_sessions.dart';
import 'package:vector_math/vector_math.dart' as vm;

List<VrDesktopKeypoint2D> _projectSquareMarker({
  required vm.Vector3 translationCameraMeters,
  required vm.Quaternion rotationCameraFromMarker,
  required double markerSizeMeters,
  required int widthPx,
  required int heightPx,
  required double horizontalFovDeg,
  required bool mirrored,
}) {
  final halfTanX = math.tan((horizontalFovDeg * math.pi / 180.0) * 0.5);
  final fx = (widthPx * 0.5) / halfTanX;
  final half = markerSizeMeters * 0.5;
  final localCorners = <vm.Vector3>[
    vm.Vector3(-half, -half, 0),
    vm.Vector3(half, -half, 0),
    vm.Vector3(half, half, 0),
    vm.Vector3(-half, half, 0),
  ];
  final out = <VrDesktopKeypoint2D>[];
  for (final lc in localCorners) {
    final pCam =
        rotationCameraFromMarker.rotated(lc) + translationCameraMeters;
    final px = fx * (pCam.x / pCam.z) + widthPx * 0.5;
    final py = fx * (pCam.y / pCam.z) + heightPx * 0.5;
    final uUnmirrored = px / widthPx;
    final u = mirrored ? (1.0 - uUnmirrored) : uUnmirrored;
    out.add(VrDesktopKeypoint2D(u, py / heightPx, 1.0));
  }
  return out;
}

void main() {
  test('VrFiducialTagCodec parses URIs and emits exact 1:1 mm QR SVG & sheet', () {
    final visor = VrFiducialTagCodec.defaultVisorTag;
    expect(visor.toUri().toString(), 'vrlizate://tag?node=visor&mm=48');
    final parsed = VrFiducialTagSpec.tryParse('vrlizate://tag?node=visor&mm=48');
    expect(parsed?.node, VrFiducialNodeKind.visor);
    expect(parsed?.markerSizeMeters, closeTo(0.048, 1e-6));

    expect(VrFiducialTagSpec.tryParse('https://example.com'), isNull);
    expect(
      VrFiducialTagSpec.tryParse('vrlizate://tag?node=visor&mm=5'),
      isNull,
    );

    final svg = VrFiducialTagCodec.buildExactQrSvg(
      data: visor.toUri().toString(),
      sizeMm: 48.0,
    );
    expect(svg, contains('width="48.0mm" height="48.0mm"'));

    final html = VrFiducialTagCodec.buildPrintableSheetHtml(
      stationName: 'Estación Test',
    );
    expect(html, contains('vrlizate://tag?node=visor&mm=48'));
    expect(html, contains('vrlizate://tag?node=joystick&mm=38'));
    expect(html, contains('50 mm'));
  });

  test(
    'VrTriNodeDepthSolver recovers Visor and Joystick 6-DoF positions within < 3 mm and encodes VRB1 wire',
    () {
      final solver = VrTriNodeDepthSolver(
        webcamHorizontalFovDeg: 68.0,
        nominalStandingDistanceMeters: 1.50,
        deskCameraHeightMeters: 1.18,
      );

      // Ground-truth user room coordinates:
      // User stepped +0.22 m right, eye height 1.61 m, leaned 0.24 m toward desk (z = -0.24, Z_cam = 1.26 m).
      const trueVisorX = 0.220;
      const trueVisorY = 1.610;
      const trueVisorZ = -0.240;
      final tVisorCam = vm.Vector3(
        -trueVisorX,
        1.18 - trueVisorY,
        1.50 + trueVisorZ,
      );
      final qVisor = vm.Quaternion.euler(0.24, 0.14, -0.05); // tilted 6-DoF head

      const trueJoyX = 0.340;
      const trueJoyY = 1.260;
      const trueJoyZ = -0.620;
      final tJoyCam = vm.Vector3(
        -trueJoyX,
        1.18 - trueJoyY,
        1.50 + trueJoyZ,
      );
      final qJoy = vm.Quaternion.euler(-0.18, 0.20, 0.08);

      final visorCorners = _projectSquareMarker(
        translationCameraMeters: tVisorCam,
        rotationCameraFromMarker: qVisor,
        markerSizeMeters: 0.048,
        widthPx: 1280,
        heightPx: 720,
        horizontalFovDeg: 68.0,
        mirrored: false,
      );
      final joyCorners = _projectSquareMarker(
        translationCameraMeters: tJoyCam,
        rotationCameraFromMarker: qJoy,
        markerSizeMeters: 0.038,
        widthPx: 1280,
        heightPx: 720,
        horizontalFovDeg: 68.0,
        mirrored: false,
      );

      // Include realistic 63.6 mm interocular keypoints at Z_cam = 1.26 m to test Auto-IPD.
      final halfTanX = math.tan((68.0 * math.pi / 180.0) * 0.5);
      final focalNormX = 0.5 / halfTanX;
      const trueIpd = 0.0636;
      final centerNormU = 0.5 + (trueVisorX / tVisorCam.z) * focalNormX;
      final halfEyeSpan = 0.5 * focalNormX * trueIpd / tVisorCam.z;
      // Convert user-aligned normU back to unmirrored u = 1.0 - normU.
      final frame = VrDesktopVisionFrame.fromPlatformMap({
        'status': 'ok',
        'timestampMicros': 100000,
        'mirrored': false,
        'frameWidth': 1280,
        'frameHeight': 720,
        'nose': {'u': 1.0 - centerNormU, 'v': 0.34, 'c': 0.98},
        'leftEye': {
          'u': 1.0 - (centerNormU - halfEyeSpan),
          'v': 0.32,
          'c': 0.97,
        },
        'rightEye': {
          'u': 1.0 - (centerNormU + halfEyeSpan),
          'v': 0.32,
          'c': 0.97,
        },
        'fiducialTags': [
          {
            'payload': 'vrlizate://tag?node=visor&mm=48',
            'frameWidth': 1280,
            'frameHeight': 720,
            'corners': [for (final c in visorCorners) c.toJson()],
          },
          {
            'payload': 'vrlizate://tag?node=joystick&mm=38',
            'frameWidth': 1280,
            'frameHeight': 720,
            'corners': [for (final c in joyCorners) c.toJson()],
          },
        ],
      })!;

      final sol = solver.solve(nowMicros: 100000, vision: frame);
      expect(sol.visorFiducialLocked, isTrue);
      expect(sol.joystickFiducialLocked, isTrue);
      expect(
        sol.activeModalitiesMask & VrTriNodeDepthSolution.modalityFiducialPnp,
        isNonZero,
      );
      expect((sol.visorRoomPosition.x - trueVisorX).abs(), lessThan(0.003));
      expect((sol.visorRoomPosition.y - trueVisorY).abs(), lessThan(0.003));
      expect((sol.visorRoomPosition.z - trueVisorZ).abs(), lessThan(0.003));
      expect((sol.computerToVisorMeters - tVisorCam.length).abs(), lessThan(0.003));

      expect((sol.joystickRoomPosition.x - trueJoyX).abs(), lessThan(0.003));
      expect((sol.joystickRoomPosition.y - trueJoyY).abs(), lessThan(0.003));
      expect((sol.joystickRoomPosition.z - trueJoyZ).abs(), lessThan(0.003));

      expect(sol.estimatedUserIpdMeters, isNotNull);
      expect((sol.estimatedUserIpdMeters! - trueIpd).abs(), lessThan(0.001));

      // Verify 140-byte VRB1 UDP binary round-trip preserves PnP lock & IPD!
      final key = List<int>.generate(32, (i) => i + 7);
      final datagram = VrDesktopBeaconWire.encodeBeaconState(
        sessionKey: key,
        solution: sol,
      );
      expect(datagram.length, VrDesktopBeaconWire.beaconStatePacketBytes);
      final decoded = VrDesktopBeaconWire.decodeBeaconState(
        sessionKey: key,
        datagram: datagram,
      )!;
      expect(decoded.visorFiducialLocked, isTrue);
      expect(decoded.joystickFiducialLocked, isTrue);
      expect(decoded.estimatedUserIpdMeters, closeTo(trueIpd, 0.0003));
    },
  );

  test(
    'Synthetic mirrored fiducial tag locks < 3 mm and self-calibrates personal shoulder scale',
    () {
      final solver = VrTriNodeDepthSolver();
      final gen = VrSyntheticDesktopVisionGenerator()
        ..simulatedDistanceMeters = 1.32
        ..simulatedLateralMeters = -0.15
        ..simulateFiducialTag = true;

      VrTriNodeDepthSolution? last;
      for (var step = 1; step <= 8; step++) {
        final f = gen.sample(step * 16000);
        last = solver.solve(nowMicros: step * 16000, vision: f);
      }
      expect(last!.visorFiducialLocked, isTrue);
      expect(last.visorRoomPosition.x, closeTo(-0.15, 0.003));
      expect(last.visorRoomPosition.z, closeTo(1.32 - 1.50, 0.003));
      expect(last.estimatedUserIpdMeters, closeTo(0.064, 0.0015));
      expect(solver.calibratedShoulderScale, isNot(equals(1.0)));
    },
  );

  test('VrDesktopMediaVaultServer serves printable 1:1 mm tags at /<token>/tags', () async {
    final tempDir = await Directory.systemTemp.createTemp('vrlizate_tags_test_');
    final vault = VrDesktopMediaVaultServer(
      stationName: 'Mac Faro PnP',
      vaultDirectoryPath: tempDir.path,
    );
    addTearDown(() async {
      await vault.stop();
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    await vault.start(preferredLanHost: '127.0.0.1');
    final tagsUri = vault.localPrintableTagsUri!;
    final res = await http.get(tagsUri);
    expect(res.statusCode, 200);
    expect(res.body, contains('vrlizate://tag?node=visor&mm=48'));
    expect(res.body, contains('50 mm'));

    final forbidden = await http.get(
      Uri.parse('http://127.0.0.1:${vault.boundPort}/wrong_token/tags'),
    );
    expect(forbidden.statusCode, 403);
  });

  test(
    'AI palm-scale metric depth projects hands into ergonomic [-0.92, -0.48] m and gates Auto-IPD when wearing headset',
    () {
      final solver = VrTriNodeDepthSolver(
        webcamHorizontalFovDeg: 68.0,
        nominalStandingDistanceMeters: 1.50,
        deskCameraHeightMeters: 1.18,
      );

      // Simulate headset-wearing user (eyesFromFaceLandmarks: false, inferenceMs != null)
      // with drifted head yaw (0.95 rad) and extended hand at ~0.85 m from webcam
      // (palmSpanNorm = focalNormX * 0.094 / 0.85 ≈ 0.082).
      final feedback = VrVisorBeaconFeedback(
        timestampMicros: 50000,
        visorOrientation: vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), 0.95),
      );

      final webcamFrame = VrDesktopVisionFrame.fromPlatformMap({
        'status': 'ok',
        'timestampMicros': 60000,
        'mirrored': false,
        'inferenceMs': 8.2,
        'eyesFromFaceLandmarks': false,
        'nose': {'u': 0.50, 'v': 0.34, 'c': 0.90},
        // Coarse body eyes under headset plastic (must NOT corrupt IPD to 50 mm!)
        'leftEye': {'u': 0.49, 'v': 0.33, 'c': 0.85},
        'rightEye': {'u': 0.51, 'v': 0.33, 'c': 0.85},
        'leftShoulder': {'u': 0.39, 'v': 0.52, 'c': 0.92},
        'rightShoulder': {'u': 0.61, 'v': 0.52, 'c': 0.92},
        'rightWrist': {'u': 0.36, 'v': 0.44, 'c': 0.91},
        'rightThumbTip': {'u': 0.38, 'v': 0.40, 'c': 0.89},
        'rightIndexTip': {'u': 0.34, 'v': 0.36, 'c': 0.92},
        'rightPalmSpan': 0.082,
        'rightExtendedFingers': 5,
      })!;

      VrTriNodeDepthSolution? sol;
      for (var step = 1; step <= 4; step++) {
        sol = solver.solve(
          nowMicros: 60000 + step * 16000,
          vision: webcamFrame,
          visorFeedback: feedback,
        );
      }

      expect(sol!.estimatedUserIpdMeters, isNull);
      expect(sol.rightHandConfidence, greaterThan(0.50));
      // Hand is projected at ergonomic stereo depth (never -0.20 m "muy pegado")!
      expect(sol.rightHandRelHead.z, lessThanOrEqualTo(-0.48));
      expect(sol.rightHandRelHead.z, greaterThanOrEqualTo(-0.92));
    },
  );
}
