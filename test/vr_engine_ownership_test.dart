import 'package:flutter_test/flutter_test.dart';
import 'package:sint/sint.dart';
import 'package:neom_vr/neom_vr_sessions.dart';
import 'package:vrlizate/vrlizate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    VRBindings.unregister();
    VRBindings.unregister(tag: 'one');
    VRBindings.unregister(tag: 'two');
    Sint.resetInstance();
  });

  test('controller creates one engine and disposes it exactly once', () {
    final controller = _Controller();
    controller.onInit();
    controller.onInit();
    expect(controller.creates, 1);
    expect(controller.ownsEngine, isTrue);
    expect(controller.engine.isRunning, isTrue);
    controller.onClose();
    controller.onClose();
    expect((controller.engine as _Engine).disposes, 1);
  });

  test('explicit borrowed engine is not disposed or callback replaced', () {
    final engine = _Engine();
    var priorUpdates = 0;
    engine.onUpdate = (_) => priorUpdates++;
    final callback = engine.onUpdate;
    final controller = _Controller(engine: engine, autoStart: false)..onInit();
    engine.step(0.02);
    expect(controller.updates, 1);
    expect(priorUpdates, 1);
    expect(engine.onUpdate, same(callback));
    engine.notifyGameStateChanged();
    expect(controller.updates, 1);
    controller.onClose();
    engine.step(0.02);
    expect(controller.updates, 1);
    expect(engine.disposes, 0);
    engine.dispose();
  });

  test('registered engine is borrowed instead of constructing another', () {
    final engine = _Engine();
    VRBindings.register(engine: engine);
    final controller = _Controller()..onInit();
    expect(controller.engine, same(engine));
    expect(controller.creates, 0);
    expect(controller.ownsEngine, isFalse);
    controller.onClose();
    VRBindings.unregister();
    expect(engine.disposes, 0);
    expect(Sint.isRegistered<VREngine>(), isFalse);
    engine.dispose();
  });

  test('bindings own their engine, close borrowers before unregister', () {
    final engine = VRBindings.register();
    expect(VRBindings.register(), same(engine));
    final controller = _Controller(autoStart: false)..onInit();
    controller.onClose();
    expect(() => engine.addListener(_noop), returnsNormally);
    VRBindings.unregister();
    VRBindings.unregister();
    expect(() => engine.addListener(_noop), throwsFlutterError);
  });

  test('existing external registration remains after unregister', () {
    final engine = _Engine();
    final raycaster = Raycaster();
    Sint.put<VREngine>(engine);
    Sint.put<Raycaster>(raycaster);
    VRBindings.register();
    VRBindings.unregister();
    expect(Sint.find<VREngine>(), same(engine));
    expect(Sint.find<Raycaster>(), same(raycaster));
    expect(engine.disposes, 0);
    engine.dispose();
  });

  test('bindings preserve foreign replacement registrations', () {
    final original = VRBindings.register();
    Sint.delete<VREngine>(force: true);
    final replacement = _Engine();
    Sint.put<VREngine>(replacement);
    VRBindings.unregister();
    expect(Sint.find<VREngine>(), same(replacement));
    expect(replacement.disposes, 0);
    expect(() => original.addListener(_noop), throwsFlutterError);
    replacement.dispose();
  });

  test('tagged registrations remain independent', () {
    final one = _Engine();
    final two = _Engine();
    VRBindings.register(engine: one, tag: 'one');
    VRBindings.register(engine: two, tag: 'two');
    final controller = _Controller(engineTag: 'two', autoStart: false)
      ..onInit();
    expect(controller.engine, same(two));
    VRBindings.unregister(tag: 'one');
    expect(Sint.find<VREngine>(tag: 'two'), same(two));
    controller.onClose();
    VRBindings.unregister(tag: 'two');
    one.dispose();
    two.dispose();
  });

  test('an existing different engine is never silently replaced', () {
    final original = _Engine();
    final other = _Engine();
    VRBindings.register(engine: original);
    expect(() => VRBindings.register(engine: other), throwsStateError);
    expect(Sint.find<VREngine>(), same(original));
    VRBindings.unregister();
    original.dispose();
    other.dispose();
  });

  test('failed controller initialization releases its owned engine', () {
    final controller = _Controller(fail: true);
    expect(controller.onInit, throwsStateError);
    expect((controller.engine as _Engine).disposes, 1);
    controller.onClose();
    expect((controller.engine as _Engine).disposes, 1);
  });

  test('closing borrower leaves an already running engine running', () {
    final engine = _Engine()..start();
    final controller = _Controller(engine: engine)..onInit();
    controller.onClose();
    expect(engine.isRunning, isTrue);
    expect(engine.disposes, 0);
    engine.dispose();
  });

  test(
    'engine adapter borrows by default and owned close is idempotent',
    () async {
      final borrowed = _Engine();
      final session = VrSessionController(
        adapter: VREngineSessionAdapter(engine: borrowed),
      );
      await session.start();
      await session.pause();
      await session.resume();
      await session.closeSession();
      session.dispose();
      expect(borrowed.isRunning, isFalse);
      expect(borrowed.disposes, 0);
      borrowed.dispose();
      final owned = _Engine();
      final adapter = VREngineSessionAdapter(engine: owned, ownsEngine: true);
      adapter.close();
      adapter.close();
      expect(owned.disposes, 1);
    },
  );
}

void _noop() {}

class _Engine extends VREngine {
  int disposes = 0;
  bool running = false;
  @override
  bool get isRunning => running;
  @override
  void start() => running = true;
  @override
  void stop() => running = false;
  @override
  void dispose() {
    disposes++;
    super.dispose();
  }
}

class _Controller extends VRController {
  _Controller({
    super.engine,
    super.engineTag,
    super.autoStart,
    this.fail = false,
  });
  final bool fail;
  int creates = 0;
  int updates = 0;
  @override
  VREngine createEngine() {
    creates++;
    return _Engine();
  }

  @override
  void onVRInit() {
    if (fail) throw StateError('init');
  }

  @override
  void onVRUpdate(double dt) => updates++;
}
