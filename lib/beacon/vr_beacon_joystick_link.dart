import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:vrlizate/vrlizate.dart' show VrCompactGamepadFrame;
import 'package:vrlizate_joystick/vrlizate_joystick.dart';

import 'vr_desktop_autonomous_bridge.dart';
import 'vr_desktop_beacon_wire.dart';

/// In-memory duplex pipe used by [VrDesktopBeaconStation] to mirror live
/// Joystick snapshots and supply neutral mode ACKs before a Visor joins.
class VrInMemoryCoordinatorControllerPipe {
  VrInMemoryCoordinatorControllerPipe() {
    _stationSide = _PipeEndpoint(
      incoming: _toStation.stream,
      onSend: (data) {
        if (!_closed && !_toJoystick.isClosed) {
          _toJoystick.add(data);
        }
      },
      onClose: close,
      isOpenGetter: () => !_closed,
    );
    _joystickSide = _PipeEndpoint(
      incoming: _toJoystick.stream,
      onSend: (data) {
        if (!_closed && !_toStation.isClosed) {
          _toStation.add(data);
        }
      },
      onClose: close,
      isOpenGetter: () => !_closed,
    );
  }

  final StreamController<Object?> _toStation =
      StreamController<Object?>.broadcast();
  final StreamController<Object?> _toJoystick =
      StreamController<Object?>.broadcast();
  bool _closed = false;
  late final VrControllerLink _stationSide;
  late final VrControllerLink _joystickSide;

  VrControllerLink get stationSide => _stationSide;
  VrControllerLink get joystickSide => _joystickSide;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _toStation.close();
    await _toJoystick.close();
  }
}

class _PipeEndpoint implements VrControllerLink, VrCompactGamepadCapableLink {
  _PipeEndpoint({
    required this.incoming,
    required this.onSend,
    required this.onClose,
    required this.isOpenGetter,
  });

  final Stream<Object?> incoming;
  final void Function(Object data) onSend;
  final Future<void> Function() onClose;
  final bool Function() isOpenGetter;

  @override
  bool get supportsCompactGamepadFrames => true;

  @override
  Stream<Object?> get messages => incoming;

  @override
  bool get isOpen => isOpenGetter();

  @override
  void add(Object data) => onSend(data);

  @override
  Future<void> close([int? code, String? reason]) => onClose();
}

/// Authenticated LAN `VrControllerLink` connecting a Smartphone in **Modo
/// Joystick** directly to a **VRlizate Desktop (Estación Faro)** `3D Set`
/// coordinator (`Joystick ↔ PC ↔ Visor`).
class VrBeaconJoystickControllerLink
    implements VrControllerLink, VrCompactGamepadCapableLink {
  VrBeaconJoystickControllerLink._(
    this._socket,
    this._stationAddress,
    this._stationPort,
    this.stationId,
    this.stationName,
    this._sessionKey,
    this._clockUs,
  ) {
    _lastServerSeenUs = _clockUs();
    _telemetryTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _sendTelemetryHeartbeat(),
    );
    _sendTelemetryHeartbeat();
  }

  void _attachSocketSubscription(StreamSubscription<RawSocketEvent> sub) {
    _socketSub = sub;
  }

  final RawDatagramSocket _socket;
  final InternetAddress _stationAddress;
  final int _stationPort;
  final String stationId;
  final String stationName;
  final List<int> _sessionKey;
  final int Function() _clockUs;

  final StreamController<Object?> _incoming =
      StreamController<Object?>.broadcast();
  StreamSubscription<RawSocketEvent>? _socketSub;
  Timer? _telemetryTimer;

  bool _closed = false;
  int _lastServerSeenUs = 0;
  int _bridgeRevision = 0;
  int _recommendedHz = 60;
  bool _castOffloadAck = true;
  bool _visionOffloadAck = false;
  int _framesSent = 0;
  int _compactBinaryFramesSent = 0;

  int get framesSent => _framesSent;
  int get compactBinaryFramesSent => _compactBinaryFramesSent;

  @override
  bool get supportsCompactGamepadFrames => true;

  @override
  Stream<Object?> get messages => _incoming.stream;

  @override
  bool get isOpen => !_closed;

  /// Connects and authenticates with [invite] as the `joystick` role in the
  /// Computer's `3D Set`.
  static Future<VrBeaconJoystickControllerLink> connect(
    VrDesktopBeaconPairingInvite invite, {
    Duration timeout = const Duration(seconds: 3),
    int Function()? monotonicMicroseconds,
  }) async {
    if (kIsWeb) {
      throw const VrControllerConnectionException(
        'El enlace UDP del 3D Set requiere VRlizate nativo.',
      );
    }
    if (!VrDesktopBeaconWire.isValidPin(invite.pin)) {
      throw const VrControllerConnectionException(
        'El PIN de la Estación Faro debe tener 6 dígitos.',
      );
    }
    final clock =
        monotonicMicroseconds ??
        (() {
          final sw = Stopwatch()..start();
          return () => sw.elapsedMicroseconds;
        })();

    final resolved =
        InternetAddress.tryParse(invite.host) ??
        (await InternetAddress.lookup(
          invite.host,
        )).firstWhere((a) => a.type == InternetAddressType.IPv4);

    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    var targetAddr = resolved;
    var targetPort = invite.port;
    final rng = math.Random.secure();
    final clientNonce = base64UrlEncode(
      List<int>.generate(16, (_) => rng.nextInt(256)),
    );
    final handshakeKey = VrDesktopBeaconWire.deriveHandshakeKey(
      invite.stationId,
      invite.pin,
    );
    final helloPacket = VrDesktopBeaconWire.encodeAuthenticatedJson(
      kind: VrDesktopBeaconWire.helloKind,
      key: handshakeKey,
      payload: {
        'cn': clientNonce,
        'role': 'joystick',
        'ts': clock(),
      },
    );
    final discoveryProbe = VrDesktopBeaconWire.encodeDiscoveryProbe();

    final completer = Completer<List<int>>();
    void Function(RawSocketEvent)? activeHandler;
    late final StreamSubscription<RawSocketEvent> sub;
    Timer? retryTimer;
    var helloAttempts = 0;

    void sendHello() {
      helloAttempts++;
      try {
        socket.send(helloPacket, targetAddr, targetPort);
      } catch (_) {}
      // If cached station port/IP changed after a Desktop restart, simultaneously
      // probe LAN discovery so the Joystick resolves the new port automatically!
      if (helloAttempts >= 2) {
        try {
          socket.send(
            discoveryProbe,
            targetAddr,
            VrDesktopBeaconWire.defaultDiscoveryPort,
          );
        } catch (_) {}
        try {
          socket.send(
            discoveryProbe,
            InternetAddress('255.255.255.255'),
            VrDesktopBeaconWire.defaultDiscoveryPort,
          );
        } catch (_) {}
      }
    }

    activeHandler = (event) {
      if (event != RawSocketEvent.read) return;
      Datagram? dg;
      while ((dg = socket.receive()) != null) {
        final raw = dg!.data;
        if (!VrDesktopBeaconWire.hasMagic(raw)) continue;
        if (raw[4] == VrDesktopBeaconWire.discoverAnnounceKind) {
          final info = VrDesktopBeaconWire.decodeDiscoveryAnnounce(
            raw,
            senderHost: dg.address.address,
            nowMicros: clock(),
          );
          if (info != null && info.stationId == invite.stationId) {
            targetAddr = dg.address;
            targetPort = info.port;
            try {
              socket.send(helloPacket, targetAddr, targetPort);
            } catch (_) {}
          }
          continue;
        }
        final map = VrDesktopBeaconWire.decodeAuthenticatedJson(
          expectedKind: VrDesktopBeaconWire.helloAckKind,
          key: handshakeKey,
          datagram: raw,
        );
        if (map == null) continue;
        final sn = map['sn'] as String?;
        final cn = map['cn'] as String?;
        if (sn == null || cn != clientNonce) continue;
        targetAddr = dg.address;
        targetPort = dg.port;
        final sessionKey = VrDesktopBeaconWire.deriveSessionKey(
          stationId: invite.stationId,
          pin: invite.pin,
          clientNonce: clientNonce,
          serverNonce: sn,
        );
        if (!completer.isCompleted) {
          completer.complete(sessionKey);
        }
        return;
      }
    };
    sub = socket.listen((event) => activeHandler?.call(event));

    sendHello();
    retryTimer = Timer.periodic(
      const Duration(milliseconds: 350),
      (_) => sendHello(),
    );

    try {
      final sessionKey = await completer.future.timeout(timeout);
      retryTimer.cancel();
      final link = VrBeaconJoystickControllerLink._(
        socket,
        targetAddr,
        targetPort,
        invite.stationId,
        invite.stationName,
        sessionKey,
        clock,
      );
      activeHandler = link._onSocketEvent;
      link._attachSocketSubscription(sub);
      // Emit initial connected Desktop Bridge state immediately so the
      // Joystick HUD reflects 3D Set coordination right away.
      Future<void>.microtask(() {
        if (!link._closed && !link._incoming.isClosed) {
          link._incoming.add(
            VrDesktopBridgeState(
              revision: ++link._bridgeRevision,
              stationConnected: true,
              stationName: invite.stationName,
              castOffloadedToDesktop: true,
              visionOffloadedToDesktop: true,
              recommendedJoystickHz: 120,
              activeDecisionSummary:
                  '3D Set activo · Coordinado por ${invite.stationName}',
            ).toJsonMessage(),
          );
        }
      });
      return link;
    } catch (_) {
      retryTimer.cancel();
      await sub.cancel();
      socket.close();
      throw const VrControllerConnectionException(
        'No se pudo vincular el mando con la Estación Faro (verifica IP/PIN).',
      );
    }
  }

  void _onSocketEvent(RawSocketEvent event) {
    if (_closed || event != RawSocketEvent.read) return;
    Datagram? dg;
    while ((dg = _socket.receive()) != null) {
      final data = dg!.data;
      if (!VrDesktopBeaconWire.hasMagic(data)) continue;
      final kind = data[4];
      if (kind == VrDesktopBeaconWire.visorControllerControlKind) {
        final frame = VrDesktopBeaconWire.decodeAuthenticatedRelayFrame(
          expectedKind: VrDesktopBeaconWire.visorControllerControlKind,
          key: _sessionKey,
          datagram: data,
        );
        if (frame != null && !_incoming.isClosed) {
          _lastServerSeenUs = _clockUs();
          _incoming.add(frame);
        }
      } else if (kind == VrDesktopBeaconWire.bridgeDirectiveKind) {
        final map = VrDesktopBeaconWire.decodeAuthenticatedJson(
          expectedKind: VrDesktopBeaconWire.bridgeDirectiveKind,
          key: _sessionKey,
          datagram: data,
        );
        if (map == null) continue;
        final directive = VrDesktopBridgeDirective.fromJson(map);
        if (directive == null) continue;
        _lastServerSeenUs = _clockUs();
        _recommendedHz = directive.recommendedJoystickHz;
        _castOffloadAck = directive.offloadCastToDesktop;
        _visionOffloadAck = directive.offloadJoystickVisionToDesktop;
        if (!_incoming.isClosed) {
          _incoming.add(
            directive
                .toJoystickBridgeState(revision: ++_bridgeRevision)
                .toJsonMessage(),
          );
        }
      }
    }
    // Keepalive check: if PC station disappears for >12s, close link so
    // PhoneControllerPage's automatic reconnect kicks in cleanly.
    if ((_clockUs() - _lastServerSeenUs) > 12000000) {
      unawaited(close());
    }
  }

  void _sendTelemetryHeartbeat() {
    if (_closed) return;
    // Proactive dead-station watchdog on the 500 ms heartbeat timer (even when
    // zero UDP packets arrive from a restarted station) so PhoneControllerPage
    // triggers automatic reconnect within ~4.5 s!
    if ((_clockUs() - _lastServerSeenUs) > 4500000) {
      unawaited(close());
      return;
    }
    final packet = VrDesktopBeaconWire.encodeAuthenticatedJson(
      kind: VrDesktopBeaconWire.joystickTelemetryKind,
      key: _sessionKey,
      payload: VrJoystickDirectBridgeTelemetry(
        timestampMicros: _clockUs(),
        linkHz: _recommendedHz,
        castOffloadedAck: _castOffloadAck,
        visionOffloadedAck: _visionOffloadAck,
      ).toJson(),
    );
    try {
      _socket.send(packet, _stationAddress, _stationPort);
    } catch (_) {}
  }

  @override
  void add(Object data) {
    if (_closed) return;
    final packet = VrDesktopBeaconWire.encodeAuthenticatedRelayFrame(
      kind: VrDesktopBeaconWire.joystickControllerFrameKind,
      key: _sessionKey,
      frame: data,
    );
    if (packet == null) return;
    try {
      _socket.send(packet, _stationAddress, _stationPort);
      _framesSent++;
      if (data is VrCompactGamepadFrame) {
        _compactBinaryFramesSent++;
      }
    } catch (_) {}
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    if (_closed) return;
    _closed = true;
    _telemetryTimer?.cancel();
    _telemetryTimer = null;
    await _socketSub?.cancel();
    _socketSub = null;
    _socket.close();
    await _incoming.close();
  }
}

/// Duplex `VrControllerLink` exposed on the **Visor** (`VrDesktopBeaconClient`)
/// so [VrRemoteControllerService.attachControllerLink] receives Joystick inputs
/// coordinated by the Computer (`Estación Faro`).
class VrBeaconVisorControllerLink
    implements VrControllerLink, VrCompactGamepadCapableLink {
  VrBeaconVisorControllerLink({required this.onSendControl});

  final void Function(Object data) onSendControl;
  final StreamController<Object?> _incoming =
      StreamController<Object?>.broadcast();
  bool _open = true;

  @override
  bool get supportsCompactGamepadFrames => true;

  @override
  Stream<Object?> get messages => _incoming.stream;

  @override
  bool get isOpen => _open;

  void deliverFromStation(Object frame) {
    if (!_open || _incoming.isClosed) return;
    _incoming.add(frame);
  }

  @override
  void add(Object data) {
    if (!_open) return;
    onSendControl(data);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    if (!_open) return;
    _open = false;
    await _incoming.close();
  }
}
