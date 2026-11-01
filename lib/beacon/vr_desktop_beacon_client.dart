import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'vr_beacon_dead_reckoning.dart';
import 'vr_beacon_joystick_link.dart';
import 'vr_desktop_autonomous_bridge.dart';
import 'vr_desktop_beacon_models.dart';
import 'vr_desktop_beacon_wire.dart';
import 'vr_desktop_capabilities.dart';
import 'vr_private_lan_loopback_relay.dart';

/// Runs inside the Visor smartphone's [VrSpatialTrackingService] to discover,
/// authenticate, and ingest 60 Hz 3-node depth + AI hand tracking packets from
/// a **VRlizate Desktop Estación Faro** while the Visor runs `.vrlz` natively.
class VrDesktopBeaconClient extends ChangeNotifier {
  VrDesktopBeaconClient({
    this.discoveryPort = VrDesktopBeaconWire.defaultDiscoveryPort,
    int Function()? monotonicMicroseconds,
  }) : _clockUs =
           monotonicMicroseconds ??
           (() {
             final sw = Stopwatch()..start();
             return () => sw.elapsedMicroseconds;
           })();

  final int discoveryPort;
  final int Function() _clockUs;

  RawDatagramSocket? _socket;
  RawDatagramSocket? _passiveDiscoverySocket;
  StreamSubscription<RawSocketEvent>? _socketSub;
  StreamSubscription<RawSocketEvent>? _passiveDiscoverySub;
  Timer? _feedbackTimer;
  Timer? _helloRetryTimer;
  Timer? _discoverySweepTimer;
  Timer? _autoReconnectTimer;
  bool _autoReconnectInFlight = false;
  VrDesktopBeaconPairingInvite? _rememberedInvite;
  void Function(VrDesktopBeaconPairingInvite invite)? onInviteAuthenticated;
  Completer<bool>? _pendingHandshake;
  VrPrivateLanLoopbackRelay? _vaultRelay;
  final VrBeaconDeadReckoningGate deadReckoning = VrBeaconDeadReckoningGate();

  final Map<String, VrDiscoveredDesktopBeacon> _discovered = {};
  final StreamController<VrTriNodeDepthSolution> _solutions =
      StreamController<VrTriNodeDepthSolution>.broadcast();
  final StreamController<VrDesktopBridgeDirective> _directives =
      StreamController<VrDesktopBridgeDirective>.broadcast();
  final StreamController<String> _vaultPushes =
      StreamController<String>.broadcast();
  final StreamController<VrBeaconVoiceCommandPacket> _voiceCommands =
      StreamController<VrBeaconVoiceCommandPacket>.broadcast();

  bool _disposed = false;
  bool _connecting = false;
  String? _connectedStationId;
  String? _connectedStationName;
  InternetAddress? _stationAddress;
  int? _stationPort;
  String? _pendingClientNonce;
  String? _pendingPin;
  List<int>? _sessionKey;
  int _lastReceivedSeq = 0;
  int _lastDirectiveEpoch = 0;
  int _lastPushedVaultSeq = 0;
  int _lastVoiceCommandSeq = 0;
  VrBeaconVoiceCommandPacket? _lastVoiceCommand;
  int _lastPacketUs = 0;
  int _handshakeSentUs = 0;
  double? _measuredRttMs;
  int _packetsReceived = 0;
  String? _lastError;
  int? _connectedVaultPort;
  String? _connectedVaultToken;
  Uri? _connectedVaultCatalogUriOverride;
  VrDesktopCapabilities? _connectedDesktopCapabilities;
  VrTriNodeDepthSolution? _latestSolution;
  VrDesktopBridgeDirective? _latestDirective;
  VrVisorBeaconFeedback Function()? feedbackBuilder;
  VrBeaconVisorControllerLink? _coordinatedControllerLink;
  int _lastJoystickFrameUs = -10000000;
  int _joystickFramesReceived = 0;
  int _feedbackSentCount = 0;
  bool _hadSentVisorCaps = false;
  bool _hadSentJoystickCaps = false;

  /// Duplex [VrControllerLink] receiving Joystick inputs relayed by the PC
  /// Coordinator (`Joystick ↔ PC ↔ Visor`) inside a `3D Set`.
  VrBeaconVisorControllerLink get coordinatedControllerLink {
    final current = _coordinatedControllerLink;
    if (current != null && current.isOpen) return current;
    final next = VrBeaconVisorControllerLink(
      onSendControl: sendVisorControllerControl,
    );
    _coordinatedControllerLink = next;
    return next;
  }

  /// True when a Joystick is actively streaming controller frames through the
  /// paired PC Coordinator (`3D Set`).
  bool get hasCoordinatedJoystick =>
      isConnected && (_clockUs() - _lastJoystickFrameUs) < 4000000;

  int get joystickFramesReceived => _joystickFramesReceived;

  Stream<VrTriNodeDepthSolution> get solutions => _solutions.stream;
  Stream<VrDesktopBridgeDirective> get directives => _directives.stream;
  Stream<String> get vaultPushItemIds => _vaultPushes.stream;
  Stream<VrBeaconVoiceCommandPacket> get voiceCommands =>
      _voiceCommands.stream;
  VrBeaconVoiceCommandPacket? get lastVoiceCommand => _lastVoiceCommand;
  VrTriNodeDepthSolution? get latestSolution => _latestSolution;

  /// Extrapolates the latest received [VrTriNodeDepthSolution] smoothly to
  /// [atMicros] (defaulting to current monotonic clock) using damped first-order
  /// Dead-Reckoning so `120 Hz` render loops see silky motion between packets.
  VrTriNodeDepthSolution? predictLatestSolution({int? atMicros}) {
    if (!isConnected) return null;
    return deadReckoning.predictAt(atMicros ?? _clockUs()) ?? _latestSolution;
  }

  VrDesktopBridgeDirective? get latestDirective => _latestDirective;
  VrDesktopCapabilities? get connectedDesktopCapabilities =>
      _connectedDesktopCapabilities;
  double? get measuredRttMs => _measuredRttMs;
  bool get isConnecting => _connecting;
  int get packetsReceived => _packetsReceived;
  String? get lastError => _lastError;
  String? get connectedStationName => _connectedStationName;
  String? get connectedStationId => _connectedStationId;
  VrDesktopBeaconPairingInvite? get rememberedInvite => _rememberedInvite;

  /// Remembers [invite] and activates background LAN discovery + zero-drop
  /// re-handshake whenever the Visor resumes or `Estación Faro` restarts.
  void enableAutoReconnect(
    VrDesktopBeaconPairingInvite invite, {
    bool connectImmediately = true,
  }) {
    if (_disposed || kIsWeb) return;
    _rememberedInvite = invite;
    _ensureAutoReconnectWatchdog();
    if (connectImmediately && !isConnected && !_connecting) {
      unawaited(_attemptAutoReconnect());
    }
  }

  void _ensureAutoReconnectWatchdog() {
    if (_autoReconnectTimer != null || _disposed || kIsWeb) return;
    _autoReconnectTimer = Timer.periodic(
      const Duration(milliseconds: 2000),
      (_) {
        if (_disposed || _rememberedInvite == null) return;
        if (isConnected || _connecting || _autoReconnectInFlight) return;
        unawaited(_attemptAutoReconnect());
      },
    );
  }

  Future<void> _attemptAutoReconnect() async {
    final invite = _rememberedInvite;
    if (invite == null || _disposed || _connecting || _autoReconnectInFlight) {
      return;
    }
    _autoReconnectInFlight = true;
    try {
      await scanLan();
      await Future<void>.delayed(const Duration(milliseconds: 220));
      if (_disposed || isConnected || _connecting) return;
      final discovered = _discovered[invite.stationId];
      final host = discovered?.host ?? invite.host;
      final port = discovered?.port ?? invite.port;
      final name = discovered?.stationName ?? invite.stationName;
      await connect(
        stationId: invite.stationId,
        stationName: name,
        host: host,
        port: port,
        pin: invite.pin,
        timeout: const Duration(milliseconds: 1600),
        isAutoReconnectAttempt: true,
      );
    } finally {
      _autoReconnectInFlight = false;
    }
  }

  /// Active ecosystem tier (`Three-Devices VR · 3D-VR` when paired with PC,
  /// `Two-Devices VR · 2D-VR` when portable standalone).
  VrEcosystemDeviceTier get activeEcosystemTier => isConnected
      ? VrEcosystemDeviceTier.threeDevices3dVr
      : VrEcosystemDeviceTier.twoDevices2dVr;

  Uri? get connectedVaultCatalogUri {
    if (!isConnected) return null;
    final relay = _vaultRelay;
    if (relay != null && relay.boundPort != null) {
      if (_connectedVaultCatalogUriOverride != null) {
        return relay.rewriteUri(_connectedVaultCatalogUriOverride!);
      }
      return relay.localCatalogUri;
    }
    if (_connectedVaultCatalogUriOverride != null) {
      return _connectedVaultCatalogUriOverride;
    }
    final addr = _stationAddress?.address;
    final port = _connectedVaultPort;
    final token = _connectedVaultToken;
    if (addr == null || port == null || token == null || token.isEmpty) {
      return null;
    }
    return Uri.parse('http://$addr:$port/$token/api/catalog.json');
  }

  Uri? get connectedVaultVrlzIndexUri =>
      connectedVaultCatalogUri?.resolve('vrlz-index.json');

  Uri? get connectedVaultWebLibraryUri =>
      connectedVaultCatalogUri?.resolve('../web');

  bool get isConnected =>
      _sessionKey != null &&
      _stationAddress != null &&
      (_clockUs() - _lastPacketUs) < 3500000;

  List<VrDiscoveredDesktopBeacon> get discoveredStations {
    final cutoff = _clockUs() - 12000000;
    _discovered.removeWhere((_, v) => v.lastSeenMicros < cutoff);
    return _discovered.values.toList(growable: false);
  }

  Future<void> _ensureSocket() async {
    if (_socket != null || kIsWeb || _disposed) return;
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _socket!.broadcastEnabled = true;
    _socketSub = _socket!.listen(_onSocketEvent);
    if (discoveryPort > 0 && _passiveDiscoverySocket == null) {
      try {
        _passiveDiscoverySocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          discoveryPort,
          reuseAddress: true,
        );
        _passiveDiscoverySocket!.broadcastEnabled = true;
        _passiveDiscoverySub = _passiveDiscoverySocket!.listen(
          _onPassiveDiscoveryEvent,
        );
      } catch (_) {
        // Port may already be bound on loopback; active scanLan() probes still work.
      }
    }
  }

  void _onPassiveDiscoveryEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read || _passiveDiscoverySocket == null) return;
    Datagram? dg;
    while ((dg = _passiveDiscoverySocket!.receive()) != null) {
      _handleDatagram(dg!);
    }
  }

  /// Broadcasts a LAN discovery probe to find active VRlizate Desktop stations.
  Future<void> scanLan({int? targetPortOverride}) async {
    if (_disposed || kIsWeb) return;
    await _ensureSocket();
    final probe = VrDesktopBeaconWire.encodeDiscoveryProbe();
    final port = targetPortOverride ?? discoveryPort;
    try {
      _socket?.send(probe, InternetAddress('255.255.255.255'), port);
    } catch (_) {}
    try {
      _socket?.send(probe, InternetAddress.loopbackIPv4, port);
    } catch (_) {}
    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      final sentSubnets = <String>{};
      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          final parts = addr.address.split('.');
          if (parts.length == 4) {
            final bcastStr = '${parts[0]}.${parts[1]}.${parts[2]}.255';
            if (sentSubnets.add(bcastStr)) {
              final bcast = InternetAddress.tryParse(bcastStr);
              if (bcast != null) {
                try {
                  _socket?.send(probe, bcast, port);
                } catch (_) {}
              }
            }
          }
        }
      }
    } catch (_) {}
    _discoverySweepTimer?.cancel();
    _discoverySweepTimer = Timer(
      const Duration(milliseconds: 350),
      notifyListeners,
    );
  }

  Future<bool> connectWithInvite(VrDesktopBeaconPairingInvite invite) =>
      connect(
        stationId: invite.stationId,
        stationName: invite.stationName,
        host: invite.host,
        port: invite.port,
        pin: invite.pin,
      );

  /// Authenticates with a Desktop Faro station using its 6-digit PIN.
  Future<bool> connect({
    required String stationId,
    required String host,
    required int port,
    required String pin,
    String stationName = 'Estación Faro Desktop',
    Duration timeout = const Duration(seconds: 3),
    bool isAutoReconnectAttempt = false,
  }) async {
    if (_disposed || kIsWeb) return false;
    if (!VrDesktopBeaconWire.isValidPin(pin)) {
      _lastError = 'El código PIN debe tener 6 dígitos.';
      notifyListeners();
      return false;
    }

    _connecting = true;
    if (!isAutoReconnectAttempt) {
      _lastError = null;
    }
    _sessionKey = null;
    _lastReceivedSeq = 0;
    _lastDirectiveEpoch = 0;
    _lastVoiceCommandSeq = 0;
    _latestDirective = null;
    _feedbackSentCount = 0;
    _hadSentVisorCaps = false;
    _hadSentJoystickCaps = false;
    deadReckoning.reset();
    await _stopVaultRelay();
    notifyListeners();

    try {
      await _ensureSocket();
      final resolved = InternetAddress.tryParse(host) ??
          (await InternetAddress.lookup(host)).firstWhere(
            (a) => a.type == InternetAddressType.IPv4,
          );
      final rng = math.Random.secure();
      final clientNonce = base64UrlEncode(
        List<int>.generate(16, (_) => rng.nextInt(256)),
      );
      _connectedStationId = stationId;
      _connectedStationName = stationName;
      _stationAddress = resolved;
      _stationPort = port;
      _pendingClientNonce = clientNonce;
      _pendingPin = pin.trim();

      final completer = Completer<bool>();
      _pendingHandshake = completer;

      final handshakeKey = VrDesktopBeaconWire.deriveHandshakeKey(
        stationId,
        _pendingPin!,
      );
      final hello = VrDesktopBeaconWire.encodeAuthenticatedJson(
        kind: VrDesktopBeaconWire.helloKind,
        key: handshakeKey,
        payload: {'cn': clientNonce, 'v': 2},
      );
      _handshakeSentUs = _clockUs();
      _socket?.send(hello, resolved, port);
      _helloRetryTimer?.cancel();
      _helloRetryTimer = Timer.periodic(
        const Duration(milliseconds: 350),
        (timer) {
          if (completer.isCompleted || _disposed) {
            timer.cancel();
            return;
          }
          try {
            _socket?.send(hello, resolved, port);
          } catch (_) {}
        },
      );

      final ok = await completer.future.timeout(
        timeout,
        onTimeout: () => false,
      );
      _helloRetryTimer?.cancel();
      _helloRetryTimer = null;
      _connecting = false;
      _pendingHandshake = null;
      _pendingPin = null;
      _pendingClientNonce = null;

      if (!ok) {
        if (!isAutoReconnectAttempt) {
          _lastError =
              'No hubo respuesta válida de la Estación Faro (verifica el PIN y la red Wi-Fi).';
        }
        disconnect(
          preserveRemembered: true,
          keepCoordinatedLink: isAutoReconnectAttempt,
        );
        return false;
      }

      final authedInvite = VrDesktopBeaconPairingInvite(
        stationId: stationId,
        stationName: _connectedStationName ?? stationName,
        host: resolved.address,
        port: port,
        pin: pin.trim(),
      );
      _rememberedInvite = authedInvite;
      _lastError = null;
      onInviteAuthenticated?.call(authedInvite);

      if (!resolved.isLoopback &&
          _connectedVaultPort != null &&
          _connectedVaultToken != null &&
          _connectedVaultToken!.isNotEmpty) {
        final relay = VrPrivateLanLoopbackRelay(
          upstreamHost: resolved.address,
          upstreamPort: _connectedVaultPort!,
          vaultToken: _connectedVaultToken!,
        );
        if (await relay.start()) {
          _vaultRelay = relay;
        }
      }

      _feedbackTimer?.cancel();
      _feedbackTimer = Timer.periodic(
        const Duration(milliseconds: 50),
        (_) => _sendVisorFeedback(),
      );
      _sendVisorFeedback();
      notifyListeners();
      return true;
    } catch (e) {
      _helloRetryTimer?.cancel();
      _helloRetryTimer = null;
      _connecting = false;
      _pendingHandshake = null;
      _pendingPin = null;
      _pendingClientNonce = null;
      _lastError = 'Error al conectar con Estación Faro: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> _stopVaultRelay() async {
    final relay = _vaultRelay;
    _vaultRelay = null;
    if (relay != null) {
      await relay.stop();
    }
  }

  void disconnect({
    bool preserveRemembered = false,
    bool keepCoordinatedLink = false,
  }) {
    if (!preserveRemembered) {
      _rememberedInvite = null;
      _autoReconnectTimer?.cancel();
      _autoReconnectTimer = null;
    }
    _helloRetryTimer?.cancel();
    _helloRetryTimer = null;
    _feedbackTimer?.cancel();
    _feedbackTimer = null;
    unawaited(_stopVaultRelay());
    _sessionKey = null;
    _stationAddress = null;
    _stationPort = null;
    _connectedStationId = null;
    _connectedStationName = null;
    _connectedDesktopCapabilities = null;
    _connectedVaultPort = null;
    _connectedVaultToken = null;
    _connectedVaultCatalogUriOverride = null;
    _measuredRttMs = null;
    _latestSolution = null;
    _latestDirective = null;
    _lastReceivedSeq = 0;
    _lastDirectiveEpoch = 0;
    _lastPushedVaultSeq = 0;
    _lastJoystickFrameUs = -10000000;
    _feedbackSentCount = 0;
    _hadSentVisorCaps = false;
    _hadSentJoystickCaps = false;
    deadReckoning.reset();
    if (!keepCoordinatedLink) {
      final prevLink = _coordinatedControllerLink;
      _coordinatedControllerLink = null;
      if (prevLink != null) {
        unawaited(prevLink.close());
      }
    }
    if (!_disposed) notifyListeners();
  }

  /// Immediately transmits fresh Visor feedback (e.g. when `castViewerUri`
  /// becomes ready right after [VrCastHost.start]) without waiting for the
  /// 50 ms periodic tick.
  void sendImmediateFeedback() => _sendVisorFeedback(forceSend: true);

  /// Sends Visor -> Joystick control messages (`mode`, `mode_ack`, haptics,
  /// cast preview) back through the PC Coordinator (`Visor -> PC -> Joystick`).
  void sendVisorControllerControl(Object controlFrame) {
    if (_sessionKey == null ||
        _stationAddress == null ||
        _stationPort == null) {
      return;
    }
    final datagram = VrDesktopBeaconWire.encodeAuthenticatedRelayFrame(
      kind: VrDesktopBeaconWire.visorControllerControlKind,
      key: _sessionKey!,
      frame: controlFrame,
    );
    if (datagram == null) return;
    try {
      _socket?.send(datagram, _stationAddress!, _stationPort!);
    } catch (_) {}
  }

  /// Sends direct LAN Joystick telemetry (`PC ↔ Joystick` direct UDP bridge).
  void sendJoystickTelemetry(VrJoystickDirectBridgeTelemetry telemetry) {
    if (_sessionKey == null ||
        _stationAddress == null ||
        _stationPort == null) {
      return;
    }
    final datagram = VrDesktopBeaconWire.encodeAuthenticatedJson(
      kind: VrDesktopBeaconWire.joystickTelemetryKind,
      key: _sessionKey!,
      payload: telemetry.toJson(),
    );
    try {
      _socket?.send(datagram, _stationAddress!, _stationPort!);
    } catch (_) {}
  }

  int _idleFeedbackSkipCounter = 0;

  void _sendVisorFeedback({
    bool forceIncludeCapabilities = false,
    bool forceSend = false,
  }) {
    if (_sessionKey == null ||
        _stationAddress == null ||
        _stationPort == null) {
      return;
    }
    // Never deadlock when `!isConnected`: continue sending a 2 Hz keepalive
    // feedback probe so `Estación Faro` immediately resumes 60 Hz streaming
    // the moment the Visor returns to Wi-Fi range or finishes headset mounting!
    if (!isConnected && !forceSend) {
      _idleFeedbackSkipCounter++;
      if (_idleFeedbackSkipCounter % 10 != 1) return;
    } else {
      _idleFeedbackSkipCounter = 0;
    }
    final fb =
        feedbackBuilder?.call() ??
        VrVisorBeaconFeedback(timestampMicros: _clockUs());
    final hasVc = fb.visorCapabilities != null;
    final hasJc = fb.joystickCapabilities != null;
    final includeCaps =
        forceIncludeCapabilities ||
        _feedbackSentCount == 0 ||
        (_feedbackSentCount % 60 == 0) ||
        (hasVc && !_hadSentVisorCaps) ||
        (hasJc && !_hadSentJoystickCaps);
    final datagram = VrDesktopBeaconWire.encodeAuthenticatedJson(
      kind: VrDesktopBeaconWire.visorFeedbackKind,
      key: _sessionKey!,
      payload: fb.toJson(includeCapabilities: includeCaps),
    );
    try {
      _socket?.send(datagram, _stationAddress!, _stationPort!);
      _feedbackSentCount++;
      if (includeCaps && hasVc) _hadSentVisorCaps = true;
      if (includeCaps && hasJc) _hadSentJoystickCaps = true;
    } catch (_) {}
  }

  void _onSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read || _socket == null) return;
    Datagram? dg;
    while ((dg = _socket!.receive()) != null) {
      _handleDatagram(dg!);
    }
  }

  void _handleDatagram(Datagram dg) {
    final data = dg.data;
    if (!VrDesktopBeaconWire.hasMagic(data)) return;
    final kind = data[4];
    final nowUs = _clockUs();

    if (kind == VrDesktopBeaconWire.discoverAnnounceKind) {
      final info = VrDesktopBeaconWire.decodeDiscoveryAnnounce(
        data,
        senderHost: dg.address.address,
        nowMicros: nowUs,
      );
      if (info != null) {
        _discovered[info.stationId] = info;
        notifyListeners();
      }
      return;
    }

    if (kind == VrDesktopBeaconWire.helloAckKind &&
        _pendingHandshake != null &&
        !_pendingHandshake!.isCompleted &&
        _connectedStationId != null &&
        _pendingPin != null &&
        _pendingClientNonce != null) {
      final handshakeKey = VrDesktopBeaconWire.deriveHandshakeKey(
        _connectedStationId!,
        _pendingPin!,
      );
      final map = VrDesktopBeaconWire.decodeAuthenticatedJson(
        expectedKind: VrDesktopBeaconWire.helloAckKind,
        key: handshakeKey,
        datagram: data,
      );
      if (map == null || map['cn'] != _pendingClientNonce) return;
      final serverNonce = map['sn'] as String?;
      if (serverNonce == null || serverNonce.length < 12) return;

      _sessionKey = VrDesktopBeaconWire.deriveSessionKey(
        stationId: _connectedStationId!,
        pin: _pendingPin!,
        clientNonce: _pendingClientNonce!,
        serverNonce: serverNonce,
      );
      _connectedStationName =
          (map['name'] as String?) ?? _connectedStationName;
      _connectedDesktopCapabilities = VrDesktopCapabilities.fromMap(
        map['pcCaps'] as Map<dynamic, dynamic>?,
      );
      _connectedVaultPort = (map['vaultPort'] as num?)?.toInt();
      _connectedVaultToken = map['vaultToken'] as String?;
      _connectedVaultCatalogUriOverride = null;
      if (_handshakeSentUs > 0 && nowUs >= _handshakeSentUs) {
        _measuredRttMs = ((nowUs - _handshakeSentUs) / 1000.0).clamp(
          0.1,
          1000.0,
        );
      }
      _lastPacketUs = nowUs;
      _pendingHandshake!.complete(true);
      return;
    }

    if (kind == VrDesktopBeaconWire.beaconStateKind && _sessionKey != null) {
      final solution = VrDesktopBeaconWire.decodeBeaconState(
        sessionKey: _sessionKey!,
        datagram: data,
      );
      if (solution == null) return;
      // Strict monotonic anti-replay check
      if (solution.sequence <= _lastReceivedSeq) return;
      _lastReceivedSeq = solution.sequence;
      _lastPacketUs = nowUs;
      _packetsReceived++;
      _latestSolution = solution;
      deadReckoning.ingestReceived(solution, receivedAtMicros: nowUs);
      if (!_solutions.isClosed) {
        _solutions.add(solution);
      }
      if (_packetsReceived % 15 == 1) {
        notifyListeners();
      }
      return;
    }

    if (kind == VrDesktopBeaconWire.bridgeDirectiveKind &&
        _sessionKey != null) {
      final map = VrDesktopBeaconWire.decodeAuthenticatedJson(
        expectedKind: VrDesktopBeaconWire.bridgeDirectiveKind,
        key: _sessionKey!,
        datagram: data,
      );
      if (map == null) return;
      final directive = VrDesktopBridgeDirective.fromJson(map);
      if (directive == null) return;
      if (directive.decisionEpoch <= _lastDirectiveEpoch) return;
      _lastDirectiveEpoch = directive.decisionEpoch;
      _lastPacketUs = nowUs;
      _latestDirective = directive;
      if (directive.vaultCatalogUrl != null) {
        _connectedVaultCatalogUriOverride = Uri.tryParse(
          directive.vaultCatalogUrl!,
        );
      }
      if (directive.pushedVaultItemId != null &&
          directive.pushedVaultSeq > _lastPushedVaultSeq) {
        _lastPushedVaultSeq = directive.pushedVaultSeq;
        if (!_vaultPushes.isClosed) {
          _vaultPushes.add(directive.pushedVaultItemId!);
        }
      }
      if (!_directives.isClosed) {
        _directives.add(directive);
      }
      notifyListeners();
      return;
    }

    if (kind == VrDesktopBeaconWire.joystickControllerFrameKind &&
        _sessionKey != null) {
      final frame = VrDesktopBeaconWire.decodeAuthenticatedRelayFrame(
        expectedKind: VrDesktopBeaconWire.joystickControllerFrameKind,
        key: _sessionKey!,
        datagram: data,
      );
      if (frame == null) return;
      final wasActive = hasCoordinatedJoystick;
      _lastJoystickFrameUs = nowUs;
      _lastPacketUs = nowUs;
      _joystickFramesReceived++;
      coordinatedControllerLink.deliverFromStation(frame);
      if (!wasActive || _joystickFramesReceived % 30 == 0) {
        notifyListeners();
      }
      return;
    }

    if (kind == VrDesktopBeaconWire.voiceCommandKind && _sessionKey != null) {
      final map = VrDesktopBeaconWire.decodeAuthenticatedJson(
        expectedKind: VrDesktopBeaconWire.voiceCommandKind,
        key: _sessionKey!,
        datagram: data,
      );
      if (map == null) return;
      final pkt = VrBeaconVoiceCommandPacket.fromJson(map);
      if (pkt == null) return;
      if (pkt.sequence <= _lastVoiceCommandSeq) return;
      _lastVoiceCommandSeq = pkt.sequence;
      _lastVoiceCommand = pkt;
      _lastPacketUs = nowUs;
      if (!_voiceCommands.isClosed) {
        _voiceCommands.add(pkt);
      }
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _autoReconnectTimer?.cancel();
    _autoReconnectTimer = null;
    disconnect();
    _discoverySweepTimer?.cancel();
    unawaited(_socketSub?.cancel());
    unawaited(_passiveDiscoverySub?.cancel());
    _socket?.close();
    _passiveDiscoverySocket?.close();
    unawaited(_solutions.close());
    unawaited(_directives.close());
    unawaited(_vaultPushes.close());
    unawaited(_voiceCommands.close());
    super.dispose();
  }
}
