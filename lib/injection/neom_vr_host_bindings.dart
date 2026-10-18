import 'package:sint/sint.dart';

import '../ai/vr_app_assistant.dart';
import '../ecosystem/auth/vr_ecosystem_session.dart';

/// SINT 2.0.0 host bindings for registering [VrEcosystemSession] and
/// [VrAppAssistant] in the dependency graph while preserving ownership rules.
class NeomVrHostBindings extends BindingsInterface<void> {
  NeomVrHostBindings({
    VrEcosystemSession? ecosystemSession,
    VrAppAssistant? assistant,
  }) : ecosystemSession =
           ecosystemSession ?? VrEcosystemSession(backendReady: false),
       assistant = assistant ?? VrAppAssistant();

  final VrEcosystemSession ecosystemSession;
  final VrAppAssistant assistant;

  bool _ownsEcosystemBinding = false;
  bool _ownsAssistantBinding = false;

  bool get ownsEcosystemBinding => _ownsEcosystemBinding;
  bool get ownsAssistantBinding => _ownsAssistantBinding;

  @override
  void dependencies() {
    if (!Sint.isRegistered<VrEcosystemSession>()) {
      Sint.put<VrEcosystemSession>(ecosystemSession);
      _ownsEcosystemBinding = true;
    }
    if (!Sint.isRegistered<VrAppAssistant>()) {
      Sint.put<VrAppAssistant>(assistant);
      _ownsAssistantBinding = true;
    }
  }

  /// Convenience helper that invokes [dependencies] and returns `this`.
  NeomVrHostBindings register() {
    dependencies();
    return this;
  }

  /// Unregisters only the bindings registered by this instance.
  void unregister() {
    unregisterOwned(
      ecosystemSession: ecosystemSession,
      assistant: assistant,
      ownsEcosystemBinding: _ownsEcosystemBinding,
      ownsAssistantBinding: _ownsAssistantBinding,
    );
    _ownsEcosystemBinding = false;
    _ownsAssistantBinding = false;
  }

  /// Removes owned [VrEcosystemSession] and [VrAppAssistant] registrations
  /// without disturbing foreign replacements.
  static void unregisterOwned({
    VrEcosystemSession? ecosystemSession,
    VrAppAssistant? assistant,
    bool ownsEcosystemBinding = true,
    bool ownsAssistantBinding = true,
  }) {
    if (ownsEcosystemBinding &&
        ecosystemSession != null &&
        Sint.isRegistered<VrEcosystemSession>() &&
        identical(Sint.find<VrEcosystemSession>(), ecosystemSession)) {
      Sint.delete<VrEcosystemSession>();
    }
    if (ownsAssistantBinding &&
        assistant != null &&
        Sint.isRegistered<VrAppAssistant>() &&
        identical(Sint.find<VrAppAssistant>(), assistant)) {
      Sint.delete<VrAppAssistant>();
    }
  }
}
