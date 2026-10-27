import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:neom_commons/utils/auth_guard.dart';
import 'package:neom_core/app_config.dart';
import 'package:neom_core/domain/model/app_profile.dart';
import 'package:neom_core/domain/model/app_user.dart';
import 'package:neom_core/domain/use_cases/login_service.dart';
import 'package:neom_core/domain/use_cases/user_service.dart';
import 'package:neom_core/utils/enums/auth_status.dart';
import 'package:sint/sint.dart';

import 'vr_ecosystem_firebase_config.dart';
import 'vr_ecosystem_root_binding.dart';

/// Coordinates the existing Open Neom account services for this host.
/// This is a guard and lifetime boundary, not a second authentication service.
class VrEcosystemSession extends ChangeNotifier {
  VrEcosystemSession({
    required this.backendReady,
    this.firebaseApp,
    this.userService,
    this.loginService,
    this.unavailableMessage,
    Stream<Object?>? authChanges,
    this.releaseBindings,
  }) {
    _observedUid = _currentUid;
    _signature = _identitySignature;
    _authSubscription = authChanges?.listen((_) => refresh());
    final user = userService;
    if (user is SintController) {
      _removeUserListener = (user as SintController).addListener(refresh);
    }
  }

  static Future<VrEcosystemSession> initialize({
    VrEcosystemFirebaseConfig config =
        const VrEcosystemFirebaseConfig.fromEnvironment(),
  }) => VrEcosystemRootBinding.initialize(config: config);

  final bool backendReady;
  final FirebaseApp? firebaseApp;
  final UserService? userService;
  final LoginService? loginService;
  final String? unavailableMessage;
  final VoidCallback? releaseBindings;
  StreamSubscription<Object?>? _authSubscription;
  VoidCallback? _removeUserListener;
  String? _observedUid;
  String _signature = '';
  int _revision = 0;
  bool _signingOut = false;
  bool _disposed = false;

  int get revision => _revision;
  bool get isDisposed => _disposed;

  String? get _currentUid {
    if (!backendReady || loginService == null) return null;
    try {
      final user = loginService!.auth.currentUser;
      return user == null || user.isAnonymous ? null : user.uid;
    } catch (_) {
      return null;
    }
  }

  bool get isAuthenticated {
    if (_disposed || _signingOut || !backendReady) return false;
    final users = userService;
    final login = loginService;
    if (users == null || login == null) return false;
    try {
      final uid = _currentUid;
      return uid != null &&
          uid.isNotEmpty &&
          Sint.isRegistered<UserService>() &&
          Sint.isRegistered<LoginService>() &&
          identical(Sint.find<UserService>(), users) &&
          identical(Sint.find<LoginService>(), login) &&
          AuthGuard.isAuthenticated &&
          login.fbaUser?.uid == uid &&
          login.fbaUser?.isAnonymous == false &&
          users.user.id == uid &&
          !users.user.isBanned &&
          users.profile.id.isNotEmpty &&
          users.user.profiles.any((profile) => profile.id == users.profile.id);
    } catch (_) {
      return false;
    }
  }

  String get _identitySignature {
    if (!isAuthenticated) return '';
    return '$_currentUid\u0000${userService!.user.id}\u0000'
        '${userService!.profile.id}';
  }

  /// Refresh after a profile/account change made through shared controllers.
  /// Firebase identity changes invalidate any previous local account immediately.
  void refresh() {
    if (_disposed) return;
    final uid = _currentUid;
    if (_observedUid != uid) {
      _observedUid = uid;
      _clearLocalAccount();
    }
    final signature = _identitySignature;
    if (signature != _signature) {
      _signature = signature;
      _revision++;
    }
    notifyListeners();
  }

  VrEcosystemIdentity? captureIdentity() {
    if (!isAuthenticated) return null;
    return VrEcosystemIdentity._(
      this,
      uid: _currentUid!,
      userId: userService!.user.id,
      profileId: userService!.profile.id,
      revision: _revision,
    );
  }

  /// Rechecks both ends of async work. Call identity.requireCurrent() again
  /// immediately before a write after any intermediate await inside [action].
  /// Server authorization remains required; this cannot undo a completed write.
  Future<T> runProtected<T>(
    Future<T> Function(VrEcosystemIdentity identity) action,
  ) async {
    final identity = captureIdentity();
    if (identity == null) throw const VrEcosystemAccessDenied();
    final result = await action(identity);
    identity.requireCurrent();
    return result;
  }

  Future<void> signOut() async {
    if (_disposed || _signingOut) return;
    _signingOut = true;
    _clearLocalAccount();
    _signature = '';
    _revision++;
    notifyListeners();
    try {
      await loginService?.signOut();
    } finally {
      _signingOut = false;
      refresh();
    }
  }

  void _clearLocalAccount() {
    AppConfig.instance
      ..isGuestMode = true
      ..isAdminMode = false
      ..authStatus = AuthStatus.notLoggedIn;
    loginService?.setAuthStatus(AuthStatus.notLoggedIn);
    userService?.user = AppUser();
    userService?.profile = AppProfile();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _revision++;
    unawaited(_authSubscription?.cancel());
    _removeUserListener?.call();
    releaseBindings?.call();
    super.dispose();
  }
}

/// Immutable identity for one guarded operation. Never serialize its token.
class VrEcosystemIdentity {
  const VrEcosystemIdentity._(
    this._session, {
    required this.uid,
    required this.userId,
    required this.profileId,
    required this.revision,
  });
  final VrEcosystemSession _session;
  final String uid;
  final String userId;
  final String profileId;
  final int revision;

  bool isCurrent() =>
      _session.isAuthenticated &&
      _session.revision == revision &&
      _session._currentUid == uid &&
      _session.userService!.user.id == userId &&
      _session.userService!.profile.id == profileId;

  void requireCurrent() {
    if (!isCurrent()) throw const VrEcosystemAccessDenied();
  }

  Future<String?> getIdToken() async {
    requireCurrent();
    final token = await _session.loginService!.auth.currentUser!.getIdToken();
    requireCurrent();
    if (token == null || token.isEmpty) {
      throw const VrEcosystemAccessDenied();
    }
    return token;
  }
}

class VrEcosystemAccessDenied implements Exception {
  const VrEcosystemAccessDenied();

  @override
  String toString() => 'Inicia sesión de nuevo para continuar.';
}
