import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neom_core/domain/model/app_profile.dart';
import 'package:neom_core/domain/use_cases/user_service.dart';
import 'package:neom_vr/ecosystem/auth/vr_ecosystem_session.dart';
import 'package:neom_vr/ecosystem/avatar/vr_avatar_room_presenter.dart';
import 'package:neom_vr/ecosystem/avatar/vr_local_avatar_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vrlizate_avatar/vrlizate_avatar.dart';
import 'package:vrlizate_home/vrlizate_home.dart';

VrHomeEcosystemRoom get _room =>
    VrHomeEcosystemRoom.defaults.singleWhere((r) => r.id == 'avatar');
VrHomeRoomAction _action(VrAvatarRoomPresenter p, String id) =>
    p.presentation(_room).actions.singleWhere((a) => a.id == id);

final _custom = VrAvatarAppearance(
  species: VrAvatarSpecies.axolotl,
  bodyColorArgb: 0xffcc704d,
  accentColorArgb: 0xff8258c9,
  heightMeters: 1.85,
  headScale: 1.2,
  featureScale: .7,
  pattern: VrAvatarPattern.stripes,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('equipping, saving and removing modify only the accessory', () async {
    final session = VrEcosystemSession(backendReady: false);
    final store = VrLocalAvatarStore();
    await store.write(
      owner: 'local-guest',
      value: VrAvatarProfile(profileId: 'local-guest', appearance: _custom),
      isCurrent: () => true,
    );
    final presenter = VrAvatarRoomPresenter(
      session,
      store: store,
      loadRewards: () async => {
        VrAvatarCosmeticCatalog.canopy,
        'unrecognized_reward',
      },
    );
    addTearDown(session.dispose);
    addTearDown(presenter.dispose);
    await presenter.dispatch(_room, 'browse');
    await presenter.dispatch(_room, 'rewards');
    expect(_action(presenter, 'reward.equip').enabled, isTrue);
    await presenter.dispatch(_room, 'reward.equip');
    expect(
      presenter.appearance.value,
      _custom.copyWith(cosmeticId: VrAvatarCosmeticCatalog.canopy),
    );
    await presenter.dispatch(_room, 'save');
    final equipped = await store.read(
      owner: 'local-guest',
      profileId: 'local-guest',
    );
    expect(
      equipped.appearance,
      _custom.copyWith(cosmeticId: VrAvatarCosmeticCatalog.canopy),
    );
    await presenter.dispatch(_room, 'reward.next');
    expect(_action(presenter, 'reward.equip').enabled, isFalse);
    await presenter.dispatch(_room, 'reward.equip');
    expect(presenter.appearance.value, equipped.appearance);
    await presenter.dispatch(_room, 'reward.clear');
    await presenter.dispatch(_room, 'save');
    expect(
      (await store.read(
        owner: 'local-guest',
        profileId: 'local-guest',
      )).appearance,
      _custom,
    );
  });

  test(
    'all four catalog pages are reachable without unlocking any species',
    () async {
      final session = VrEcosystemSession(backendReady: false);
      final presenter = VrAvatarRoomPresenter(
        session,
        loadRewards: () async => {},
      );
      addTearDown(session.dispose);
      addTearDown(presenter.dispose);
      await presenter.dispatch(_room, 'browse');
      for (var i = 0; i < VrAvatarSpecies.values.length; i++) {
        expect(_action(presenter, 'style').enabled, isTrue);
        await presenter.dispatch(_room, 'style');
      }
      await presenter.dispatch(_room, 'rewards');
      for (final cosmetic in VrAvatarCosmeticCatalog.all) {
        expect(
          presenter.presentation(_room).description,
          contains(cosmetic.title),
        );
        expect(_action(presenter, 'reward.equip').enabled, isFalse);
        await presenter.dispatch(_room, 'reward.next');
      }
      expect(
        presenter.presentation(_room).description,
        contains(VrAvatarCosmeticCatalog.all.first.title),
      );
      await presenter.dispatch(_room, 'reward.previous');
      expect(
        presenter.presentation(_room).description,
        contains(VrAvatarCosmeticCatalog.all.last.title),
      );
    },
  );

  test(
    'loader failure preserves saved accessory and independent personalization',
    () async {
      final session = VrEcosystemSession(backendReady: false);
      final store = VrLocalAvatarStore();
      final original = _custom.copyWith(
        cosmeticId: VrAvatarCosmeticCatalog.neon,
      );
      await store.write(
        owner: 'local-guest',
        value: VrAvatarProfile(profileId: 'local-guest', appearance: original),
        isCurrent: () => true,
      );
      final presenter = VrAvatarRoomPresenter(
        session,
        store: store,
        loadRewards: () async => throw StateError('No passport'),
      );
      addTearDown(session.dispose);
      addTearDown(presenter.dispose);
      await presenter.prepareAppearance();
      expect(
        presenter.appearance.value,
        _custom,
        reason: 'Unverified accessory is hidden, not erased from storage.',
      );
      expect(
        (await store.read(
          owner: 'local-guest',
          profileId: 'local-guest',
        )).appearance,
        original,
      );
      await presenter.dispatch(_room, 'browse');
      await presenter.dispatch(_room, 'color');
      await presenter.dispatch(_room, 'save');
      final changed = (await store.read(
        owner: 'local-guest',
        profileId: 'local-guest',
      )).appearance;
      expect(changed.cosmeticId, original.cosmeticId);
      expect(changed.species, original.species);
      expect(changed.pattern, original.pattern);
      expect(changed.bodyColorArgb, isNot(original.bodyColorArgb));
    },
  );

  test(
    'equipping and saving revalidate instead of trusting an earlier reward page',
    () async {
      final session = VrEcosystemSession(backendReady: false);
      var rewards = <String>{VrAvatarCosmeticCatalog.canopy};
      var fail = false;
      final presenter = VrAvatarRoomPresenter(
        session,
        loadRewards: () async {
          if (fail) throw StateError('Passport unavailable');
          return rewards;
        },
      );
      addTearDown(session.dispose);
      addTearDown(presenter.dispose);
      await presenter.dispatch(_room, 'browse');
      await presenter.dispatch(_room, 'rewards');
      rewards = {};
      await presenter.dispatch(_room, 'reward.equip');
      expect(presenter.appearance.value?.cosmeticId, isNull);
      rewards = {VrAvatarCosmeticCatalog.canopy};
      await presenter.dispatch(_room, 'appearance');
      await presenter.dispatch(_room, 'rewards');
      await presenter.dispatch(_room, 'reward.equip');
      fail = true;
      await presenter.dispatch(_room, 'save');
      expect(_action(presenter, 'save').enabled, isTrue);
      final saved = await VrLocalAvatarStore().read(
        owner: 'local-guest',
        profileId: 'local-guest',
      );
      expect(saved.appearance.cosmeticId, isNull);
    },
  );

  test(
    'a late reward read cannot equip or publish after identity changes',
    () async {
      final session = _Session();
      Completer<Set<String>>? gate;
      final presenter = VrAvatarRoomPresenter(
        session,
        loadRewards: () async =>
      gate == null ? {VrAvatarCosmeticCatalog.canopy} : gate.future,
      );
      addTearDown(session.dispose);
      addTearDown(presenter.dispose);
      await presenter.dispatch(_room, 'browse');
      await presenter.dispatch(_room, 'rewards');
      gate = Completer<Set<String>>();
      final pending = presenter.dispatch(_room, 'reward.equip');
      await Future<void>.delayed(Duration.zero);
      session.switchProfile();
      gate.complete({VrAvatarCosmeticCatalog.canopy});
      await pending;
      expect(presenter.isCurrentOwner, isFalse);
      expect(presenter.content, isNull);
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    },
  );

  test(
    'reward cache is partitioned by account/profile even on a failed read',
    () async {
      final session = _Session();
      var fail = false;
      final presenter = VrAvatarRoomPresenter(
        session,
        loadRewards: () async {
          if (fail) throw StateError('No passport for next profile');
          return {VrAvatarCosmeticCatalog.canopy};
        },
      );
      addTearDown(session.dispose);
      addTearDown(presenter.dispose);
      await presenter.dispatch(_room, 'browse');
      await presenter.dispatch(_room, 'rewards');
      expect(_action(presenter, 'reward.equip').enabled, isTrue);
      presenter.close();
      session.switchProfile();
      fail = true;
      await presenter.dispatch(_room, 'browse');
      await presenter.dispatch(_room, 'rewards');
      expect(_action(presenter, 'reward.equip').enabled, isFalse);
    },
  );

  test(
    'missing expedition integration keeps ordinary avatar editing available',
    () async {
      final session = VrEcosystemSession(backendReady: false);
      final presenter = VrAvatarRoomPresenter(session);
      addTearDown(session.dispose);
      addTearDown(presenter.dispose);
      await presenter.dispatch(_room, 'browse');
      await presenter.dispatch(_room, 'style');
      await presenter.dispatch(_room, 'save');
      expect(presenter.appearance.value?.species, VrAvatarSpecies.robot);
      await presenter.dispatch(_room, 'rewards');
      expect(_action(presenter, 'reward.equip').enabled, isFalse);
      expect(
        presenter.presentation(_room).description,
        contains('no está conectada'),
      );
    },
  );
}

class _Session extends VrEcosystemSession {
  _Session() : super(backendReady: false, userService: _Users());
  var generation = 0;
  @override
  int get revision => generation;
  @override
  VrEcosystemIdentity? captureIdentity() =>
      isDisposed ? null : _Identity(this, generation);
  void switchProfile() {
    generation++;
    (userService as _Users).id = 'profile-$generation';
    notifyListeners();
  }
}

class _Identity extends Fake implements VrEcosystemIdentity {
  _Identity(this.session, this.revision);
  final _Session session;
  @override
  final int revision;
  @override
  String get uid => 'account';
  @override
  String get profileId => 'profile-$revision';
  @override
  bool isCurrent() => !session.isDisposed && session.generation == revision;
}

class _Users extends Fake implements UserService {
  var id = 'profile-0';
  @override
  AppProfile get profile => AppProfile(id: id, name: 'Test profile');
}
