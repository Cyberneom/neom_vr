import 'package:sint/sint.dart';
import 'package:vrlizate/vrlizate.dart';

/// Canvas-engine controller with explicit ownership.
///
/// An explicitly supplied or SINT-registered engine is borrowed. If neither
/// exists, this controller creates and owns one. Close controllers before
/// unregistering their shared engine with VRBindings.
abstract class VRController extends SintController {
  VRController({VREngine? engine, this.engineTag, this.autoStart = true})
    : _providedEngine = engine;

  final VREngine? _providedEngine;
  final String? engineTag;
  final bool autoStart;
  late final VREngine engine;
  bool _ownsEngine = false;
  bool _didInit = false;
  bool _didClose = false;
  bool _engineAttached = false;
  bool _startedLoop = false;
  int _lastFrameCount = 0;

  bool get ownsEngine => _ownsEngine;

  final isVRRunning = false.obs;
  final isStereoMode = true.obs;
  final showDebugOverlay = false.obs;
  final currentFps = 0.0.obs;

  /// Override for custom construction of an engine owned by this controller.
  VREngine createEngine() => VREngine();

  @override
  void onInit() {
    if (_didInit || _didClose) return;
    _didInit = true;
    super.onInit();
    if (_providedEngine != null) {
      engine = _providedEngine;
    } else if (Sint.isRegistered<VREngine>(tag: engineTag)) {
      engine = Sint.find<VREngine>(tag: engineTag);
    } else {
      engine = createEngine();
      _ownsEngine = true;
    }
    engine.addListener(_onEngineTick);
    _engineAttached = true;
    _lastFrameCount = engine.frameCount;
    try {
      onVRInit();
      if (autoStart && !engine.isRunning) {
        _startedLoop = true;
        engine.start();
      }
      isVRRunning.value = engine.isRunning;
    } catch (_) {
      onClose();
      rethrow;
    }
  }

  // Observe frames without replacing another owner's engine.onUpdate hook.
  void _onEngineTick() {
    if (_didClose || engine.frameCount == _lastFrameCount) return;
    _lastFrameCount = engine.frameCount;
    currentFps.value = engine.fps;
    onVRUpdate(engine.frameTimeMs / 1000);
  }

  void onVRInit();
  void onVRUpdate(double dt) {}

  void toggleStereo() => isStereoMode.toggle();
  void toggleDebug() => showDebugOverlay.toggle();

  void toggleRunning() {
    if (!_engineAttached || _didClose) return;
    if (engine.isRunning) {
      engine.stop();
    } else {
      _startedLoop = true;
      engine.start();
    }
    isVRRunning.value = engine.isRunning;
  }

  @override
  void onClose() {
    if (_didClose) return;
    _didClose = true;
    if (_engineAttached) {
      engine.removeListener(_onEngineTick);
      if (_ownsEngine) {
        engine.dispose();
      } else if (_startedLoop) {
        // Release a loop started here, but never dispose a borrowed engine.
        engine.stop();
      }
    }
    isVRRunning.value = false;
    super.onClose();
  }
}
