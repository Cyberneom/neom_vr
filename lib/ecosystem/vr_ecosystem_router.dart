import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:neom_books/neom_books_reader.dart';
import 'package:vrlizate_home/vrlizate_home.dart';

import 'auth/vr_ecosystem_auth.dart';
import 'content/vr_content_provider.dart';
import 'content/vr_content_configuration.dart';
import 'content/vr_content_room_page.dart';
import 'content/vr_neom_content_playback.dart';
import 'creator/vr_creator_page.dart';
import 'creator/vr_creator_service.dart';
import 'social/vr_ecosystem_social_page.dart';
import 'social/vr_ecosystem_profile_page.dart';
import 'vr_granted_book_page.dart';

/// The official host composes services and guards. Home receives only callbacks.
class VrEcosystemRouter {
  VrEcosystemRouter(
    this.session, {
    this.themeListenable,
    this.onExperiences,
    this.roomWrapper,
  });
  final VrEcosystemSession session;
  final ValueListenable<VrHomeThemeData>? themeListenable;
  final VoidCallback? onExperiences;
  final Widget Function(BuildContext context, Widget child)? roomWrapper;

  Widget lobby(BuildContext context) {
    Widget buildLobby(VrHomeThemeData theme) => VrHomeEcosystemLobby(
      theme: theme,
      onBack: () => Navigator.of(context).maybePop(),
      onOpenRoom: (room) => openRoom(context, room),
      onExperiences: onExperiences ?? () {},
    );
    final listenable = themeListenable;
    if (listenable == null) {
      return buildLobby(VrHomeThemeData.aurora);
    }
    return ValueListenableBuilder<VrHomeThemeData>(
      valueListenable: listenable,
      builder: (context, theme, _) => buildLobby(theme),
    );
  }

  Future<void> openRoom(BuildContext context, VrHomeEcosystemRoom room) async {
    if (!VrHomeEcosystemRoom.defaults.any((allowed) => allowed.id == room.id)) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        settings: RouteSettings(name: '/rooms/${room.id}'),
        builder: (context) => roomPage(context, room.id),
      ),
    );
  }

  Widget roomPage(BuildContext context, String id) {
    if (!VrHomeEcosystemRoom.defaults.any((room) => room.id == id)) {
      return lobby(context);
    }
    final guard = VrEcosystemRouteGuard(
      session: session,
      onSignIn: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          settings: const RouteSettings(name: '/account'),
          builder: (_) => VrEcosystemAccountPage(
            session: session,
            onContinue: () => Navigator.of(context).maybePop(),
          ),
        ),
      ),
      builder: (context, identity) => _RoomBody(
        key: ValueKey('$id:${identity.revision}:${identity.profileId}'),
        id: id,
        session: session,
        identity: identity,
      ),
    );
    return roomWrapper != null ? roomWrapper!(context, guard) : guard;
  }
}

class _RoomBody extends StatefulWidget {
  const _RoomBody({
    super.key,
    required this.id,
    required this.session,
    required this.identity,
  });
  final String id;
  final VrEcosystemSession session;
  final VrEcosystemIdentity identity;
  @override
  State<_RoomBody> createState() => _RoomBodyState();
}

class _RoomBodyState extends State<_RoomBody> {
  late final Widget _body;
  @override
  void initState() {
    super.initState();
    final session = widget.session;
    final identity = widget.identity;
    switch (widget.id) {
      case 'profile':
        _body = VrEcosystemProfilePage(session: session, identity: identity);
      case 'social':
        _body = VrEcosystemSocialPage(session: session, identity: identity);
      case 'creator':
        const endpoint = String.fromEnvironment('VRLIZATE_CREATOR_URL');
        const origins = String.fromEnvironment(
          'VRLIZATE_CREATOR_UPLOAD_ORIGINS',
        );
        VrCreatorService create(Uri? uri, Set<String> origins) =>
            VrCreatorService(
              endpoint: uri,
              uploadOrigins: origins,
              identity: () => identity.isCurrent()
                  ? VrCreatorIdentity(
                      uid: identity.uid,
                      profileId: identity.profileId,
                      isCurrent: identity.isCurrent,
                      getIdToken: identity.getIdToken,
                    )
                  : null,
            );
        VrCreatorService service;
        try {
          service = create(
            endpoint.isEmpty ? null : Uri.parse(endpoint),
            origins
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toSet(),
          );
        } catch (_) {
          service = create(null, const {});
        }
        _body = VrCreatorPage(service: service);
      default:
        final source = VrContentSource.values.byName(widget.id);
        _body = VrContentRoomPage(
          provider: configuredContentProvider(source),
          ownsProvider: true,
          sessionChanges: session,
          captureIdentity: () => identity.isCurrent()
              ? VrContentIdentity(
                  userId: identity.uid,
                  profileId: identity.profileId,
                  revision: identity.revision,
                  isCurrent: identity.isCurrent,
                  getIdToken: identity.getIdToken,
                )
              : null,
          playback: createNeomContentPlayback(
            readBook: PdfDocumentSurface.isSupported
                ? (content) async {
                    if (!mounted || !content.isCurrent) return;
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        settings: const RouteSettings(name: '/reader'),
                        builder: (_) => VrGrantedBookPage(
                          content: content,
                          session: session,
                        ),
                      ),
                    );
                  }
                : null,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) => _body;
}
