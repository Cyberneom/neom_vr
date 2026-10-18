import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:neom_core/domain/model/post.dart';
import 'package:vrlizate_home/vrlizate_home.dart';
import 'package:vrlizate_avatar/vrlizate_avatar.dart';

import 'auth/vr_ecosystem_session.dart';
import 'avatar/vr_avatar_room_presenter.dart';
import 'avatar/vr_local_avatar_store.dart';
import 'content/vr_content_configuration.dart';
import 'content/vr_content_playback.dart';
import 'content/vr_content_provider.dart';
import 'content/vr_neom_content_playback.dart';
import 'social/vr_ecosystem_social_source.dart';
import 'widgets/vr_neom_post_card.dart';
import 'widgets/vr_neom_profile_card.dart';
import 'widgets/vr_neom_room_preview.dart';

/// Owns account/content work for the host; Home receives presentation and action
/// IDs only. Notifications mean external invalidation, never dispatch progress.
class VrEcosystemSpatialPresenter extends ChangeNotifier
    with WidgetsBindingObserver {
  VrEcosystemSpatialPresenter(
    this.session, {
    VrContentProvider Function(VrContentSource)? providerFactory,
    VrContentPlayback Function()? playbackFactory,
    VrEcosystemSocialSource Function(VrEcosystemIdentity)? socialSourceFactory,
    this.onOpenCinema,
    VrLocalAvatarStore? avatarStore,
    this.pageSize = 3,
  }) : _avatarRoom = VrAvatarRoomPresenter(session, store: avatarStore),
       _providerFactory = providerFactory ?? configuredContentProvider,
       _playbackFactory =
           playbackFactory ?? (() => createNeomContentPlayback()),
       _socialSourceFactory =
           socialSourceFactory ??
           ((identity) => NeomVrEcosystemSocialSource(
             session: session,
             identity: identity,
           )) {
    if (pageSize != 3 && pageSize != 4) {
      throw ArgumentError.value(pageSize, 'pageSize', 'Use 3 or 4 items.');
    }
    session.addListener(_sessionChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  final VrEcosystemSession session;
  final VrAvatarRoomPresenter _avatarRoom;
  final Future<void> Function()? onOpenCinema;
  final int pageSize;
  final VrContentProvider Function(VrContentSource) _providerFactory;
  final VrContentPlayback Function() _playbackFactory;
  final VrEcosystemSocialSource Function(VrEcosystemIdentity)
  _socialSourceFactory;
  VrHomeEcosystemRoom? _room;
  VrHomeRoomPresentation? _presentation;
  VrEcosystemIdentity? _identity;
  VrContentProvider? _provider;
  VrContentPlayback? _playback;
  VrEcosystemSocialSource? _socialSource;
  List<Post> _posts = const [];
  bool _socialLoaded = false;
  List<VrContentItem> _items = const [];
  int _page = 0, _generation = 0;
  bool _busy = false, _disposed = false, _loaded = false;
  String? _message, _playingTitle;
  Timer? _grantExpiry;
  Future<void> _stopping = Future<void>.value();

  VrHomeRoomPresentation? get presentation => _presentation;
  String? get roomId => _room?.id;
  bool get busy => _busy;
  ValueListenable<VrAvatarAppearance?> get avatarAppearance =>
      _avatarRoom.appearance;
  Future<void> prepareAvatar() => _avatarRoom.prepareAppearance();

  /// Supplies existing NEOM widgets only for the currently displayed snapshot.
  /// Home owns their placement; this host retains all account and data access.
  VrHomeRoomContent? buildRoomContent(
    VrHomeEcosystemRoom room,
    VrHomeRoomPresentation presentation,
  ) {
    if (_disposed ||
        _busy ||
        _room?.id != room.id ||
        !identical(_presentation, presentation)) {
      return null;
    }
    if (room.id == 'avatar') {
      final avatarContent = _avatarRoom.content;
      if (avatarContent != null) return avatarContent;
    }
    final identity = _identity;
    if (identity == null) {
      return VrHomeRoomContent(
        child: VrNeomRoomPreview(room: _room!, status: _previewStatus),
        logicalSize: VrNeomRoomPreview.logicalSize,
      );
    }
    if (!identity.isCurrent()) return null;
    if (room.id == 'profile') {
      return VrHomeRoomContent(
        child: VrNeomProfileCard(session: session, identity: identity),
        logicalSize: VrNeomProfileCard.logicalSize,
      );
    }
    if (room.id == 'social' && _socialLoaded && _posts.isNotEmpty) {
      final post = _posts[_page.clamp(0, _posts.length - 1)];
      return VrHomeRoomContent(
        child: AnimatedBuilder(
          animation: session,
          builder: (context, _) => identity.isCurrent()
              ? VrNeomPostCard(post: post)
              : const SizedBox.shrink(),
        ),
        logicalSize: VrNeomPostCard.logicalSize,
      );
    }
    return VrHomeRoomContent(
      child: VrNeomRoomPreview(room: _room!, status: _previewStatus),
      logicalSize: VrNeomRoomPreview.logicalSize,
    );
  }

  String get _previewStatus {
    if (_room?.id == 'cinema') return 'Entra al auditorio con A';
    if (_room?.id == 'avatar') return 'Diseña tu avatar con el mando';
    if (_room?.id == 'creator') return 'Publicación .vrlz en preparación';
    if (_socialLoaded && _posts.isEmpty) return 'Sin publicaciones disponibles';
    if (!session.backendReady) return 'Exploración · cuentas no configuradas';
    return session.isAuthenticated
        ? 'Abre el contenido con tu cuenta'
        : 'Tu contenido requiere iniciar sesión';
  }

  static final _cancelled = VrHomeRoomPresentation(
    title: 'Sala actualizada',
    description: 'Vuelve a abrir la sala para continuar.',
  );

  VrHomeEcosystemRoom? _canonicalRoom(String id) {
    for (final room in VrHomeEcosystemRoom.defaults) {
      if (room.id == id) return room;
    }
    return null;
  }

  /// A null action opens public room promotion without network/account work.
  /// Subsequent actions must be currently displayed and enabled for this room.
  Future<VrHomeRoomPresentation> dispatch(
    VrHomeEcosystemRoom room,
    String? actionId,
  ) async {
    if (_disposed) return _cancelled;
    final canonical = _canonicalRoom(room.id);
    if (canonical == null) return _cancelled;
    if (actionId == null) {
      closeRoom();
      _room = canonical;
      return _render();
    }
    if (_room?.id != canonical.id) return _cancelled;
    if (_busy) return _presentation ?? _cancelled;
    if (!(_presentation?.actions.any(
          (action) => action.id == actionId && action.enabled,
        ) ??
        false)) {
      _message = 'Esta acción no está disponible en la sala actual.';
      return _render();
    }

    if (canonical.id == 'avatar') {
      final generation = ++_generation;
      _busy = true;
      try {
        await _avatarRoom.dispatch(canonical, actionId);
        if (_disposed ||
            generation != _generation ||
            _room?.id != canonical.id) {
          return _cancelled;
        }
        return _render();
      } finally {
        if (!_disposed && generation == _generation) _busy = false;
      }
    }

    // Public cinema demo has no private catalogue, uploads or account data.
    // It remains subject to the same currently-presented action allowlist.
    if (canonical.id == 'cinema' && actionId == 'enterCinema') {
      _busy = true;
      try {
        await onOpenCinema?.call();
      } finally {
        _busy = false;
      }
      return _room == null ? _cancelled : _render();
    }

    // Even local paging/actions are gated against the live account. A stale
    // catalogue must never survive a silent profile mutation between frames.
    final identity = session.captureIdentity();
    if (identity == null) {
      _clearData();
      _message = session.backendReady
          ? 'Vuelve al inicio y elige «Preparar mi cuenta» para acceder a tu contenido.'
          : 'Las cuentas aún no están disponibles. Puedes seguir explorando.';
      return _render();
    }
    if (_identity != null && !_identity!.isCurrent()) {
      _clearData();
      _message = 'La sesión cambió. Vuelve a ver el contenido de esta sala.';
      return _render();
    }
    _identity = identity;
    final generation = ++_generation;
    _busy = true;
    _message = null;
    try {
      if (actionId == 'signOut') {
        await session.signOut();
        // The session listener invalidates this operation before it returns.
        return _cancelled;
      }
      if (canonical.id == 'profile') {
        identity.requireCurrent();
        return _render();
      }
      if (canonical.id == 'social') {
        if (actionId == 'previous' || actionId == 'next') {
          final next = _page + (actionId == 'next' ? 1 : -1);
          if (next >= 0 && next < _posts.length) _page = next;
        } else if (actionId == 'browse' || actionId == 'reloadSocial') {
          _closeSocial();
          final source = _socialSourceFactory(identity);
          _socialSource = source;
          // Initialization reads the existing account-scoped NEOM timeline.
          // refresh() also retries queued uploads, so a gallery never calls it.
          await source.initialize();
          if (!_current(generation, identity) ||
              !identical(_socialSource, source)) {
            return _cancelled;
          }
          _posts = List.unmodifiable(source.posts.take(100));
          _page = 0;
          _socialLoaded = true;
        }
        if (!_current(generation, identity)) return _cancelled;
        return _render();
      }
      if (canonical.id == 'creator') {
        _message =
            'Próximamente: publicar tus experiencias .vrlz desde esta sala.';
        return _render();
      }
      if (actionId == 'previous' || actionId == 'next') {
        final next = _page + (actionId == 'next' ? 1 : -1);
        if (next >= 0 && next * pageSize < _items.length) _page = next;
      } else if (actionId == 'stop') {
        await _stopAudio();
      } else if (actionId == 'browse' || actionId == 'refresh') {
        await _stopAudio();
        if (!_current(generation, identity)) return _cancelled;
        final source = VrContentSource.values.byName(canonical.id);
        final provider = _provider ??= _providerFactory(source);
        if (provider.source != source) {
          throw const VrContentUnavailable(
            'El proveedor no corresponde a esta sala.',
          );
        }
        if (!provider.configured) {
          throw VrContentUnavailable(provider.unavailableReason);
        }
        final items = await provider.catalog(_contentIdentity(identity));
        if (!_current(generation, identity)) return _cancelled;
        _items = List.unmodifiable(items);
        _page = 0;
        _loaded = true;
      } else if (actionId.startsWith('open:')) {
        final id = actionId.substring(5);
        VrContentItem? item;
        // Only the current page's real loaded items can be dispatched.
        for (final candidate in _visibleItems) {
          if (candidate.id == id) item = candidate;
        }
        if (item == null ||
            item.kind == VrContentKind.book ||
            _provider == null) {
          throw const VrContentUnavailable(
            'Esta acción no está disponible en VR.',
          );
        }
        await _stopping;
        if (!_current(generation, identity)) return _cancelled;
        final content = await _provider!.authorize(
          item,
          _contentIdentity(identity),
        );
        if (!_current(generation, identity) || !content.isCurrent) {
          return _cancelled;
        }
        final playback = _playback ??= _playbackFactory();
        if (!playback.supports(item)) {
          throw const VrContentUnavailable(
            'El reproductor todavía no está disponible.',
          );
        }
        await playback.open(content);
        if (!_current(generation, identity) || !content.isCurrent) {
          return _cancelled;
        }
        _playingTitle = item.title;
        _grantExpiry?.cancel();
        _grantExpiry = Timer(
          content.expiresAt.difference(DateTime.now()),
          _invalidateExternally,
        );
      }
      if (!_current(generation, identity)) return _cancelled;
      return _render();
    } catch (error) {
      if (!_current(generation, identity)) return _cancelled;
      if (canonical.id == 'social') _closeSocial();
      _message = error is VrContentUnavailable
          ? error.message
          : 'No se pudo completar la acción. Inténtalo de nuevo.';
      return _render();
    } finally {
      if (!_disposed && generation == _generation) _busy = false;
    }
  }

  bool _current(int generation, VrEcosystemIdentity identity) =>
      !_disposed &&
      _room != null &&
      generation == _generation &&
      identity.isCurrent();

  VrContentIdentity _contentIdentity(VrEcosystemIdentity identity) =>
      VrContentIdentity(
        userId: identity.uid,
        profileId: identity.profileId,
        revision: identity.revision,
        isCurrent: identity.isCurrent,
        getIdToken: identity.getIdToken,
      );

  Iterable<VrContentItem> get _visibleItems =>
      _items.skip(_page * pageSize).take(pageSize);

  VrHomeRoomPresentation _render() {
    final room = _room;
    if (room == null) return _cancelled;
    if (room.id == 'avatar') {
      return _presentation = _avatarRoom.presentation(room);
    }
    final actions = <VrHomeRoomAction>[];
    var subtitle = 'Explora la sala';
    var description = _message ?? room.description;
    if (room.id == 'cinema') {
      subtitle = 'Auditorio · YouTube';
      actions.add(
        VrHomeRoomAction(
          id: 'enterCinema',
          label: 'Entrar al cine',
          enabled: onOpenCinema != null,
        ),
      );
    } else if (room.id == 'profile' && _identity?.isCurrent() == true) {
      final profile = session.userService!.profile;
      subtitle = _short(profile.name, 64);
      description =
          _message ??
          '${profile.aboutMe.isEmpty ? 'Tu espacio personal en VRlizate.' : _short(profile.aboutMe, 52)}\n'
              '${profile.posts?.length ?? 0} publicaciones · ${profile.followers?.length ?? 0} seguidores';
      actions.add(
        const VrHomeRoomAction(id: 'signOut', label: 'Cerrar sesión'),
      );
    } else if (room.id == 'social' &&
        _socialLoaded &&
        _identity?.isCurrent() == true) {
      subtitle = _posts.isEmpty
          ? 'Sin publicaciones disponibles'
          : 'Publicación ${_page + 1} de ${_posts.length}';
      description =
          _message ??
          _socialSource?.loadMessage ??
          (_socialSource?.offline == true
              ? 'Contenido de esta cuenta guardado en el dispositivo.'
              : _posts.isEmpty
              ? 'No hay publicaciones de tu comunidad para mostrar.'
              : 'Una publicación por vez. Anterior y Siguiente con el mando.');
      if (_page > 0) {
        actions.add(const VrHomeRoomAction(id: 'previous', label: 'Anterior'));
      }
      if (_page + 1 < _posts.length) {
        actions.add(const VrHomeRoomAction(id: 'next', label: 'Siguiente'));
      }
      actions.add(
        const VrHomeRoomAction(id: 'reloadSocial', label: 'Actualizar muro'),
      );
    } else if (_loaded && _identity?.isCurrent() == true) {
      final pages = (_items.length / pageSize).ceil();
      subtitle = _items.isEmpty
          ? 'Sin contenido disponible'
          : 'Página ${_page + 1} de $pages';
      description =
          _message ??
          (_playingTitle == null
              ? room.id == 'emxi'
                    ? 'El proveedor verificará tu acceso. Lectura VR próximamente.'
                    : 'El proveedor verificará tu acceso al abrir.'
              : 'Audio iniciado: ${_short(_playingTitle!, 70)}');
      for (final item in _visibleItems) {
        actions.add(
          VrHomeRoomAction(
            id: 'open:${item.id}',
            label: item.kind == VrContentKind.book
                ? '${_short(item.title, 65)} · Lectura VR próximamente'
                : 'Escuchar: ${_short(item.title, 80)}',
            enabled: item.kind != VrContentKind.book,
          ),
        );
      }
      if (_page > 0) {
        actions.add(const VrHomeRoomAction(id: 'previous', label: 'Anterior'));
      }
      if ((_page + 1) * pageSize < _items.length) {
        actions.add(const VrHomeRoomAction(id: 'next', label: 'Siguiente'));
      }
      actions.add(const VrHomeRoomAction(id: 'refresh', label: 'Actualizar'));
      if (_playback != null) {
        actions.add(const VrHomeRoomAction(id: 'stop', label: 'Detener audio'));
      }
    } else {
      actions.add(const VrHomeRoomAction(id: 'browse', label: 'Ver contenido'));
    }
    return _presentation = VrHomeRoomPresentation(
      title: room.title,
      subtitle: subtitle,
      description: description,
      actions: List.unmodifiable(actions),
    );
  }

  static String _short(String text, int limit) =>
      text.length <= limit ? text : '${text.substring(0, limit - 1)}…';

  Future<void> _stopAudio() {
    _grantExpiry?.cancel();
    _grantExpiry = null;
    _playingTitle = null;
    final playback = _playback;
    if (playback == null) return _stopping;
    final stop = playback.pause().catchError((Object _) {});
    return _stopping = Future.wait<void>([_stopping, stop]).then((_) {});
  }

  void _clearData() {
    _generation++;
    _avatarRoom.close();
    _busy = false;
    _identity = null;
    _items = const [];
    _closeSocial();
    _loaded = false;
    _page = 0;
    _message = null;
    _playingTitle = null;
    _grantExpiry?.cancel();
    _grantExpiry = null;
    _provider?.close();
    _provider = null;
    final playback = _playback;
    _playback = null;
    if (playback != null) {
      final close = playback.close().catchError((Object _) {});
      _stopping = Future.wait<void>([_stopping, close]).then((_) {});
    }
  }

  void _closeSocial() {
    final source = _socialSource;
    _socialSource = null;
    _posts = const [];
    _socialLoaded = false;
    source?.dispose();
  }

  void _sessionChanged() {
    if (!_disposed) unawaited(_avatarRoom.prepareAppearance());
    if (_disposed || _room == null || _identity?.isCurrent() == true) return;
    if (_room?.id == 'avatar' && _avatarRoom.isCurrentOwner) return;
    _invalidateExternally();
  }

  void _invalidateExternally() {
    if (_disposed || _room == null) return;
    _clearData();
    _render();
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _invalidateExternally();
  }

  /// Host-driven close; deliberately does not notify Home back into a reload.
  void closeRoom() {
    if (_disposed) return;
    _clearData();
    _room = null;
    _presentation = null;
  }

  @override
  void dispose() {
    if (_disposed) return;
    closeRoom();
    _disposed = true;
    _avatarRoom.dispose();
    session.removeListener(_sessionChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
