import 'package:hive_flutter/hive_flutter.dart';
import 'package:neom_core/data/implementations/app_hive_controller.dart';
import 'package:neom_core/domain/use_cases/app_hive_service.dart';
import 'package:sint/sint.dart';

/// Borrows the host's existing Hive service. Only the binding created here is
/// released after its last borrower; shared boxes and their contents stay open.
class VrHiveLease {
  VrHiveLease._(this.service);

  final AppHiveService service;
  static Future<void>? _preparation;
  static final Map<AppHiveService, int> _owned = Map.identity();
  bool _released = false;

  static Future<void> prepare() {
    // An existing service owns its Hive path and initialization policy.
    if (Sint.isRegistered<AppHiveService>()) return Future<void>.value();
    return _preparation ??= Hive.initFlutter().catchError((
      Object error,
      StackTrace stack,
    ) {
      _preparation = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  static VrHiveLease acquire() {
    if (!Sint.isRegistered<AppHiveService>()) {
      final created = AppHiveController();
      Sint.put<AppHiveService>(created, permanent: true);
      _owned[created] = 0;
    }
    final service = Sint.find<AppHiveService>();
    if (_owned.containsKey(service)) _owned[service] = _owned[service]! + 1;
    return VrHiveLease._(service);
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
