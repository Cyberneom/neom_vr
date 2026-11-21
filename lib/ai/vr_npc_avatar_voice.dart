import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:neom_tts/reader_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vrlizate_assistant/vrlizate_assistant.dart';

export 'package:neom_tts/reader_tts.dart' show ReaderTtsVoice;

/// Native voices only. The local reader verifies installation and re-selects
/// the exact voice before each line, including after an avatar change.
class NeomNpcAvatarSpeechOutput implements VrAssistantSpeechOutput {
  NeomNpcAvatarSpeechOutput({ReaderTtsService? nativeSpeech})
    : _speech = nativeSpeech ?? createLocalReaderTtsService();
  final ReaderTtsService _speech;
  int _epoch = 0;
  String gender = 'system';
  String? previewId;
  String? unavailableNotice;
  Future<String>? _engine;

  Future<List<ReaderTtsVoice>> spanishVoices() =>
      _speech.getLocalVoices(language: 'es');

  Future<void> prepare() async {
    final voices = await spanishVoices();
    if (voices.isEmpty) {
      throw const ReaderTtsUnavailable('Falta una voz española local.');
    }
  }

  static Future<String> _engineId() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await const MethodChannel(
            'flutter_tts',
          ).invokeMethod<String>('getDefaultEngine') ??
          '';
    }
    return defaultTargetPlatform.name;
  }

  Future<String> _key(String gender) async =>
      'vrlizate.npc.voz.${await (_engine ??= _engineId())}.$gender';

  Future<String?> assignedVoice(String gender) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(await _key(gender));
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> assignVoice(String gender, String? voiceId) async {
    final key = await _key(gender);
    final prefs = await SharedPreferences.getInstance();
    if (voiceId == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, voiceId);
    }
  }

  @visibleForTesting
  static (ReaderTtsVoice, String)? choose(
    List<ReaderTtsVoice> voices,
    String gender,
    String? assignedId, {
    String engine = '',
  }) {
    final local = voices
        .where(
          (v) => v.language.toLowerCase().split(RegExp('[-_]')).first == 'es',
        )
        .toList();
    if (local.isEmpty) return null;
    int rank(ReaderTtsVoice v) =>
        v.language.replaceAll('_', '-').toLowerCase() == 'es-mx' ? 0 : 1;
    local.sort((a, b) {
      final languageOrder = rank(a).compareTo(rank(b));
      return languageOrder == 0 ? a.id.compareTo(b.id) : languageOrder;
    });
    for (final v in local) {
      if (v.id == assignedId) return (v, 'asignada');
    }
    for (final v in local) {
      if (gender != 'system' && v.gender == gender) return (v, 'catalogo');
    }
    // Google languagepack-tts-es-us-108, voice.zvoice/backend_pipeline.textproto.
    // The QA manifest records the speaker labels and the upstream digest.
    const googleUsSpeakers = {
      'es-us-x-esd-local': 'male',
      'es-us-x-esf-local': 'male',
      'es-us-x-esc-local': 'female',
      'es-us-x-sfb-local': 'female',
    };
    if (engine == 'com.google.android.tts') {
      for (final voice in local) {
        if ((voice.gender == null || voice.gender == 'unspecified') &&
            voice.language.toLowerCase() == 'es-us' &&
            googleUsSpeakers[voice.name] == gender) {
          return (voice, 'google_es_us_108');
        }
      }
    }
    return gender == 'system' ? (local.first, 'local_sin_perfil') : null;
  }

  @override
  Future<bool> speak(String text) async {
    final epoch = ++_epoch;
    unavailableNotice = null;
    final profile = gender;
    final explicit = previewId ?? await assignedVoice(profile);
    if (_epoch != epoch) return false;
    final voices = await spanishVoices();
    if (_epoch != epoch) return false;
    final engine = await (_engine ??= _engineId());
    if (_epoch != epoch) return false;
    final selection = choose(voices, profile, explicit, engine: engine);
    if (selection == null) {
      unavailableNotice = 'Selecciona una voz local para este personaje en Ajustes → Voces de los avatares.';
      debugPrint('[VR-NPC] tts no_local_match profile=$profile');
      return false;
    }
    final (voice, source) = selection;
    debugPrint(
      '[VR-NPC] tts profile=$profile source=$source voice=${voice.id} locale=${voice.language}',
    );
    final result = await _speech.speak(
      text,
      voiceId: voice.id,
      language: voice.language,
    );
    return _epoch == epoch && result == ReaderSpeechOutcome.completed;
  }

  @override
  Future<void> stop() async {
    _epoch++;
    await _speech.stop();
  }

  @override
  void dispose() {
    _epoch++;
    unawaited(_speech.dispose());
  }
}
