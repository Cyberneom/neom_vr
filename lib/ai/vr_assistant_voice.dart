import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:neom_tts/data/providers/flutter_tts_provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Stable failure categories; native messages are never displayed verbatim.
enum VrAssistantSpeechFailure {
  noSpeech,
  permission,
  language,
  network,
  busy,
  unavailable,
  unknown;

  static VrAssistantSpeechFailure fromPlatformCode(
    String code,
  ) => switch (code) {
    'error_no_match' || 'error_speech_timeout' => noSpeech,
    'error_permission' || 'error_insufficient_permissions' => permission,
    'error_language_not_supported' || 'error_language_unavailable' => language,
    'error_network' ||
    'error_network_timeout' ||
    'error_server' ||
    'error_server_disconnected' => network,
    'error_busy' ||
    'error_recognizer_busy' ||
    'error_too_many_requests' => busy,
    'error_recognizer_not_available' || 'recognizerNotAvailable' => unavailable,
    _ => unknown,
  };

  String get message => switch (this) {
    noSpeech => 'No escuché una frase. Pulsa Hablar e inténtalo de nuevo.',
    permission =>
      'El micrófono no tiene permiso. Actívalo en los ajustes de la app.',
    language =>
      'El idioma de reconocimiento no está disponible. Instala o activa español en el teléfono.',
    network =>
      'No pude conectar con el reconocimiento de voz. Revisa tu conexión e inténtalo de nuevo.',
    busy =>
      'El reconocimiento de voz está ocupado. Espera un momento e inténtalo de nuevo.',
    unavailable =>
      'El reconocimiento de voz no está disponible en este teléfono.',
    unknown =>
      'No pude completar el reconocimiento de voz. Inténtalo de nuevo.',
  };
}

/// Injectable speech boundary; the default uses the device speech recognizer.
abstract class VrAssistantSpeechInput {
  Future<bool> initialize();
  Future<List<String>> locales();
  Future<void> start({
    required void Function(String text, bool isFinal) onResult,
    required void Function(VrAssistantSpeechFailure) onError,
    required VoidCallback onDone,
    required Duration timeout,
    String? localeId,
  });
  Future<void> cancel();
}

abstract class VrAssistantSpeechOutput {
  Future<bool> speak(String text);
  Future<void> stop();
  void dispose();
}

/// One user-initiated listening turn at a time; never starts a wake-word loop.
class VrAssistantVoice extends ChangeNotifier {
  VrAssistantVoice({
    VrAssistantSpeechInput? input,
    VrAssistantSpeechOutput? output,
    Duration listenTimeout = const Duration(seconds: 20),
  }) : _input = input ?? _DeviceSpeechInput(),
       _output = output ?? _DeviceSpeechOutput(),
       _listenTimeout = listenTimeout > const Duration(seconds: 20)
           ? const Duration(seconds: 20)
           : listenTimeout > Duration.zero
           ? listenTimeout
           : const Duration(seconds: 20);

  final VrAssistantSpeechInput _input;
  final VrAssistantSpeechOutput _output;
  final Duration _listenTimeout;
  Timer? _deadline;
  Timer? _finalResultWait;
  int _generation = 0;
  bool _disposed = false;
  bool _listening = false;
  String _status = '';
  String _transcript = '';

  bool get listening => _listening;
  String get status => _status;
  String get transcript => _transcript;

  Future<bool> startListening({required void Function(String) onFinal}) async {
    if (_disposed) return false;
    final generation = ++_generation;
    _deadline?.cancel();
    _finalResultWait?.cancel();
    _finalResultWait = null;
    _listening = false;
    _transcript = '';
    _status = 'Preparando micrófono…';
    notifyListeners();
    try {
      await _stopDevices(generation);
      if (!_isCurrent(generation)) return false;
      // Initial permission dialogs need user time. This setup allowance is
      // separate from the maximum 20 seconds of actual listening below.
      final available = await _input.initialize().timeout(
        const Duration(seconds: 30),
      );
      if (!_isCurrent(generation)) return false;
      if (!available) {
        _finish(generation, 'Micrófono o reconocimiento de voz no disponible.');
        return false;
      }
      final locales = await _input.locales().timeout(
        const Duration(seconds: 3),
      );
      if (!_isCurrent(generation)) return false;
      _listening = true;
      _status = 'Escuchando…';
      notifyListeners();
      _deadline = Timer(_listenTimeout, () {
        _finish(
          generation,
          'Tiempo de escucha terminado. Vuelve a intentarlo.',
        );
      });
      await _input.start(
        localeId: _spanishLocale(locales),
        timeout: _listenTimeout,
        onResult: (text, isFinal) {
          if (!_isCurrent(generation) || !_listening) return;
          final trimmed = text.trim();
          _transcript = trimmed.length <= 2000
              ? trimmed
              : trimmed.substring(0, 2000);
          if (!isFinal) {
            notifyListeners();
            return;
          }
          final finalText = _transcript;
          _finish(
            generation,
            finalText.isEmpty
                ? 'No escuché una frase. Inténtalo de nuevo.'
                : '',
          );
          if (!_disposed &&
              _generation == generation + 1 &&
              finalText.isNotEmpty) {
            onFinal(finalText);
          }
        },
        onError: (failure) => _finish(generation, failure.message),
        onDone: () {
          if (!_isCurrent(generation) || !_listening) return;
          // Android can report done before onResults (or after an intermediate
          // result). Do not cancel recognition while its final result is still
          // arriving. The original 20-second deadline remains in force.
          _status = 'Terminando reconocimiento…';
          _finalResultWait ??= Timer(const Duration(milliseconds: 2500), () {
            _finish(
              generation,
              'No escuché una frase completa. Inténtalo de nuevo.',
            );
          });
          notifyListeners();
        },
      );
      return _isCurrent(generation) && _listening;
    } catch (_) {
      _finish(generation, 'No pude iniciar el reconocimiento de voz.');
      return false;
    }
  }

  /// Stops listening and discards unfinished recognition results.
  Future<void> stopListening() async {
    if (_disposed) return;
    ++_generation;
    _deadline?.cancel();
    _finalResultWait?.cancel();
    _finalResultWait = null;
    _listening = false;
    _status = '';
    notifyListeners();
    await _quiet(_input.cancel);
  }

  Future<void> speak(String text) async {
    if (_disposed || text.trim().isEmpty) return;
    final generation = ++_generation;
    _deadline?.cancel();
    _finalResultWait?.cancel();
    _finalResultWait = null;
    _listening = false;
    _status = 'Respondiendo…';
    notifyListeners();
    try {
      await _stopDevices(generation);
      if (!_isCurrent(generation)) return;
      final spoken = text.trim();
      final success = await _output
          .speak(spoken.length <= 2000 ? spoken : spoken.substring(0, 2000))
          .timeout(const Duration(seconds: 90));
      if (!_isCurrent(generation)) return;
      _status = success ? '' : 'No pude reproducir la respuesta de voz.';
      notifyListeners();
    } catch (_) {
      if (!_isCurrent(generation)) return;
      await _quiet(_output.stop);
      if (!_isCurrent(generation)) return;
      _status = 'No pude reproducir la respuesta de voz.';
      notifyListeners();
    }
  }

  Future<void> cancel() async {
    if (_disposed) return;
    final generation = ++_generation;
    _deadline?.cancel();
    _finalResultWait?.cancel();
    _finalResultWait = null;
    _listening = false;
    _status = '';
    notifyListeners();
    await _stopDevices(generation);
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _finish(int generation, String status) {
    if (!_isCurrent(generation)) return;
    ++_generation;
    _deadline?.cancel();
    _finalResultWait?.cancel();
    _finalResultWait = null;
    _listening = false;
    _status = status;
    unawaited(_quiet(_input.cancel));
    notifyListeners();
  }

  Future<void> _stopDevices(int generation) async {
    await _quiet(_input.cancel);
    if (!_isCurrent(generation)) return;
    await _quiet(_output.stop);
  }

  static Future<void> _quiet(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (_) {
      // Platform errors are intentionally not exposed in the UI.
    }
  }

  static String? _spanishLocale(List<String> locales) {
    for (final locale in locales) {
      if (locale.replaceAll('-', '_').toLowerCase() == 'es_mx') return locale;
    }
    for (final locale in locales) {
      if (locale.toLowerCase().startsWith('es')) return locale;
    }
    return null; // Use the device default when no Spanish recognizer exists.
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    _deadline?.cancel();
    _finalResultWait?.cancel();
    _finalResultWait = null;
    _listening = false;
    unawaited(_quiet(_input.cancel));
    unawaited(_quiet(_output.stop));
    _output.dispose();
    super.dispose();
  }
}

class _DeviceSpeechInput implements VrAssistantSpeechInput {
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
  Future<List<String>> locales() async =>
      (await _speech.locales()).map((locale) => locale.localeId).toList();

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
    await _speech.listen(
      onResult: (result) =>
          onResult(result.recognizedWords, result.finalResult),
      listenOptions: stt.SpeechListenOptions(
        localeId: localeId,
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

class _DeviceSpeechOutput implements VrAssistantSpeechOutput {
  final FlutterTtsProvider _provider = FlutterTtsProvider();

  @override
  Future<bool> speak(String text) =>
      _provider.speakWithCompletion(text, language: 'es-MX');

  @override
  Future<void> stop() => _provider.stop();

  @override
  void dispose() => _provider.dispose();
}
