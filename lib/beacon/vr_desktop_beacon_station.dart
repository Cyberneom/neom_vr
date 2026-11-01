import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:vrlizate/vrlizate.dart'
    show VrCompactGamepadFrame, VrRemoteBinaryCodec, VrRemotePoseFrame;
import 'package:vrlizate_cast/vrlizate_cast.dart';
import 'package:vrlizate_joystick/vrlizate_joystick.dart';

import '../ai/itzli_vr_assistant.dart';
import 'vr_beacon_dead_reckoning.dart';
import 'vr_beacon_joystick_link.dart';
import 'vr_desktop_autonomous_bridge.dart';
import 'vr_desktop_beacon_models.dart';
import 'vr_desktop_beacon_wire.dart';
import 'vr_desktop_capabilities.dart';
import 'vr_desktop_media_vault.dart';
import 'vr_desktop_vision_platform.dart';
import 'vr_tri_node_depth_solver.dart';

/// Runs inside VRlizate Desktop to turn a personal computer into an
/// **Estación Faro** (3rd spatial sensor & AI pose node) that elevates the
/// tracking quality of a smartphone Visor running `.vrlz` experiences.
class VrDesktopBeaconStation extends ChangeNotifier {
  VrDesktopBeaconStation({
    VrDesktopVisionPlatform? visionPlatform,
    VrDesktopVoicePlatform? voicePlatform,
    VrDesktopCapabilities? desktopCapabilities,
    this.stationName = 'VRlizate Desktop Faro',
    this.discoveryPort = VrDesktopBeaconWire.defaultDiscoveryPort,
    int? bindPort,
    String? initialStationId,
    String? initialPin,
    this.vaultDirectoryPath,
    this.enableMediaVault = true,
    int Function()? monotonicMicroseconds,
  }) : _vision = visionPlatform ?? MethodChannelVrDesktopVisionPlatform(),
       _voice = voicePlatform ?? MethodChannelVrDesktopVoicePlatform(),
       _desktopCapabilities = desktopCapabilities,
       _hasExplicitCapabilities = desktopCapabilities != null,
       bindPort = bindPort ?? _resolveEnvPort(),
       _clockUs =
           monotonicMicroseconds ??
           (() {
             final sw = Stopwatch()..start();
             return () => sw.elapsedMicroseconds;
           })(),
       stationId = _resolveInitialStationId(initialStationId),
       pin = _resolveInitialPin(initialPin) {
    mediaVault.addListener(_onVaultChanged);
  }

  final VrDesktopVisionPlatform _vision;
  final VrDesktopVoicePlatform _voice;
  final ItzliVrAssistant itzliAssistant = ItzliVrAssistant();
  final int Function() _clockUs;
  final String stationName;
  final String stationId;
  final int discoveryPort;
  final int bindPort;
  final String? vaultDirectoryPath;
  final bool enableMediaVault;
  String pin;

  final VrTriNodeDepthSolver solver = VrTriNodeDepthSolver();
  final VrBeaconDeadReckoningGate deadReckoning = VrBeaconDeadReckoningGate();
  final VrSyntheticDesktopVisionGenerator syntheticVision =
      VrSyntheticDesktopVisionGenerator();
  final VrDesktopAutonomousBridgeEngine autonomousBridge =
      VrDesktopAutonomousBridgeEngine();

  /// Live PC-side mirror of the Joystick's [RemoteControllerState] when the
  /// Joystick joins the Computer's `3D Set` (`role: 'joystick'`).
  final VrRemoteControllerService coordinatorJoystickMirror =
      VrRemoteControllerService();
  VrInMemoryCoordinatorControllerPipe? _coordinatorPipe;
  StreamSubscription<Object?>? _coordinatorOutSub;

  late final VrDesktopMediaVaultServer mediaVault = VrDesktopMediaVaultServer(
    stationId: stationId,
    stationName: stationName,
    vaultDirectoryPath: vaultDirectoryPath,
    poseProvider: () => _latestSolution,
    capabilitiesProvider: () => _desktopCapabilities,
    coordinatorTelemetryProvider: _buildCoordinatorTelemetry,
    onPushToVisor: (_) {
      _pendingImmediateDirective = true;
      if (!_disposed) notifyListeners();
    },
    onVoiceCommandApi: (text, source) {
      final guidance = submitVoiceCommand(text, source: source);
      return {
        'ok': true,
        'seq': _voiceSequence,
        'transcript': _lastVoiceTranscript,
        'source': _lastVoiceSource,
        'relayedToVisor': _canRelayToPairedVisor,
        'actionType': guidance.actionType.name,
        'summaryEs': guidance.summaryEs,
        'speechResponse': guidance.speechResponse,
        if (guidance.targetDemoId != null)
          'targetDemoId': guidance.targetDemoId,
        if (guidance.targetWingId != null)
          'targetWingId': guidance.targetWingId,
        if (guidance.motionKind != null)
          'motionKind': guidance.motionKind!.name,
        if (guidance.uiCommand != null) 'uiCommand': guidance.uiCommand!.name,
      };
    },
    onSimulateExpressionApi: (exprName) {
      final expr = VrFacialExpression.fromWire(exprName);
      pulseSimulatedFacialExpression(expr);
      return {
        'ok': true,
        'facialExpression': expr.name,
        'labelEs': expr.labelEs,
        'actionHintEs': expr.actionHintEs,
      };
    },
  );

  RawDatagramSocket? _dataSocket;
  RawDatagramSocket? _discoverySocket;
  StreamSubscription<RawSocketEvent>? _dataSub;
  StreamSubscription<RawSocketEvent>? _discoverySub;
  StreamSubscription<VrDesktopVisionFrame>? _visionSub;
  StreamSubscription<VrDesktopVoiceEvent>? _voiceSub;
  Timer? _tickTimer;
  Timer? _announceTimer;
  Timer? _voiceBurstRetryTimer;
  Timer? _simulatedExpressionResetTimer;

  bool _running = false;
  bool _disposed = false;
  bool _webcamEnabled = false;
  bool _webcamNativeActive = false;
  bool _syntheticAssistEnabled = true;
  bool _monitorFiducialEnabled = true;
  bool _stereoSonarAssistEnabled = false;
  List<String> _localIps = const [];

  InternetAddress? _pairedVisorAddress;
  int? _pairedVisorPort;
  InternetAddress? _pairedJoystickAddress;
  int? _pairedJoystickPort;
  List<int>? _sessionKey;
  List<int>? _joystickSessionKey;
  String? _lastHelloClientNonce;
  String? _lastHelloServerNonce;
  String? _lastJoystickHelloClientNonce;
  String? _lastJoystickHelloServerNonce;
  int _lastVisorSeenUs = -10000000;
  int _lastJoystickSeenUs = -10000000;
  int _visorProtocolVersion = 1;
  int _packetsSent = 0;
  int _directivesSent = 0;
  int _feedbackReceived = 0;
  int _joystickFramesCoordinated = 0;
  int _compactJoystickFramesCoordinated = 0;
  int _visorRelayedGamepadFrames = 0;
  int _visorControlsRelayedToJoystick = 0;
  int _nativeVisionFramesReceived = 0;
  int _lastNativeVisionReceivedUs = -10000000;
  bool _pendingImmediateDirective = false;

  VrDesktopCapabilities? _desktopCapabilities;
  final bool _hasExplicitCapabilities;
  VrDesktopVisionFrame? _latestVisionFrame;
  VrDesktopVisionFrame? _latestNativeVisionFrame;
  VrVisorBeaconFeedback? _latestVisorFeedback;
  VrMobileNodeCapabilities? _cachedVisorCapabilities;
  VrMobileNodeCapabilities? _cachedJoystickCapabilities;
  VrJoystickDirectBridgeTelemetry? _latestJoystickTelemetry;
  VrCompactGamepadFrame? _latestCompactJoystickFrame;
  VrTriNodeDepthSolution? _latestSolution;
  VrDesktopBridgeDirective? _latestDirective;

  bool _desktopVoiceSupported = false;
  bool _desktopVoiceListening = false;
  String _desktopVoiceLocale = 'es-MX';
  String _desktopVoicePartialText = '';
  String _lastVoiceTranscript = '';
  String _lastVoiceSource = '';
  ItzliVrGuidance? _lastVoiceGuidance;
  int _voiceSequence = 0;
  int _voiceCommandsSent = 0;
  String? _lastVoiceError;
  VrFacialExpression _manualFacialOverride = VrFacialExpression.neutral;
  int _manualFacialOverrideUntilUs = 0;

  bool get desktopVoiceSupported => _desktopVoiceSupported;
  bool get desktopVoiceListening => _desktopVoiceListening;
  String get desktopVoiceLocale => _desktopVoiceLocale;
  String get desktopVoicePartialText => _desktopVoicePartialText;
  String get lastVoiceTranscript => _lastVoiceTranscript;
  String get lastVoiceSource => _lastVoiceSource;
  ItzliVrGuidance? get lastVoiceGuidance => _lastVoiceGuidance;
  int get voiceCommandsSent => _voiceCommandsSent;
  String? get lastVoiceError => _lastVoiceError;

  bool get isRunning => _running;
  bool get webcamEnabled => _webcamEnabled;
  bool get webcamNativeActive => _webcamNativeActive;

  /// True when a physical webcam frame arrived within the last 1.0 s on the
  /// station's monotonic clock (independent of the OS native uptime epoch).
  bool get isNativeVisionLive =>
      _webcamNativeActive &&
      _latestNativeVisionFrame != null &&
      (_clockUs() - _lastNativeVisionReceivedUs) < 1000000;

  VrDesktopVisionFrame? get latestNativeVisionFrame => _latestNativeVisionFrame;
  int get nativeVisionFramesReceived => _nativeVisionFramesReceived;
  int get joystickFramesCoordinated => _joystickFramesCoordinated;
  int get compactJoystickFramesCoordinated => _compactJoystickFramesCoordinated;
  int get packetsSuppressedByPrediction => deadReckoning.suppressedCount;
  bool get syntheticAssistEnabled => _syntheticAssistEnabled;
  bool get monitorFiducialEnabled => _monitorFiducialEnabled;
  bool get stereoSonarAssistEnabled => _stereoSonarAssistEnabled;
  bool get autonomousModeEnabled => autonomousBridge.autonomousModeEnabled;
  bool get castToDesktopEnabled => autonomousBridge.castToDesktopEnabled;
  bool get preferPcProjectorMode => autonomousBridge.preferPcProjectorMode;
  VrDesktopCapabilities? get desktopCapabilities => _desktopCapabilities;
  VrTriDeviceExecutionPlan? get latestExecutionPlan =>
      autonomousBridge.latestExecutionPlan;
  int? get boundPort => _dataSocket?.port;
  List<String> get localIps => _localIps;
  String get primaryHost => _localIps.isNotEmpty ? _localIps.first : '127.0.0.1';
  int get packetsSent => _packetsSent;
  int get directivesSent => _directivesSent;
  int get feedbackReceived => _feedbackReceived;
  VrDesktopVisionFrame? get latestVisionFrame => _latestVisionFrame;
  VrVisorBeaconFeedback? get latestVisorFeedback => _latestVisorFeedback;
  VrJoystickDirectBridgeTelemetry? get latestJoystickTelemetry =>
      _latestJoystickTelemetry;
  VrTriNodeDepthSolution? get latestSolution => _latestSolution;
  VrDesktopBridgeDirective? get latestDirective => _latestDirective;

  bool get isVisorConnected =>
      _sessionKey != null &&
      _pairedVisorAddress != null &&
      (_clockUs() - _lastVisorSeenUs) < 8000000;

  bool get isDirectJoystickConnected =>
      (_joystickSessionKey != null || _sessionKey != null) &&
      _pairedJoystickAddress != null &&
      (_clockUs() - _lastJoystickSeenUs) < 8000000;

  bool get _canRelayToPairedVisor =>
      _sessionKey != null &&
      _pairedVisorAddress != null &&
      _pairedVisorPort != null &&
      (_clockUs() - _lastVisorSeenUs) < 60000000;

  bool get _canKeepalivePairedJoystick =>
      (_joystickSessionKey != null || _sessionKey != null) &&
      _pairedJoystickAddress != null &&
      _pairedJoystickPort != null &&
      (_clockUs() - _lastJoystickSeenUs) < 60000000;

  /// Validated LAN viewer URL of the Visor's live screen cast whenever the PC
  /// is actively taking over the cast display to free the Joystick smartphone.
  Uri? get activeCastViewerUri {
    if (!isVisorConnected || !autonomousBridge.castToDesktopEnabled) {
      return null;
    }
    final raw = _latestVisorFeedback?.castViewerUri;
    if (raw == null) return null;
    return VrCastSession.tryParse(raw)?.viewerUri ?? Uri.tryParse(raw);
  }

  VrDesktopBeaconPairingInvite? get pairingInvite {
    final port = boundPort;
    if (port == null) return null;
    return VrDesktopBeaconPairingInvite(
      stationId: stationId,
      stationName: stationName,
      host: primaryHost,
      port: port,
      pin: pin,
    );
  }

  int get capabilitiesMask {
    var mask = VrTriNodeDepthSolution.modalityWifiUdp;
    if (_webcamNativeActive || _syntheticAssistEnabled) {
      mask |= VrTriNodeDepthSolution.modalityWebcamAi;
    }
    if (_monitorFiducialEnabled) {
      mask |= VrTriNodeDepthSolution.modalityMonitorFiducial;
    }
    if (_stereoSonarAssistEnabled) {
      mask |= VrTriNodeDepthSolution.modalityStereoSonar;
    }
    return mask;
  }

  static int _resolveEnvPort() {
    if (kIsWeb) return 0;
    final raw = Platform.environment['VRLIZATE_BEACON_PORT']?.trim();
    if (raw == null || raw.isEmpty) return 0;
    final parsed = int.tryParse(raw);
    return (parsed != null && parsed > 0 && parsed <= 65535) ? parsed : 0;
  }

  static String _resolveInitialStationId(String? explicitId) {
    final candidate =
        explicitId?.trim() ??
        (kIsWeb ? null : Platform.environment['VRLIZATE_BEACON_STATION_ID']?.trim());
    if (candidate != null &&
        candidate.length >= 6 &&
        candidate.length <= 48 &&
        RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(candidate)) {
      return candidate;
    }
    return _generateStationId();
  }

  static String _resolveInitialPin(String? explicitPin) {
    final candidate =
        explicitPin?.trim() ??
        (kIsWeb ? null : Platform.environment['VRLIZATE_BEACON_PIN']?.trim());
    if (candidate != null && VrDesktopBeaconWire.isValidPin(candidate)) {
      return candidate;
    }
    return _generateSixDigitPin();
  }

  static String _generateStationId() {
    final rng = math.Random.secure();
    final bytes = List<int>.generate(6, (_) => rng.nextInt(256));
    return 'faro_${base64UrlEncode(bytes).replaceAll('=', '')}';
  }

  static String _generateSixDigitPin() {
    final rng = math.Random.secure();
    final n = 100000 + rng.nextInt(900000);
    return '$n';
  }

  void _onVaultChanged() {
    if (!_disposed) notifyListeners();
  }

  void regeneratePin() {
    pin = _generateSixDigitPin();
    _sessionKey = null;
    _joystickSessionKey = null;
    _lastHelloClientNonce = null;
    _lastHelloServerNonce = null;
    _lastJoystickHelloClientNonce = null;
    _lastJoystickHelloServerNonce = null;
    _pairedVisorAddress = null;
    _pairedVisorPort = null;
    _pairedJoystickAddress = null;
    _pairedJoystickPort = null;
    _cachedVisorCapabilities = null;
    _cachedJoystickCapabilities = null;
    deadReckoning.reset();
    mediaVault.rotateToken();
    notifyListeners();
  }

  void setMonitorFiducialEnabled(bool value) {
    if (_monitorFiducialEnabled == value) return;
    _monitorFiducialEnabled = value;
    notifyListeners();
  }

  void setStereoSonarAssistEnabled(bool value) {
    if (_stereoSonarAssistEnabled == value) return;
    _stereoSonarAssistEnabled = value;
    notifyListeners();
  }

  void setSyntheticAssistEnabled(bool value) {
    if (_syntheticAssistEnabled == value) return;
    _syntheticAssistEnabled = value;
    notifyListeners();
  }

  /// Pulses a facial expression on Estación Faro (works both in Synthetic AI
  /// mode and as a live override while a physical webcam is streaming).
  void pulseSimulatedFacialExpression(
    VrFacialExpression expr, {
    Duration hold = const Duration(milliseconds: 1100),
  }) {
    syntheticVision.simulatedFacialExpression = expr;
    _simulatedExpressionResetTimer?.cancel();
    if (expr == VrFacialExpression.neutral) {
      _manualFacialOverride = VrFacialExpression.neutral;
      _manualFacialOverrideUntilUs = 0;
    } else {
      _manualFacialOverride = expr;
      _manualFacialOverrideUntilUs = _clockUs() + hold.inMicroseconds;
      _simulatedExpressionResetTimer = Timer(hold, () {
        syntheticVision.simulatedFacialExpression = VrFacialExpression.neutral;
        _manualFacialOverride = VrFacialExpression.neutral;
        _manualFacialOverrideUntilUs = 0;
        if (!_disposed) notifyListeners();
      });
    }
    if (!_disposed) notifyListeners();
  }

  /// Enables or disables continuous Spanish speech recognition on the Desktop
  /// microphone (`SFSpeechRecognizer` + `AVAudioEngine`).
  Future<bool> setDesktopVoiceListening(bool enabled) async {
    if (_disposed) return false;
    if (!enabled) {
      _desktopVoiceListening = false;
      _desktopVoicePartialText = '';
      await _voice.stopListening();
      if (!_disposed) notifyListeners();
      return false;
    }
    _lastVoiceError = null;
    _voiceSub ??= _voice.events.listen(
      _onDesktopVoiceEvent,
      onError: (Object err) {
        _lastVoiceError = '$err';
        _desktopVoiceListening = false;
        if (!_disposed) notifyListeners();
      },
    );
    final ok = await _voice.startListening(locale: _desktopVoiceLocale);
    _desktopVoiceListening = ok;
    if (!ok && _lastVoiceError == null) {
      _lastVoiceError =
          'No se pudo activar el micrófono o reconocimiento de voz en esta computadora (verifica permisos en Configuración del Sistema).';
    }
    if (!_disposed) notifyListeners();
    return ok;
  }

  void _onDesktopVoiceEvent(VrDesktopVoiceEvent event) {
    if (_disposed) return;
    if (event.locale != null && event.locale!.isNotEmpty) {
      _desktopVoiceLocale = event.locale!;
    }
    if (event.kind == 'status') {
      _desktopVoiceListening = event.listening;
      if (!_disposed) notifyListeners();
      return;
    }
    if (event.kind == 'error') {
      _lastVoiceError = event.error ?? 'Error de reconocimiento de voz';
      _desktopVoiceListening = event.listening;
      if (!_disposed) notifyListeners();
      return;
    }
    if (event.kind == 'transcript') {
      if (event.isFinal) {
        _desktopVoicePartialText = '';
        if (event.text.isNotEmpty) {
          submitVoiceCommand(event.text, source: 'desktop_mic');
        }
      } else {
        _desktopVoicePartialText = event.text;
        if (!_disposed) notifyListeners();
      }
    }
  }

  /// Evaluates [transcript] with [ItzliVrAssistant] on the Computer and relays
  /// an authenticated `VRB1` `voiceCommandKind` burst to the paired Visor.
  ItzliVrGuidance submitVoiceCommand(
    String transcript, {
    String source = 'desktop_console',
  }) {
    final clean = transcript.trim();
    final guidance = itzliAssistant.interpretRequest(clean);
    if (clean.isEmpty) return guidance;

    _lastVoiceTranscript = clean;
    _lastVoiceSource = source;
    _lastVoiceGuidance = guidance;
    _desktopVoicePartialText = '';
    _lastVoiceError = null;
    final seq = ++_voiceSequence;

    if (_canRelayToPairedVisor && _sessionKey != null) {
      final pkt = VrBeaconVoiceCommandPacket(
        sequence: seq,
        timestampMicros: _clockUs(),
        transcript: clean,
        source: source,
      );
      final encoded = VrDesktopBeaconWire.encodeAuthenticatedJson(
        kind: VrDesktopBeaconWire.voiceCommandKind,
        key: _sessionKey!,
        payload: pkt.toJson(),
      );
      final dstAddr = _pairedVisorAddress!;
      final dstPort = _pairedVisorPort!;
      try {
        _dataSocket?.send(encoded, dstAddr, dstPort);
        _dataSocket?.send(encoded, dstAddr, dstPort);
        _voiceCommandsSent++;
      } catch (_) {}
      _voiceBurstRetryTimer?.cancel();
      _voiceBurstRetryTimer = Timer(const Duration(milliseconds: 45), () {
        if (_disposed || !_canRelayToPairedVisor) return;
        try {
          _dataSocket?.send(encoded, dstAddr, dstPort);
        } catch (_) {}
      });
    }

    if (!_disposed) notifyListeners();
    return guidance;
  }

  void setAutonomousModeEnabled(bool value) {
    if (autonomousBridge.autonomousModeEnabled == value) return;
    autonomousBridge.autonomousModeEnabled = value;
    _pendingImmediateDirective = true;
    notifyListeners();
  }

  void setCastToDesktopEnabled(bool value) {
    if (autonomousBridge.castToDesktopEnabled == value) return;
    autonomousBridge.castToDesktopEnabled = value;
    _pendingImmediateDirective = true;
    notifyListeners();
  }

  void setPreferPcProjectorMode(bool value) {
    if (autonomousBridge.preferPcProjectorMode == value) return;
    autonomousBridge.preferPcProjectorMode = value;
    _pendingImmediateDirective = true;
    notifyListeners();
  }

  Future<bool> setWebcamEnabled(bool enabled) async {
    if (_disposed) return false;
    _webcamEnabled = enabled;
    if (!enabled) {
      await _visionSub?.cancel();
      _visionSub = null;
      await _vision.stopCapture();
      _webcamNativeActive = false;
      notifyListeners();
      return false;
    }
    final supported = await _vision.isSupported();
    if (!supported) {
      _webcamNativeActive = false;
      notifyListeners();
      return false;
    }
    _visionSub ??= _vision.frames.listen((frame) {
      _latestNativeVisionFrame = frame;
      _latestVisionFrame = frame;
      _lastNativeVisionReceivedUs = _clockUs();
      _nativeVisionFramesReceived++;
      if (!_webcamNativeActive && _webcamEnabled) {
        _webcamNativeActive = true;
        notifyListeners();
      }
    });
    _webcamNativeActive = await _vision.startCapture();
    if (!_webcamNativeActive) {
      await _visionSub?.cancel();
      _visionSub = null;
    } else {
      debugPrint('[VrDesktopBeaconStation] Native webcam capture active');
    }
    notifyListeners();
    return _webcamNativeActive;
  }

  Future<void> start({bool enableWebcam = false}) async {
    if (_disposed || _running || kIsWeb) return;
    if (!_hasExplicitCapabilities) {
      _desktopCapabilities = await VrDesktopHardwareProbe.probe(
        visionPlatform: _vision,
        hasWebcamFallback: enableWebcam,
      );
    }
    _desktopVoiceSupported = await _voice.isSupported();
    _localIps = await _discoverLanIps();
    if (enableMediaVault) {
      await mediaVault.start(preferredLanHost: primaryHost);
    } else {
      mediaVault.updatePreferredLanHost(primaryHost);
    }
    _dataSocket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      bindPort,
    );
    _dataSub = _dataSocket!.listen(_onDataSocketEvent);

    if (discoveryPort > 0) {
      try {
        _discoverySocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          discoveryPort,
          reuseAddress: true,
        );
        _discoverySocket!.broadcastEnabled = true;
        _discoverySub = _discoverySocket!.listen(_onDiscoverySocketEvent);
      } catch (_) {
        // Discovery port may already be bound on the same machine during tests;
        // direct QR / IP:port pairing on _dataSocket continues unaffected.
      }
    }

    _running = true;

    // 60 Hz spatial fusion & authenticated UDP broadcast to paired Visor
    // starts immediately so LAN pairing & Vault work even while the OS waits
    // on a first-time camera permission dialog.
    _tickTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _tick(),
    );
    _announceTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _broadcastAnnounce(),
    );
    _broadcastAnnounce();
    debugPrint(
      '[VrDesktopBeaconStation] Ready stationId=$stationId '
      'endpoint=$primaryHost:${_dataSocket?.port} '
      'webcamRequested=$enableWebcam',
    );
    if (const bool.fromEnvironment('VRLIZATE_BEACON_PRINT_INVITE')) {
      debugPrint(
        '[VrDesktopBeaconStation] LocalSession '
        'invite=${pairingInvite?.toUri()} '
        'joystickInvite=${pairingInvite?.toJoystickUri()} '
        'pin=$pin '
        'vaultWeb=${mediaVault.lanWebLibraryUri} '
        'tagsSheet=${mediaVault.lanPrintableTagsUri}',
      );
    }
    notifyListeners();

    if (enableWebcam) {
      await setWebcamEnabled(true);
    }
  }

  Future<void> stop() async {
    _running = false;
    _tickTimer?.cancel();
    _tickTimer = null;
    _announceTimer?.cancel();
    _announceTimer = null;
    _voiceBurstRetryTimer?.cancel();
    _voiceBurstRetryTimer = null;
    _simulatedExpressionResetTimer?.cancel();
    _simulatedExpressionResetTimer = null;
    await _voiceSub?.cancel();
    _voiceSub = null;
    if (_desktopVoiceListening) {
      await _voice.stopListening();
      _desktopVoiceListening = false;
    }
    await _visionSub?.cancel();
    _visionSub = null;
    if (_webcamNativeActive) {
      await _vision.stopCapture();
      _webcamNativeActive = false;
    }
    await _dataSub?.cancel();
    _dataSub = null;
    await _discoverySub?.cancel();
    _discoverySub = null;
    _dataSocket?.close();
    _dataSocket = null;
    _discoverySocket?.close();
    _discoverySocket = null;
    await _coordinatorOutSub?.cancel();
    _coordinatorOutSub = null;
    await _coordinatorPipe?.close();
    _coordinatorPipe = null;
    await mediaVault.stop();
    _sessionKey = null;
    _joystickSessionKey = null;
    _pairedVisorAddress = null;
    _pairedVisorPort = null;
    _pairedJoystickAddress = null;
    _pairedJoystickPort = null;
    _cachedVisorCapabilities = null;
    _cachedJoystickCapabilities = null;
    deadReckoning.reset();
    if (!_disposed) notifyListeners();
  }

  void _broadcastAnnounce() {
    final sock = _discoverySocket ?? _dataSocket;
    final port = boundPort;
    if (!_running || sock == null || port == null) return;
    final packet = VrDesktopBeaconWire.encodeDiscoveryAnnounce(
      stationId: stationId,
      stationName: stationName,
      port: port,
      capabilitiesMask: capabilitiesMask,
    );
    final dstPort = discoveryPort > 0 ? discoveryPort : port;
    try {
      sock.broadcastEnabled = true;
      sock.send(packet, InternetAddress('255.255.255.255'), dstPort);
    } catch (_) {}
    for (final ip in _localIps) {
      final bcast = _ipv4DirectedBroadcast24(ip);
      if (bcast != null) {
        try {
          sock.send(packet, bcast, dstPort);
        } catch (_) {}
      }
    }
  }

  static InternetAddress? _ipv4DirectedBroadcast24(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    if (parts[0] == '127') return null;
    return InternetAddress.tryParse('${parts[0]}.${parts[1]}.${parts[2]}.255');
  }

  void _onDiscoverySocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read || _discoverySocket == null) return;
    Datagram? dg;
    while ((dg = _discoverySocket!.receive()) != null) {
      final data = dg!.data;
      if (VrDesktopBeaconWire.hasMagic(data) &&
          data[4] == VrDesktopBeaconWire.discoverProbeKind) {
        final port = boundPort;
        if (port == null) continue;
        final reply = VrDesktopBeaconWire.encodeDiscoveryAnnounce(
          stationId: stationId,
          stationName: stationName,
          port: port,
          capabilitiesMask: capabilitiesMask,
        );
        _discoverySocket!.send(reply, dg.address, dg.port);
      }
    }
  }

  void _onDataSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read || _dataSocket == null) return;
    Datagram? dg;
    while ((dg = _dataSocket!.receive()) != null) {
      _handleIncomingDatagram(dg!);
    }
  }

  void _handleIncomingDatagram(Datagram dg) {
    final data = dg.data;
    if (!VrDesktopBeaconWire.hasMagic(data)) return;
    final kind = data[4];

    if (kind == VrDesktopBeaconWire.discoverProbeKind) {
      final port = boundPort;
      if (port == null) return;
      final reply = VrDesktopBeaconWire.encodeDiscoveryAnnounce(
        stationId: stationId,
        stationName: stationName,
        port: port,
        capabilitiesMask: capabilitiesMask,
      );
      _dataSocket?.send(reply, dg.address, dg.port);
      return;
    }

    if (kind == VrDesktopBeaconWire.helloKind) {
      final handshakeKey = VrDesktopBeaconWire.deriveHandshakeKey(
        stationId,
        pin,
      );
      final map = VrDesktopBeaconWire.decodeAuthenticatedJson(
        expectedKind: VrDesktopBeaconWire.helloKind,
        key: handshakeKey,
        datagram: data,
      );
      if (map == null) return;
      final clientNonce = map['cn'] as String?;
      if (clientNonce == null ||
          clientNonce.length < 12 ||
          clientNonce.length > 64) {
        return;
      }
      final isJoystickHello = map['role'] == 'joystick';
      final String serverNonce;
      if (isJoystickHello) {
        if (clientNonce == _lastJoystickHelloClientNonce &&
            _lastJoystickHelloServerNonce != null &&
            _joystickSessionKey != null) {
          serverNonce = _lastJoystickHelloServerNonce!;
        } else {
          final rng = math.Random.secure();
          serverNonce = base64UrlEncode(
            List<int>.generate(16, (_) => rng.nextInt(256)),
          );
          _lastJoystickHelloClientNonce = clientNonce;
          _lastJoystickHelloServerNonce = serverNonce;
          _joystickSessionKey = VrDesktopBeaconWire.deriveSessionKey(
            stationId: stationId,
            pin: pin,
            clientNonce: clientNonce,
            serverNonce: serverNonce,
          );
          _resetCoordinatorMirrorPipe();
        }
        _pairedJoystickAddress = dg.address;
        _pairedJoystickPort = dg.port;
        _lastJoystickSeenUs = _clockUs();
      } else {
        if (clientNonce == _lastHelloClientNonce &&
            _lastHelloServerNonce != null &&
            _sessionKey != null) {
          serverNonce = _lastHelloServerNonce!;
        } else {
          final rng = math.Random.secure();
          serverNonce = base64UrlEncode(
            List<int>.generate(16, (_) => rng.nextInt(256)),
          );
          _lastHelloClientNonce = clientNonce;
          _lastHelloServerNonce = serverNonce;
          _sessionKey = VrDesktopBeaconWire.deriveSessionKey(
            stationId: stationId,
            pin: pin,
            clientNonce: clientNonce,
            serverNonce: serverNonce,
          );
          _cachedVisorCapabilities = null;
          _cachedJoystickCapabilities = null;
          deadReckoning.reset();
        }
        _pairedVisorAddress = dg.address;
        _pairedVisorPort = dg.port;
        _visorProtocolVersion = ((map['v'] as num?)?.toInt() ?? 1).clamp(1, 99);
        _lastVisorSeenUs = _clockUs();
      }
      _pendingImmediateDirective = true;

      final ack = VrDesktopBeaconWire.encodeAuthenticatedJson(
        kind: VrDesktopBeaconWire.helloAckKind,
        key: handshakeKey,
        payload: {
          'sn': serverNonce,
          'cn': clientNonce,
          'id': stationId,
          'name': stationName,
          'role': isJoystickHello ? 'joystick' : 'visor',
          'caps': capabilitiesMask,
          if (_desktopCapabilities != null)
            'pcCaps': _desktopCapabilities!.toJson(),
          if (mediaVault.boundPort != null) ...{
            'vaultPort': mediaVault.boundPort,
            'vaultToken': mediaVault.vaultToken,
          },
        },
      );
      _dataSocket?.send(ack, dg.address, dg.port);
      notifyListeners();
      return;
    }

    if (kind == VrDesktopBeaconWire.visorFeedbackKind && _sessionKey != null) {
      final map = VrDesktopBeaconWire.decodeAuthenticatedJson(
        expectedKind: VrDesktopBeaconWire.visorFeedbackKind,
        key: _sessionKey!,
        datagram: data,
      );
      if (map == null) return;
      final rawFb = VrVisorBeaconFeedback.fromJson(map);
      if (rawFb == null) return;
      if (rawFb.visorCapabilities != null) {
        _cachedVisorCapabilities = rawFb.visorCapabilities;
      }
      if (rawFb.joystickCapabilities != null) {
        _cachedJoystickCapabilities = rawFb.joystickCapabilities;
      }
      final fb = rawFb.withFallbackCapabilities(
        fallbackVisorCapabilities: _cachedVisorCapabilities,
        fallbackJoystickCapabilities: _cachedJoystickCapabilities,
      );
      final prevCast = _latestVisorFeedback?.castViewerUri;
      final hadVisorCaps = _latestVisorFeedback?.visorCapabilities != null;
      _latestVisorFeedback = fb;
      _pairedVisorAddress = dg.address;
      _pairedVisorPort = dg.port;
      _lastVisorSeenUs = _clockUs();
      _feedbackReceived++;
      if (_feedbackReceived == 1 ||
          prevCast != fb.castViewerUri ||
          (!hadVisorCaps && fb.visorCapabilities != null)) {
        _pendingImmediateDirective = true;
        if (!_disposed) notifyListeners();
      }
      return;
    }

    if (kind == VrDesktopBeaconWire.joystickTelemetryKind) {
      Map<String, dynamic>? map;
      if (_joystickSessionKey != null) {
        map = VrDesktopBeaconWire.decodeAuthenticatedJson(
          expectedKind: VrDesktopBeaconWire.joystickTelemetryKind,
          key: _joystickSessionKey!,
          datagram: data,
        );
      }
      if (map == null && _sessionKey != null) {
        map = VrDesktopBeaconWire.decodeAuthenticatedJson(
          expectedKind: VrDesktopBeaconWire.joystickTelemetryKind,
          key: _sessionKey!,
          datagram: data,
        );
      }
      if (map == null) return;
      final jt = VrJoystickDirectBridgeTelemetry.fromJson(map);
      if (jt == null) return;
      _latestJoystickTelemetry = jt;
      _pairedJoystickAddress = dg.address;
      _pairedJoystickPort = dg.port;
      _lastJoystickSeenUs = _clockUs();
      _pendingImmediateDirective = true;
      return;
    }

    if (kind == VrDesktopBeaconWire.joystickControllerFrameKind) {
      Object? frame;
      if (_joystickSessionKey != null) {
        frame = VrDesktopBeaconWire.decodeAuthenticatedRelayFrame(
          expectedKind: VrDesktopBeaconWire.joystickControllerFrameKind,
          key: _joystickSessionKey!,
          datagram: data,
        );
      }
      if (frame == null && _sessionKey != null) {
        frame = VrDesktopBeaconWire.decodeAuthenticatedRelayFrame(
          expectedKind: VrDesktopBeaconWire.joystickControllerFrameKind,
          key: _sessionKey!,
          datagram: data,
        );
      }
      if (frame == null) return;
      _pairedJoystickAddress = dg.address;
      _pairedJoystickPort = dg.port;
      _lastJoystickSeenUs = _clockUs();
      _joystickFramesCoordinated++;
      if (frame is VrCompactGamepadFrame) {
        _compactJoystickFramesCoordinated++;
        _latestCompactJoystickFrame = frame;
      }

      // Mirror Joystick state on the PC Coordinator & synthesize local mode ACKs
      // when no Visor is paired yet.
      _ensureCoordinatorMirrorPipe().joystickSide.add(frame);

      // Sub-millisecond authenticated UDP relay directly to the paired Visor!
      // Uses a generous 60s paired grace window so temporary headset mounting
      // pauses NEVER drop or deadlock Joystick -> PC -> Visor relay!
      if (_canRelayToPairedVisor) {
        Object outboundFrame = frame;
        if (frame is VrCompactGamepadFrame && _visorProtocolVersion < 2) {
          var buttons = 0;
          if (frame.trigger) buttons |= 0x0001;
          if (frame.action) buttons |= 0x0002;
          if (frame.btnA) buttons |= 0x0004;
          if (frame.btnB) buttons |= 0x0008;
          if (frame.btnGrip) buttons |= 0x0010;
          if (frame.stickClick) buttons |= 0x0020;
          outboundFrame = const VrRemoteBinaryCodec().encodePose(
            VrRemotePoseFrame(
              sequence: frame.sequence & 0xFFFF,
              senderTimestampMicroseconds: frame.senderTimestampMicroseconds,
              orientation: frame.orientation,
              angularVelocity: frame.angularVelocity,
              buttonsBitset: buttons,
              touchX: ((frame.stickX + 1.0) * 0.5).clamp(0.0, 1.0),
              touchY: ((frame.stickY + 1.0) * 0.5).clamp(0.0, 1.0),
              rangeMeters: frame.rangeMeters,
            ),
          );
        }
        final relayed = VrDesktopBeaconWire.encodeAuthenticatedRelayFrame(
          kind: VrDesktopBeaconWire.joystickControllerFrameKind,
          key: _sessionKey!,
          frame: outboundFrame,
        );
        if (relayed != null) {
          _dataSocket?.send(relayed, _pairedVisorAddress!, _pairedVisorPort!);
          _visorRelayedGamepadFrames++;
        }
      }
      if (_joystickFramesCoordinated == 1 ||
          _joystickFramesCoordinated % 15 == 0) {
        if (!_disposed) notifyListeners();
      }
      return;
    }

    if (kind == VrDesktopBeaconWire.visorControllerControlKind &&
        _sessionKey != null) {
      final control = VrDesktopBeaconWire.decodeAuthenticatedRelayFrame(
        expectedKind: VrDesktopBeaconWire.visorControllerControlKind,
        key: _sessionKey!,
        datagram: data,
      );
      if (control == null) return;
      _lastVisorSeenUs = _clockUs();
      final joyKey = _joystickSessionKey ?? _sessionKey;
      if (isDirectJoystickConnected &&
          joyKey != null &&
          _pairedJoystickAddress != null &&
          _pairedJoystickPort != null) {
        final relayed = VrDesktopBeaconWire.encodeAuthenticatedRelayFrame(
          kind: VrDesktopBeaconWire.visorControllerControlKind,
          key: joyKey,
          frame: control,
        );
        if (relayed != null) {
          _dataSocket?.send(
            relayed,
            _pairedJoystickAddress!,
            _pairedJoystickPort!,
          );
          _visorControlsRelayedToJoystick++;
        }
      }
    }
  }

  VrInMemoryCoordinatorControllerPipe _ensureCoordinatorMirrorPipe() {
    final existing = _coordinatorPipe;
    if (existing != null && existing.stationSide.isOpen) {
      return existing;
    }
    _resetCoordinatorMirrorPipe();
    return _coordinatorPipe!;
  }

  void _resetCoordinatorMirrorPipe() {
    unawaited(_coordinatorOutSub?.cancel());
    _coordinatorOutSub = null;
    final prev = _coordinatorPipe;
    if (prev != null) {
      unawaited(prev.close());
    }
    final pipe = VrInMemoryCoordinatorControllerPipe();
    _coordinatorPipe = pipe;
    coordinatorJoystickMirror.attachControllerLink(
      pipe.stationSide,
      sessionToken: coordinatorJoystickMirror.sessionToken,
    );
    _coordinatorOutSub = pipe.joystickSide.messages.listen((control) {
      if (control == null || _disposed || !_running) return;
      // When a Visor is paired, the Visor owns mode/haptic control messages;
      // before a Visor connects, the PC Coordinator answers mode handshakes.
      if (isVisorConnected) return;
      final joyKey = _joystickSessionKey ?? _sessionKey;
      if (joyKey == null ||
          _pairedJoystickAddress == null ||
          _pairedJoystickPort == null) {
        return;
      }
      final packet = VrDesktopBeaconWire.encodeAuthenticatedRelayFrame(
        kind: VrDesktopBeaconWire.visorControllerControlKind,
        key: joyKey,
        frame: control,
      );
      if (packet != null) {
        _dataSocket?.send(
          packet,
          _pairedJoystickAddress!,
          _pairedJoystickPort!,
        );
      }
    });
  }

  Map<String, Object?> _buildCoordinatorTelemetry() {
    final nativeLive = isNativeVisionLive;
    final nf = _latestNativeVisionFrame;
    final joyState = coordinatorJoystickMirror.latestState;
    final cf = _latestCompactJoystickFrame;
    final joyActive = isDirectJoystickConnected;
    final effStickX = cf?.stickX ?? joyState.stickX;
    final effStickY = cf?.stickY ?? joyState.stickY;
    final effLookX = cf?.lookX ?? joyState.turnRate;
    final effLookY = cf?.lookY ?? joyState.pitchRate;
    final effTrigger = cf != null
        ? (cf.trigger || cf.btnR)
        : joyState.isTriggerPressed;
    final effBtnA = cf?.btnA ?? joyState.btnA;
    final effBtnB = cf != null ? (cf.btnB || cf.action) : joyState.btnB;
    final effRecenter = cf?.recenter ?? joyState.recenter;
    final effMode = cf != null
        ? switch (cf.modeIndex) {
            1 => 'laser',
            2 => 'driving',
            3 => 'nes',
            _ => 'joystick',
          }
        : joyState.mode.name;
    final effOrient = cf?.orientation ?? joyState.orientation;
    return {
      'visionSource': nativeLive
          ? 'native_webcam'
          : (_webcamNativeActive ? 'webcam_idle' : 'synthetic_assist'),
      'webcamNativeActive': _webcamNativeActive,
      'nativeVisionFrames': _nativeVisionFramesReceived,
      if (nf != null && _webcamNativeActive)
        'webcamDetected': {
          'upperBody': nf.hasUpperBody,
          'leftHand': nf.hasLeftHand,
          'rightHand': nf.hasRightHand,
          'fiducialTags': nf.fiducialTags.length,
          if (nf.inferenceMs != null)
            'inferenceMs': double.parse(nf.inferenceMs!.toStringAsFixed(1)),
        },
      'threeDeviceSet': {
        'visorConnected': isVisorConnected,
        'joystickConnected': joyActive,
        if (_pairedVisorAddress != null && _pairedVisorPort != null)
          'visorEndpoint': '${_pairedVisorAddress!.address}:$_pairedVisorPort',
        if (_pairedJoystickAddress != null && _pairedJoystickPort != null)
          'joystickEndpoint':
              '${_pairedJoystickAddress!.address}:$_pairedJoystickPort',
        'visorProtocolVersion': _visorProtocolVersion,
        if (_latestVisorFeedback?.visorCapabilities?.modelLabel
            case final vmModel?)
          'visorModel': vmModel,
        if (_latestJoystickTelemetry?.capabilities?.modelLabel ??
                _latestVisorFeedback?.joystickCapabilities?.modelLabel
            case final jmModel?)
          'joystickModel': jmModel,
        if (_latestVisorFeedback case final vfb?) ...{
          'visorExperience': vfb.activeExperience,
          'visorFps': double.parse(vfb.visorFps.toStringAsFixed(1)),
          if (vfb.rttMs != null)
            'visorRttMs': double.parse(vfb.rttMs!.toStringAsFixed(1)),
          'visorOrientation': {
            'qx': double.parse(vfb.visorOrientation.x.toStringAsFixed(4)),
            'qy': double.parse(vfb.visorOrientation.y.toStringAsFixed(4)),
            'qz': double.parse(vfb.visorOrientation.z.toStringAsFixed(4)),
            'qw': double.parse(vfb.visorOrientation.w.toStringAsFixed(4)),
          },
        },
        if (_latestDirective case final dir?) ...{
          'topologyMode': dir.topologyMode.name,
          'autonomousMode': dir.autonomousMode,
          'recommendedJoystickHz': dir.recommendedJoystickHz,
          'targetVisorRefreshHz': dir.targetVisorRefreshHz,
          'offloadCastToDesktop': dir.offloadCastToDesktop,
          'pcRendersStereoFrame': dir.pcRendersStereoFrame,
        },
        'joystickFramesCoordinated': _joystickFramesCoordinated,
        'visorRelayedGamepadFrames': _visorRelayedGamepadFrames,
        'visorControlsRelayedToJoystick': _visorControlsRelayedToJoystick,
        'visorFeedbackFrames': _feedbackReceived,
        'stickX': double.parse(effStickX.toStringAsFixed(3)),
        'stickY': double.parse(effStickY.toStringAsFixed(3)),
        'lookX': double.parse(effLookX.toStringAsFixed(3)),
        'lookY': double.parse(effLookY.toStringAsFixed(3)),
        'trigger': effTrigger,
        'btnA': effBtnA,
        'btnB': effBtnB,
        'recenter': effRecenter,
        'mode': effMode,
        'qx': double.parse(effOrient.x.toStringAsFixed(4)),
        'qy': double.parse(effOrient.y.toStringAsFixed(4)),
        'qz': double.parse(effOrient.z.toStringAsFixed(4)),
        'qw': double.parse(effOrient.w.toStringAsFixed(4)),
      },
      'wireOptimization': {
        'beaconTicksEvaluated': deadReckoning.evaluatedCount,
        'beaconPacketsSent': _packetsSent,
        'beaconPacketsSuppressed': deadReckoning.suppressedCount,
        'beaconSuppressionPct': double.parse(
          (deadReckoning.suppressionRatio * 100.0).toStringAsFixed(1),
        ),
        'compactGamepadFrames': _compactJoystickFramesCoordinated,
        'compactGamepadDatagramBytes':
            VrDesktopBeaconWire.compactGamepadPacketBytes,
      },
      'voiceAndFace': {
        'desktopVoiceSupported': _desktopVoiceSupported,
        'desktopVoiceListening': _desktopVoiceListening,
        'desktopVoiceLocale': _desktopVoiceLocale,
        if (_desktopVoicePartialText.isNotEmpty)
          'partialTranscript': _desktopVoicePartialText,
        if (_lastVoiceTranscript.isNotEmpty) ...{
          'lastTranscript': _lastVoiceTranscript,
          'lastSource': _lastVoiceSource,
          'voiceSequence': _voiceSequence,
          'voiceCommandsSent': _voiceCommandsSent,
        },
        if (_lastVoiceGuidance case final g?) ...{
          'lastActionType': g.actionType.name,
          'lastSummaryEs': g.summaryEs,
          if (g.targetDemoId != null) 'lastTargetDemoId': g.targetDemoId,
          if (g.targetWingId != null) 'lastTargetWingId': g.targetWingId,
          if (g.motionKind != null) 'lastMotionKind': g.motionKind!.name,
          if (g.uiCommand != null) 'lastUiCommand': g.uiCommand!.name,
        },
        'facialExpression':
            (_latestSolution?.facialExpression ?? VrFacialExpression.neutral)
                .name,
        'facialConfidence': double.parse(
          (_latestSolution?.facialConfidence ?? 0.0).toStringAsFixed(2),
        ),
      },
    };
  }

  void _tick() {
    if (!_running || _disposed) return;
    final nowUs = _clockUs();
    final nativeLive = isNativeVisionLive;
    VrDesktopVisionFrame? vision;
    final bool visionFresh;
    if (nativeLive) {
      vision = _latestNativeVisionFrame;
      _latestVisionFrame = vision;
      visionFresh = true;
    } else {
      vision = _latestVisionFrame;
      visionFresh =
          vision != null && (nowUs - vision.timestampMicros).abs() < 450000;
      if (!visionFresh && _syntheticAssistEnabled && !_webcamNativeActive) {
        vision = syntheticVision.sample(nowUs);
        _latestVisionFrame = vision;
      }
    }

    final visorConnected = isVisorConnected;
    final useVision =
        visionFresh || (_syntheticAssistEnabled && !_webcamNativeActive);
    var solution = solver.solve(
      nowMicros: nowUs,
      vision: useVision ? vision : null,
      visorFeedback: visorConnected ? _latestVisorFeedback : null,
      activeModalitiesMask: capabilitiesMask,
    );
    if (_manualFacialOverride != VrFacialExpression.neutral &&
        nowUs < _manualFacialOverrideUntilUs) {
      solution = VrTriNodeDepthSolution(
        timestampMicros: solution.timestampMicros,
        sequence: solution.sequence,
        computerToVisorMeters: solution.computerToVisorMeters,
        computerToJoystickMeters: solution.computerToJoystickMeters,
        visorToJoystickMeters: solution.visorToJoystickMeters,
        visorRoomPosition: solution.visorRoomPosition,
        joystickRoomPosition: solution.joystickRoomPosition,
        deskClearanceMeters: solution.deskClearanceMeters,
        visorAzimuthRadians: solution.visorAzimuthRadians,
        yawAnchorCorrectionRadians: solution.yawAnchorCorrectionRadians,
        leftHandRelHead: solution.leftHandRelHead,
        rightHandRelHead: solution.rightHandRelHead,
        leftHandVelocity: solution.leftHandVelocity,
        rightHandVelocity: solution.rightHandVelocity,
        leftHandConfidence: solution.leftHandConfidence,
        rightHandConfidence: solution.rightHandConfidence,
        leftHandRaised: solution.leftHandRaised,
        rightHandRaised: solution.rightHandRaised,
        leftPinchStrength: solution.leftPinchStrength,
        rightPinchStrength: solution.rightPinchStrength,
        gesture: solution.gesture,
        confidence: solution.confidence,
        activeModalitiesMask: solution.activeModalitiesMask,
        visorFiducialLocked: solution.visorFiducialLocked,
        joystickFiducialLocked: solution.joystickFiducialLocked,
        visorFiducialReprojectionRmsPx: solution.visorFiducialReprojectionRmsPx,
        estimatedUserIpdMeters: solution.estimatedUserIpdMeters,
        facialExpression: _manualFacialOverride,
        facialConfidence: 0.94,
      );
    }
    _latestSolution = solution;

    if (_canRelayToPairedVisor) {
      final isIdleKeepalive = !visorConnected && (solution.sequence % 60 == 1);
      if (isIdleKeepalive ||
          (visorConnected &&
              deadReckoning.shouldTransmit(solution, nowMicros: nowUs))) {
        final datagram = VrDesktopBeaconWire.encodeBeaconState(
          sessionKey: _sessionKey!,
          solution: solution,
        );
        _dataSocket?.send(datagram, _pairedVisorAddress!, _pairedVisorPort!);
        _packetsSent++;
      }
    }

    // Autonomous Compute & Offload Bridge evaluation (~4 Hz + immediate triggers)
    if (_pendingImmediateDirective || solution.sequence % 15 == 1) {
      _pendingImmediateDirective = false;
      String? vaultCatalogUrl;
      final vPort = mediaVault.boundPort;
      if (vPort != null) {
        final targetHost = (_pairedVisorAddress?.isLoopback ?? false)
            ? '127.0.0.1'
            : primaryHost;
        vaultCatalogUrl =
            'http://$targetHost:$vPort/${mediaVault.vaultToken}/api/catalog.json';
      }
      final directive = autonomousBridge.evaluate(
        nowMicros: nowUs,
        stationName: stationName,
        visorConnected: visorConnected,
        solution: solution,
        desktopCapabilities: _desktopCapabilities,
        visorFeedback: visorConnected ? _latestVisorFeedback : null,
        joystickTelemetry: isDirectJoystickConnected
            ? _latestJoystickTelemetry
            : null,
        vaultCatalogUrl: vaultCatalogUrl,
        pushedVaultItemId: mediaVault.lastPushedItemId,
        pushedVaultSeq: mediaVault.pushedSequence,
      );
      _latestDirective = directive;
      if (_canRelayToPairedVisor &&
          (visorConnected || solution.sequence % 60 == 1)) {
        final visorDirective = VrDesktopBeaconWire.encodeAuthenticatedJson(
          kind: VrDesktopBeaconWire.bridgeDirectiveKind,
          key: _sessionKey!,
          payload: directive.toJson(),
        );
        _dataSocket?.send(
          visorDirective,
          _pairedVisorAddress!,
          _pairedVisorPort!,
        );
        _directivesSent++;
      }
      final joyKey = _joystickSessionKey ?? _sessionKey;
      if (_canKeepalivePairedJoystick &&
          joyKey != null &&
          (isDirectJoystickConnected || solution.sequence % 60 == 1)) {
        final joyDirective = VrDesktopBeaconWire.encodeAuthenticatedJson(
          kind: VrDesktopBeaconWire.bridgeDirectiveKind,
          key: joyKey,
          payload: directive.toJson(),
        );
        _dataSocket?.send(
          joyDirective,
          _pairedJoystickAddress!,
          _pairedJoystickPort!,
        );
      }
    }

    // Throttle UI listener notifications to ~15 Hz while UDP streams at 60 Hz
    if (solution.sequence % 4 == 0) {
      notifyListeners();
    }
  }

  static Future<List<String>> _discoverLanIps() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      final candidates = <VrLocalAddressCandidate>[];
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) {
            candidates.add(VrLocalAddressCandidate(iface.name, addr.address));
          }
        }
      }
      return VrLocalNetworkAddress.selectAll(candidates, limit: 4);
    } catch (_) {
      return const ['127.0.0.1'];
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    mediaVault.removeListener(_onVaultChanged);
    unawaited(stop());
    coordinatorJoystickMirror.dispose();
    mediaVault.dispose();
    super.dispose();
  }
}
