import 'package:sint/sint.dart';
import 'package:vrlizate_ble/vrlizate_ble.dart';
import 'package:vrlizate_joystick/vrlizate_joystick.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';
import 'package:vrlizate_tracking/vrlizate_tracking.dart';

import '../ai/itzli_vr_assistant.dart';
import '../ai/vr_app_assistant.dart';
import '../ai/vr_assistant_voice.dart';
import '../ai/vr_embedded_saia_provider.dart';
import '../ble/neom_ble_gatt_peripheral_adapter.dart';
import '../ecosystem/auth/vr_ecosystem_session.dart';

/// SINT 2.0.0 host bindings for registering [VrEcosystemSession] and
/// [VrAppAssistant] in the dependency graph while preserving ownership rules.
class NeomVrHostBindings extends BindingsInterface<void> {
  NeomVrHostBindings({
    VrEcosystemSession? ecosystemSession,
    VrAppAssistant? assistant,
  }) : ecosystemSession =
           ecosystemSession ?? VrEcosystemSession(backendReady: false),
       assistant = assistant ?? VrAppAssistant() {
    registerSdkIntegrations();
  }

  /// Registers Open Neom default factories (`ItzliVrAssistant`, `neom_ble`,
  /// `speech_to_text` + `neom_tts`, and `1D`/`2D`/`3D` `VrEmbeddedSaiaRuntime`
  /// co-processors) into VRlizate SDK extension hooks.
  static void registerSdkIntegrations() {
    VrVoiceIntentRouter.defaultFactory = ItzliVrAssistant.new;
    VrBleGattPeripheralAdapter.defaultFactory ??=
        NeomBleGattPeripheralAdapter.new;
    VrDesktopBeaconStation.defaultAiInferenceHandler ??=
        VrEmbeddedSaiaRuntime.instance.handleDesktopFaroRequest;
    VrDesktopBeaconStation.defaultAiStatusProvider ??=
        VrEmbeddedSaiaRuntime.instance.buildStatusSnapshot;
    VrJoystickAiCoProcessor.defaultCoProcessor ??=
        VrEmbeddedSaiaRuntime.instance.buildJoystickCoProcessor();
    StereoSceneView.onGlobalQualityStepDown ??= (nextPreset) {
      VrEmbeddedSaiaRuntime.instance.notifyThermalStepDown(
        steppedDownToLow: nextPreset.tier == VrQualityTier.low,
      );
    };
    VrThermalGovernor.onGlobalThermalEvent ??= (event) {
      VrEmbeddedSaiaRuntime.instance.notifyThermalStepDown(
        steppedDownToLow: event.newPreset.tier == VrQualityTier.low,
      );
    };
    registerNeomVrSpeechDefaults();
  }

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
