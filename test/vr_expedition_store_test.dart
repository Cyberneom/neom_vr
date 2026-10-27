import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:neom_core/domain/use_cases/app_hive_service.dart';
import 'package:neom_vr/ecosystem/auth/vr_ecosystem_session.dart';
import 'package:neom_vr/ecosystem/expedition/vr_expedition_store.dart';
import 'package:neom_vr/ecosystem/storage/vr_hive_lease.dart';
import 'package:sint/sint.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Hive hive;
  final stores = <NeomVrExpeditionStore>[];
  NeomVrExpeditionStore store(String owner, {bool Function()? current}) {
    final value = NeomVrExpeditionStore(
      hive: hive,
      owner: owner,
      isCurrent: current ?? () => true,
    );
    stores.add(value);
    return value;
  }

  setUp(() => hive = _Hive());
  tearDown(() async {
    for (final value in stores) {
      value.dispose();
    }
    stores.clear();
    Sint.reset();
  });

  test(
    'guest, accounts, profiles and expeditions have separate hashed keys',
    () async {
      final guest = store('local-guest');
      final profile = store('["uid-a","profile-a"]');
      final sibling = store('["uid-a","profile-b"]');
      final account = store('["uid-b","profile-a"]');
      await guest.write('expedition-one', Uint8List.fromList([1]));
      await profile.write('expedition-one', Uint8List.fromList([2]));
      await sibling.write('expedition-one', Uint8List.fromList([3]));
      await account.write('expedition-one', Uint8List.fromList([4]));
      await profile.write('expedition-two', Uint8List.fromList([5]));
      expect(await guest.read('expedition-one'), [1]);
      expect(await profile.read('expedition-one'), [2]);
      expect(await sibling.read('expedition-one'), [3]);
      expect(await account.read('expedition-one'), [4]);
      expect(await profile.read('expedition-two'), [5]);
      expect(await guest.read('expedition-two'), isNull);
      expect(hive.box.data, hasLength(5));
      for (final key in hive.box.data.keys) {
        expect(key, matches(RegExp(r'^v1\.[a-f0-9]{64}\.[a-f0-9]{64}$')));
      }
      expect(hive.limits.every((limit) => !limit), isTrue);
      expect(hive.names.toSet(), {'vrlizate_expedition_v1'});
    },
  );

  test(
    'queued writes clone input and reads return independent snapshots',
    () async {
      final value = store('clone-owner');
      hive.openGate = Completer<void>();
      final input = Uint8List.fromList([1, 2, 3]);
      final writing = value.write('clone-expedition', input);
      input[0] = 99;
      await _turn();
      hive.openGate!.complete();
      await writing;
      final first = await value.read('clone-expedition');
      expect(first, [1, 2, 3]);
      first![1] = 99;
      expect(await value.read('clone-expedition'), [1, 2, 3]);
    },
  );

  test(
    'instances serialize same-key writes and reads wait for own writes',
    () async {
      final oldRoute = store('serial-owner');
      final newRoute = store('serial-owner');
      hive.box.putGate = Completer<void>();
      final first = oldRoute.write(
        'serial-expedition',
        Uint8List.fromList([1]),
      );
      await _turn();
      final second = newRoute.write(
        'serial-expedition',
        Uint8List.fromList([2]),
      );
      final reading = oldRoute.read('serial-expedition');
      var readDone = false;
      unawaited(reading.then((_) => readDone = true));
      await _turn();
      expect(hive.box.putCalls, 1);
      expect(readDone, isFalse);
      hive.box.putGate!.complete();
      await Future.wait([first, second]);
      expect(await reading, [2]);
      expect(hive.box.putCalls, 2);
    },
  );

  test('unrelated owners do not wait for a blocked writer', () async {
    final oldOwner = store('blocked-owner');
    final other = store('independent-owner');
    final gate = Completer<void>();
    hive.box.putHook = (key) async {
      if (hive.box.putCalls == 1) await gate.future;
    };
    final writing = oldOwner.write(
      'shared-expedition',
      Uint8List.fromList([1]),
    );
    await _turn();
    await other.write('shared-expedition', Uint8List.fromList([2]));
    expect(await other.read('shared-expedition'), [2]);
    gate.complete();
    await writing;
  });

  test('storage errors propagate without poisoning the shared queue', () async {
    final value = store('retry-owner');
    hive.box.failPuts = 1;
    await expectLater(
      value.write('retry-expedition', Uint8List.fromList([1])),
      throwsStateError,
    );
    await value.write('retry-expedition', Uint8List.fromList([2]));
    expect(await value.read('retry-expedition'), [2]);
    hive.failOpens = 1;
    await expectLater(value.read('retry-expedition'), throwsStateError);
    expect(await value.read('retry-expedition'), [2]);
  });

  test(
    'identity change while opening storage prevents both read and write',
    () async {
      var current = true;
      final value = store('pending-owner', current: () => current);
      hive.openGate = Completer<void>();
      final writing = value.write(
        'pending-expedition',
        Uint8List.fromList([1]),
      );
      final assertion = expectLater(writing, throwsStateError);
      await _turn();
      current = false;
      hive.openGate!.complete();
      await assertion;
      expect(hive.box.putCalls, 0);
      expect(hive.box.data, isEmpty);
      current = true;
      hive.openGate = Completer<void>();
      final reading = value.read('pending-expedition');
      final readAssertion = expectLater(reading, throwsStateError);
      await _turn();
      current = false;
      hive.openGate!.complete();
      await readAssertion;
    },
  );

  test(
    'an in-flight old-owner write never becomes a new-owner snapshot',
    () async {
      var current = true;
      final previous = store('previous-owner', current: () => current);
      final replacement = store('replacement-owner');
      hive.box.putGate = Completer<void>();
      final writing = previous.write(
        'identity-expedition',
        Uint8List.fromList([1]),
      );
      final assertion = expectLater(writing, throwsStateError);
      await _turn();
      current = false;
      hive.box.putGate!.complete();
      await assertion;
      expect(await replacement.read('identity-expedition'), isNull);
      expect(previous.isCurrent, isFalse);
    },
  );

  test(
    'dispose invalidates queued work and does not close shared boxes',
    () async {
      final value = store('disposed-owner');
      hive.openGate = Completer<void>();
      final writing = value.write(
        'disposed-expedition',
        Uint8List.fromList([1]),
      );
      final assertion = expectLater(writing, throwsStateError);
      await _turn();
      value.dispose();
      value.dispose();
      hive.openGate!.complete();
      await assertion;
      expect(value.isCurrent, isFalse);
      await expectLater(value.read('disposed-expedition'), throwsStateError);
      expect(hive.box.closeCalls, 0);
    },
  );

  test(
    'size boundary and corrupt stored bytes fail without overwriting',
    () async {
      final value = store('bounded-owner');
      await value.write('bounded-expedition', Uint8List(32768));
      expect(await value.read('bounded-expedition'), hasLength(32768));
      await expectLater(
        value.write('bounded-expedition', Uint8List(32769)),
        throwsArgumentError,
      );
      expect(await value.read('bounded-expedition'), hasLength(32768));
      final key = hive.box.data.keys.single;
      hive.box.data[key] = Uint8List(32769);
      await expectLater(
        value.read('bounded-expedition'),
        throwsFormatException,
      );
      expect((hive.box.data[key] as Uint8List).length, 32769);
      hive.box.data[key] = {'untrusted': 'record'};
      await expectLater(
        value.read('bounded-expedition'),
        throwsFormatException,
      );
      await expectLater(value.read(''), throwsArgumentError);
    },
  );

  test(
    'offline guest open borrows the shared service and survives reopening',
    () async {
      Sint.put<AppHiveService>(hive, permanent: true);
      final first = await NeomVrExpeditionStore.open();
      await first.write('offline-expedition', Uint8List.fromList([7]));
      first.dispose();
      final reopened = await NeomVrExpeditionStore.open();
      stores.add(reopened);
      expect(await reopened.read('offline-expedition'), [7]);
      expect(Sint.find<AppHiveService>(), same(hive));
      expect(hive.box.closeCalls, 0);
    },
  );

  test(
    'guest store observes session disposal and rejects stale operations',
    () async {
      Sint.put<AppHiveService>(hive, permanent: true);
      final session = VrEcosystemSession(backendReady: false);
      expect(session.isDisposed, isFalse);
      final value = await NeomVrExpeditionStore.open(session: session);
      stores.add(value);
      await value.write('guest-session-expedition', Uint8List.fromList([8]));
      expect(value.isCurrent, isTrue);
      session.dispose();
      expect(session.isDisposed, isTrue);
      expect(value.isCurrent, isFalse);
      await expectLater(
        value.read('guest-session-expedition'),
        throwsStateError,
      );
    },
  );

  test(
    'already disposed sessions cannot acquire a guest storage scope',
    () async {
      Sint.put<AppHiveService>(hive, permanent: true);
      final session = VrEcosystemSession(backendReady: false)..dispose();
      await expectLater(
        NeomVrExpeditionStore.open(session: session),
        throwsStateError,
      );
      expect(hive.names, isEmpty);
      expect(Sint.find<AppHiveService>(), same(hive));
    },
  );

  test('pose storage scopes are stable digests separated by owner', () {
    final first = store('scope-owner');
    final again = store('scope-owner');
    final other = store('another-owner');
    expect(first.storageScope, matches(RegExp(r'^[a-f0-9]{64}$')));
    expect(again.storageScope, first.storageScope);
    expect(other.storageScope, isNot(first.storageScope));
  });

  test(
    'shared lease removes its owned binding only after the last borrower',
    () {
      final first = VrHiveLease.acquire();
      final second = VrHiveLease.acquire();
      expect(second.service, same(first.service));
      first.release();
      expect(Sint.isRegistered<AppHiveService>(), isTrue);
      second.release();
      expect(Sint.isRegistered<AppHiveService>(), isFalse);
      second.release();
    },
  );

  test('lease never removes a service binding replaced by its host', () {
    final previous = VrHiveLease.acquire();
    Sint.delete<AppHiveService>(force: true);
    Sint.put<AppHiveService>(hive, permanent: true);
    previous.release();
    expect(Sint.find<AppHiveService>(), same(hive));
  });
}

Future<void> _turn() => Future<void>.delayed(Duration.zero);

class _Hive implements AppHiveService {
  final box = _Box();
  final names = <String>[];
  final limits = <bool>[];
  Completer<void>? openGate;
  int failOpens = 0;

  @override
  Future<Box> getBox(String boxName, {bool limit = false}) async {
    names.add(boxName);
    limits.add(limit);
    if (openGate != null) await openGate!.future;
    if (failOpens > 0) {
      failOpens--;
      throw StateError('Storage unavailable.');
    }
    return box;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Box implements Box<dynamic> {
  final data = <String, dynamic>{};
  Completer<void>? putGate;
  Future<void> Function(String key)? putHook;
  int putCalls = 0, failPuts = 0, closeCalls = 0;

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => data[key] ?? defaultValue;

  @override
  Future<void> put(dynamic key, dynamic value) async {
    putCalls++;
    if (putHook != null) await putHook!(key as String);
    if (putGate != null) await putGate!.future;
    if (failPuts > 0) {
      failPuts--;
      throw StateError('Write unavailable.');
    }
    data[key as String] = value;
  }

  @override
  Future<void> close() async => closeCalls++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
