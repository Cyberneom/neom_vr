import 'package:sint/sint.dart';
import 'package:vrlizate/vrlizate.dart';

/// Registers a shared Canvas engine and its services in SINT.
///
/// The registration owns engines it creates. Supplied/existing engines remain
/// borrowed. Services are kept until explicit unregister; renderer pages must
/// close first. Use tags for independently owned sessions.
class VRBindings {
  VRBindings._();

  static final Map<String?, _Registration> _registrations = {};

  /// Idempotently registers missing services and returns the shared engine.
  static VREngine register({
    DeviceParams deviceParams = DeviceParams.cardboardV2,
    VREngine? engine,
    String? tag,
  }) {
    final previous = _registrations[tag];
    if (previous != null) {
      if (!Sint.isRegistered<VREngine>(tag: tag) ||
          !identical(Sint.find<VREngine>(tag: tag), previous.engine)) {
        throw StateError(
          'VRBindings registration was replaced; unregister first.',
        );
      }
      if (engine != null && !identical(engine, previous.engine)) {
        throw StateError(
          'A different VREngine is already registered for $tag.',
        );
      }
      return previous.engine;
    }

    final existing = Sint.isRegistered<VREngine>(tag: tag)
        ? Sint.find<VREngine>(tag: tag)
        : null;
    if (existing != null && engine != null && !identical(existing, engine)) {
      throw StateError('A different VREngine is already registered for $tag.');
    }
    final shared = existing ?? engine ?? VREngine();
    final registration = _Registration(
      shared,
      ownsEngine: existing == null && engine == null,
    );
    _registrations[tag] = registration;
    try {
      _putMissing<VREngine>(shared, tag, registration);
      _putMissing<Raycaster>(Raycaster(), tag, registration);
      _putMissing<DeviceParams>(deviceParams, tag, registration);
      final effectiveParams = Sint.find<DeviceParams>(tag: tag);
      _putMissing<DistortionMesh>(
        DistortionMesh(
          coefficients: effectiveParams.distortionCoefficients,
          screenToLensDistance: effectiveParams.screenToLensDistance,
          interLensDistance: effectiveParams.interLensDistance,
        ),
        tag,
        registration,
      );
      return shared;
    } catch (_) {
      unregister(tag: tag);
      rethrow;
    }
  }

  static void _putMissing<T>(T instance, String? tag, _Registration owner) {
    if (Sint.isRegistered<T>(tag: tag)) return;
    Sint.put<T>(instance, tag: tag, permanent: true);
    owner.removeRegistrations.add(() {
      if (Sint.isRegistered<T>(tag: tag) &&
          identical(Sint.find<T>(tag: tag), instance)) {
        Sint.delete<T>(tag: tag, force: true);
      }
    });
  }

  /// Removes only registrations made here and disposes only an owned engine.
  /// Repeated calls are safe and never remove another scope's replacements.
  static void unregister({String? tag}) {
    final registration = _registrations.remove(tag);
    if (registration == null) return;
    for (final remove in registration.removeRegistrations.reversed) {
      remove();
    }
    if (registration.ownsEngine) registration.engine.dispose();
  }
}

class _Registration {
  _Registration(this.engine, {required this.ownsEngine});
  final VREngine engine;
  final bool ownsEngine;
  final List<void Function()> removeRegistrations = [];
}
