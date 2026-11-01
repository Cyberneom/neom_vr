import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neom_vr/neom_vr_ai.dart';
import 'package:neom_vr/neom_vr_sessions.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate/vrlizate.dart'
    show VrCompactGamepadFrame, VrRemoteBinaryCodec, VrRemotePoseFrame;
import 'package:vrlizate_joystick/vrlizate_joystick.dart';

class _FakeUptimeWebcamPlatform implements VrDesktopVisionPlatform {
  final StreamController<VrDesktopVisionFrame> _controller =
      StreamController<VrDesktopVisionFrame>.broadcast();
  bool capturing = false;

  @override
  Stream<VrDesktopVisionFrame> get frames => _controller.stream;

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<Map<String, dynamic>?> readCapabilities() async => const {
    'hasWebcam': true,
  };

  @override
  Future<bool> startCapture() async {
    capturing = true;
    return true;
  }

  @override
  Future<void> stopCapture() async {
    capturing = false;
  }

  void pushFrame(VrDesktopVisionFrame frame) {
    if (capturing && !_controller.isClosed) {
      _controller.add(frame);
    }
  }

  Future<void> dispose() => _controller.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test(
    'Native webcam frames with OS systemUptime epoch are never overwritten by syntheticVision',
    () async {
      final fakeCam = _FakeUptimeWebcamPlatform();
      var stationClockUs = 100000;
      final station = VrDesktopBeaconStation(
        visionPlatform: fakeCam,
        discoveryPort: 0,
        enableMediaVault: true,
        monotonicMicroseconds: () => stationClockUs,
      );
      addTearDown(() async {
        station.dispose();
        await fakeCam.dispose();
      });

      await station.start(enableWebcam: true);
      expect(station.webcamNativeActive, isTrue);

      // Simulate macOS ProcessInfo.systemUptime (~120 hours = 4.32e11 us)
      const osUptimeMicros = 432000000000;
      fakeCam.pushFrame(
        const VrDesktopVisionFrame(
          timestampMicros: osUptimeMicros,
          mirrored: true,
          inferenceMs: 9.4,
          nose: VrDesktopKeypoint2D(0.72, 0.30, 0.96),
          leftShoulder: VrDesktopKeypoint2D(0.58, 0.52, 0.95),
          rightShoulder: VrDesktopKeypoint2D(0.86, 0.52, 0.95),
          rightWrist: VrDesktopKeypoint2D(0.88, 0.22, 0.92),
          rightThumbTip: VrDesktopKeypoint2D(0.87, 0.18, 0.91),
          rightIndexTip: VrDesktopKeypoint2D(0.872, 0.182, 0.91),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      stationClockUs += 32000;
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(station.isNativeVisionLive, isTrue);
      expect(station.nativeVisionFramesReceived, 1);
      expect(station.latestVisionFrame?.timestampMicros, osUptimeMicros);
      expect(station.latestSolution, isNotNull);
      expect(station.latestSolution!.visorRoomPosition.x, greaterThan(0.05));

      // Verify /api/pose.json reports native_webcam telemetry
      final poseUri = station.mediaVault.lanBaseUri!.resolve('api/pose.json');
      final httpClient = HttpClient();
      addTearDown(() => httpClient.close(force: true));
      final req = await httpClient.getUrl(poseUri);
      final resp = await req.close();
      final body = await utf8.decodeStream(resp);
      final map = jsonDecode(body) as Map<String, dynamic>;
      expect(map['visionSource'], 'native_webcam');
      expect((map['webcamDetected'] as Map)['upperBody'], isTrue);
      expect((map['webcamDetected'] as Map)['rightHand'], isTrue);
    },
  );

  test(
    'Full 3D Set coordination: Joystick <-> PC Faro <-> Visor relays 120 Hz frames and control messages',
    () async {
      final station = VrDesktopBeaconStation(
        discoveryPort: 0,
        enableMediaVault: true,
      );
      final visorClient = VrDesktopBeaconClient(discoveryPort: 0);
      final visorRemote = VrRemoteControllerService();
      VrBeaconJoystickControllerLink? joystickLink;

      addTearDown(() async {
        await joystickLink?.close();
        visorRemote.dispose();
        visorClient.dispose();
        station.dispose();
      });

      await station.start(enableWebcam: false);
      final baseInvite = station.pairingInvite!;
      final loopbackInvite = VrDesktopBeaconPairingInvite(
        stationId: baseInvite.stationId,
        stationName: baseInvite.stationName,
        host: '127.0.0.1',
        port: baseInvite.port,
        pin: baseInvite.pin,
      );

      // 1. Connect Joystick (Moto Edge role) to PC 3D Set Coordinator
      final joyUri = loopbackInvite.toJoystickUri().toString();
      final parsedJoyInvite = VrDesktopBeaconPairingInvite.tryParse(joyUri)!;
      expect(parsedJoyInvite.isJoystickRole, isTrue);

      joystickLink = await VrBeaconJoystickControllerLink.connect(
        parsedJoyInvite,
      );
      expect(station.isDirectJoystickConnected, isTrue);

      // 2. Connect Visor (Galaxy S25 role) to PC Faro
      final visorOk = await visorClient.connectWithInvite(loopbackInvite);
      expect(visorOk, isTrue);
      expect(station.isVisorConnected, isTrue);

      // 3. Send binary pose packet from Joystick -> PC -> Visor
      const codec = VrRemoteBinaryCodec();
      final packet1 = codec.encodePose(
        VrRemotePoseFrame(
          sequence: 1,
          senderTimestampMicroseconds: 1000,
          orientation: vm.Quaternion.identity(),
          touchX: (0.65 + 1.0) * 0.5,
          touchY: (-0.40 + 1.0) * 0.5,
          buttonsBitset: 0x0001 | 0x0004,
        ),
      );
      joystickLink.add(packet1);

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(station.joystickFramesCoordinated, greaterThanOrEqualTo(1));
      expect(
        station.coordinatorJoystickMirror.latestState.stickX,
        closeTo(0.65, 0.02),
      );
      expect(visorClient.hasCoordinatedJoystick, isTrue);

      // Attach Visor's coordinatedControllerLink to Visor's VrRemoteControllerService
      final attached = visorRemote.attachControllerLink(
        visorClient.coordinatedControllerLink,
        sessionToken: visorRemote.sessionToken,
      );
      expect(attached, isTrue);

      // Track control messages arriving back on Joystick from Visor -> PC -> Joystick
      final incomingOnJoystick = <String>[];
      final joySub = joystickLink.messages.listen((msg) {
        if (msg is String) incomingOnJoystick.add(msg);
      });
      addTearDown(joySub.cancel);

      visorRemote.requestControllerMode(
        RemoteControllerMode.driving,
        actions: const {'A': 'Turbo'},
      );

      final packet2 = codec.encodePose(
        VrRemotePoseFrame(
          sequence: 2,
          senderTimestampMicroseconds: 9000,
          orientation: vm.Quaternion.identity(),
          touchX: (-0.75 + 1.0) * 0.5,
          touchY: (0.85 + 1.0) * 0.5,
          buttonsBitset: 0x0008,
        ),
      );
      joystickLink.add(packet2);

      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(visorRemote.latestState.stickX, closeTo(-0.75, 0.02));
      expect(visorRemote.latestState.stickY, closeTo(0.85, 0.02));
      expect(visorRemote.latestState.btnB, isTrue);
      expect(
        incomingOnJoystick.any((m) => m.contains('"driving"')),
        isTrue,
      );
    },
  );

  test(
    '68-byte VrCompactGamepadFrame (Smallest-Three quaternion) relays zero-JSON across Joystick -> PC -> Visor',
    () async {
      final station = VrDesktopBeaconStation(
        discoveryPort: 0,
        enableMediaVault: false,
      );
      final visorClient = VrDesktopBeaconClient(discoveryPort: 0);
      final visorRemote = VrRemoteControllerService();
      VrBeaconJoystickControllerLink? joystickLink;

      addTearDown(() async {
        await joystickLink?.close();
        visorRemote.dispose();
        visorClient.dispose();
        station.dispose();
      });

      await station.start(enableWebcam: false);
      final baseInvite = station.pairingInvite!;
      final loopbackInvite = VrDesktopBeaconPairingInvite(
        stationId: baseInvite.stationId,
        stationName: baseInvite.stationName,
        host: '127.0.0.1',
        port: baseInvite.port,
        pin: baseInvite.pin,
      );

      joystickLink = await VrBeaconJoystickControllerLink.connect(
        loopbackInvite,
      );
      expect(await visorClient.connectWithInvite(loopbackInvite), isTrue);
      expect(
        visorRemote.attachControllerLink(
          visorClient.coordinatedControllerLink,
          sessionToken: visorRemote.sessionToken,
        ),
        isTrue,
      );

      final compactFrame = VrCompactGamepadFrame(
        sequence: 1,
        senderTimestampMicroseconds: 17000,
        orientation: vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), 0.35),
        angularVelocity: vm.Vector3(0.4, -0.2, 0.0),
        stickX: 0.42,
        stickY: -0.68,
        lookX: -0.55,
        lookY: 0.25,
        laserX: 0.18,
        laserY: -0.12,
        laserSlideActive: true,
        trigger: true,
        btnA: true,
        passthroughActive: true,
        passthroughMix: 0.50,
      );
      final encodedRelay = VrDesktopBeaconWire.encodeAuthenticatedRelayFrame(
        kind: VrDesktopBeaconWire.joystickControllerFrameKind,
        key: List<int>.filled(32, 7),
        frame: compactFrame,
      )!;
      expect(
        encodedRelay.length,
        VrDesktopBeaconWire.compactGamepadPacketBytes,
      );
      expect(encodedRelay.length, 68);

      joystickLink.add(compactFrame);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(joystickLink.compactBinaryFramesSent, 1);
      expect(station.compactJoystickFramesCoordinated, 1);
      expect(visorRemote.latestState.stickX, closeTo(0.42, 0.01));
      expect(visorRemote.latestState.stickY, closeTo(-0.68, 0.01));
      expect(visorRemote.latestState.turnRate, closeTo(-0.55, 0.01));
      expect(visorRemote.latestState.laserSlideActive, isTrue);
      expect(visorRemote.latestState.laserX, closeTo(0.18, 0.01));
      expect(visorRemote.latestState.isTriggerPressed, isTrue);
      expect(visorRemote.latestState.btnA, isTrue);
      expect(visorRemote.latestState.passthroughMix, closeTo(0.50, 0.02));
    },
  );

  test(
    'VrBeaconDeadReckoningGate suppresses >80% redundant 62.5 Hz packets and extrapolates 120 Hz hands',
    () {
      final gate = VrBeaconDeadReckoningGate();

      VrTriNodeDepthSolution buildSample({
        required int seq,
        required int tsUs,
        required vm.Vector3 head,
        required vm.Vector3 rightHand,
        required vm.Vector3 rightVel,
        VrBeaconHandGesture gesture = VrBeaconHandGesture.none,
      }) => VrTriNodeDepthSolution(
        timestampMicros: tsUs,
        sequence: seq,
        computerToVisorMeters: 1.48,
        computerToJoystickMeters: 1.22,
        visorToJoystickMeters: 0.44,
        visorRoomPosition: head,
        joystickRoomPosition: vm.Vector3(0.1, 1.05, -0.2),
        deskClearanceMeters: 1.48,
        visorAzimuthRadians: 0.0,
        yawAnchorCorrectionRadians: 0.0,
        leftHandRelHead: vm.Vector3(-0.2, -0.25, -0.45),
        rightHandRelHead: rightHand,
        rightHandVelocity: rightVel,
        leftHandConfidence: 0.85,
        rightHandConfidence: 0.92,
        leftHandRaised: false,
        rightHandRaised: true,
        leftPinchStrength: 0.0,
        rightPinchStrength: 0.0,
        gesture: gesture,
        confidence: 0.90,
      );

      // Simulate 1.0 second at 62.5 Hz (62 ticks of 16 ms) while user is stationary
      var sent = 0;
      for (var i = 0; i < 62; i++) {
        final tUs = 1000000 + i * 16000;
        final s = buildSample(
          seq: i + 1,
          tsUs: tUs,
          head: vm.Vector3(0.0, 1.60, 0.0),
          rightHand: vm.Vector3(0.22, -0.10, -0.48),
          rightVel: vm.Vector3.zero(),
        );
        if (gate.shouldTransmit(s, nowMicros: tUs)) {
          sent++;
        }
      }
      // 62 ticks at 16ms -> only initial + ~6 sync heartbeats (160ms) = 7 packets!
      expect(sent, lessThanOrEqualTo(8));
      expect(gate.suppressionRatio, greaterThan(0.84));

      // Sudden hand movement of +4 cm immediately passes the gate on the very next tick!
      final suddenUs = 1000000 + 62 * 16000;
      final sudden = buildSample(
        seq: 63,
        tsUs: suddenUs,
        head: vm.Vector3(0.0, 1.60, 0.0),
        rightHand: vm.Vector3(0.26, -0.10, -0.48),
        rightVel: vm.Vector3(0.80, 0.0, 0.0),
      );
      expect(gate.shouldTransmit(sudden, nowMicros: suddenUs), isTrue);

      // Receiver side: ingest sudden packet and predict 8.33 ms later (120 Hz intermediate frame)
      gate.ingestReceived(sudden, receivedAtMicros: suddenUs);
      final pred120Hz = gate.predictAt(suddenUs + 8333)!;
      expect(pred120Hz.rightHandRelHead.x, greaterThan(0.265));
      expect(pred120Hz.rightHandRelHead.x, lessThan(0.275));
    },
  );

  test(
    'Estación Faro preserves stationId/PIN across restarts and Joystick + Visor recover without mutual timeout deadlock',
    () async {
      final station1 = VrDesktopBeaconStation(
        discoveryPort: 0,
        enableMediaVault: false,
        initialStationId: 'faro_sync_test',
        initialPin: '130315',
      );
      await station1.start(enableWebcam: false);
      final invite1 = station1.pairingInvite!;
      expect(invite1.stationId, 'faro_sync_test');
      expect(invite1.pin, '130315');

      var visorClockUs = 1000000;
      final visorClient = VrDesktopBeaconClient(
        discoveryPort: 0,
        monotonicMicroseconds: () => visorClockUs,
      );
      addTearDown(visorClient.dispose);

      final loopbackInvite = VrDesktopBeaconPairingInvite(
        stationId: invite1.stationId,
        stationName: invite1.stationName,
        host: '127.0.0.1',
        port: invite1.port,
        pin: invite1.pin,
      );
      expect(await visorClient.connectWithInvite(loopbackInvite), isTrue);
      expect(visorClient.rememberedInvite?.stationId, 'faro_sync_test');

      // Advance simulated Visor clock past 5 seconds (>4.5s old timeout) while
      // station1 continues sending 1 Hz keepalives: link MUST stay connected
      // and recover immediately without mutual silence deadlock!
      visorClockUs += 5200000;
      await Future<void>.delayed(const Duration(milliseconds: 1150));
      expect(visorClient.isConnected, isTrue);
      expect(station1.isVisorConnected, isTrue);

      station1.dispose();

      // Restart Estación Faro on a brand-new UDP port with the same stationId & PIN
      final station2 = VrDesktopBeaconStation(
        discoveryPort: 0,
        enableMediaVault: false,
        initialStationId: 'faro_sync_test',
        initialPin: '130315',
      );
      addTearDown(station2.dispose);
      await station2.start(enableWebcam: false);
      expect(station2.pairingInvite!.stationId, 'faro_sync_test');
      expect(station2.pairingInvite!.pin, '130315');

      final joyInvite2 = VrDesktopBeaconPairingInvite(
        stationId: 'faro_sync_test',
        stationName: station2.stationName,
        host: '127.0.0.1',
        port: station2.boundPort!,
        pin: '130315',
        role: 'joystick',
      );
      final joyLink = await VrBeaconJoystickControllerLink.connect(joyInvite2);
      addTearDown(joyLink.close);
      expect(station2.isDirectJoystickConnected, isTrue);
    },
  );

  test(
    'Hands-free facial expressions pack into 140-byte VRB1 datagram with 0-latency pass-through and Estación Faro relays Spanish voice commands over HMAC UDP',
    () async {
      final station = VrDesktopBeaconStation(
        discoveryPort: 0,
        enableMediaVault: false,
      );
      final visorClient = VrDesktopBeaconClient(discoveryPort: 0);
      addTearDown(() {
        visorClient.dispose();
        station.dispose();
      });

      await station.start(enableWebcam: false);
      final invite = station.pairingInvite!;
      final loopbackInvite = VrDesktopBeaconPairingInvite(
        stationId: invite.stationId,
        stationName: invite.stationName,
        host: '127.0.0.1',
        port: invite.port,
        pin: invite.pin,
      );
      expect(await visorClient.connectWithInvite(loopbackInvite), isTrue);

      final receivedVoices = <VrBeaconVoiceCommandPacket>[];
      final voiceSub = visorClient.voiceCommands.listen(receivedVoices.add);
      addTearDown(voiceSub.cancel);

      // 1) Pulse eyebrowsRaised on Estación Faro -> verify immediate 140-byte VRB1 delivery
      station.pulseSimulatedFacialExpression(VrFacialExpression.eyebrowsRaised);
      await Future<void>.delayed(const Duration(milliseconds: 65));
      expect(
        visorClient.latestSolution?.facialExpression,
        VrFacialExpression.eyebrowsRaised,
      );
      expect(
        visorClient.latestSolution?.facialConfidence ?? 0.0,
        greaterThan(0.85),
      );

      // 2) Submit natural Spanish voice commands on Estación Faro -> verify HMAC relay & deduplication
      final mallGuidance = station.submitVoiceCommand('Abre Plaza Artz');
      expect(mallGuidance.actionType, ItzliActionType.launchExperience);
      expect(mallGuidance.targetDemoId, 'mall_plaza_artz_mx');

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(receivedVoices, hasLength(1));
      expect(receivedVoices.single.transcript, 'Abre Plaza Artz');

      // 3) Verify Itzli Spanish locomotion, world & UI routing without Joystick
      final itzli = ItzliVrAssistant();
      final walk = itzli.interpretRequest('camina hacia adelante bastante');
      expect(walk.actionType, ItzliActionType.moveInSpace);
      expect(walk.motionKind, VrVoiceMotionKind.walkForward);
      expect(walk.motionDurationSeconds, closeTo(4.0, 0.01));

      final turn = itzli.interpretRequest('date media vuelta');
      expect(turn.actionType, ItzliActionType.moveInSpace);
      expect(turn.motionKind, VrVoiceMotionKind.turnAround);

      final stop = itzli.interpretRequest('detente');
      expect(stop.actionType, ItzliActionType.moveInSpace);
      expect(stop.motionKind, VrVoiceMotionKind.stop);

      final menuOpen = itzli.interpretRequest('abre el menú');
      expect(menuOpen.actionType, ItzliActionType.uiCommand);
      expect(menuOpen.uiCommand, VrVoiceUiCommand.openMenu);

      final solar = itzli.interpretRequest('llévame a Ciudad Solar');
      expect(solar.actionType, ItzliActionType.launchExperience);
      expect(solar.targetDemoId, 'ecosystems_solar_city');

      // 4) Verify Visor IMU head-nod fusion when webcam face is occluded (neutral)
      final solver = VrTriNodeDepthSolver();
      final pitches = [0.0, 0.12, -0.10, 0.13, -0.09, 0.11, 0.0];
      VrTriNodeDepthSolution? fused;
      for (var i = 0; i < pitches.length; i++) {
        final q = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), pitches[i]);
        fused = solver.solve(
          nowMicros: 100000 + i * 45000,
          vision: null,
          visorFeedback: VrVisorBeaconFeedback(
            timestampMicros: 100000 + i * 45000,
            visorOrientation: q,
          ),
        );
      }
      expect(fused?.facialExpression, VrFacialExpression.headNod);
    },
  );
}
