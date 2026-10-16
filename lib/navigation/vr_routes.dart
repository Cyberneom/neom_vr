import 'package:flutter/material.dart';
import 'package:sint/sint.dart';

/// Route constants for VR scenes.
class VRRouteConstants {
  VRRouteConstants._();

  static const String vrHome = '/vr';
  static const String vrScene = '/vr/scene';
  static const String vrStereo = '/vr/stereo';
  static const String vrSpatial = '/vr/spatial';
  static const String vrSettings = '/vr/settings';
}

/// Generates SintPage routes for VR scenes.
///
/// ```dart
/// // In your app routes:
/// ...VRRoutes.generate(scenes: [
///   VRSceneRoute(
///     name: '/vr/myScene',
///     builder: () => MyVRScenePage(),
///   ),
/// ]),
/// ```
class VRRoutes {
  VRRoutes._();

  static List<SintPage> generate({
    List<VRSceneRoute> scenes = const [],
    Transition transition = Transition.fadeIn,
  }) {
    return scenes
        .map(
          (scene) => SintPage(
            name: scene.name,
            page: scene.builder,
            transition: scene.transition ?? transition,
            fullscreenDialog: scene.fullscreen,
          ),
        )
        .toList();
  }
}

/// Definition of a VR scene route.
class VRSceneRoute {
  final String name;
  final Widget Function() builder;
  final Transition? transition;
  final bool fullscreen;

  const VRSceneRoute({
    required this.name,
    required this.builder,
    this.transition,
    this.fullscreen = true,
  });
}
