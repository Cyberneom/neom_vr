import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:neom_core/domain/use_cases/app_hive_service.dart';
import 'package:neom_vr/ecosystem/auth/vr_ecosystem_session.dart';
import 'package:neom_vr/ecosystem/expedition/vr_expedition_rewards.dart';
import 'package:neom_vr/ecosystem/expedition/vr_expedition_store.dart';
import 'package:sint/sint.dart';
import 'package:vrlizate_apps/vrlizate_apps_expedition.dart';
import 'package:vrlizate_avatar/vrlizate_avatar.dart';

VrlzExpeditionDefinition _definition() => VrlzExpeditionDefinition(
  id: 'reward-campaign',
  experienceId: 'reward-worlds',
  title: 'Rewards',
  revision: 1,
  worlds: {'clearing': 'Clearing'},
  missions: [
    for (final (id, reward) in [
      ('first', VrAvatarCosmeticCatalog.canopy),
      ('second', 'non_avatar_reward'),
    ])
      VrlzExpeditionMission(
        id: id,
        world: 'clearing',
        title: id,
        instruction: 'Observe',
        discovery: 'Discovered',
        position: [8, 1.6, 12],
        rewardId: reward,
      ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Hive hive;
  setUp(() {
    hive = _Hive();
    Sint.put<AppHiveService>(hive, permanent: true);
  });
  tearDown(Sint.reset);

  test(
    'reward helper derives known accessories from the durable passport only',
    () async {
      final definition = _definition();
      final store = NeomVrExpeditionStore(
        hive: hive,
        owner: 'local-guest',
        isCurrent: () => true,
      );
      final controller = VrlzExpeditionController(
        definition: definition,
        store: store,
      );
      await controller.restore();
      controller.visit('clearing');
      expect(controller.complete('first', 'clearing', [8, 1.6, 12]), isTrue);
      expect(controller.complete('second', 'clearing', [8, 1.6, 12]), isTrue);
      expect(await controller.flush(), isTrue);
      final writes = hive.box.writes;
      expect(await NeomVrExpeditionRewards.read(definition: definition), {
        VrAvatarCosmeticCatalog.canopy,
      });
      expect(
        hive.box.writes,
        writes,
        reason: 'Reading rewards must not create another inventory.',
      );
      controller.dispose();
      store.dispose();
    },
  );

  test(
    'accepted but unsaved progress does not grant a cosmetic through helper',
    () async {
      final definition = _definition();
      final store = NeomVrExpeditionStore(
        hive: hive,
        owner: 'local-guest',
        isCurrent: () => true,
      );
      final controller = VrlzExpeditionController(
        definition: definition,
        store: store,
      );
      await controller.restore();
      hive.box.fail = true;
      controller.visit('clearing');
      controller.complete('first', 'clearing', [8, 1.6, 12]);
      expect(controller.rewardIds, contains(VrAvatarCosmeticCatalog.canopy));
      expect(await controller.flush(), isFalse);
      expect(
        await NeomVrExpeditionRewards.read(definition: definition),
        isEmpty,
      );
      controller.dispose();
      store.dispose();
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'a corrupt passport is not treated as an empty inventory or overwritten',
    () async {
      final store = NeomVrExpeditionStore(
        hive: hive,
        owner: 'local-guest',
        isCurrent: () => true,
      );
      await store.write('reward-campaign', Uint8List.fromList([1, 2, 3]));
      final writes = hive.box.writes;
      await expectLater(
        NeomVrExpeditionRewards.read(definition: _definition()),
        throwsFormatException,
      );
      expect(hive.box.writes, writes);
      expect(hive.box.data.values.single, [1, 2, 3]);
      store.dispose();
    },
  );

  test(
    'session invalidation during reward read rejects its late result',
    () async {
      final session = VrEcosystemSession(backendReady: false);
      final opened = Completer<void>();
      hive.gate = Completer<void>();
      hive.onOpen = () => opened.complete();
      final reading = NeomVrExpeditionRewards.read(
        definition: _definition(),
        session: session,
      );
      final assertion = expectLater(reading, throwsStateError);
      await opened.future;
      session.dispose();
      hive.gate!.complete();
      await assertion;
      expect(hive.box.writes, 0);
      expect(Sint.find<AppHiveService>(), same(hive));
    },
  );
}

class _Hive extends Fake implements AppHiveService {
  final box = _Box();
  Completer<void>? gate;
  void Function()? onOpen;
  @override
  Future<Box> getBox(String name, {bool limit = false}) async {
    expect(limit, isFalse);
    onOpen?.call();
    await gate?.future;
    return box;
  }
}

class _Box extends Fake implements Box<dynamic> {
  final data = <String, dynamic>{};
  var writes = 0;
  var fail = false;
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => data[key] ?? defaultValue;
  @override
  Future<void> put(dynamic key, dynamic value) async {
    if (fail) throw StateError('No storage');
    writes++;
    data[key as String] = value;
  }
}
