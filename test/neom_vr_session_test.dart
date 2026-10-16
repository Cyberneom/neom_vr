import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neom_vr/neom_vr_sessions.dart';
import 'package:sint/sint.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(Sint.resetInstance);

  test(
    'SINT registration observes a core session without starting it',
    () async {
      final adapter = _Adapter();
      final session = VrSessionController(adapter: adapter);
      final bridge = Sint.put(NeomVrSessionController(session: session));
      expect(bridge.session, same(session));
      expect(bridge.adapter, same(adapter));
      expect(bridge.rendererId, 'test');
      expect(adapter.events, isEmpty);
      expect(bridge.status.value, VrSessionStatus.idle);

      await bridge.start();
      expect(bridge.status.value, VrSessionStatus.running);
      await bridge.pause();
      expect(bridge.status.value, VrSessionStatus.paused);
      await bridge.resume();
      expect(bridge.status.value, VrSessionStatus.running);
      Sint.delete<NeomVrSessionController>();
      await bridge.closeSession();
      expect(adapter.events, ['start', 'pause', 'resume', 'close']);
      expect(bridge.status.value, VrSessionStatus.closed);
      // Removing the bridge does not dispose the core owner's notifier.
      void listener() {}
      expect(() => session.status.addListener(listener), returnsNormally);
      session.status.removeListener(listener);
      session.dispose();
    },
  );

  test('SINT deletion closes once and preserves cleanup errors', () async {
    final error = StateError('cleanup failed');
    final adapter = _Adapter(closeError: error);
    final session = VrSessionController(adapter: adapter);
    final bridge = Sint.put(NeomVrSessionController(session: session));
    await bridge.start();
    expect(Sint.delete<NeomVrSessionController>(), isTrue);
    expect(bridge.isClosed, isTrue);
    await expectLater(bridge.closeSession(), throwsA(same(error)));
    bridge.onClose();
    expect(adapter.events, ['start', 'close']);
    expect(bridge.lastError, same(error));
    expect(bridge.lastStackTrace, isNotNull);
    expect(bridge.status.value, VrSessionStatus.closed);
    session.dispose();
  });

  test('core failures reach SINT state and do not prevent cleanup', () async {
    final error = StateError('start failed');
    final adapter = _Adapter(startError: error);
    final session = VrSessionController(adapter: adapter);
    final bridge = Sint.put(NeomVrSessionController(session: session));
    await expectLater(bridge.start(), throwsA(same(error)));
    expect(bridge.status.value, VrSessionStatus.failed);
    expect(bridge.lastError, same(error));
    Sint.delete<NeomVrSessionController>();
    await bridge.closeSession();
    expect(adapter.events, ['start', 'close']);
    expect(bridge.lastError, same(error));
    session.dispose();
  });

  testWidgets('nested hosts have independent permanent SINT registrations', (
    tester,
  ) async {
    final outerAdapter = _Adapter();
    final innerAdapter = _Adapter();
    late NeomVrSessionController outer;
    late NeomVrSessionController inner;
    final showInner = ValueNotifier(true);
    addTearDown(showInner.dispose);
    await tester.pumpWidget(
      _shell(
        NeomVrSessionHost(
          adapter: outerAdapter,
          builder: (context, controller, active) {
            outer = controller;
            expect(NeomVrSessionHost.of(context), same(outer));
            expect(VrSessionHost.of(context), same(outer.session));
            return ValueListenableBuilder<bool>(
              valueListenable: showInner,
              builder: (_, visible, __) => visible
                  ? NeomVrSessionHost(
                      adapter: innerAdapter,
                      builder: (context, controller, active) {
                        inner = controller;
                        expect(NeomVrSessionHost.of(context), same(inner));
                        expect(VrSessionHost.of(context), same(inner.session));
                        return const SizedBox();
                      },
                    )
                  : const SizedBox(),
            );
          },
        ),
      ),
    );
    await tester.pump();
    expect(outer.registrationTag, isNot(inner.registrationTag));
    expect(_registered(outer), isTrue);
    expect(_registered(inner), isTrue);
    expect(
      Sint.delete<NeomVrSessionController>(tag: outer.registrationTag),
      isFalse,
    );
    expect(outerAdapter.events, ['start']);
    expect(innerAdapter.events, ['start']);

    showInner.value = false;
    await tester.pump();
    await tester.pump();
    expect(_registered(inner), isFalse);
    expect(_registered(outer), isTrue);
    expect(innerAdapter.events, ['start', 'close']);
    expect(outerAdapter.events, ['start']);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(_registered(outer), isFalse);
    expect(outerAdapter.events, ['start', 'close']);
  });

  testWidgets('external SINT deletion disables a mounted core host', (
    tester,
  ) async {
    final adapter = _Adapter();
    late NeomVrSessionController bridge;
    var active = false;
    await tester.pumpWidget(
      _shell(
        NeomVrSessionHost(
          adapter: adapter,
          builder: (context, controller, visible) {
            bridge = controller;
            active = visible;
            expect(TickerMode.valuesOf(context).enabled, visible);
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pump();
    expect(active, isTrue);
    Sint.delete<NeomVrSessionController>(
      tag: bridge.registrationTag,
      force: true,
    );
    await tester.pump();
    expect(active, isFalse);
    expect(adapter.events, ['start', 'close']);
    expect(_registered(bridge), isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(adapter.events, ['start', 'close']);
  });

  testWidgets('host disposal preserves a foreign replacement registration', (
    tester,
  ) async {
    final originalAdapter = _Adapter();
    late NeomVrSessionController original;
    await tester.pumpWidget(
      _shell(
        NeomVrSessionHost(
          adapter: originalAdapter,
          onCreated: (controller) => original = controller,
          builder: (_, __, ___) => const SizedBox(),
        ),
      ),
    );
    await tester.pump();
    Sint.delete<NeomVrSessionController>(
      tag: original.registrationTag,
      force: true,
    );
    final foreignAdapter = _Adapter();
    final foreignSession = VrSessionController(adapter: foreignAdapter);
    final foreign = Sint.put(
      NeomVrSessionController(session: foreignSession),
      tag: original.registrationTag,
      permanent: true,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(
      Sint.find<NeomVrSessionController>(tag: original.registrationTag),
      same(foreign),
    );
    expect(originalAdapter.events, ['start', 'close']);
    expect(foreignAdapter.events, isEmpty);
    Sint.delete<NeomVrSessionController>(
      tag: original.registrationTag,
      force: true,
    );
    await foreignSession.closeSession();
    foreignSession.dispose();
  });
}

bool _registered(NeomVrSessionController bridge) =>
    Sint.isRegistered<NeomVrSessionController>(tag: bridge.registrationTag);

Widget _shell(Widget child) =>
    Directionality(textDirection: TextDirection.ltr, child: child);

class _Adapter implements VrSessionAdapter {
  _Adapter({this.startError, this.closeError});
  final Object? startError;
  final Object? closeError;
  final events = <String>[];

  @override
  String get rendererId => 'test';
  @override
  void start() {
    events.add('start');
    if (startError != null) throw startError!;
  }

  @override
  void pause() => events.add('pause');
  @override
  void resume() => events.add('resume');
  @override
  void close() {
    events.add('close');
    if (closeError != null) throw closeError!;
  }
}
