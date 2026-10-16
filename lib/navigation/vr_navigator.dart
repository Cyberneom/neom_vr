import 'package:flutter/services.dart';
import 'package:sint/sint.dart';

/// VR-aware navigation that handles fullscreen, orientation locks,
/// and system UI visibility for VR scenes.
class VRNavigator {
  VRNavigator._();

  /// Navigates to a VR scene with proper VR mode setup.
  static Future<void> toVRScene(String routeName, {dynamic arguments}) async {
    await _enterVRMode();
    Sint.toNamed(routeName, arguments: arguments);
  }

  /// Returns from a VR scene and restores normal mode.
  static Future<void> exitVRScene() async {
    await _exitVRMode();
    Sint.back();
  }

  /// Forces landscape orientation and hides system UI.
  static Future<void> _enterVRMode() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  /// Restores portrait orientation and system UI.
  static Future<void> _exitVRMode() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
}
