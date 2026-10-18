import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:neom_auth/ui/login/login_controller.dart';
import 'package:neom_core/app_config.dart';
import 'package:neom_core/app_properties.dart';
import 'package:neom_core/data/implementations/user_controller.dart';
import 'package:neom_core/domain/use_cases/login_service.dart';
import 'package:neom_core/domain/use_cases/user_service.dart';
import 'package:neom_core/utils/enums/app_in_use.dart';
import 'package:sint/sint.dart';

import 'vr_ecosystem_firebase_config.dart';
import 'vr_ecosystem_login_controller.dart';
import 'vr_ecosystem_session.dart';

/// The reduced platform binding for account access. No media/social modules are
/// eagerly registered, and no shared application secrets/defaults are loaded.
class VrEcosystemRootBinding {
  VrEcosystemRootBinding._();

  static Future<VrEcosystemSession> initialize({
    required VrEcosystemFirebaseConfig config,
  }) async {
    AppConfig.instance.appInUse = AppInUse.v;
    // Public host presentation only; do not instantiate AppProperties or load
    // another application's CloudProperties/default Firebase configuration.
    AppProperties.appProperties = <String, Object>{
      'appName': 'VRlizate',
      'notificationChannelId': 'com.openneom.vrlizate_app.audio',
      'notificationChannelName': 'Audio VRlizate',
      'notificationIcon': 'drawable/ic_audio_notification',
    };
    if (!config.isComplete) {
      AppConfig.instance.isGuestMode = true;
      return VrEcosystemSession(
        backendReady: false,
        unavailableMessage:
            'Las cuentas todavía no están disponibles. '
            'Puedes explorar las salas y los demos como invitado.',
      );
    }

    final removals = <void Function()>[];
    VrEcosystemSession? pendingSession;
    try {
      FirebaseApp? app;
      for (final existing in Firebase.apps) {
        if (existing.name == '[DEFAULT]') app = existing;
      }
      if (app != null && !config.matches(app.options)) {
        throw StateError(
          'The configured backend does not match the active app.',
        );
      }
      app ??= await Firebase.initializeApp(options: config.options);
      if (!config.matches(app.options)) {
        throw StateError('The initialized backend differs from configuration.');
      }
      final auth = FirebaseAuth.instanceFor(app: app);

      UserService users;
      final ownsUser = !Sint.isRegistered<UserService>();
      if (Sint.isRegistered<UserService>()) {
        users = Sint.find<UserService>();
      } else if (Sint.isRegistered<UserController>()) {
        throw StateError(
          'The existing user controller has no service binding.',
        );
      } else {
        users = UserController();
      }
      late VrEcosystemSession session;
      LoginService login;
      final ownsLogin = !Sint.isRegistered<LoginService>();
      if (Sint.isRegistered<LoginService>()) {
        login = Sint.find<LoginService>();
      } else if (Sint.isRegistered<LoginController>()) {
        throw StateError(
          'The existing login controller has no service binding.',
        );
      } else {
        login = VrEcosystemLoginController(
          userService: users,
          firebaseAuth: auth,
          onSessionChanged: () => session.refresh(),
        );
      }
      if (!config.matches(login.auth.app.options) ||
          login.auth.app.name != app.name) {
        throw StateError('Shared login belongs to a different backend.');
      }
      if (login is LoginController &&
          !identical(login.userServiceImpl, users)) {
        throw StateError('Shared login and user services are inconsistent.');
      }
      session = VrEcosystemSession(
        backendReady: true,
        firebaseApp: app,
        userService: users,
        loginService: login,
        authChanges: auth.idTokenChanges(),
        releaseBindings: () {
          for (final remove in removals.reversed) {
            remove();
          }
        },
      );
      pendingSession = session;
      _register<UserService>(users, removals);
      if (ownsUser && users is UserController) {
        _register<UserController>(users, removals);
      }
      _register<LoginService>(login, removals);
      if (ownsLogin && login is LoginController) {
        _register<LoginController>(login, removals);
      }
      session.refresh();
      return session;
    } catch (_) {
      AppConfig.instance.isGuestMode = true;
      pendingSession?.dispose();
      for (final remove in removals.reversed) {
        remove();
      }
      return VrEcosystemSession(
        backendReady: false,
        unavailableMessage:
            'Las cuentas no están disponibles en este momento. '
            'Puedes seguir explorando como invitado.',
      );
    }
  }

  static void _register<T>(T value, List<void Function()> removals) {
    if (Sint.isRegistered<T>()) {
      if (!identical(Sint.find<T>(), value)) {
        throw StateError('A different shared service is already registered.');
      }
      return;
    }
    Sint.put<T>(value, permanent: true);
    removals.add(() {
      if (Sint.isRegistered<T>() && identical(Sint.find<T>(), value)) {
        Sint.delete<T>(force: true);
      }
    });
  }
}
