import 'package:neom_audio_player/audio_player_invoker.dart';
import 'package:neom_core/domain/use_cases/audio_player_invoker_service.dart';
import 'package:sint/sint.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:neom_core/domain/use_cases/app_hive_service.dart';

import 'vr_content_playback.dart';
import 'vr_content_provider.dart';

/// Call when entering a content room, after ecosystem bootstrap. Creating an
/// invoker does not initialize its native audio handler; that happens on play.
/// Root owns this app-wide registration. Individual rooms borrow it and stop
/// their playback through VrContentPlayback without deleting the registration.
VrContentPlayback createNeomContentPlayback({
  Future<void> Function(VrAuthorizedContent)? readBook,
}) {
  if (!Sint.isRegistered<AudioPlayerInvokerService>()) {
    Sint.put<AudioPlayerInvokerService>(AudioPlayerInvoker(), permanent: true);
  }
  return VrContentPlayback(
    audio: Sint.find<AudioPlayerInvokerService>(),
    readBook: readBook,
    prepareAudio: _prepareAudioStorage,
  );
}

Future<void>? _audioStoragePreparation;
Future<void> _prepareAudioStorage() {
  if (Sint.isRegistered<AppHiveService>()) return Future<void>.value();
  return _audioStoragePreparation ??= Hive.initFlutter().catchError((
    Object error,
    StackTrace stack,
  ) {
    _audioStoragePreparation = null;
    Error.throwWithStackTrace(error, stack);
  });
}
