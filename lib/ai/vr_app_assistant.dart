import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:vrlizate_assistant/vrlizate_assistant.dart';
import 'package:vrlizate_home/vrlizate_home_spatial.dart' as home;
import 'package:vrlizate_scene/vrlizate_scene.dart';

import 'itzli_vr_assistant.dart';
import 'vr_assistant_voice.dart';
import 'vr_itzli_cloud_provider.dart';

/// App-owned coordination: the SDK owns request/capture bounds; Open Neom
/// supplies inference and voice; Home only presents the result.
class VrAppAssistant extends ChangeNotifier with WidgetsBindingObserver {
  VrAppAssistant({VrAssistantProvider? provider, VrAssistantVoice? voice})
    : controller = VrAssistantController(
        provider: provider ?? VrItzliCloudProvider(),
      ),
      voice = voice ?? VrAssistantVoice() {
    controller.addListener(_changed);
    this.voice.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
  }

  final VrAssistantController controller;
  final VrAssistantVoice voice;
  final capture = VrAssistantCaptureController();
  final _guidance = StreamController<home.VrHomeGuidance>.broadcast();
  final _rules = ItzliVrAssistant();
  Map<String, String> _experiences = const {};
  Map<String, Object?> _context = const {};
  String? _message;
  bool _preparing = false;
  bool _disposed = false;
  int _generation = 0;
  int lastImageBytes = 0;
  int lastLatencyMs = 0;
  String? lastAction;

  Stream<home.VrHomeGuidance> get guidance => _guidance.stream;
  bool get busy => _preparing || controller.busy;
  bool get listening => voice.listening;
  String get text =>
      _message ??
      (listening
          ? '${voice.status}\n${voice.transcript}'
          : busy
          ? (lastImageBytes > 0
                ? 'Itzli está analizando tu vista…'
                : 'Itzli está preparando una respuesta…')
          : (voice.status.isNotEmpty
                ? voice.status
                : 'Habla con Itzli, pide ayuda o consulta lo que estás viendo. '
                      'Las consultas de IA usan el servicio de Itzli por Internet. '
                      '«Qué estoy viendo» envía una captura de esta experiencia.'));

  void setExperiences(Map<String, String> experiences) {
    _experiences = Map.unmodifiable(experiences);
  }

  VrAssistantContext context({bool allowActions = true}) => VrAssistantContext(
    experienceId: 'home',
    title: 'Plaza de VRlizate',
    details: {
      ..._context,
      'controls':
          'Stick izquierdo: caminar y girar al mantener el borde; '
          'derecho: Vista o Láser. A: seleccionar; B: cerrar panel o regresar. '
          'Las experiencias tienen sus propios controles.',
      'experiences': [
        for (final e in _experiences.entries) {'id': e.key, 'title': e.value},
      ],
    },
    allowedActions: allowActions
        ? const {
            'launchExperience',
            'jumpToWing',
            'changeLook',
            'changeResolution',
            'recenter',
          }
        : const {},
  );

  Future<void> dispatch(
    String action,
    Map<String, Object?> spatialContext,
  ) async {
    if (_disposed) return;
    _context = Map.unmodifiable(spatialContext);
    if (action == 'cancel') {
      cancel();
      return;
    }
    if (action == 'listen') {
      final generation = _generation;
      if (listening) {
        final phrase = voice.transcript.trim();
        await voice.stopListening();
        if (_disposed || generation != _generation) return;
        if (phrase.isNotEmpty) {
          unawaited(ask(phrase));
        } else {
          _message =
              'No escuché una frase. Pulsa Hablar para intentarlo de nuevo.';
          _changed();
        }
        return;
      }
      if (busy) return;
      _message = null;
      await voice.startListening(
        onFinal: (phrase) {
          if (!_disposed && generation == _generation) {
            unawaited(ask(phrase));
          }
        },
      );
      if (_disposed || generation != _generation) return;
      if (!listening && !busy) _message = voice.status;
      _changed();
      return;
    }
    if (busy || listening) return;
    if (action == 'vision') {
      // Home hides its assistant panel only until this local capture completes.
      final generation = _generation;
      _preparing = true;
      lastImageBytes = 0;
      _changed();
      Uint8List? bytes;
      try {
        bytes = await capture.capture().timeout(const Duration(seconds: 3));
      } catch (_) {
        /* Report a stable UI message below. */
      }
      _preparing = false;
      if (_disposed || generation != _generation) return;
      if (bytes == null) {
        _message =
            'No pude capturar la experiencia. Regresa al Home e inténtalo otra vez.';
        _changed();
        return;
      }
      unawaited(
        ask(
          '¿Qué estoy viendo y qué puedo hacer aquí?',
          image: bytes,
          allowActions: false,
          useRules: false,
        ),
      );
    } else if (action == 'help') {
      unawaited(
        ask(
          'Ayúdame a usar esta sala. Explica brevemente cómo recorrerla '
          'y seleccionar una experiencia con mi mando.',
          allowActions: false,
          useRules: false,
        ),
      );
    }
  }

  Future<VrAssistantReply?> ask(
    String phrase, {
    Uint8List? image,
    bool includeImage = false,
    bool allowActions = true,
    bool useRules = true,
  }) async {
    if (_disposed || busy || phrase.trim().isEmpty) return null;
    final generation = _generation;
    _preparing = true;
    await voice.cancel();
    _preparing = false;
    if (_disposed || generation != _generation) return null;
    _message = null;
    lastAction = null;
    lastImageBytes = image?.length ?? 0;
    final watch = Stopwatch()..start();
    if (useRules && allowActions && image == null && !includeImage) {
      final rule = _rules.interpretRequest(phrase);
      final reply = _ruleReply(rule);
      if (reply != null && _decodeAction(reply) != null) {
        lastLatencyMs = watch.elapsedMilliseconds;
        _accept(reply);
        return reply;
      }
    }
    final reply = await controller.ask(
      phrase,
      context: context(allowActions: allowActions),
      includeImage: includeImage || image != null,
      capture: image != null
          ? () async => image
          : () async {
              final result = await capture.capture();
              lastImageBytes = result?.length ?? 0;
              return result;
            },
    );
    lastLatencyMs = watch.elapsedMilliseconds;
    if (_disposed || generation != _generation || reply == null) return null;
    _accept(reply, allowActions: allowActions);
    return reply;
  }

  void _accept(VrAssistantReply reply, {bool allowActions = true}) {
    _message = reply.text;
    if (!reply.isError && allowActions && reply.action != null) {
      final action = _decodeAction(reply);
      if (action != null) {
        lastAction = reply.action;
        _guidance.add(action);
      } else {
        _message =
            'No ejecuté esa acción porque no corresponde a una opción disponible.';
      }
    }
    _changed();
    if (!reply.isError) unawaited(voice.speak(_message!));
  }

  home.VrHomeGuidance? _decodeAction(VrAssistantReply reply) {
    if (reply.isError) return null;
    final id = reply.arguments['id'];
    if (reply.arguments.keys.any((key) => key != 'id')) return null;
    switch (reply.action) {
      case 'launchExperience':
        if (id is! String || !_experiences.containsKey(id)) return null;
        return home.VrHomeGuidance(
          actionType: home.VrHomeActionType.launchExperience,
          speechResponse: reply.text,
          targetDemoId: id,
          targetDemoTitle: _experiences[id],
        );
      case 'jumpToWing':
        if (!const {
          'north_games',
          'east_prod',
          'west_media',
          'south_labs',
          'center',
        }.contains(id)) {
          return null;
        }
        return home.VrHomeGuidance(
          actionType: home.VrHomeActionType.jumpToWing,
          speechResponse: reply.text,
          targetWingId: id as String,
        );
      case 'changeLook':
        final look = {
          'natural': VrLook.standard,
          'cyberpunk': VrLook.cyberpunk,
          'stellar': VrLook.stellar,
          'cinematic': VrLook.cinematic,
          'night': VrLook.night,
        }[id];
        if (look == null) return null;
        return home.VrHomeGuidance(
          actionType: home.VrHomeActionType.changeLook,
          speechResponse: reply.text,
          targetLook: look,
        );
      case 'changeResolution':
        final quality = const {
          'low': VrQualityPreset.low,
          'medium': VrQualityPreset.medium,
          'high': VrQualityPreset.high,
        }[id];
        if (quality == null) return null;
        return home.VrHomeGuidance(
          actionType: home.VrHomeActionType.changeResolution,
          speechResponse: reply.text,
          targetPreset: quality,
        );
      case 'recenter':
        if (reply.arguments.isNotEmpty) return null;
        return home.VrHomeGuidance(
          actionType: home.VrHomeActionType.recenter,
          speechResponse: reply.text,
        );
    }
    return null;
  }

  static VrAssistantReply? _ruleReply(ItzliVrGuidance g) {
    final (action, id) = switch (g.actionType) {
      ItzliActionType.launchExperience => ('launchExperience', g.targetDemoId),
      ItzliActionType.jumpToWing => ('jumpToWing', g.targetWingId),
      ItzliActionType.recenter => ('recenter', null),
      ItzliActionType.changeLook => (
        'changeLook',
        g.targetLook == VrLook.cyberpunk
            ? 'cyberpunk'
            : g.targetLook == VrLook.cinematic
            ? 'cinematic'
            : g.targetLook == VrLook.stellar
            ? 'stellar'
            : g.targetLook == VrLook.night
            ? 'night'
            : 'natural',
      ),
      _ => (null, null),
    };
    return action == null
        ? null
        : VrAssistantReply(
            text: g.speechResponse,
            action: action,
            arguments: {if (id != null) 'id': id},
          );
  }

  void cancel() {
    if (_disposed) return;
    _generation++;
    controller.cancel();
    unawaited(voice.cancel());
    _message = 'Asistente pausado.';
    _changed();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      cancel();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_changed);
    voice.removeListener(_changed);
    controller.dispose();
    voice.dispose();
    capture.dispose();
    _guidance.close();
    super.dispose();
  }
}

class VrAssistantScope extends InheritedWidget {
  const VrAssistantScope({
    super.key,
    required this.assistant,
    required super.child,
  });
  final VrAppAssistant assistant;
  static VrAppAssistant? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<VrAssistantScope>()?.assistant;
  @override
  bool updateShouldNotify(VrAssistantScope oldWidget) =>
      assistant != oldWidget.assistant;
}
