import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate/vrlizate.dart'
    show VrCompactGamepadCodec, VrCompactGamepadFrame;

import 'vr_desktop_beacon_models.dart';

/// Parsed `vrlizate://beacon?...` pairing invitation emitted by VRlizate Desktop.
class VrDesktopBeaconPairingInvite {
  const VrDesktopBeaconPairingInvite({
    required this.stationId,
    required this.stationName,
    required this.host,
    required this.port,
    required this.pin,
    this.role,
  });

  final String stationId;
  final String stationName;
  final String host;
  final int port;
  final String pin;

  /// Optional target role (`'visor'` or `'joystick'`). Null defaults to Visor
  /// unless scanned inside the Joystick pairing screen.
  final String? role;

  bool get isJoystickRole => role == 'joystick';

  Uri toUri({String? roleOverride}) => Uri(
    scheme: 'vrlizate',
    host: 'beacon',
    queryParameters: {
      'id': stationId,
      'name': stationName,
      'host': host,
      'port': '$port',
      'pin': pin,
      if ((roleOverride ?? role) != null) 'role': (roleOverride ?? role)!,
    },
  );

  Uri toJoystickUri() => toUri(roleOverride: 'joystick');

  static VrDesktopBeaconPairingInvite? tryParse(String? raw) =>
      VrDesktopBeaconWire.tryParseInviteUri(raw);
}

/// Binary + JSON wire codec with constant-time HMAC-SHA256 authentication for
/// VRlizate Desktop Estación Faro (`VRB1` UDP protocol).
abstract final class VrDesktopBeaconWire {
  static const int defaultDiscoveryPort = 45891;
  static const int hmacTagBytes = 16;

  static const int discoverProbeKind = 1;
  static const int discoverAnnounceKind = 2;
  static const int helloKind = 3;
  static const int helloAckKind = 4;
  static const int beaconStateKind = 5;
  static const int visorFeedbackKind = 6;
  static const int bridgeDirectiveKind = 7;
  static const int joystickTelemetryKind = 8;
  static const int joystickControllerFrameKind = 9;
  static const int visorControllerControlKind = 10;
  static const int voiceCommandKind = 11;

  static const int maxRelayPayloadBytes = 1200;

  static const int relayBinaryPoseFrameType = 0;
  static const int relayJsonStringFrameType = 1;
  static const int relayCompactGamepadFrameType = 2;

  /// `6 B` `VRB1` relay header + `46 B` `VrCompactGamepadFrame` + `16 B` HMAC = `68 B`.
  static const int compactGamepadPacketBytes =
      6 + VrCompactGamepadCodec.packetLength + hmacTagBytes;

  /// 124-byte fixed body + 16-byte truncated HMAC-SHA256 = 140 bytes single UDP PDU.
  static const int beaconStateBodyBytes = 124;
  static const int beaconStatePacketBytes =
      beaconStateBodyBytes + hmacTagBytes;

  static final RegExp _pinPattern = RegExp(r'^[0-9]{6}$');
  static final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_-]{4,40}$');
  static final RegExp _hostPattern = RegExp(r'^[A-Za-z0-9._:-]{1,128}$');

  static bool isValidPin(String? pin) =>
      pin != null && _pinPattern.hasMatch(pin.trim());

  static VrDesktopBeaconPairingInvite? tryParseInviteUri(String? raw) {
    if (raw == null || raw.isEmpty || raw.length > 1024) return null;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        uri.scheme != 'vrlizate' ||
        uri.host != 'beacon' ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      return null;
    }
    final id = uri.queryParameters['id']?.trim() ?? '';
    final name = uri.queryParameters['name']?.trim() ?? 'Estación Faro';
    final host = uri.queryParameters['host']?.trim() ?? '';
    final port = int.tryParse(uri.queryParameters['port'] ?? '');
    final pin = uri.queryParameters['pin']?.trim() ?? '';
    final rawRole = uri.queryParameters['role']?.trim();
    final role = (rawRole == 'joystick' || rawRole == 'visor') ? rawRole : null;
    if (!_idPattern.hasMatch(id) ||
        !_hostPattern.hasMatch(host) ||
        host.contains(RegExp(r'[\s/?#@]')) ||
        port == null ||
        port < 1024 ||
        port > 65535 ||
        !_pinPattern.hasMatch(pin) ||
        name.isEmpty ||
        name.length > 64) {
      return null;
    }
    return VrDesktopBeaconPairingInvite(
      stationId: id,
      stationName: name,
      host: host,
      port: port,
      pin: pin,
      role: role,
    );
  }

  static List<int> deriveHandshakeKey(String stationId, String pin) => Hmac(
    sha256,
    utf8.encode('vrlizate-beacon-pin-v1:$stationId'),
  ).convert(utf8.encode(pin.trim())).bytes;

  static List<int> deriveSessionKey({
    required String stationId,
    required String pin,
    required String clientNonce,
    required String serverNonce,
  }) => Hmac(
    sha256,
    deriveHandshakeKey(stationId, pin),
  ).convert(utf8.encode('vrlizate-beacon-session-v1/$clientNonce/$serverNonce')).bytes;

  static bool hasMagic(Uint8List d) =>
      d.length >= 5 &&
      d[0] == 0x56 && // 'V'
      d[1] == 0x52 && // 'R'
      d[2] == 0x42 && // 'B'
      d[3] == 0x31; // '1'

  static Uint8List computeTag(List<int> key, Uint8List body) {
    final digest = Hmac(sha256, key).convert(body).bytes;
    return Uint8List.fromList(digest.sublist(0, hmacTagBytes));
  }

  static bool verifyTagConstantTime(
    List<int> key,
    Uint8List datagram,
    int bodyEndOffset,
  ) {
    if (datagram.length != bodyEndOffset + hmacTagBytes) return false;
    final body = Uint8List.sublistView(datagram, 0, bodyEndOffset);
    final expected = Hmac(sha256, key).convert(body).bytes;
    var diff = 0;
    for (var i = 0; i < hmacTagBytes; i++) {
      diff |= datagram[bodyEndOffset + i] ^ expected[i];
    }
    return diff == 0;
  }

  /// Unauthenticated LAN discovery probe emitted by a Visor looking for stations.
  static Uint8List encodeDiscoveryProbe() =>
      Uint8List.fromList([0x56, 0x52, 0x42, 0x31, discoverProbeKind]);

  /// Public station announcement (never includes PIN or session secrets).
  static Uint8List encodeDiscoveryAnnounce({
    required String stationId,
    required String stationName,
    required int port,
    required int capabilitiesMask,
    int monitorWidthMm = 344,
    int monitorHeightMm = 215,
  }) {
    final jsonBytes = utf8.encode(
      jsonEncode({
        'id': stationId,
        'name': stationName,
        'port': port,
        'caps': capabilitiesMask,
        'mw': monitorWidthMm,
        'mh': monitorHeightMm,
      }),
    );
    final out = Uint8List(5 + jsonBytes.length);
    out[0] = 0x56;
    out[1] = 0x52;
    out[2] = 0x42;
    out[3] = 0x31;
    out[4] = discoverAnnounceKind;
    out.setRange(5, out.length, jsonBytes);
    return out;
  }

  static VrDiscoveredDesktopBeacon? decodeDiscoveryAnnounce(
    Uint8List datagram, {
    required String senderHost,
    required int nowMicros,
  }) {
    if (!hasMagic(datagram) ||
        datagram[4] != discoverAnnounceKind ||
        datagram.length > 512) {
      return null;
    }
    try {
      final raw = utf8.decode(Uint8List.sublistView(datagram, 5));
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final id = map['id'] as String?;
      final name = map['name'] as String?;
      final port = (map['port'] as num?)?.toInt();
      final caps = (map['caps'] as num?)?.toInt() ?? 0;
      if (id == null ||
          !_idPattern.hasMatch(id) ||
          name == null ||
          name.isEmpty ||
          name.length > 64 ||
          port == null ||
          port < 1024 ||
          port > 65535) {
        return null;
      }
      return VrDiscoveredDesktopBeacon(
        stationId: id,
        stationName: name,
        host: senderHost,
        port: port,
        capabilitiesMask: caps,
        lastSeenMicros: nowMicros,
        monitorWidthMm: ((map['mw'] as num?)?.toInt() ?? 344).clamp(120, 2000),
        monitorHeightMm: ((map['mh'] as num?)?.toInt() ?? 215).clamp(80, 1500),
      );
    } catch (_) {
      return null;
    }
  }

  static Uint8List encodeAuthenticatedJson({
    required int kind,
    required List<int> key,
    required Map<String, Object?> payload,
  }) {
    final jsonBytes = utf8.encode(jsonEncode(payload));
    final bodyLen = 5 + jsonBytes.length;
    final packet = Uint8List(bodyLen + hmacTagBytes);
    packet[0] = 0x56;
    packet[1] = 0x52;
    packet[2] = 0x42;
    packet[3] = 0x31;
    packet[4] = kind;
    packet.setRange(5, bodyLen, jsonBytes);
    final tag = computeTag(key, Uint8List.sublistView(packet, 0, bodyLen));
    packet.setRange(bodyLen, packet.length, tag);
    return packet;
  }

  /// Encodes an authenticated controller/control relay frame (`VrCompactGamepadFrame`
  /// `46 B` compact state, `String` JSON, or `List<int>` binary pose packet)
  /// inside a single `VRB1` UDP PDU.
  static Uint8List? encodeAuthenticatedRelayFrame({
    required int kind,
    required List<int> key,
    required Object frame,
  }) {
    final int frameType;
    final List<int> payloadBytes;
    if (frame is VrCompactGamepadFrame) {
      frameType = relayCompactGamepadFrameType;
      payloadBytes = const VrCompactGamepadCodec().encode(frame);
    } else if (frame is String) {
      frameType = relayJsonStringFrameType;
      payloadBytes = utf8.encode(frame);
    } else if (frame is Uint8List) {
      frameType = relayBinaryPoseFrameType;
      payloadBytes = frame;
    } else if (frame is List<int>) {
      frameType = relayBinaryPoseFrameType;
      payloadBytes = Uint8List.fromList(frame);
    } else {
      return null;
    }
    if (payloadBytes.isEmpty || payloadBytes.length > maxRelayPayloadBytes) {
      return null;
    }
    final bodyLen = 6 + payloadBytes.length;
    final packet = Uint8List(bodyLen + hmacTagBytes);
    packet[0] = 0x56;
    packet[1] = 0x52;
    packet[2] = 0x42;
    packet[3] = 0x31;
    packet[4] = kind;
    packet[5] = frameType;
    packet.setRange(6, bodyLen, payloadBytes);
    final tag = computeTag(key, Uint8List.sublistView(packet, 0, bodyLen));
    packet.setRange(bodyLen, packet.length, tag);
    return packet;
  }

  /// Decodes and HMAC-verifies an authenticated controller/control relay frame.
  static Object? decodeAuthenticatedRelayFrame({
    required int expectedKind,
    required List<int> key,
    required Uint8List datagram,
  }) {
    final minLen = 6 + 1 + hmacTagBytes;
    final maxLen = 6 + maxRelayPayloadBytes + hmacTagBytes;
    if (!hasMagic(datagram) ||
        datagram.length < minLen ||
        datagram.length > maxLen ||
        datagram[4] != expectedKind) {
      return null;
    }
    final bodyLen = datagram.length - hmacTagBytes;
    if (!verifyTagConstantTime(key, datagram, bodyLen)) {
      return null;
    }
    final frameType = datagram[5];
    final body = Uint8List.sublistView(datagram, 6, bodyLen);
    if (frameType == relayCompactGamepadFrameType) {
      return const VrCompactGamepadCodec().tryDecode(body);
    }
    if (frameType == relayBinaryPoseFrameType) {
      return Uint8List.fromList(body);
    }
    if (frameType == relayJsonStringFrameType) {
      try {
        return utf8.decode(body);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static Map<String, dynamic>? decodeAuthenticatedJson({
    required int expectedKind,
    required List<int> key,
    required Uint8List datagram,
    int maxBytes = 1024,
  }) {
    if (!hasMagic(datagram) ||
        datagram[4] != expectedKind ||
        datagram.length <= 5 + hmacTagBytes ||
        datagram.length > maxBytes) {
      return null;
    }
    final bodyLen = datagram.length - hmacTagBytes;
    if (!verifyTagConstantTime(key, datagram, bodyLen)) return null;
    try {
      final decoded = utf8.decode(Uint8List.sublistView(datagram, 5, bodyLen));
      return jsonDecode(decoded) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static int _quantizeUnit(double v) =>
      (v.clamp(0.0, 1.0) * 255.0).round().clamp(0, 255);

  static double _dequantizeUnit(int b) => (b & 0xFF) / 255.0;

  /// Packs [VrTriNodeDepthSolution] into a zero-JSON 140-byte binary datagram.
  static Uint8List encodeBeaconState({
    required List<int> sessionKey,
    required VrTriNodeDepthSolution solution,
  }) {
    final packet = Uint8List(beaconStatePacketBytes);
    final bd = ByteData.sublistView(packet);
    packet[0] = 0x56;
    packet[1] = 0x52;
    packet[2] = 0x42;
    packet[3] = 0x31;
    packet[4] = beaconStateKind;
    var flags = 0;
    if (solution.leftHandRaised) flags |= 1 << 0;
    if (solution.rightHandRaised) flags |= 1 << 1;
    if (solution.visorFiducialLocked) flags |= 1 << 2;
    if (solution.joystickFiducialLocked) flags |= 1 << 3;
    packet[5] = flags;
    packet[6] = solution.gesture.index.clamp(0, 255);
    packet[7] = solution.activeModalitiesMask & 0xFF;

    bd.setUint32(8, solution.sequence, Endian.little);
    bd.setInt64(12, solution.timestampMicros, Endian.little);

    bd.setFloat32(20, solution.computerToVisorMeters, Endian.little);
    bd.setFloat32(24, solution.computerToJoystickMeters, Endian.little);
    bd.setFloat32(28, solution.visorToJoystickMeters, Endian.little);
    bd.setFloat32(32, solution.deskClearanceMeters, Endian.little);
    bd.setFloat32(36, solution.visorAzimuthRadians, Endian.little);
    bd.setFloat32(40, solution.yawAnchorCorrectionRadians, Endian.little);

    final vp = solution.visorRoomPosition;
    bd.setFloat32(44, vp.x, Endian.little);
    bd.setFloat32(48, vp.y, Endian.little);
    bd.setFloat32(52, vp.z, Endian.little);

    final jp = solution.joystickRoomPosition;
    bd.setFloat32(56, jp.x, Endian.little);
    bd.setFloat32(60, jp.y, Endian.little);
    bd.setFloat32(64, jp.z, Endian.little);

    final lh = solution.leftHandRelHead;
    bd.setFloat32(68, lh.x, Endian.little);
    bd.setFloat32(72, lh.y, Endian.little);
    bd.setFloat32(76, lh.z, Endian.little);

    final rh = solution.rightHandRelHead;
    bd.setFloat32(80, rh.x, Endian.little);
    bd.setFloat32(84, rh.y, Endian.little);
    bd.setFloat32(88, rh.z, Endian.little);

    final lv = solution.leftHandVelocity;
    bd.setFloat32(92, lv.x, Endian.little);
    bd.setFloat32(96, lv.y, Endian.little);
    bd.setFloat32(100, lv.z, Endian.little);

    final rv = solution.rightHandVelocity;
    bd.setFloat32(104, rv.x, Endian.little);
    bd.setFloat32(108, rv.y, Endian.little);
    bd.setFloat32(112, rv.z, Endian.little);

    packet[116] = _quantizeUnit(solution.leftHandConfidence);
    packet[117] = _quantizeUnit(solution.rightHandConfidence);
    packet[118] = _quantizeUnit(solution.leftPinchStrength);
    packet[119] = _quantizeUnit(solution.rightPinchStrength);
    packet[120] = _quantizeUnit(solution.confidence);
    final ipdM = solution.estimatedUserIpdMeters;
    packet[121] = (ipdM != null && ipdM.isFinite && ipdM >= 0.050 && ipdM <= 0.080)
        ? (((ipdM * 1000.0 - 50.0) * 5.0).round().clamp(1, 150))
        : 0;
    packet[122] = solution.facialExpression.index.clamp(0, 255);
    packet[123] = _quantizeUnit(solution.facialConfidence);

    final tag = computeTag(
      sessionKey,
      Uint8List.sublistView(packet, 0, beaconStateBodyBytes),
    );
    packet.setRange(beaconStateBodyBytes, beaconStatePacketBytes, tag);
    return packet;
  }

  /// Verifies HMAC-SHA256 in constant time and unpacks [VrTriNodeDepthSolution].
  static VrTriNodeDepthSolution? decodeBeaconState({
    required List<int> sessionKey,
    required Uint8List datagram,
  }) {
    if (!hasMagic(datagram) ||
        datagram.length != beaconStatePacketBytes ||
        datagram[4] != beaconStateKind) {
      return null;
    }
    if (!verifyTagConstantTime(sessionKey, datagram, beaconStateBodyBytes)) {
      return null;
    }
    final bd = ByteData.sublistView(datagram, 0, beaconStateBodyBytes);
    final flags = datagram[5];
    final gestureIdx = datagram[6];
    final modalities = datagram[7];
    final seq = bd.getUint32(8, Endian.little);
    final ts = bd.getInt64(12, Endian.little);

    final floats = List<double>.generate(
      24,
      (i) => bd.getFloat32(20 + i * 4, Endian.little),
    );
    if (floats.any((f) => !f.isFinite) || ts < 0) return null;

    final gesture = gestureIdx < VrBeaconHandGesture.values.length
        ? VrBeaconHandGesture.values[gestureIdx]
        : VrBeaconHandGesture.none;

    return VrTriNodeDepthSolution(
      timestampMicros: ts,
      sequence: seq,
      computerToVisorMeters: floats[0],
      computerToJoystickMeters: floats[1],
      visorToJoystickMeters: floats[2],
      deskClearanceMeters: floats[3],
      visorAzimuthRadians: floats[4],
      yawAnchorCorrectionRadians: floats[5],
      visorRoomPosition: vm.Vector3(floats[6], floats[7], floats[8]),
      joystickRoomPosition: vm.Vector3(floats[9], floats[10], floats[11]),
      leftHandRelHead: vm.Vector3(floats[12], floats[13], floats[14]),
      rightHandRelHead: vm.Vector3(floats[15], floats[16], floats[17]),
      leftHandVelocity: vm.Vector3(floats[18], floats[19], floats[20]),
      rightHandVelocity: vm.Vector3(floats[21], floats[22], floats[23]),
      leftHandConfidence: _dequantizeUnit(datagram[116]),
      rightHandConfidence: _dequantizeUnit(datagram[117]),
      leftPinchStrength: _dequantizeUnit(datagram[118]),
      rightPinchStrength: _dequantizeUnit(datagram[119]),
      confidence: _dequantizeUnit(datagram[120]),
      leftHandRaised: (flags & (1 << 0)) != 0,
      rightHandRaised: (flags & (1 << 1)) != 0,
      gesture: gesture,
      activeModalitiesMask: modalities,
      visorFiducialLocked: (flags & (1 << 2)) != 0,
      joystickFiducialLocked: (flags & (1 << 3)) != 0,
      estimatedUserIpdMeters: datagram[121] > 0
          ? (50.0 + datagram[121] / 5.0) / 1000.0
          : null,
      facialExpression: datagram[122] < VrFacialExpression.values.length
          ? VrFacialExpression.values[datagram[122]]
          : VrFacialExpression.neutral,
      facialConfidence: _dequantizeUnit(datagram[123]),
    );
  }
}
