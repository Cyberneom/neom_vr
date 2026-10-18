import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

export 'package:vrlizate_scene/vrlizate_scene.dart'
    show VrDeviceCapabilities, VrDisplayMode;

/// Catalog-based initial quality preference; this is not a hardware benchmark.
/// Actual scene timings and physical headset calibration remain necessary.
class VrDeviceProfiler {
  static const String _prefKey = 'vrlizate_quality_tier';
  static const _channel = MethodChannel('vrlizate/device_capabilities');
  static Future<void>? _initialization;
  static VrDeviceCapabilities? _capabilities;
  static VrDevicePerformanceProfile? _profile;

  static VrDeviceCapabilities? get capabilities => _capabilities;
  static VrDevicePerformanceProfile? get profile => _profile;

  /// Reads Android once, before runApp. Missing/slow native hosts keep defaults.
  /// Does not select a display mode or load/overwrite a user's saved preset.
  static Future<void> initialize() => _initialization ??= _readCapabilities();

  static Future<void> _readCapabilities() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    var status = 'unavailable';
    try {
      final response = await _channel
          .invokeMethod<Object?>('read')
          .timeout(const Duration(seconds: 2));
      _capabilities = VrDeviceCapabilities.fromPlatform(response);
      final device = _capabilities;
      if (device != null) {
        _profile = VrDevicePerformanceCatalog.match(
          manufacturer: device.manufacturer,
          model: device.model,
        );
        status = _profile == null ? 'unknown_model' : 'catalog_match';
      } else {
        status = 'invalid_response';
      }
    } on MissingPluginException {
      status = 'missing_plugin';
    } on PlatformException {
      status = 'platform_error';
    } on TimeoutException {
      status = 'timeout';
    } catch (_) {
      status = 'invalid_response';
    }
    debugPrint(
      '[VR_DEVICE] ${jsonEncode({'status': status, 'capabilities': _capabilities?.toJson(), 'profile': _profile?.id, 'initialTier': detectInitialPreset().tier.name, 'catalogDisplayMaxHz': _profile?.displayMaxHz, 'measuredFps': null})}',
    );
  }

  /// Chooses a starting budget; supported Hz do not predict rendered FPS.
  static VrQualityPreset detectInitialPreset() {
    if (kIsWeb) return VrQualityPreset.medium;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android =>
        _profile == null
            ? VrQualityPreset.medium
            : VrQualityPreset.forTier(_profile!.initialTier),
      TargetPlatform.iOS => VrQualityPreset.high,
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => VrQualityPreset.ultra,
      TargetPlatform.fuchsia => VrQualityPreset.medium,
    };
  }

  /// Loads the persisted user quality preset preference if available.
  static Future<VrQualityPreset> loadPreferredPreset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tierName = prefs.getString(_prefKey);
      if (tierName != null) {
        for (final tier in VrQualityTier.values) {
          if (tier.name == tierName) {
            return VrQualityPreset.forTier(tier);
          }
        }
      }
    } catch (_) {}
    return detectInitialPreset();
  }

  /// Persists the user quality preset preference.
  static Future<void> savePreferredPreset(VrQualityPreset preset) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, preset.tier.name);
    } catch (_) {}
  }

  /// Clears startup state between tests; never needed during an app session.
  @visibleForTesting
  static void resetForTesting() {
    _initialization = null;
    _capabilities = null;
    _profile = null;
  }
}
