import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:neom_tts/data/providers/flutter_tts_provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:vrlizate_assistant/vrlizate_assistant.dart';

export 'vr_npc_avatar_voice.dart';

export 'package:vrlizate_assistant/vrlizate_assistant.dart'
    show
        VrAssistantSpeechFailure,
        VrAssistantSpeechInput,
        VrAssistantSpeechOutput,
        VrAssistantVoice;

/// Registers Open Neom's `speech_to_text` + `neom_tts` adapters as the default
/// factories for [VrAssistantVoice] when `neom_vr` is active.
void registerNeomVrSpeechDefaults() {
  VrAssistantVoice.defaultInputFactory ??= NeomDeviceSpeechInput.new;
  VrAssistantVoice.defaultOutputFactory ??= NeomTtsSpeechOutput.new;
}

/// Device speech recognizer implementation backed by `speech_to_text`.
class NeomDeviceSpeechInput implements VrAssistantSpeechInput {
  NeomDeviceSpeechInput({this.onDevice = false});

  final bool onDevice;
  final stt.SpeechToText _speech = stt.SpeechToText();
  void Function(VrAssistantSpeechFailure)? _onError;
  VoidCallback? _onDone;

  @override
  Future<bool> initialize() => _speech.initialize(
    onError: (error) => _onError?.call(
      VrAssistantSpeechFailure.fromPlatformCode(error.errorMsg),
    ),
    onStatus: (status) {
      if (status == stt.SpeechToText.doneStatus) _onDone?.call();
    },
  );

  @override
  Future<List<String>> locales() async {
    if (onDevice && defaultTargetPlatform == TargetPlatform.android) {
      List<String>? installed;
      try {
        installed = await const MethodChannel('vrlizate/device_capabilities')
            .invokeListMethod<String>('installedSpeechLocales');
      } on MissingPluginException {
        // Older hosts can still use their device's current Spanish locale.
      } on PlatformException {
        // Some recognizers decline capability queries.
      }
      final current = PlatformDispatcher.instance.locale;
      if (installed != null) {
        final spanish = installed.where((s) => s.split(RegExp('[-_]')).first.toLowerCase() == 'es').toList();
        if (spanish.isNotEmpty) {
          final preferred = spanish.where((s) => s.replaceAll('_','-').toLowerCase() == current.toLanguageTag().toLowerCase());
          return preferred.isEmpty ? spanish : [preferred.first];
        }
      } else if (current.languageCode.toLowerCase() == 'es') {
        return [current.toLanguageTag()];
      }
    }
    return (await _speech.locales()).map((locale) => locale.localeId).toList();
  }

  @override
  Future<void> start({
    required void Function(String text, bool isFinal) onResult,
    required void Function(VrAssistantSpeechFailure) onError,
    required VoidCallback onDone,
    required Duration timeout,
    String? localeId,
  }) async {
    _onError = onError;
    _onDone = onDone;
    if (onDevice) debugPrint('[VR-NPC] stt locale=${localeId ?? 'system'} onDevice=true');
    await _speech.listen(
      onResult: (result) =>
          onResult(result.recognizedWords, result.finalResult),
      listenOptions: stt.SpeechListenOptions(
        localeId: localeId,
        onDevice: onDevice,
        listenFor: timeout,
        pauseFor: const Duration(seconds: 4),
        partialResults: true,
        cancelOnError: true,
        listenMode: stt.ListenMode.confirmation,
      ),
    );
  }

  @override
  Future<void> cancel() async {
    _onError = null;
    _onDone = null;
    await _speech.cancel();
  }
}

/// Text-to-speech output implementation backed by Open Neom `neom_tts`.
class NeomTtsSpeechOutput implements VrAssistantSpeechOutput {
  final FlutterTtsProvider _provider = FlutterTtsProvider();

  /// Initializes the device synthesizer without opening the microphone or playing audio.
  Future<void> prepare() => _provider.initialize();

  @override
  Future<bool> speak(String text) =>
      _provider.speakWithCompletion(text, language: 'es-MX');

  @override
  Future<void> stop() => _provider.stop();

  @override
  void dispose() => _provider.dispose();
}
