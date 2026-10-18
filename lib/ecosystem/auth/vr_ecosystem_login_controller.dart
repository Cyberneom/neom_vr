import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:neom_auth/ui/login/login_controller.dart';
import 'package:neom_core/app_config.dart';
import 'package:neom_core/domain/model/app_profile.dart';
import 'package:neom_core/domain/model/app_user.dart';
import 'package:neom_core/utils/enums/auth_status.dart';

/// Host adapter for the shared LoginController's Firebase email sign-in.
/// It replaces application redirects/onboarding and owns an awaitable account
/// load, so a signed-in identity never becomes an invented local account.
class VrEcosystemLoginController extends LoginController {
  VrEcosystemLoginController({
    required super.userService,
    required super.firebaseAuth,
    required this.onSessionChanged,
  });

  final VoidCallback onSessionChanged;
  StreamSubscription<User?>? _subscription;
  Future<void> _loadTail = Future<void>.value();
  int _generation = 0;
  bool _closed = false;
  String? message;

  // The shared controller retains private subscriptions and redirects routes in
  // onInit/onReady. This host supplies their lifetime and route policy instead.
  @override
  // ignore: must_call_super
  void onInit() {
    isLoading.value = false;
    _subscription = auth.authStateChanges().listen((user) {
      unawaited(handleAuthChanged(user));
    });
  }

  @override
  void onReady() {}

  @override
  Future<void> handleAuthChanged(User? user) {
    if (_closed || user?.uid != auth.currentUser?.uid) {
      return Future<void>.value();
    }
    final generation = ++_generation;
    _clearAccount();
    fbaUser = user;
    message = null;
    if (user == null || user.isAnonymous) {
      isLoading.value = false;
      onSessionChanged();
      return Future<void>.value();
    }
    final uid = user.uid;
    isLoading.value = true;
    setAuthStatus(AuthStatus.waiting);
    onSessionChanged();

    // Shared UserService mutates its account during load. Serializing prevents
    // an older account request from overwriting a newer account's result.
    final operation = _loadTail.then((_) async {
      if (!_isCurrent(generation, uid)) return;
      try {
        await userServiceImpl.setUserById(uid);
        if (!_isCurrent(generation, uid)) {
          _clearAccount();
          return;
        }
        final account = userServiceImpl.user;
        final profile = userServiceImpl.profile;
        if (account.id != uid ||
            account.isBanned ||
            profile.id.isEmpty ||
            !account.profiles.any((value) => value.id == profile.id)) {
          _clearAccount();
          message =
              'Tu cuenta todavía no tiene un perfil disponible aquí. '
              'Puedes seguir explorando como invitado.';
        } else {
          fbaUser = auth.currentUser;
          setAuthStatus(AuthStatus.loggedIn);
          AppConfig.instance
            ..authStatus = AuthStatus.loggedIn
            ..isGuestMode = false;
        }
      } catch (_) {
        if (_isCurrent(generation, uid)) {
          _clearAccount();
          hasAccountLoadError.value = true;
          message =
              'No pudimos cargar tu cuenta. Inténtalo de nuevo o sigue '
              'explorando como invitado.';
        }
      } finally {
        if (!_closed && generation == _generation) {
          isLoading.value = false;
          onSessionChanged();
        }
      }
    });
    _loadTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  bool _isCurrent(int generation, String uid) =>
      !_closed && generation == _generation && auth.currentUser?.uid == uid;

  @override
  Future<void> emailLogin() async {
    if (_closed) return;
    fbaUser = null;
    _clearAccount();
    message = null;
    onSessionChanged();
    await super.emailLogin();
    if (fbaUser != null && fbaUser!.uid == auth.currentUser?.uid) {
      await handleAuthChanged(fbaUser);
    } else if (!_closed) {
      message =
          'No se pudo iniciar sesión. Revisa tus datos e inténtalo de nuevo.';
      onSessionChanged();
    }
  }

  @override
  Future<void> retryAccountLoad() => handleAuthChanged(auth.currentUser);

  // OAuth is deliberately unavailable until its VRlizate-specific client IDs
  // are configured. Shared CloudProperties defaults must not select another app.
  @override
  Future<void> googleLogin() async => _providerUnavailable();
  @override
  Future<void> appleLogin() async => _providerUnavailable();

  void _providerUnavailable() {
    message = 'Este método de acceso todavía no está disponible.';
    isLoading.value = false;
    onSessionChanged();
  }

  @override
  Future<void> signOut() async {
    ++_generation;
    _clearAccount();
    clear();
    message = null;
    onSessionChanged();
    await auth.signOut();
  }

  @override
  void loginAsGuest() {
    ++_generation;
    _clearAccount();
    clear();
    message = null;
    isLoading.value = false;
    onSessionChanged();
  }

  void _clearAccount() {
    userServiceImpl.user = AppUser();
    userServiceImpl.profile = AppProfile();
    setAuthStatus(AuthStatus.notLoggedIn);
    AppConfig.instance
      ..authStatus = AuthStatus.notLoggedIn
      ..isGuestMode = true
      ..isAdminMode = false;
  }

  @override
  void onClose() {
    if (_closed) return;
    _closed = true;
    ++_generation;
    unawaited(_subscription?.cancel());
    emailController.dispose();
    passwordController.dispose();
    emailFocusNode.dispose();
    passwordFocusNode.dispose();
    super.onClose();
  }
}
