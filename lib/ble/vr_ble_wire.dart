import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

/// Compact native-phone BLE wire format, not the core remote pose protocol.
///
/// State is exactly 21 bytes: tag, uint16 flags, mode, uint32 sequence, uint32
/// host revision (FFFFFFFF means absent), seven signed axes and two pedals.
/// Driving tilt contributes to the existing throttle/brake fields using the
/// greater of the explicit pedal and directional tilt. This preserves the
/// envelope and leaves touch axes unchanged. The receiver gives brake priority
/// when accelerator and brake arrive together.
/// Axes use -127..127; pedals use 0..255. All integers are little endian.
/// Modes are joystick=0, driving=1 and NES=2; higher values are rejected. Aiming is touch-pad-only: pose,
/// gyro, timestamp, legacy aliases and synthetic range are intentionally omitted.
/// Typed control messages (authentication/mode negotiation) remain UTF-8 JSON.
/// Bit 15 carries raw left-rim intent only after both peers negotiate
/// `edgeTurnIntent`. Legacy links leave this bit unset and omit the hint.
class VrBleWireCodec {
  static const maxPacketBytes = 1024;
  static const statePacketBytes = 21;
  static const _stateTag = 1;
  static const _controlTag = 2;
  static const _absentRevision = 0xFFFFFFFF;
  static const _flags = [
    'btnA',
    'btnB',
    'btnX',
    'btnY',
    'btnL',
    'btnR',
    'btnGrip',
    'trigger',
    'action',
    'stickClick',
    'laserSlideActive',
    'controllerVisible',
    'recenter',
    'motionAvailable',
    'drivingPaused',
    'moveAtEdge',
  ];
  static const _axes = [
    'stickX',
    'stickY',
    'lookX',
    'lookY',
    'laserX',
    'laserY',
    'steering',
    'throttle',
    'brake',
  ];

  static Uint8List encode(String json, {bool allowEdgeTurnIntent = false}) {
    // Native full snapshots contain harmless pose/legacy fields, but this is
    // still bounded before parsing untrusted input into a Dart object graph.
    if (json.length > 16384) {
      throw const FormatException('BLE JSON exceeds the input limit.');
    }
    final value = _object(json);
    if (!_isState(value)) {
      final utf = utf8.encode(json);
      if (utf.length + 1 > maxPacketBytes) {
        throw const FormatException('BLE control packet exceeds 1024 bytes.');
      }
      return Uint8List(utf.length + 1)
        ..[0] = _controlTag
        ..setRange(1, utf.length + 1, utf);
    }

    final sequence = _counter(value['sequence'], 'sequence', 0xFFFFFFFF);
    final revision = value['hostModeRevision'] == null
        ? _absentRevision
        : _counter(value['hostModeRevision'], 'hostModeRevision', 0xFFFFFFFE);
    final mode = switch (value['mode'] ?? 'joystick') {
      'joystick' => 0,
      'driving' => 1,
      'nes' => 2,
      _ => throw const FormatException(
        'BLE mode must be joystick, driving or nes.',
      ),
    };
    var flags = 0;
    for (var i = 0; i < _flags.length; i++) {
      final name = _flags[i];
      final field = value[name];
      if (value.containsKey(name) && field is! bool) {
        throw FormatException('BLE $name must be a boolean.');
      }
      if (name == 'moveAtEdge' && !allowEdgeTurnIntent) continue;
      if (field == true || (field == null && name == 'controllerVisible')) {
        flags |= 1 << i;
      }
    }
    final tiltField = value['drivingTilt'];
    if (value.containsKey('drivingTilt') &&
        (tiltField is! num ||
            !tiltField.isFinite ||
            tiltField < -1 ||
            tiltField > 1)) {
      throw const FormatException('BLE drivingTilt must be in -1..1.');
    }
    final tilt = (tiltField as num?)?.toDouble() ?? 0;
    final result = Uint8List(statePacketBytes)..[0] = _stateTag;
    final data = ByteData.sublistView(result);
    data.setUint16(1, flags, Endian.little);
    data.setUint8(3, mode);
    data.setUint32(4, sequence, Endian.little);
    data.setUint32(8, revision, Endian.little);
    for (var i = 0; i < _axes.length; i++) {
      final name = _axes[i];
      final field = value[name];
      if (value.containsKey(name) && field is! num) {
        throw FormatException('BLE $name must be numeric.');
      }
      var number = (field as num?)?.toDouble() ?? 0;
      final pedal = i >= 7;
      if (!number.isFinite || number < (pedal ? 0 : -1) || number > 1) {
        throw FormatException('BLE $name is outside its normalized range.');
      }
      if (pedal &&
          mode == 1 &&
          value['motionAvailable'] == true &&
          value['drivingPaused'] != true) {
        final motionPedal = (name == 'throttle' ? tilt : -tilt).clamp(0.0, 1.0);
        // Validate the explicit field first: a positive tilt must never hide
        // a malformed/negative pedal value by winning this maximum.
        if (motionPedal > number) number = motionPedal;
      }
      if (pedal) {
        data.setUint8(12 + i, (number * 255).round());
      } else {
        data.setInt8(12 + i, (number * 127).round());
      }
    }
    return result;
  }

  static String decode(Uint8List packet, {bool allowEdgeTurnIntent = false}) {
    _checkPacketLength(packet);
    if (packet[0] == _controlTag) {
      final text = utf8.decode(packet.sublist(1), allowMalformed: false);
      final object = _object(text);
      if (_isState(object)) {
        throw const FormatException('BLE states require the binary envelope.');
      }
      return text;
    }
    if (packet[0] != _stateTag || packet.length != statePacketBytes) {
      throw const FormatException('Unknown or malformed BLE packet envelope.');
    }
    final data = ByteData.sublistView(packet);
    final flags = data.getUint16(1, Endian.little);
    if (!allowEdgeTurnIntent && flags & 0x8000 != 0) {
      throw const FormatException('Reserved BLE state flag is set.');
    }
    final mode = switch (packet[3]) {
      0 => 'joystick',
      1 => 'driving',
      2 => 'nes',
      _ => throw const FormatException('Unknown BLE controller mode.'),
    };
    final revision = data.getUint32(8, Endian.little);
    final value = <String, Object?>{
      'sequence': data.getUint32(4, Endian.little),
      'hostModeRevision': revision == _absentRevision ? null : revision,
      'mode': mode,
      for (var i = 0; i < _flags.length; i++)
        if (_flags[i] != 'moveAtEdge' || allowEdgeTurnIntent)
          _flags[i]: flags & (1 << i) != 0,
    };
    for (var i = 0; i < _axes.length; i++) {
      final pedal = i >= 7;
      final encoded = pedal ? packet[12 + i] : data.getInt8(12 + i);
      if (encoded == -128) {
        throw const FormatException('Non-canonical BLE signed axis.');
      }
      value[_axes[i]] = encoded / (pedal ? 255 : 127);
    }
    return jsonEncode(value);
  }

  /// ATT chunks default to 20 bytes: B7, message ID, index, count, payload.
  /// The sender must finish one packet before starting the next on a link.
  static List<Uint8List> frame(
    Uint8List packet, {
    int messageId = 0,
    int maxChunkBytes = 20,
  }) {
    _checkPacketLength(packet);
    _checkChunkSize(maxChunkBytes);
    if (messageId < 0 || messageId > 255) {
      throw RangeError.range(messageId, 0, 255, 'messageId');
    }
    final capacity = maxChunkBytes - 4;
    final count = (packet.length + capacity - 1) ~/ capacity;
    if (count > 255) {
      throw const FormatException('BLE packet needs too many ATT fragments.');
    }
    return List.generate(count, (index) {
      final start = index * capacity;
      final end = (start + capacity).clamp(0, packet.length);
      return Uint8List(4 + end - start)
        ..[0] = 0xB7
        ..[1] = messageId
        ..[2] = index
        ..[3] = count
        ..setRange(4, 4 + end - start, packet, start);
    }, growable: false);
  }

  static Map<String, dynamic> _object(String json) {
    final value = jsonDecode(json);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('BLE JSON must be an object.');
    }
    if (value.containsKey('type') &&
        (value['type'] is! String || (value['type'] as String).isEmpty)) {
      throw const FormatException(
        'BLE control type must be a non-empty string.',
      );
    }
    return value;
  }

  static bool _isState(Map<String, dynamic> value) =>
      !value.containsKey('type') &&
      (value.containsKey('sequence') ||
          value.containsKey('hostModeRevision') ||
          value.containsKey('mode') ||
          value.containsKey('drivingTilt') ||
          _flags.any(value.containsKey) ||
          _axes.any(value.containsKey));

  static int _counter(Object? value, String name, int maximum) {
    if (value is! int || value < 0 || value > maximum) {
      throw FormatException('BLE $name must be an integer in 0..$maximum.');
    }
    return value;
  }

  static void _checkPacketLength(Uint8List packet) {
    if (packet.isEmpty || packet.length > maxPacketBytes) {
      throw const FormatException('BLE packet length must be 1..1024 bytes.');
    }
  }

  static void _checkChunkSize(int size) {
    if (size < 5 || size > 512) {
      throw RangeError.range(size, 5, 512, 'maxChunkBytes');
    }
  }
}

/// A structurally valid fragment cannot complete the current ordered packet.
/// The session must be replaced, but transport loss can be retried.
class VrBleFragmentInterrupted extends FormatException {
  const VrBleFragmentInterrupted(super.message);
}

/// One bounded, ordered packet in flight per BLE link. No timers are created.
/// Expiry is checked on [add]; [reset] discards state on disconnect/reconnect.
/// Invalid, duplicate or interleaved fragments reset state and throw.
class VrBleReassembler {
  VrBleReassembler({
    this.maxChunkBytes = 20,
    this.timeout = const Duration(seconds: 2),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    VrBleWireCodec._checkChunkSize(maxChunkBytes);
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be positive.');
    }
  }

  final int maxChunkBytes;
  final Duration timeout;
  final DateTime Function() _now;
  final _buffer = Uint8List(VrBleWireCodec.maxPacketBytes);
  int? _messageId;
  int _count = 0;
  int _nextIndex = 0;
  int _length = 0;
  DateTime? _deadline;

  int get bufferedBytes => _length;

  Uint8List? add(Uint8List chunk) {
    final now = _now();
    if (_deadline != null && !now.isBefore(_deadline!)) reset();
    if (chunk.length < 5 || chunk.length > maxChunkBytes || chunk[0] != 0xB7) {
      return _invalid('Invalid BLE ATT fragment header or length.');
    }
    final id = chunk[1], index = chunk[2], count = chunk[3];
    final capacity = maxChunkBytes - 4;
    final maxCount = (VrBleWireCodec.maxPacketBytes + capacity - 1) ~/ capacity;
    if (count == 0 ||
        count > maxCount ||
        index >= count ||
        (index != count - 1 && chunk.length != maxChunkBytes)) {
      return _invalid('Invalid BLE fragment count, index or payload length.');
    }
    if (_messageId == null) {
      if (index != 0) return _interrupted('Missing first BLE fragment.');
      _messageId = id;
      _count = count;
      _deadline = now.add(timeout);
    }
    if (id != _messageId || count != _count || index != _nextIndex) {
      return _interrupted('Incomplete or out-of-order BLE fragments.');
    }
    final payloadBytes = chunk.length - 4;
    if (_length + payloadBytes > _buffer.length) {
      return _invalid('Reassembled BLE packet exceeds 1024 bytes.');
    }
    _buffer.setRange(_length, _length + payloadBytes, chunk, 4);
    _length += payloadBytes;
    _nextIndex++;
    if (_nextIndex != _count) return null;
    final packet = _buffer.sublist(0, _length);
    reset();
    return packet;
  }

  Never _invalid(String message) {
    reset();
    throw FormatException(message);
  }

  Never _interrupted(String message) {
    reset();
    throw VrBleFragmentInterrupted(message);
  }

  void reset() {
    _messageId = null;
    _count = _nextIndex = _length = 0;
    _deadline = null;
  }
}

/// Serial ATT writer. At most [maxPendingMessages] messages (including the
/// active packet) are retained. Only adjacent, pending state snapshots with
/// identical discrete controls/mode/revision may be replaced by newer axes.
/// Control messages and every button/visibility edge retain their order.
/// Overflow/write/encoding errors close the writer and notify [onError] once.
class VrBlePacketWriter {
  VrBlePacketWriter({
    required this.writeChunk,
    required this.onError,
    this.maxChunkBytes = 20,
    this.maxPendingMessages = 8,
  }) {
    VrBleWireCodec._checkChunkSize(maxChunkBytes);
    if (maxPendingMessages < 1 || maxPendingMessages > 64) {
      throw RangeError.range(maxPendingMessages, 1, 64, 'maxPendingMessages');
    }
  }

  final Future<void> Function(Uint8List chunk) writeChunk;
  final void Function(Object error) onError;
  final int maxChunkBytes;
  final int maxPendingMessages;

  /// Enable only after the peer explicitly accepts the optional wire flag.
  /// Existing queued packets retain the capabilities they were encoded with.
  bool allowEdgeTurnIntent = false;
  final _queue = ListQueue<Uint8List>();
  Uint8List? _active;
  bool _running = false;
  bool _closed = false;
  int _messageId = 0;

  bool get isClosed => _closed;
  int get pendingMessages => _queue.length + (_active == null ? 0 : 1);

  void add(String json) {
    if (_closed) throw StateError('BLE packet writer is closed.');
    late final Uint8List packet;
    try {
      packet = VrBleWireCodec.encode(
        json,
        allowEdgeTurnIntent: allowEdgeTurnIntent,
      );
    } catch (error) {
      _fail(error);
      return;
    }
    if (_queue.isNotEmpty && _canCoalesce(_queue.last, packet)) {
      _queue.removeLast();
      _queue.add(packet);
    } else {
      if (pendingMessages >= maxPendingMessages) {
        _fail(StateError('BLE packet queue overflow; connection must close.'));
        return;
      }
      _queue.add(packet);
    }
    if (!_running) unawaited(_drain());
  }

  static bool _canCoalesce(Uint8List previous, Uint8List next) {
    if (previous[0] != VrBleWireCodec._stateTag ||
        next[0] != VrBleWireCodec._stateTag) {
      return false;
    }
    for (final index in const [1, 2, 3, 8, 9, 10, 11]) {
      if (previous[index] != next[index]) return false;
    }
    return true;
  }

  Future<void> _drain() async {
    _running = true;
    try {
      while (!_closed && _queue.isNotEmpty) {
        _active = _queue.removeFirst();
        final chunks = VrBleWireCodec.frame(
          _active!,
          messageId: _messageId,
          maxChunkBytes: maxChunkBytes,
        );
        _messageId = (_messageId + 1) & 0xFF;
        for (final chunk in chunks) {
          if (_closed) break;
          await writeChunk(chunk);
        }
        _active = null;
      }
    } catch (error) {
      if (!_closed) _fail(error);
    } finally {
      _active = null;
      _running = false;
    }
  }

  void _fail(Object error) {
    if (_closed) return;
    close();
    onError(error);
  }

  /// Does not cancel a platform write already awaiting completion. It prevents
  /// every subsequent fragment and discards the bounded pending queue.
  void close() {
    _closed = true;
    _queue.clear();
  }
}
