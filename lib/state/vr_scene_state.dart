import 'package:sint/sint.dart';
import 'package:vrlizate/vrlizate.dart';

/// Reactive wrapper around VREngine scene for Sint state management.
/// Tracks node count, light count, and scene changes reactively.
class VRSceneState {
  final VREngine engine;

  final nodeCount = 0.obs;
  final lightCount = 0.obs;
  final isLoading = false.obs;

  VRSceneState(this.engine);

  void addNode(Node node) {
    engine.scene.add(node);
    _refresh();
  }

  void removeNode(Node node) {
    engine.scene.remove(node);
    _refresh();
  }

  void clear() {
    engine.scene.clear();
    _refresh();
  }

  void _refresh() {
    nodeCount.value = engine.scene.visibleNodes.length;
    lightCount.value = engine.scene.lights.length;
  }
}
