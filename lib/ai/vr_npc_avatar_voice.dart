import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:neom_tts/reader_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vrlizate_assistant/vrlizate_assistant.dart';

export 'package:neom_tts/reader_tts.dart' show ReaderTtsVoice;

/// Adapts brand tokens and VR acronyms for natural Spanish TTS playback without
/// changing visible UI or spatial speech-bubble copy.
String normalizeVrTtsPronunciation(String text) {
  if (text.isEmpty) return text;
  return text
      .replaceAllMapped(
        RegExp(r'\bVRlizate\b', caseSensitive: false),
        (_) => 'Vi Ar Lizate',
      )
      .replaceAllMapped(
        RegExp(r'(?<![A-Za-zÁÉÍÓÚÜÑáéíóúüñ0-9])VR(?![A-Za-zÁÉÍÓÚÜÑáéíóúüñ0-9])'),
        (_) => 'Vi Ar',
      );
}

/// Native voices only. The local reader verifies installation and re-selects
/// the exact voice before each line, including after an avatar change.
class NeomNpcAvatarSpeechOutput implements VrAssistantSpeechOutput {
  NeomNpcAvatarSpeechOutput({ReaderTtsService? nativeSpeech})
    : _speech = nativeSpeech ?? createLocalReaderTtsService();
  final ReaderTtsService _speech;
  int _epoch = 0;
  String gender = 'system';
  String? speakerKey;
  String? previewId;
  String? unavailableNotice;
  Future<String>? _engine;

  static int _stableSpeakerHash(String key) {
    var hash = 0x811c9dc5;
    for (final unit in key.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  /// Subtle, human-range pitch & speech-rate differentiation per NPC so nearby
  /// characters never sound like the exact same person even on devices with a
  /// small set of installed Spanish local speakers.
  @visibleForTesting
  static ({double pitch, double rate}) vocalProfileForSpeaker(
    String? speakerKey,
  ) {
    final clean = speakerKey?.trim();
    if (clean == null || clean.isEmpty) {
      return (pitch: 1.0, rate: 1.0);
    }
    const pitches = <double>[1.00, 0.93, 1.07, 0.96, 1.04, 0.90];
    const rates = <double>[1.00, 1.04, 0.96, 1.02, 0.98];
    final h = _stableSpeakerHash(clean);
    return (
      pitch: pitches[h % pitches.length],
      rate: rates[(h ~/ pitches.length) % rates.length],
    );
  }

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
    String? speakerKey,
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

    ReaderTtsVoice pickForSpeaker(List<ReaderTtsVoice> pool) {
      final clean = speakerKey?.trim();
      if (clean == null || clean.isEmpty || pool.length <= 1) {
        return pool.first;
      }
      return pool[_stableSpeakerHash(clean) % pool.length];
    }

    if (gender != 'system') {
      final catalogMatches = local
          .where((v) => v.gender == gender)
          .toList(growable: false);
      if (catalogMatches.isNotEmpty) {
        return (pickForSpeaker(catalogMatches), 'catalogo');
      }
    }
    // Google languagepack-tts-es-us-108 & es-es local speaker packs.
    // The QA manifest records the speaker labels and the upstream digest.
    const googleUsSpeakers = {
      'es-us-x-esd-local': 'male',
      'es-us-x-esf-local': 'male',
      'es-us-x-esc-local': 'female',
      'es-us-x-sfb-local': 'female',
    };
    const googleEsSpeakers = {
      'es-es-x-eef-local': 'male',
      'es-es-x-eed-local': 'male',
      'es-es-x-eee-local': 'female',
      'es-es-x-eec-local': 'female',
    };
    if (engine == 'com.google.android.tts' && gender != 'system') {
      final googleMatches = <ReaderTtsVoice>[
        for (final voice in local)
          if ((voice.gender == null || voice.gender == 'unspecified') &&
              ((voice.language.toLowerCase() == 'es-us' &&
                      googleUsSpeakers[voice.name] == gender) ||
                  (voice.language.toLowerCase() == 'es-es' &&
                      googleEsSpeakers[voice.name] == gender)))
            voice,
      ];
      if (googleMatches.isNotEmpty) {
        return (pickForSpeaker(googleMatches), 'google_es_us_108');
      }
    }
    return gender == 'system'
        ? (pickForSpeaker(local), 'local_sin_perfil')
        : null;
  }

  @override
  Future<bool> speak(String text) async {
    final epoch = ++_epoch;
    unavailableNotice = null;
    final profile = gender;
    final speaker = speakerKey;
    final explicit = previewId ?? await assignedVoice(profile);
    if (_epoch != epoch) return false;
    final voices = await spanishVoices();
    if (_epoch != epoch) return false;
    final engine = await (_engine ??= _engineId());
    if (_epoch != epoch) return false;
    final selection = choose(
      voices,
      profile,
      explicit,
      engine: engine,
      speakerKey: explicit == null ? speaker : null,
    );
    if (selection == null) {
      unavailableNotice =
          'Selecciona una voz local para este personaje en Ajustes → Voces de los avatares.';
      debugPrint('[VR-NPC] tts no_local_match profile=$profile');
      return false;
    }
    final (voice, source) = selection;
    final vocal = vocalProfileForSpeaker(speaker);
    final spokenText = normalizeVrTtsPronunciation(text);
    debugPrint(
      '[VR-NPC] tts profile=$profile speaker=${speaker ?? '-'} source=$source '
      'voice=${voice.id} locale=${voice.language} '
      'pitch=${vocal.pitch.toStringAsFixed(2)} rate=${vocal.rate.toStringAsFixed(2)}',
    );
    final result = await _speech.speak(
      spokenText,
      voiceId: voice.id,
      language: voice.language,
      rate: vocal.rate,
      pitch: vocal.pitch,
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
