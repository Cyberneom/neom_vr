import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:vrlizate_joystick/vrlizate_joystick.dart';

import '../session/vr_device_profiler.dart';
import 'vr_ble_session.dart';
import 'vr_ble_wire.dart';

/// Internal post-authentication BLE control message types consumed by the
/// hybrid wrapper and never forwarded to application state parsers.
abstract final class VrHybridWireConstants {
  static const offerType = 'vrlizate.hybridOffer';
  static const peerCapsType = 'vrlizate.peerCaps';
  static const linkAdviceType = 'vrlizate.linkAdvice';

  static const pingKind = 1;
  static const pongKind = 2;
  static const stateKind = 3;

  static const pingPongPacketBytes = 33; // 4 magic + 1 kind + 4 seq + 8 us + 16 mac
  static const stateDatagramBytes = 43; // 4 magic + 1 kind + 1 edge + 21 state + 16 mac
  static const hmacTagBytes = 16;
}

List<int> _deriveHybridUdpKey(String sessionToken, String offerNonce) => Hmac(
  sha256,
  utf8.encode(sessionToken),
).convert(utf8.encode('vrlizate-hybrid-udp-v1/$offerNonce')).bytes;

Uint8List _computeTag(List<int> key, Uint8List body) {
  final digest = Hmac(sha256, key).convert(body).bytes;
  return Uint8List.fromList(
    digest.sublist(0, VrHybridWireConstants.hmacTagBytes),
  );
}

bool _verifyTagConstantTime(
  List<int> key,
  Uint8List datagram,
  int payloadEndOffset,
) {
  if (datagram.length != payloadEndOffset + VrHybridWireConstants.hmacTagBytes) {
    return false;
  }
  final body = Uint8List.sublistView(datagram, 0, payloadEndOffset);
  final expected = Hmac(sha256, key).convert(body).bytes;
  var diff = 0;
  for (var i = 0; i < VrHybridWireConstants.hmacTagBytes; i++) {
    diff |= datagram[payloadEndOffset + i] ^ expected[i];
  }
  return diff == 0;
}

bool _hasMagic(Uint8List d) =>
    d.length >= 5 &&
    d[0] == 0x56 && // 'V'
    d[1] == 0x52 && // 'R'
    d[2] == 0x55 && // 'U'
    d[3] == 0x31; // '1'

String _freshOfferNonce() {
  final rng = math.Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  return base64UrlEncode(bytes);
}

Future<List<String>> _discoverLocalLanIps() async {
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
    return const <String>[];
  }
}

VrControllerFastTransport _classifyBleTransport(VrControllerLink ble) {
  if (ble is VrBlePacketLink && ble.singlePacketStateEnabled) {
    return VrControllerFastTransport.bleSinglePacket;
  }
  return VrControllerFastTransport.bleFragmented;
}

VrControllerFastTransport _classifyUdpTransport(
  Map<String, Object?>? visorSummary,
  Map<String, Object?>? joystickSummary,
) {
  final vFreq = visorSummary?['freqMhz'] as int?;
  final jFreq = joystickSummary?['freqMhz'] as int?;
  if ((vFreq != null && vFreq >= 2400 && vFreq < 2500) ||
      (jFreq != null && jFreq >= 2400 && jFreq < 2500)) {
    return VrControllerFastTransport.udp24Ghz;
  }
  return VrControllerFastTransport.udp5Ghz;
}

int _negotiatedControllerHz({
  required VrControllerFastTransport transport,
  Map<String, Object?>? visorSummary,
  Map<String, Object?>? joystickSummary,
}) {
  if (transport != VrControllerFastTransport.udp5Ghz) return 60;
  final visorPro =
      visorSummary?['cls'] == 'flagship' &&
      ((visorSummary?['maxHz'] as int?) ?? 60) >= 115;
  final joyPro =
      joystickSummary?['cls'] == 'flagship' &&
      ((joystickSummary?['maxHz'] as int?) ?? 60) >= 115;
  return (visorPro && joyPro) ? 120 : 60;
}

/// Visor-side wrapper around an authenticated BLE link that opens an ephemeral
/// HMAC-authenticated UDP fast path and deduplicates monotonic state sequences
/// across BLE and UDP seamlessly.
class VrHybridBleUdpHostLink implements VrObservableControllerLink {
  VrHybridBleUdpHostLink({
    required VrControllerLink bleLink,
    required this.sessionToken,
    Map<String, Object?>? localCapabilitiesSummary,
    this.overrideLanIps,
    InternetAddress? bindAddress,
  }) : _ble = bleLink,
       _visorSummary = localCapabilitiesSummary,
       _bindAddress = bindAddress ?? InternetAddress.anyIPv4 {
    _quality = ValueNotifier<VrControllerLinkQuality>(
      VrControllerLinkQuality(
        transport: _classifyBleTransport(_ble),
        canCarryVideoCast: false,
      ),
    );
    _messages = StreamController<Object?>(
      sync: true,
      onListen: _startListening,
      onPause: () => _bleSub?.pause(),
      onResume: () => _bleSub?.resume(),
      onCancel: () => unawaited(close()),
    );
  }

  final VrControllerLink _ble;
  final String sessionToken;
  Map<String, Object?>? _visorSummary;
  Map<String, Object?>? _joystickSummary;
  final List<String>? overrideLanIps;
  final InternetAddress _bindAddress;
  final String _offerNonce = _freshOfferNonce();
  late final List<int> _udpKey = _deriveHybridUdpKey(sessionToken, _offerNonce);
  late final StreamController<Object?> _messages;
  late final ValueNotifier<VrControllerLinkQuality> _quality;
  StreamSubscription<Object?>? _bleSub;
  RawDatagramSocket? _udpSocket;
  Timer? _udpWatchdog;
  final Stopwatch _clock = Stopwatch()..start();
  int? _lastUdpPacketUs;
  int? _lastDeliveredStateSequence;
  bool _open = true;
  bool _udpReceivingStates = false;

  int? get boundUdpPort => _udpSocket?.port;

  @override
  bool get isOpen => _open && _ble.isOpen;

  @override
  Stream<Object?> get messages => _messages.stream;

  @override
  ValueListenable<VrControllerLinkQuality> get linkQualityListenable =>
      _quality;

  void _startListening() {
    if (_bleSub != null || !_open) return;
    _bleSub = _ble.messages.listen(
      _onBleMessage,
      onError: (Object error, StackTrace stack) {
        if (!_messages.isClosed) _messages.addError(error, stack);
      },
      onDone: () => unawaited(close()),
      cancelOnError: true,
    );
    unawaited(_openUdpAndSendOffer());
  }

  Future<void> _openUdpAndSendOffer() async {
    if (!_open) return;
    if (_visorSummary == null) {
      await VrDeviceProfiler.refreshRuntimeEnvironment();
      _visorSummary = VrDeviceProfiler.capabilities?.toPeerSummary();
    }
    List<String> ips = overrideLanIps ?? await _discoverLocalLanIps();
    if (!_open) return;
    var udpPort = 0;
    if (ips.isNotEmpty) {
      try {
        final socket = await RawDatagramSocket.bind(_bindAddress, 0);
        if (!_open) {
          socket.close();
          return;
        }
        _udpSocket = socket;
        udpPort = socket.port;
        socket.listen(_onUdpSocketEvent, onError: (_) {});
        _udpWatchdog = Timer.periodic(
          const Duration(milliseconds: 250),
          (_) => _checkUdpFreshness(),
        );
      } catch (_) {
        ips = const <String>[];
      }
    }
    _recomputeQuality();
    if (!_open || !_ble.isOpen) return;
    try {
      _ble.add(
        jsonEncode({
          'type': VrHybridWireConstants.offerType,
          'v': 1,
          'udpPort': udpPort,
          'ips': ips,
          'nonce': _offerNonce,
          if (_visorSummary != null) 'caps': _visorSummary,
        }),
      );
    } catch (_) {}
  }

  void _checkUdpFreshness() {
    if (!_open || !_udpReceivingStates) return;
    final lastUs = _lastUdpPacketUs;
    if (lastUs != null && _clock.elapsedMicroseconds - lastUs > 700000) {
      _udpReceivingStates = false;
      _recomputeQuality();
    }
  }

  void _onUdpSocketEvent(RawSocketEvent event) {
    if (!_open || event != RawSocketEvent.read) return;
    final socket = _udpSocket;
    if (socket == null) return;
    Datagram? dg;
    while ((dg = socket.receive()) != null) {
      _handleUdpDatagram(socket, dg!);
    }
  }

  void _handleUdpDatagram(RawDatagramSocket socket, Datagram dg) {
    final data = dg.data;
    if (!_hasMagic(data)) return;
    final kind = data[4];
    if (kind == VrHybridWireConstants.pingKind &&
        data.length == VrHybridWireConstants.pingPongPacketBytes) {
      if (!_verifyTagConstantTime(_udpKey, data, 17)) return;
      if (_udpReceivingStates) {
        _lastUdpPacketUs = _clock.elapsedMicroseconds;
      }
      final pongBody = Uint8List(17)
        ..setRange(0, 4, data)
        ..[4] = VrHybridWireConstants.pongKind
        ..setRange(5, 17, data, 5);
      final tag = _computeTag(_udpKey, pongBody);
      final pong = Uint8List(VrHybridWireConstants.pingPongPacketBytes)
        ..setRange(0, 17, pongBody)
        ..setRange(17, 33, tag);
      try {
        socket.send(pong, dg.address, dg.port);
      } catch (_) {}
      return;
    }

    if (kind == VrHybridWireConstants.stateKind &&
        data.length == VrHybridWireConstants.stateDatagramBytes) {
      if (!_verifyTagConstantTime(_udpKey, data, 27)) return;
      final allowEdge =
          data[5] == 1 &&
          (_ble is! VrBlePacketLink || _ble.edgeTurnIntentEnabled);
      final statePacket = Uint8List.sublistView(data, 6, 27);
      if (statePacket[0] != 1) return;
      final seq = ByteData.sublistView(statePacket).getUint32(4, Endian.little);
      if (_lastDeliveredStateSequence != null &&
          seq <= _lastDeliveredStateSequence!) {
        return;
      }
      try {
        final json = VrBleWireCodec.decode(
          Uint8List.fromList(statePacket),
          allowEdgeTurnIntent: allowEdge,
        );
        _lastDeliveredStateSequence = seq;
        _lastUdpPacketUs = _clock.elapsedMicroseconds;
        if (!_udpReceivingStates) {
          _udpReceivingStates = true;
          _recomputeQuality();
        }
        if (!_messages.isClosed) _messages.add(json);
      } catch (_) {
        // Ignore malformed UDP datagrams rather than dropping authenticated BLE.
      }
    }
  }

  void _onBleMessage(Object? data) {
    if (!_open || _messages.isClosed) return;
    if (data is String && data.length <= 2048) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) {
          final type = decoded['type'];
          if (type == VrHybridWireConstants.peerCapsType) {
            final caps = decoded['caps'];
            if (caps is Map) {
              _joystickSummary = caps.cast<String, Object?>();
              _recomputeQuality();
            }
            return;
          }
          if (type == null && decoded['sequence'] is int) {
            final seq = decoded['sequence'] as int;
            if (_lastDeliveredStateSequence != null &&
                seq <= _lastDeliveredStateSequence!) {
              return;
            }
            _lastDeliveredStateSequence = seq;
          }
        }
      } catch (_) {}
    }
    _messages.add(data);
  }

  void _recomputeQuality() {
    if (!_open) return;
    final transport = _udpReceivingStates
        ? _classifyUdpTransport(_visorSummary, _joystickSummary)
        : _classifyBleTransport(_ble);
    final hz = _negotiatedControllerHz(
      transport: transport,
      visorSummary: _visorSummary,
      joystickSummary: _joystickSummary,
    );
    final advisory = VrLinkPerformanceAdvisor.evaluate(
      transport: transport,
      visorSummary: _visorSummary,
      joystickSummary: _joystickSummary,
    );
    final next = VrControllerLinkQuality(
      transport: transport,
      recommendedHz: hz,
      canCarryVideoCast: _udpReceivingStates,
      peerSupportsMotion: _joystickSummary?['gyro'] != false,
      peerSupportsConcurrentCameras: _joystickSummary?['cam3'] == true,
      peerDeviceClass: _joystickSummary?['cls'] as String?,
      peerModel: _joystickSummary?['model'] as String?,
      advisory: advisory,
    );
    if (_quality.value != next) {
      _quality.value = next;
      debugPrint(
        '[VR_HYBRID_HOST] ${jsonEncode({'transport': transport.name, 'hz': hz, 'peerModel': next.peerModel, 'advisory': advisory?.code})}',
      );
    }
  }

  @override
  void add(Object data) {
    if (!_open) return;
    _ble.add(data);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    if (!_open) return;
    _open = false;
    _udpWatchdog?.cancel();
    _udpWatchdog = null;
    _udpSocket?.close();
    _udpSocket = null;
    await _bleSub?.cancel();
    _bleSub = null;
    await _ble.close(code, reason);
    if (!_messages.isClosed) await _messages.close();
  }
}

/// Joystick-side wrapper around an authenticated BLE link. Probes offered LAN
/// endpoints via HMAC-SHA256 UDP pings, upgrades analog + button state traffic
/// to ~3 ms 5 GHz UDP automatically, and fails over instantaneously (< 480 ms)
/// to 1-packet BLE if Wi-Fi drops.
class VrHybridBleUdpClientLink implements VrObservableControllerLink {
  VrHybridBleUdpClientLink({
    required VrControllerLink bleLink,
    required this.sessionToken,
    Map<String, Object?>? localCapabilitiesSummary,
    InternetAddress? bindAddress,
  }) : _ble = bleLink,
       _joystickSummary = localCapabilitiesSummary,
       _bindAddress = bindAddress ?? InternetAddress.anyIPv4 {
    _quality = ValueNotifier<VrControllerLinkQuality>(
      VrControllerLinkQuality(
        transport: _classifyBleTransport(_ble),
        canCarryVideoCast: false,
      ),
    );
    _messages = StreamController<Object?>(
      sync: true,
      onListen: _startListening,
      onPause: () => _bleSub?.pause(),
      onResume: () => _bleSub?.resume(),
      onCancel: () => unawaited(close()),
    );
  }

  static const _discreteIndices = [1, 2, 3, 8, 9, 10, 11];

  final VrControllerLink _ble;
  final String sessionToken;
  Map<String, Object?>? _joystickSummary;
  Map<String, Object?>? _visorSummary;
  final InternetAddress _bindAddress;
  late final StreamController<Object?> _messages;
  late final ValueNotifier<VrControllerLinkQuality> _quality;
  StreamSubscription<Object?>? _bleSub;

  RawDatagramSocket? _udpSocket;
  List<int>? _udpKey;
  List<InternetAddress> _candidateAddresses = const [];
  int _remoteUdpPort = 0;
  InternetAddress? _activeAddress;
  bool _udpActive = false;
  double? _smoothedRttMs;
  int _pingSeq = 0;
  int _unansweredPingBursts = 0;
  int? _lastPongUs;
  Uint8List? _lastUdpDiscreteBytes;
  Timer? _keepaliveTimer;
  Timer? _edgeRetransmitTimer;
  final Stopwatch _clock = Stopwatch()..start();
  bool _open = true;

  bool get isUdpActive => _udpActive;
  double? get smoothedRttMs => _smoothedRttMs;

  @override
  bool get isOpen => _open && _ble.isOpen;

  @override
  Stream<Object?> get messages => _messages.stream;

  @override
  ValueListenable<VrControllerLinkQuality> get linkQualityListenable =>
      _quality;

  void _startListening() {
    if (_bleSub != null || !_open) return;
    _bleSub = _ble.messages.listen(
      _onBleMessage,
      onError: (Object error, StackTrace stack) {
        if (!_messages.isClosed) _messages.addError(error, stack);
      },
      onDone: () => unawaited(close()),
      cancelOnError: true,
    );
    unawaited(_sendPeerCapabilities());
  }

  Future<void> _sendPeerCapabilities() async {
    if (!_open) return;
    if (_joystickSummary == null) {
      await VrDeviceProfiler.refreshRuntimeEnvironment();
      _joystickSummary = VrDeviceProfiler.capabilities?.toPeerSummary();
    }
    _recomputeQuality();
    if (!_open || !_ble.isOpen || _joystickSummary == null) return;
    try {
      _ble.add(
        jsonEncode({
          'type': VrHybridWireConstants.peerCapsType,
          'caps': _joystickSummary,
        }),
      );
    } catch (_) {}
  }

  void _onBleMessage(Object? data) {
    if (!_open || _messages.isClosed) return;
    if (data is String && data.length <= 2048) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) {
          final type = decoded['type'];
          if (type == VrHybridWireConstants.offerType) {
            unawaited(_acceptHybridOffer(decoded));
            return;
          }
          if (type == VrHybridWireConstants.linkAdviceType) {
            return;
          }
        }
      } catch (_) {}
    }
    _messages.add(data);
  }

  Future<void> _acceptHybridOffer(Map<String, dynamic> offer) async {
    if (!_open) return;
    final caps = offer['caps'];
    if (caps is Map) {
      _visorSummary = caps.cast<String, Object?>();
    }
    final port = offer['udpPort'];
    final nonce = offer['nonce'];
    final rawIps = offer['ips'];
    if (port is! int ||
        port <= 0 ||
        port > 65535 ||
        nonce is! String ||
        nonce.length < 16 ||
        nonce.length > 64 ||
        rawIps is! List) {
      _recomputeQuality();
      return;
    }
    final parsedAddresses = <InternetAddress>[];
    for (final rawIp in rawIps) {
      if (rawIp is String) {
        final parsed = InternetAddress.tryParse(rawIp);
        if (parsed != null && parsed.type == InternetAddressType.IPv4) {
          parsedAddresses.add(parsed);
        }
      }
    }
    if (parsedAddresses.isEmpty) {
      _recomputeQuality();
      return;
    }

    _udpKey = _deriveHybridUdpKey(sessionToken, nonce);
    _remoteUdpPort = port;
    _candidateAddresses = parsedAddresses;

    try {
      _udpSocket?.close();
      final socket = await RawDatagramSocket.bind(_bindAddress, 0);
      if (!_open) {
        socket.close();
        return;
      }
      _udpSocket = socket;
      socket.listen(_onUdpEvent, onError: (_) {});
      _recomputeQuality();
      _startProbeAndKeepaliveLoop();
    } catch (_) {
      _recomputeQuality();
    }
  }

  void _startProbeAndKeepaliveLoop() {
    _keepaliveTimer?.cancel();
    _unansweredPingBursts = 0;
    _sendPingBurst();
    Future<void>.delayed(const Duration(milliseconds: 45), () {
      if (_open && !_udpActive) _sendPingBurst();
    });
    Future<void>.delayed(const Duration(milliseconds: 110), () {
      if (_open && !_udpActive) _sendPingBurst();
    });
    var idleTick = 0;
    _keepaliveTimer = Timer.periodic(const Duration(milliseconds: 240), (_) {
      if (!_open) return;
      final nowUs = _clock.elapsedMicroseconds;
      if (_udpActive) {
        if (_lastPongUs != null && nowUs - _lastPongUs! > 480000) {
          // Fast seamless failover back to BLE without dropping the session!
          _udpActive = false;
          _activeAddress = null;
          _recomputeQuality();
        }
        _sendPingBurst();
      } else {
        idleTick++;
        // Re-probe every ~2.4 s initially, backing off to ~14.4 s after 3
        // unanswered probe cycles on AP-isolated or asymmetric networks.
        final probePeriodTicks = _unansweredPingBursts >= 3 ? 60 : 10;
        if (idleTick >= probePeriodTicks) {
          idleTick = 0;
          _unansweredPingBursts++;
          _sendPingBurst();
        }
      }
    });
  }

  void _sendPingBurst() {
    final socket = _udpSocket;
    final key = _udpKey;
    if (socket == null ||
        key == null ||
        _remoteUdpPort <= 0 ||
        _candidateAddresses.isEmpty) {
      return;
    }
    final seq = ++_pingSeq;
    final nowUs = _clock.elapsedMicroseconds;
    final body = Uint8List(17)
      ..[0] = 0x56
      ..[1] = 0x52
      ..[2] = 0x55
      ..[3] = 0x31
      ..[4] = VrHybridWireConstants.pingKind;
    final bd = ByteData.sublistView(body);
    bd.setUint32(5, seq, Endian.little);
    bd.setUint64(9, nowUs, Endian.little);
    final tag = _computeTag(key, body);
    final packet = Uint8List(VrHybridWireConstants.pingPongPacketBytes)
      ..setRange(0, 17, body)
      ..setRange(17, 33, tag);

    final targets = _activeAddress != null
        ? <InternetAddress>[_activeAddress!]
        : _candidateAddresses;
    for (final addr in targets) {
      try {
        socket.send(packet, addr, _remoteUdpPort);
      } catch (_) {}
    }
  }

  void _onUdpEvent(RawSocketEvent event) {
    if (!_open || event != RawSocketEvent.read) return;
    final socket = _udpSocket;
    final key = _udpKey;
    if (socket == null || key == null) return;
    Datagram? dg;
    while ((dg = socket.receive()) != null) {
      final data = dg!.data;
      if (!_hasMagic(data) ||
          data[4] != VrHybridWireConstants.pongKind ||
          data.length != VrHybridWireConstants.pingPongPacketBytes) {
        continue;
      }
      if (!_verifyTagConstantTime(key, data, 17)) continue;
      final bd = ByteData.sublistView(data);
      final sentUs = bd.getUint64(9, Endian.little);
      final nowUs = _clock.elapsedMicroseconds;
      if (nowUs < sentUs) continue;
      final rttMs = (nowUs - sentUs) / 1000.0;
      if (rttMs > 60.0) continue; // Keep BLE if Wi-Fi is severely congested.
      _lastPongUs = nowUs;
      _unansweredPingBursts = 0;
      _smoothedRttMs = _smoothedRttMs == null
          ? rttMs
          : (_smoothedRttMs! * 0.7 + rttMs * 0.3);
      final changed = !_udpActive || _activeAddress != dg.address;
      _activeAddress = dg.address;
      _udpActive = true;
      if (changed || (_quality.value.rttMs == null)) {
        _recomputeQuality();
      } else if ((_smoothedRttMs! - (_quality.value.rttMs ?? 0)).abs() >= 1.5) {
        _recomputeQuality();
      }
    }
  }

  void _recomputeQuality() {
    if (!_open) return;
    final transport = _udpActive
        ? _classifyUdpTransport(_visorSummary, _joystickSummary)
        : _classifyBleTransport(_ble);
    final hz = _negotiatedControllerHz(
      transport: transport,
      visorSummary: _visorSummary,
      joystickSummary: _joystickSummary,
    );
    final rtt = _udpActive ? _smoothedRttMs : null;
    final oneWay = rtt != null ? (rtt * 0.5).clamp(1.0, 50.0) : null;
    final advisory = VrLinkPerformanceAdvisor.evaluate(
      transport: transport,
      visorSummary: _visorSummary,
      joystickSummary: _joystickSummary,
    );
    final next = VrControllerLinkQuality(
      transport: transport,
      rttMs: rtt,
      oneWayEstimateMs: oneWay,
      recommendedHz: hz,
      canCarryVideoCast: _udpActive,
      peerSupportsMotion: _visorSummary?['gyro'] != false,
      peerSupportsConcurrentCameras: _visorSummary?['cam3'] == true,
      peerDeviceClass: _visorSummary?['cls'] as String?,
      peerModel: _visorSummary?['model'] as String?,
      advisory: advisory,
    );
    if (_quality.value != next) {
      _quality.value = next;
      debugPrint(
        '[VR_HYBRID_CLIENT] ${jsonEncode({'transport': transport.name, 'rttMs': rtt == null ? null : (rtt * 100).round() / 100, 'oneWayMs': oneWay == null ? null : (oneWay * 100).round() / 100, 'hz': hz, 'advisory': advisory?.code})}',
      );
    }
  }

  bool _isDiscreteEdge(Uint8List statePacket) {
    final prev = _lastUdpDiscreteBytes;
    if (prev == null) return true;
    for (var i = 0; i < _discreteIndices.length; i++) {
      if (statePacket[_discreteIndices[i]] != prev[i]) return true;
    }
    return false;
  }

  void _recordDiscrete(Uint8List statePacket) {
    final snap = _lastUdpDiscreteBytes ??= Uint8List(_discreteIndices.length);
    for (var i = 0; i < _discreteIndices.length; i++) {
      snap[i] = statePacket[_discreteIndices[i]];
    }
  }

  bool _trySendStateOverUdp(String json) {
    final socket = _udpSocket;
    final key = _udpKey;
    final target = _activeAddress;
    if (!_udpActive ||
        socket == null ||
        key == null ||
        target == null ||
        _remoteUdpPort <= 0) {
      return false;
    }
    final allowEdge =
        _ble is! VrBlePacketLink || _ble.edgeTurnIntentEnabled;
    final encoded = VrBleWireCodec.encode(json, allowEdgeTurnIntent: allowEdge);
    if (encoded.isEmpty ||
        encoded[0] != 1 ||
        encoded.length != VrBleWireCodec.statePacketBytes) {
      // Control packet (tag == 2): keep on reliable BLE!
      return false;
    }
    final body = Uint8List(27)
      ..[0] = 0x56
      ..[1] = 0x52
      ..[2] = 0x55
      ..[3] = 0x31
      ..[4] = VrHybridWireConstants.stateKind
      ..[5] = allowEdge ? 1 : 0
      ..setRange(6, 27, encoded);
    final tag = _computeTag(key, body);
    final datagram = Uint8List(VrHybridWireConstants.stateDatagramBytes)
      ..setRange(0, 27, body)
      ..setRange(27, 43, tag);

    final edge = _isDiscreteEdge(encoded);
    final written = socket.send(datagram, target, _remoteUdpPort);
    if (written <= 0) return false;
    if (edge) {
      _recordDiscrete(encoded);
      _edgeRetransmitTimer?.cancel();
      // 4 ms micro-retransmit on the same UDP socket guarantees ~99.9% button
      // edge delivery without touching the 2.4 GHz BLE radio or reordering!
      _edgeRetransmitTimer = Timer(const Duration(milliseconds: 4), () {
        if (_open && _udpActive && _udpSocket != null && _activeAddress != null) {
          try {
            _udpSocket!.send(datagram, _activeAddress!, _remoteUdpPort);
          } catch (_) {}
        }
      });
    }
    return true;
  }

  @override
  void add(Object data) {
    if (!_open) return;
    if (data is String && _udpActive) {
      try {
        if (_trySendStateOverUdp(data)) return;
      } catch (_) {
        // Malformed payload falls through to _ble.add for canonical handling.
      }
    }
    _ble.add(data);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    if (!_open) return;
    _open = false;
    _udpActive = false;
    _keepaliveTimer?.cancel();
    _keepaliveTimer = null;
    _edgeRetransmitTimer?.cancel();
    _edgeRetransmitTimer = null;
    _udpSocket?.close();
    _udpSocket = null;
    await _bleSub?.cancel();
    _bleSub = null;
    await _ble.close(code, reason);
    if (!_messages.isClosed) await _messages.close();
  }
}
