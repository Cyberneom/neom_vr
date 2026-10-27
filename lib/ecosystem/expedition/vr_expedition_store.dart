import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:neom_core/domain/use_cases/app_hive_service.dart';
import 'package:vrlizate_apps/vrlizate_apps.dart';

import '../auth/vr_ecosystem_session.dart';
import '../storage/vr_hive_lease.dart';

/// Device-local expedition snapshots, isolated by verified account/profile or
/// the device's guest. This adapter neither authenticates nor publishes awards.
class NeomVrExpeditionStore implements VrlzExpeditionPersistence {
  NeomVrExpeditionStore({
    required AppHiveService hive,
    required String owner,
    required bool Function() isCurrent,
    // Keep the injected service private while preserving a public named argument.
    // ignore: prefer_initializing_formals
  }) : _hive = hive,
       _ownerHash = _hash(owner),
       _isOwnerCurrent = isCurrent {
    if (owner.isEmpty || utf8.encode(owner).length > 4096) {
      throw ArgumentError('A bounded expedition owner is required.');
    }
  }

  static const int maxSnapshotBytes = 32 * 1024;
  static const String _boxName = 'vrlizate_expedition_v1';
  // Shared across instances: a replacement route reads its preceding route's
  // completed write, and a failed write never poisons later work on that key.
  static final Map<String, Future<void>> _pending = {};

  final AppHiveService _hive;
  final String _ownerHash;
  final bool Function() _isOwnerCurrent;
  VrHiveLease? _lease;
  bool _disposed = false;

  static Future<NeomVrExpeditionStore> open({
    VrEcosystemSession? session,
  }) async {
    final identity = session?.captureIdentity();
    final revision = session?.revision;
    final owner = identity == null
        ? 'local-guest'
        : jsonEncode([identity.uid, identity.profileId]);
    bool current() =>
        session == null ||
        (!session.isDisposed &&
            session.revision == revision &&
            (identity == null
                ? session.captureIdentity() == null
                : identity.isCurrent()));
    if (!current()) throw StateError('Expedition session changed.');
    await VrHiveLease.prepare();
    if (!current()) throw StateError('Expedition session changed.');
    final lease = VrHiveLease.acquire();
    late NeomVrExpeditionStore store;
    try {
      store = NeomVrExpeditionStore(
        hive: lease.service,
        owner: owner,
        isCurrent: current,
      ).._lease = lease;
    } catch (_) {
      lease.release();
      rethrow;
    }
    if (!store.isCurrent) {
      store.dispose();
      throw StateError('Expedition session changed.');
    }
    return store;
  }

  bool get isCurrent => !_disposed && _isOwnerCurrent();

  /// Opaque device-local namespace reusable by the host for pose save stores.
  /// This digest identifies a partition; it is never proof of authorization.
  String get storageScope => _ownerHash;

  void _requireCurrent() {
    if (!isCurrent) throw StateError('Expedition session changed.');
  }

  static String _hash(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  String _key(String expeditionId) {
    if (expeditionId.isEmpty ||
        expeditionId.length > 256 ||
        expeditionId.codeUnits.any((c) => c < 32 || c == 127)) {
      throw ArgumentError('A bounded expedition identifier is required.');
    }
    return 'v1.$_ownerHash.${_hash(expeditionId)}';
  }

  Future<T> _serial<T>(String key, Future<T> Function() operation) {
    final result = (_pending[key] ?? Future<void>.value()).then((_) async {
      _requireCurrent();
      return operation();
    });
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _pending[key] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_pending[key], tail)) _pending.remove(key);
      }),
    );
    return result;
  }

  @override
  Future<Uint8List?> read(String expeditionId) async {
    _requireCurrent();
    final key = _key(expeditionId);
    return _serial(key, () async {
      final box = await _hive.getBox(_boxName, limit: false);
      _requireCurrent();
      final value = box.get(key);
      if (value == null) return null;
      if (value is! Uint8List || value.length > maxSnapshotBytes) {
        throw const FormatException('Invalid local expedition snapshot.');
      }
      final copy = Uint8List.fromList(value);
      _requireCurrent();
      return copy;
    });
  }

  @override
  Future<void> write(String expeditionId, Uint8List snapshot) async {
    _requireCurrent();
    final key = _key(expeditionId);
    if (snapshot.length > maxSnapshotBytes) {
      throw ArgumentError('Expedition snapshot exceeds its storage limit.');
    }
    // Clone before joining the queue, so callers cannot mutate a pending write.
    final copy = Uint8List.fromList(snapshot);
    await _serial(key, () async {
      final box = await _hive.getBox(_boxName, limit: false);
      _requireCurrent();
      await box.put(key, copy);
      _requireCurrent();
    });
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _lease?.release();
    _lease = null;
  }
}
