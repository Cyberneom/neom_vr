import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:vrlizate_avatar/vrlizate_avatar.dart';
import 'package:vrlizate_home/vrlizate_home.dart';

import '../auth/vr_ecosystem_session.dart';
import 'vr_local_avatar_store.dart';

/// Adapts the SDK avatar editor to Home's gaze/gamepad action panels.
/// The SDK owns the model/preview; the application owns identity and storage.
class VrAvatarRoomPresenter {
  VrAvatarRoomPresenter(
    this.session, {
    VrLocalAvatarStore? store,
    this.loadRewards,
  }) : store = store ?? VrLocalAvatarStore();

  final VrEcosystemSession session;
  final VrLocalAvatarStore store;
  final Future<Set<String>> Function()? loadRewards;
  final ValueNotifier<VrAvatarAppearance?> appearance = ValueNotifier(null);
  VrAvatarAppearance? _savedAppearance;
  String? _appearanceOwner;
  int? _appearanceRevision;
  int _appearanceGeneration = 0;
  Future<void>? _preparingAppearance;
  String? _preparingOwner;
  int? _preparingRevision;
  bool _disposed = false;
  VrAvatarProfile? _value;
  String? _owner, _displayName, _message;
  int _generation = 0, _page = 0;
  int? _ownerRevision;
  bool _busy = false, _dirty = false;
  Set<String> _rewards = const {};
  String? _rewardMessage;
  int _rewardPage = 0;
  String? _rewardOwner;
  int? _rewardRevision;

  String _ownerFor(VrEcosystemIdentity? identity) => identity == null
      ? 'local-guest'
      : jsonEncode([identity.uid, identity.profileId]);

  bool get _ownerCurrent =>
      !_disposed &&
      !session.isDisposed &&
      _owner != null &&
      _ownerRevision == session.revision &&
      _owner == _ownerFor(session.captureIdentity());

  bool get isCurrentOwner => _ownerCurrent;

  /// Loads only the host's local appearance; it does not open the editor.
  /// The generation/owner checks also cover logout during storage acquisition.
  Future<void> prepareAppearance() {
    if (_disposed || session.isDisposed) return Future<void>.value();
    final identity = session.captureIdentity();
    final owner = _ownerFor(identity);
    final revision = session.revision;
    _ensureRewardScope(owner, revision);
    if (_disposed ||
        (_appearanceOwner == owner && _appearanceRevision == revision)) {
      return Future<void>.value();
    }
    if (_preparingAppearance != null &&
        _preparingOwner == owner &&
        _preparingRevision == revision) {
      return _preparingAppearance!;
    }
    final generation = ++_appearanceGeneration;
    _preparingOwner = owner;
    _preparingRevision = revision;
    _savedAppearance = null;
    appearance.value = null;
    return _preparingAppearance = _readAppearance(
      owner,
      identity?.profileId ?? 'local-guest',
      revision,
      generation,
    );
  }

  Future<void> _readAppearance(
    String owner,
    String profileId,
    int revision,
    int generation,
  ) async {
    try {
      final profile = await store.read(owner: owner, profileId: profileId);
      bool current() =>
          !_disposed &&
          !session.isDisposed &&
          generation == _appearanceGeneration &&
          revision == session.revision &&
          owner == _ownerFor(session.captureIdentity());
      if (!current()) return;
      await _refreshRewards(current);
      if (!current()) return;
      _savedAppearance = profile.appearance;
      _appearanceOwner = owner;
      _appearanceRevision = revision;
      appearance.value = _visibleAppearance(profile.appearance);
    } catch (_) {
      // Keep the neutral showcase. The editor reports storage failures and
      // offers retry without overwriting a corrupt persisted record.
      if (generation == _appearanceGeneration) _appearanceRevision = null;
    } finally {
      if (generation == _appearanceGeneration) _preparingAppearance = null;
    }
  }

  VrAvatarAppearance _visibleAppearance(VrAvatarAppearance value) =>
      value.cosmeticId == null || _rewards.contains(value.cosmeticId)
      ? value
      : value.copyWith(clearCosmetic: true);

  void _ensureRewardScope(String owner, int revision) {
    if (_rewardOwner == owner && _rewardRevision == revision) return;
    _rewardOwner = owner;
    _rewardRevision = revision;
    _rewards = const {};
    _rewardMessage = null;
    _rewardPage = 0;
  }

  Future<bool> _refreshRewards(bool Function() current) async {
    final loader = loadRewards;
    if (loader == null) {
      if (current()) {
        _rewardMessage = 'La expedición todavía no está conectada a esta sala.';
      }
      return false;
    }
    try {
      final unlocked = await loader();
      if (!current()) return false;
      _rewards = Set<String>.unmodifiable({
        for (final cosmetic in VrAvatarCosmeticCatalog.all)
          if (unlocked.contains(cosmetic.id)) cosmetic.id,
      });
      _rewardMessage = null;
      return true;
    } catch (_) {
      if (current()) {
        _rewardMessage =
            'No se pudo leer el pasaporte. Tu diseño guardado se conserva; puedes reintentar.';
      }
      return false;
    }
  }

  void _publishAppearance({required bool saved}) {
    _appearanceGeneration++;
    _preparingAppearance = null;
    _appearanceOwner = _owner;
    _appearanceRevision = _ownerRevision;
    if (saved) _savedAppearance = _value!.appearance;
    appearance.value = _visibleAppearance(_value!.appearance);
  }

  VrHomeRoomContent? get content {
    final value = _value;
    if (value == null || !_ownerCurrent) return null;
    return VrHomeRoomContent(
      logicalSize: const Size(720, 300),
      child: Material(
        color: const Color(0xFF122C32),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              VrAvatarPreview(
                appearance: _visibleAppearance(value.appearance),
                size: 230,
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Text(
                  '${_displayName ?? 'Mi avatar'}\n'
                  '${const VrAvatarLabels().speciesName(value.appearance.species)} · '
                  '${value.appearance.heightMeters.toStringAsFixed(1)} m\n\n'
                  '${_dirty ? 'Cambios sin guardar' : 'Diseño local'}\n'
                  'Selecciona las opciones con mirada + A.',
                  style: const TextStyle(fontSize: 23, color: Colors.white),
                  maxLines: 8,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  VrHomeRoomPresentation presentation(VrHomeEcosystemRoom room) {
    final value = _value;
    if (value == null || !_ownerCurrent) {
      return VrHomeRoomPresentation(
        title: room.title,
        subtitle: 'Apariencia virtual',
        description: _message ?? room.description,
        actions: const [
          VrHomeRoomAction(id: 'browse', label: 'Crear o editar avatar'),
        ],
      );
    }
    final appearance = value.appearance;
    final prefs = value.preferences;
    final reward = VrAvatarCosmeticCatalog.all[_rewardPage];
    return VrHomeRoomPresentation(
      title: room.title,
      subtitle: _page == 0
          ? 'Diseño del avatar'
          : _page == 2
          ? 'Colores y proporciones'
          : _page == 3
          ? 'Recompensas de expedición'
          : 'Preferencias de convivencia',
      description:
          _message ??
          (_page == 3
              ? '${reward.title} · ${_rewardPage + 1}/4\n${reward.description}\n'
                    '${_rewardMessage ?? (_rewards.contains(reward.id) ? 'Desbloqueado en este perfil.' : 'Completa la misión para desbloquearlo.')}\n'
                    'Accesorio: ${VrAvatarCosmeticCatalog.byId(appearance.cosmeticId)?.title ?? 'ninguno'}'
              : _page != 1
              ? 'Tu modelo 3D cambia en la plataforma de esta sala. Guarda para conservarlo en este dispositivo.'
              : 'Preferencias preparadas para multijugador; la voz y los avatares remotos aún no están conectados.'),
      actions: [
        if (_page == 0) ...[
          VrHomeRoomAction(
            id: 'style',
            label:
                'Especie: ${const VrAvatarLabels().speciesName(appearance.species)}${appearance.species == VrAvatarSpecies.human ? ' · Explorador' : ''}',
          ),
          const VrHomeRoomAction(id: 'color', label: 'Color principal'),
          VrHomeRoomAction(
            id: 'height',
            label:
                'Estatura virtual: ${appearance.heightMeters.toStringAsFixed(1)} m',
          ),
          const VrHomeRoomAction(id: 'details', label: 'Colores y rasgos →'),
          const VrHomeRoomAction(id: 'preferences', label: 'Convivencia →'),
          const VrHomeRoomAction(
            id: 'rewards',
            label: 'Recompensas de expedición →',
          ),
        ] else if (_page == 2) ...[
          const VrHomeRoomAction(id: 'accent', label: 'Color de detalles'),
          VrHomeRoomAction(
            id: 'pattern',
            label:
                'Patrón: ${const VrAvatarLabels().patternName(appearance.pattern)}',
          ),
          VrHomeRoomAction(
            id: 'head',
            label: 'Cabeza: ${(appearance.headScale * 100).round()} %',
          ),
          VrHomeRoomAction(
            id: 'features',
            label: 'Rasgos: ${(appearance.featureScale * 100).round()} %',
          ),
          const VrHomeRoomAction(id: 'appearance', label: '← Apariencia'),
        ] else if (_page == 3) ...[
          const VrHomeRoomAction(id: 'reward.previous', label: '← Anterior'),
          const VrHomeRoomAction(id: 'reward.next', label: 'Siguiente →'),
          VrHomeRoomAction(
            id: 'reward.equip',
            label: appearance.cosmeticId == reward.id
                ? 'Accesorio equipado'
                : 'Equipar ${reward.title}',
            enabled:
                _rewards.contains(reward.id) &&
                appearance.cosmeticId != reward.id,
          ),
          VrHomeRoomAction(
            id: 'reward.clear',
            label: 'Quitar accesorio',
            enabled: appearance.cosmeticId != null,
          ),
          const VrHomeRoomAction(id: 'appearance', label: '← Apariencia'),
        ] else ...[
          VrHomeRoomAction(
            id: 'voice',
            label:
                'Permitir voz cercana: ${prefs.proximityVoiceEnabled ? 'sí' : 'no'}',
          ),
          VrHomeRoomAction(
            id: 'space',
            label:
                'Espacio personal: ${prefs.personalSpaceMeters.toStringAsFixed(1)} m',
          ),
          VrHomeRoomAction(
            id: 'nameplates',
            label: 'Ver nombres: ${prefs.showNameplates ? 'sí' : 'no'}',
          ),
          const VrHomeRoomAction(id: 'appearance', label: '← Apariencia'),
        ],
        VrHomeRoomAction(
          id: 'save',
          label: 'Guardar diseño local',
          enabled: _dirty,
        ),
      ],
    );
  }

  Future<void> dispatch(VrHomeEcosystemRoom room, String actionId) async {
    if (_busy ||
        !presentation(room).actions.any((a) => a.id == actionId && a.enabled)) {
      return;
    }
    final identity = session.captureIdentity();
    final owner = _ownerFor(identity);
    final ownerRevision = session.revision;
    _ensureRewardScope(owner, ownerRevision);
    if (_owner != null && _owner != owner) {
      close();
      _message = 'La cuenta cambió. Vuelve a abrir el editor.';
      return;
    }
    _busy = true;
    final generation = ++_generation;
    bool current() =>
        !_disposed &&
        !session.isDisposed &&
        generation == _generation &&
        ownerRevision == session.revision &&
        owner == _ownerFor(session.captureIdentity()) &&
        (identity == null || identity.isCurrent());
    _message = null;
    try {
      if (actionId == 'browse') {
        _appearanceGeneration++;
        _preparingAppearance = null;
        final value = await store.read(
          owner: owner,
          profileId: identity?.profileId ?? 'local-guest',
        );
        if (!current()) return;
        await _refreshRewards(current);
        if (!current()) return;
        _owner = owner;
        _ownerRevision = ownerRevision;
        _value = value;
        _displayName = identity == null
            ? 'Avatar de invitado'
            : session.userService!.profile.name;
        _dirty = false;
        _publishAppearance(saved: true);
      } else if (actionId == 'save') {
        final cosmetic = _value!.appearance.cosmeticId;
        if (cosmetic != null && cosmetic != _savedAppearance?.cosmeticId) {
          if (!await _refreshRewards(current) || !current()) return;
          if (!_rewards.contains(cosmetic)) {
            _message =
                'Este accesorio todavía no está desbloqueado en tu pasaporte.';
            return;
          }
        }
        await store.write(owner: owner, value: _value!, isCurrent: current);
        if (!current()) return;
        _dirty = false;
        _publishAppearance(saved: true);
        _message = 'Diseño guardado en este dispositivo.';
      } else if (actionId == 'rewards') {
        await _refreshRewards(current);
        if (!current()) return;
        _page = 3;
        _rewardPage = 0;
      } else if (actionId == 'reward.previous' || actionId == 'reward.next') {
        _rewardPage =
            (_rewardPage + (actionId == 'reward.next' ? 1 : -1)) %
            VrAvatarCosmeticCatalog.all.length;
      } else if (actionId == 'reward.equip' || actionId == 'reward.clear') {
        final cosmetic = VrAvatarCosmeticCatalog.all[_rewardPage];
        if (actionId == 'reward.equip') {
          if (!await _refreshRewards(current) || !current()) return;
          if (!_rewards.contains(cosmetic.id)) {
            _message = 'Completa la misión para desbloquear este accesorio.';
            return;
          }
        }
        _value = _value!.copyWith(
          appearance: _value!.appearance.copyWith(
            cosmeticId: actionId == 'reward.equip' ? cosmetic.id : null,
            clearCosmetic: actionId == 'reward.clear',
          ),
        );
        _dirty = true;
        _publishAppearance(saved: false);
      } else if (actionId == 'preferences' ||
          actionId == 'appearance' ||
          actionId == 'details') {
        _page = actionId == 'preferences'
            ? 1
            : actionId == 'details'
            ? 2
            : 0;
      } else {
        final value = _value!;
        var appearance = value.appearance;
        var preferences = value.preferences;
        switch (actionId) {
          case 'style':
            appearance = appearance.copyWith(
              species:
                  VrAvatarSpecies.values[(appearance.species.index + 1) %
                      VrAvatarSpecies.values.length],
            );
          case 'color':
            final palette = VrAvatarAppearance.palette;
            appearance = appearance.copyWith(
              bodyColorArgb:
                  palette[(palette.indexOf(appearance.bodyColorArgb) + 1) %
                      palette.length],
            );
          case 'height':
            final height = (appearance.heightMeters * 10).round() + 1;
            appearance = appearance.copyWith(
              heightMeters: height > 22 ? 10 / 10 : height / 10,
            );
          case 'accent':
            final palette = VrAvatarAppearance.palette;
            appearance = appearance.copyWith(
              accentColorArgb:
                  palette[(palette.indexOf(appearance.accentColorArgb) + 1) %
                      palette.length],
            );
          case 'pattern':
            appearance = appearance.copyWith(
              pattern:
                  VrAvatarPattern.values[(appearance.pattern.index + 1) %
                      VrAvatarPattern.values.length],
            );
          case 'head':
            final next = (appearance.headScale * 100).round() + 5;
            appearance = appearance.copyWith(
              headScale: next > 125 ? .8 : next / 100,
            );
          case 'features':
            final next = (appearance.featureScale * 100).round() + 10;
            appearance = appearance.copyWith(
              featureScale: next > 140 ? .6 : next / 100,
            );
          case 'voice':
            preferences = preferences.copyWith(
              proximityVoiceEnabled: !preferences.proximityVoiceEnabled,
            );
          case 'space':
            final decimeters =
                (preferences.personalSpaceMeters * 10).round() + 4;
            preferences = preferences.copyWith(
              personalSpaceMeters: decimeters > 20 ? .4 : decimeters / 10,
            );
          case 'nameplates':
            preferences = preferences.copyWith(
              showNameplates: !preferences.showNameplates,
            );
        }
        _value = value.copyWith(
          appearance: appearance,
          preferences: preferences,
        );
        _dirty = true;
        _publishAppearance(saved: false);
      }
    } catch (_) {
      if (current()) {
        _message = 'No se pudo leer o guardar el avatar. Inténtalo de nuevo.';
      }
    } finally {
      if (generation == _generation) _busy = false;
    }
  }

  void close() {
    _generation++;
    appearance.value =
        _appearanceRevision == session.revision &&
            _appearanceOwner == _ownerFor(session.captureIdentity())
        ? (_savedAppearance == null
              ? null
              : _visibleAppearance(_savedAppearance!))
        : null;
    _value = null;
    _owner = null;
    _ownerRevision = null;
    _displayName = null;
    _message = null;
    _page = 0;
    _busy = _dirty = false;
  }

  void dispose() {
    if (_disposed) return;
    close();
    _disposed = true;
    appearance.dispose();
  }
}
