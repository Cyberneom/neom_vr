import 'dart:async';

import 'package:neom_core/domain/model/app_media_item.dart';
import 'package:neom_core/domain/use_cases/audio_player_invoker_service.dart';
import 'package:neom_core/utils/enums/app_media_source.dart';
import 'package:neom_core/utils/enums/media_item_type.dart';
import 'package:neom_audio_player/domain/use_cases/ephemeral_audio_service.dart';

import 'vr_content_provider.dart';

/// Borrows the official app's existing audio invoker. No player is constructed
/// or disposed here. A book reader must be provided by the configured host.
class VrContentPlayback {
  VrContentPlayback({this.audio, this.readBook, this.prepareAudio});
  final Future<void> Function()? prepareAudio;
  final AudioPlayerInvokerService? audio;
  final Future<void> Function(VrAuthorizedContent)? readBook;
  static final _audioOwners = <AudioPlayerInvokerService, Object>{};
  static final _audioQueues = <AudioPlayerInvokerService, Future<void>>{};
  final _owner = Object();
  Timer? _expiry;
  int _revision = 0;
  bool _closed = false;

  bool supports(VrContentItem item) =>
      !_closed &&
      (item.kind == VrContentKind.book
          ? readBook != null
          : audio is EphemeralAudioService);

  Future<void> open(VrAuthorizedContent content) async {
    if (!content.isCurrent || !supports(content.item)) {
      throw const VrContentUnavailable(
        'El lector o reproductor no está disponible.',
      );
    }
    final revision = ++_revision;
    _expiry?.cancel();
    if (content.item.kind == VrContentKind.book) {
      await readBook!(content);
      return;
    }
    final player = audio!;
    _audioOwners[player] = _owner;
    bool current() =>
        !_closed &&
        _revision == revision &&
        content.isCurrent &&
        identical(_audioOwners[player], _owner);
    try {
      await _serialize(player, () async {
        if (!current()) {
          throw const VrContentUnavailable(
            'La sesión cambió antes de iniciar el audio.',
          );
        }
        await prepareAudio?.call();
        if (!current()) {
          throw const VrContentUnavailable(
            'La sesión cambió antes de iniciar el audio.',
          );
        }
        final playbackId =
            'vrlizate:${content.source.name}:${content.item.id}:${content.grantId}';
        // This capability initializes the existing handler and disables disk
        // caches/history/quality rewrites for this specific expiring source.
        await (player as EphemeralAudioService).beginEphemeralAudio(
          EphemeralAudioGrant(
            itemId: playbackId,
            uri: content.uri,
            expiresAt: content.expiresAt,
            isAuthorized: current,
          ),
        );
        if (!current()) {
          throw const VrContentUnavailable(
            'La sesión cambió durante el inicio del audio.',
          );
        }
        final handler = await player.getOrInitAudioHandler();
        if (handler == null || !current()) {
          throw const VrContentUnavailable(
            'El reproductor no está listo o la sesión cambió.',
          );
        }
        // updateNowPlaying avoids init -> setValues -> catalog writes for these
        // external grants. isOffline stays false: the source is a remote URL.
        await player.updateNowPlaying(
          items: [
            AppMediaItem(
              id: playbackId,
              name: content.item.title,
              ownerName: content.source.title,
              url: content.uri.toString(),
              mediaSource: AppMediaSource.external,
              type: switch (content.item.kind) {
                VrContentKind.audiobook => MediaItemType.audiobook,
                VrContentKind.meditation => MediaItemType.frequency,
                _ => MediaItemType.song,
              },
            ),
          ],
          recommend: false,
          playItem: true,
          isOffline: false,
        );
        if (!current()) {
          // The next room's queue update cannot begin before this serialized
          // operation ends. Stop a late native update without stopping that room.
          await player.stop();
          throw const VrContentUnavailable(
            'La autorización dejó de estar vigente.',
          );
        }
        _expiry = Timer(content.expiresAt.difference(DateTime.now()), () {
          unawaited(pause().catchError((Object _) {}));
        });
      });
    } catch (_) {
      if (_revision == revision && identical(_audioOwners[player], _owner)) {
        await pause();
      }
      rethrow;
    }
  }

  static Future<void> _serialize(
    AudioPlayerInvokerService player,
    Future<void> Function() operation,
  ) {
    final previous = _audioQueues[player] ?? Future<void>.value();
    final result = previous.then((_) => operation());
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _audioQueues[player] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_audioQueues[player], tail)) _audioQueues.remove(player);
      }),
    );
    return result;
  }

  /// Called on route cover, app background, account change and grant expiry.
  /// It relinquishes only playback this adapter acquired, never the service.
  Future<void> pause() async {
    _revision++;
    _expiry?.cancel();
    _expiry = null;
    final player = audio;
    if (player != null && identical(_audioOwners[player], _owner)) {
      // Keep this ownership token until another adapter takes over: a pending
      // native queue update may finish after stop and must be stopped again by
      // open's revision check. The token retains no widget or player resources.
      // Stop clears ongoing playback rather than leaving a revoked grant
      // resumable through the adapter. The borrowed invoker remains alive.
      await player.stop();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await pause();
  }
}
