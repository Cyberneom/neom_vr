import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:neom_core/data/implementations/app_hive_controller.dart';
import 'package:neom_core/domain/model/post.dart';
import 'package:neom_core/domain/use_cases/app_hive_service.dart';
import 'package:neom_posts/data/hive/posts_hive_controller.dart';
import 'package:neom_posts/data/sync/posts_sync_service.dart';
import 'package:neom_posts/ui/upload/post_upload_controller.dart';
import 'package:neom_timeline/ui/timeline_controller.dart';
import 'package:sint/sint.dart';

import '../auth/vr_ecosystem_session.dart';

/// Host adapter to existing posts/timeline storage. Implementations own their
/// listeners/controllers; the page owns the source returned by its factory.
abstract class VrEcosystemSocialSource extends ChangeNotifier {
  List<Post> get posts;
  bool get offline;
  String? get loadMessage;
  Future<void> initialize();
  Future<void> refresh();
  Future<bool> submitText(String text);
  void invalidate();
}

class NeomVrEcosystemSocialSource extends VrEcosystemSocialSource {
  NeomVrEcosystemSocialSource({required this.session, required this.identity});

  final VrEcosystemSession session;
  final VrEcosystemIdentity identity;
  final PostsHiveController _storage = PostsHiveController();
  TimelineController? _timeline;
  VoidCallback? _removeListener;
  _HiveLease? _hiveLease;
  VrPostsAccountLease? _accountLease;
  PostUploadController? _composer;
  int? _storageRevision;
  bool _disposed = false;

  bool get _current =>
      !_disposed &&
      identity.isCurrent() &&
      _storageRevision == _storage.sessionRevision &&
      _storage.accountId == identity.uid;

  @override
  List<Post> get posts => !_current
      ? const []
      : List.unmodifiable(_timeline?.sortedPosts.values ?? const <Post>[]);
  @override
  bool get offline => _timeline?.isOfflineMode ?? false;
  @override
  String? get loadMessage => _timeline?.loadFailure == null
      ? null
      : 'No se pudo actualizar el muro. Se conserva el contenido de esta cuenta guardado en el dispositivo.';

  @override
  Future<void> initialize() async {
    identity.requireCurrent();
    if (_timeline != null) return;
    await _HiveLease.prepare();
    identity.requireCurrent();
    if (_disposed || _timeline != null) return;
    _hiveLease ??= _HiveLease.acquire();
    _accountLease = VrPostsAccountLease.acquire(
      storage: _storage,
      identity: identity,
    );
    _storageRevision = _accountLease!.revision;
    final timeline = TimelineController(
      sessionManaged: true,
      postsStorage: _storage,
      canUseCloud: () => _current && session.backendReady,
    );
    _timeline = timeline;
    _removeListener = timeline.addListener(() {
      if (_current) notifyListeners();
    });
    timeline.onStart();
    await timeline.refreshSession();
    if (_current) notifyListeners();
  }

  @override
  Future<void> refresh() async {
    identity.requireCurrent();
    if (_timeline == null) return initialize();
    if (!_current) throw const VrEcosystemAccessDenied();
    // Reuse the queue's idempotent, account-checked upload path. Connectivity
    // and a local save are never presented as proof that Firebase accepted it.
    await PostsSyncService().syncPendingPosts();
    if (!_current) throw const VrEcosystemAccessDenied();
    await _timeline!.refreshSession();
    if (_current) notifyListeners();
  }

  @override
  Future<bool> submitText(String text) async {
    identity.requireCurrent();
    if (!_current || _composer != null || text.trim().isEmpty) return false;
    final composer = PostUploadController();
    _composer = composer;
    var saved = false;
    composer.onPostCreated = () => saved = _current;
    composer.onStart();
    composer.captionController.text = text.trim();
    try {
      identity.requireCurrent();
      await composer.handleSubmit();
      if (!_current) throw const VrEcosystemAccessDenied();
      await _timeline!.refreshSession();
      if (_current) notifyListeners();
      return saved;
    } finally {
      composer.onPostCreated = null;
      composer.onDelete();
      if (identical(_composer, composer)) _composer = null;
    }
  }

  @override
  void invalidate() {
    _composer?.onDelete();
    _composer = null;
    _removeListener?.call();
    _removeListener = null;
    _timeline?.onDelete();
    _timeline = null;
    _accountLease?.release();
    _accountLease = null;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    invalidate();
    _hiveLease?.release();
    _hiveLease = null;
    super.dispose();
  }
}

/// Multiple room routes may borrow the same account scope. Only its last
/// borrower releases it; an old route cannot reset a replacement account or
/// profile. Account changes never migrate queued posts between scopes.
class VrPostsAccountLease {
  VrPostsAccountLease._(this.storage, this.uid, this.revision);
  final PostsHiveController storage;
  final String uid;
  final int revision;
  bool _released = false;
  static final Map<PostsHiveController, Map<int, _AccountScope>> _scopes =
      Map.identity();

  static VrPostsAccountLease acquire({
    required PostsHiveController storage,
    required VrEcosystemIdentity identity,
  }) {
    identity.requireCurrent();
    final scopes = _scopes.putIfAbsent(storage, () => {});
    final key = (identity.uid, identity.profileId, identity.revision);
    final previous = scopes[storage.sessionRevision];
    storage.configureSession(
      accountId: identity.uid,
      forceReset: previous != null && previous.key != key,
    );
    final revision = storage.sessionRevision;
    final scope = scopes.putIfAbsent(revision, () => _AccountScope(key));
    scope.borrowers++;
    return VrPostsAccountLease._(storage, identity.uid, revision);
  }

  void release() {
    if (_released) return;
    _released = true;
    final scopes = _scopes[storage];
    final scope = scopes?[revision];
    if (scope == null || --scope.borrowers > 0) return;
    scopes!.remove(revision);
    if (scopes.isEmpty) _scopes.remove(storage);
    if (storage.sessionRevision == revision && storage.accountId == uid) {
      storage.configureSession(forceReset: true);
    }
  }
}

class _AccountScope {
  _AccountScope(this.key);
  final (String, String, int) key;
  int borrowers = 0;
}

/// Borrow existing application services; remove only the binding this adapter
/// created, after its final borrower leaves, and never close shared Hive boxes.
class _HiveLease {
  _HiveLease._(this.service);
  final AppHiveService service;
  static Future<void>? _preparation;
  static final Map<AppHiveService, int> _owned = Map.identity();
  bool _released = false;

  static Future<void> prepare() {
    // Borrowers retain their existing Hive path and initialization ownership.
    if (Sint.isRegistered<AppHiveService>()) return Future<void>.value();
    return _preparation ??= Hive.initFlutter().catchError((
      Object error,
      StackTrace stack,
    ) {
      _preparation = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  static _HiveLease acquire() {
    if (!Sint.isRegistered<AppHiveService>()) {
      final created = AppHiveController();
      Sint.put<AppHiveService>(created, permanent: true);
      _owned[created] = 0;
    }
    final service = Sint.find<AppHiveService>();
    if (_owned.containsKey(service)) _owned[service] = _owned[service]! + 1;
    return _HiveLease._(service);
  }

  void release() {
    if (_released) return;
    _released = true;
    final borrowers = _owned[service];
    if (borrowers == null) return;
    if (borrowers > 1) {
      _owned[service] = borrowers - 1;
      return;
    }
    if (Sint.isRegistered<AppHiveService>() &&
        identical(Sint.find<AppHiveService>(), service)) {
      Sint.delete<AppHiveService>(force: true);
    }
    _owned.remove(service);
  }
}
