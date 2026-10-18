import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:vrlizate/vrlizate.dart';
import 'package:vrlizate_joystick/vrlizate_joystick.dart';

/// A short-lived invitation, not a permanent authorization of a viewer.
/// Restoring it always performs the transport's authentication again.
class VrControllerPairingStore {
  VrControllerPairingStore({
    FlutterSecureStorage? storage,
    DateTime Function()? now,
    this.lifetime = const Duration(hours: 24),
    bool? enabled,
  }) : _storage =
           storage ??
           const FlutterSecureStorage(
             aOptions: AndroidOptions(
               encryptedSharedPreferences: true,
               sharedPreferencesName: 'vrlizate_controller_pairing',
             ),
             iOptions: IOSOptions(
               accessibility: KeychainAccessibility.first_unlock_this_device,
             ),
           ),
       _now = now ?? DateTime.now,
       _enabled =
           enabled ??
           (!kIsWeb &&
               (defaultTargetPlatform == TargetPlatform.android ||
                   defaultTargetPlatform == TargetPlatform.iOS)) {
    if (lifetime <= Duration.zero) {
      throw ArgumentError.value(lifetime, 'lifetime');
    }
  }

  static final instance = VrControllerPairingStore();
  static const storageKey = 'vrlizate_controller_invitation_v1';
  final FlutterSecureStorage _storage;
  final DateTime Function() _now;
  final Duration lifetime;
  final bool _enabled;
  Future<void> _pending = Future.value();

  // Serialize read/write/forget so a late expired-session callback cannot
  // erase a newly authenticated invitation or resurrect a forgotten one.
  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<VrPairingPayload?> load() => _serial(_load);

  Future<VrPairingPayload?> _load() async {
    if (!_enabled) return null;
    try {
      final raw = await _storage.read(key: storageKey);
      if (raw == null) return null;
      if (raw.length > 16384) throw const FormatException();
      final value = jsonDecode(raw);
      if (value is! Map ||
          value['version'] != 1 ||
          value['expiresAt'] is! int ||
          value['invitation'] is! String) {
        throw const FormatException();
      }
      final remaining =
          (value['expiresAt'] as int) - _now().millisecondsSinceEpoch;
      if (remaining <= 0 || remaining > lifetime.inMilliseconds) {
        throw const FormatException();
      }
      return parseVrControllerPairingCode(
        value['invitation'] as String,
        supportedTransports: const {VrTransportType.bluetoothLe},
      );
    } on FormatException {
      // Never log an invitation, token or platform exception containing one.
      try {
        await _storage.delete(key: storageKey);
      } catch (_) {}
      return null;
    } catch (_) {
      // A locked/unavailable vault is not an expired invitation. Keep it so
      // unlocking the device can restore the same pairing on the next read.
      return null;
    }
  }

  /// Call only after a link has authenticated; scanning a QR alone is not enough.
  Future<void> remember(VrPairingPayload invitation) => _serial(() async {
    if (!_enabled) return;
    try {
      final uri = invitation.toUri().toString();
      parseVrControllerPairingCode(
        uri,
        supportedTransports: const {VrTransportType.bluetoothLe},
      );
      await _storage.write(
        key: storageKey,
        value: jsonEncode({
          'version': 1,
          'expiresAt': _now().add(lifetime).millisecondsSinceEpoch,
          'invitation': uri,
        }),
      );
    } catch (_) {
      // Secure storage is optional; an unavailable vault must not break input.
    }
  });

  Future<void> forget({VrPairingPayload? matching}) => _serial(() async {
    if (!_enabled) return;
    try {
      if (matching != null) {
        final current = await _load();
        if (current == null || current.toUri() != matching.toUri()) return;
      }
      await _storage.delete(key: storageKey);
    } catch (_) {}
  });
}
