import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:neom_ia/neom_ia.dart';
import 'package:neom_ollama/neom_ollama.dart';
import 'package:path_provider/path_provider.dart';
import 'package:saia_core/saia_core.dart';
import 'package:saia_gguf/saia_gguf.dart';
import 'package:vrlizate_assistant/vrlizate_assistant.dart';
import 'package:vrlizate_joystick/vrlizate_joystick.dart';
import 'package:vrlizate_tracking/vrlizate_tracking.dart';

/// Active device topology selected for embedded SAIA inference without cloud Itzli.
enum VrEmbeddedAiTopology {
  /// `1D` — Single smartphone (Handheld Console or standalone Visor) running
  /// embedded SAIA (`saia_gguf` when RAM/thermals sustain it, or local SAIA micro).
  oneDeviceSmartphone,

  /// `2D` — Visor smartphone offloading embedded SAIA inference to the paired
  /// secondary Joystick/Support smartphone over `VrControllerLink`.
  twoDevicesCompanionPhone,

  /// `3D` — Visor + Joystick offloading embedded SAIA inference to the paired
  /// personal computer acting as **Estación Faro** (`neom_ollama` / `saia_gguf`).
  threeDevicesFaro;

  String get badgeEs => switch (this) {
    VrEmbeddedAiTopology.oneDeviceSmartphone => '1D · IA EMBEBIDA SMARTPHONE',
    VrEmbeddedAiTopology.twoDevicesCompanionPhone => '2D · IA EN MANDO APOYO',
    VrEmbeddedAiTopology.threeDevicesFaro => '3D · IA EN ESTACIÓN FARO',
  };
}

/// Zero-RAM, 100% offline deterministic Spanish `IaService` built on
/// `neom_ia` + `saia_core` contracts for devices without downloaded `.gguf`
/// weights or modest smartphones (`< 4–6 GB RAM`) that should preserve 100% of
/// memory for 60–120 Hz VR rendering.
class SaiaContextualMicroIaService implements IaService {
  final List<IaChatMessage> _history = <IaChatMessage>[];
  bool _ready = false;

  /// Exposed `saia_core` descriptor identifying this embedded fallback spirit.
  static const SaiaSpirit embeddedSpirit = SaiaSpirit(
    userId: 'saia_vr_embedded_micro',
    ownerName: 'SAIA Embebida VR',
    tierLevel: 2,
    tstLevel: 3,
    isRecognized: true,
  );

  @override
  Future<void> initialize() async {
    _ready = true;
  }

  @override
  bool get isReady => _ready;

  @override
  List<IaChatMessage> get chatHistory => List.unmodifiable(_history);

  @override
  void clearHistory() => _history.clear();

  @override
  void rebuildHistory(List<IaChatMessage> messagesToKeep) {
    _history
      ..clear()
      ..addAll(messagesToKeep);
  }

  @override
  void dispose() {
    _ready = false;
    _history.clear();
  }

  @override
  Future<IaChatMessage> sendMessage(String message) async {
    final text = await generateContent(message) ?? '';
    final reply = IaChatMessage.agent(text);
    _history.add(reply);
    return reply;
  }

  @override
  Stream<String> sendMessageStream(String message) async* {
    final msg = await sendMessage(message);
    yield msg.text;
  }

  @override
  Future<IaChatMessage> sendMessageWithMedia(
    String message,
    List<IaAttachment> attachments,
  ) => sendMessage(message);

  @override
  Stream<String> sendMessageStreamWithMedia(
    String message,
    List<IaAttachment> attachments,
  ) => sendMessageStream(message);

  @override
  Future<String?> generateStructuredContent(
    String prompt,
    Map<String, dynamic> jsonSchema,
  ) async {
    final text = await generateContent(prompt) ?? '';
    return jsonEncode(<String, Object?>{
      'text': text,
      'action': null,
      'arguments': const <String, Object?>{},
    });
  }

  @override
  Stream<String> generateContentStream(String prompt) async* {
    final out = await generateContent(prompt);
    if (out != null) yield out;
  }

  @override
  Future<String?> generateContent(String prompt) async {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty) return null;

    // Inspect optional JSON context if wrapped by VrEmbeddedSaiaProvider.
    Map<String, dynamic>? ctx;
    final jsonIdx = trimmed.lastIndexOf('{"experienceId":');
    if (jsonIdx >= 0) {
      try {
        final decoded = jsonDecode(trimmed.substring(jsonIdx));
        if (decoded is Map<String, dynamic>) ctx = decoded;
      } catch (_) {}
    }

    final details = ctx?['details'] is Map
        ? Map<String, dynamic>.from(ctx!['details'] as Map)
        : const <String, dynamic>{};
    final npc = details['npc'] is Map
        ? Map<String, dynamic>.from(details['npc'] as Map)
        : null;
    final plaza = (details['plaza'] as String?) ??
        (ctx?['title'] as String?) ??
        'esta plaza VR';
    final userReq = ((ctx?['userRequest'] as String?) ?? trimmed).toLowerCase();

    final expTitles = <String>[];
    final exps = details['experiences'];
    if (exps is List) {
      for (final item in exps.take(4)) {
        if (item is Map && item['title'] is String) {
          expTitles.add(item['title'] as String);
        }
      }
    }

    if (npc != null) {
      final name = (npc['name'] as String?) ?? 'Visitante';
      final role = (npc['role'] as String?) ?? 'Explorador VR';
      final nearest = npc['nearestRoom'] as String?;
      final pickA = expTitles.isNotEmpty
          ? '«${expTitles.first}»'
          : (nearest != null ? '«$nearest»' : 'la galería central');
      final pickB = expTitles.length > 1 ? ' o «${expTitles[1]}»' : '';

      if (userReq.contains('recomi') || userReq.contains('sugier')) {
        return 'Soy $name ($role). Desde aquí te recomiendo entrar a '
            '$pickA$pickB: corren súper fluidos y aprovechan el audio espacial.';
      }
      if (userReq.contains('lugar') || userReq.contains('especial')) {
        return 'Estás en $plaza'
            '${nearest != null ? ", justo cerca de «$nearest»" : ""}. '
            'Toda la conversación corre con IA local SAIA sin depender de la nube.';
      }
      if (userReq.contains('sorpr') ||
          userReq.contains('curios') ||
          userReq.contains('consejo')) {
        return 'Dato de ${role.toLowerCase()}: en 1D la IA vive en tu teléfono, '
            'en 2D se apoya en el segundo smartphone mando y en 3D corre directo en tu Estación Faro.';
      }
      return '¡Hola! Soy $name, ${role.toLowerCase()} en $plaza'
          '${nearest != null ? " admirando «$nearest»" : ""}. '
          'Pregúntame por salas cercanas o pulsa «Leer en voz (TTS)» si prefieres escucharme.';
    }

    final pick = expTitles.isNotEmpty ? '«${expTitles.first}»' : 'las salas 3D';
    return 'SAIA local lista en $plaza. Usa el stick izquierdo para caminar, '
        'la cruceta en el borde para navegar menús y el botón A para abrir $pick.';
  }
}

/// Hardware-aware local model & inference manager coordinating **`saia_gguf`**
/// (`fllama` / `llama.cpp` GGUF), **`neom_ollama`** + **`neom_ia`**
/// (`HttpLlmIaService`), and **`SaiaContextualMicroIaService`** across
/// Smartphone (`1D`), Companion Joystick (`2D`), and Desktop Faro (`3D`).
class VrEmbeddedSaiaRuntime {
  VrEmbeddedSaiaRuntime({
    this.ramMbProbe,
    this.thermalLevelProbe,
    this.extraModelDirectories,
    IaService? injectedLocalService,
    String? injectedEngineLabel,
  }) : _cachedLocalService = injectedLocalService,
       _cachedEngineLabel = injectedEngineLabel;

  static final VrEmbeddedSaiaRuntime instance = VrEmbeddedSaiaRuntime();

  static const Set<String> _embeddingArchitectures = <String>{
    'bert',
    'nomic-bert',
    'jina-bert-v2',
    'xlm-roberta',
    'bge',
  };

  /// Minimum smartphone RAM (`5.5 GB`) to run in-process GGUF weights alongside
  /// an active stereoscopic 3D Impeller scene (`1D`).
  static const int minVisorSmartphoneGgufRamMb = 5500;

  /// Minimum secondary smartphone RAM (`3.8 GB`) to sustain GGUF weights when
  /// acting solely as a `2D` Joystick / AI Support Co-Processor.
  static const int minCompanionPhoneGgufRamMb = 3800;

  final int Function()? ramMbProbe;
  final int Function()? thermalLevelProbe;
  final List<String> Function()? extraModelDirectories;

  IaService? _cachedLocalService;
  String? _cachedEngineLabel;
  bool? _cachedIsDesktopRole;
  bool? _cachedIsVisorRole;
  DateTime? _lastOllamaProbeAt;

  int detectRamMb() {
    if (ramMbProbe != null) return ramMbProbe!();
    if (kIsWeb) return 4096;
    try {
      final hw = GgufHardwareProfile.detect();
      if (hw.totalRamBytes > 0) {
        return (hw.totalRamBytes / (1024 * 1024)).round();
      }
    } catch (_) {}
    final capRam = VrDeviceProfiler.capabilities?.totalRamMb ?? 0;
    return capRam > 0 ? capRam : 4096;
  }

  int detectThermalLevel() {
    if (thermalLevelProbe != null) return thermalLevelProbe!();
    return VrDeviceProfiler.readThermalStatusSync() ?? 0;
  }

  /// Evaluates whether a smartphone can sustain embedded GGUF LLM inference.
  bool canSmartphoneSustainGguf({required bool isActiveVrVisor}) {
    if (kIsWeb) return false;
    final thermal = detectThermalLevel();
    if (thermal >= 2) return false;
    final ramMb = detectRamMb();
    final minRequired = isActiveVrVisor
        ? minVisorSmartphoneGgufRamMb
        : minCompanionPhoneGgufRamMb;
    return ramMb >= minRequired;
  }

  /// Strips `<think>...</think>` blocks (emitted by DeepSeek-R1-Distill
  /// `itzli-fugaz`) and Markdown code fences from local SLM outputs.
  static String cleanSlmOutput(String raw) {
    var cleaned = raw
        .replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '')
        .trim();
    if (cleaned.contains('<think>')) {
      cleaned = cleaned.split('<think>').first.trim();
    }
    if (cleaned.startsWith('```')) {
      cleaned = cleaned
          .replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), '')
          .trim();
    }
    return cleaned;
  }

  Future<List<Directory>> _candidateModelDirectories() async {
    final dirs = <Directory>[];
    final extra = extraModelDirectories?.call() ?? const <String>[];
    for (final path in extra) {
      if (path.trim().isNotEmpty) dirs.add(Directory(path.trim()));
    }
    if (kIsWeb) return dirs;

    final envDir = Platform.environment['SAIA_MODELS_DIR'] ??
        Platform.environment['ITZLI_MODELS_DIR'];
    if (envDir != null && envDir.trim().isNotEmpty) {
      dirs.add(Directory(envDir.trim()));
    }

    if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      final home = Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'] ??
          '';
      if (home.isNotEmpty) {
        dirs.addAll([
          Directory('$home/.saia/models'),
          Directory('$home/.itzli/models'),
          Directory('$home/Library/Application Support/saia/models'),
          Directory('$home/Library/Application Support/itzli/models'),
        ]);
      }
    }

    try {
      final docDir = await getApplicationDocumentsDirectory();
      dirs.add(Directory('${docDir.path}/saia_edge_models'));
      dirs.add(Directory('${docDir.path}/models'));
    } catch (_) {}
    return dirs;
  }

  /// Selects the best causal chat `.gguf` file on disk that fits [ramMb],
  /// skipping embedding-only models (`nomic-bert` / `bert`).
  Future<({String path, String label})?> findBestLocalGgufModel({
    required int ramMb,
    required bool isActiveVrVisor,
    required bool isDesktopFaro,
  }) async {
    if (kIsWeb) return null;
    const definedPath = String.fromEnvironment('VRLIZATE_GGUF_MODEL_PATH');
    final candidates = <File>[];
    if (definedPath.isNotEmpty && File(definedPath).existsSync()) {
      candidates.add(File(definedPath));
    }
    for (final dir in await _candidateModelDirectories()) {
      if (!dir.existsSync()) continue;
      try {
        for (final entity in dir.listSync(followLinks: false)) {
          if (entity is File && entity.path.toLowerCase().endsWith('.gguf')) {
            candidates.add(entity);
          }
        }
      } catch (_) {}
    }
    if (candidates.isEmpty) return null;

    // Max model file budget so OS + VR scene keep generous headroom.
    final int maxModelBytes;
    if (isDesktopFaro) {
      maxModelBytes = ramMb >= 14000
          ? 6 * 1024 * 1024 * 1024
          : 3 * 1024 * 1024 * 1024;
    } else if (isActiveVrVisor) {
      // On an active Visor, prefer nimble 1.5B–3B models (<= 2.35 GiB) for <1s replies.
      maxModelBytes = ramMb >= 10000
          ? 2400 * 1024 * 1024
          : 1400 * 1024 * 1024;
    } else {
      // 2D Companion Joystick phone has no 3D GPU load!
      maxModelBytes = ramMb >= 7500
          ? 2500 * 1024 * 1024
          : 1400 * 1024 * 1024;
    }

    ({String path, String label, int score})? best;
    for (final file in candidates) {
      try {
        final size = file.lengthSync();
        if (size < 20 * 1024 * 1024 || size > maxModelBytes) continue;
        final meta = GgufHeaderParser.parseFile(file.path);
        if (meta == null) continue;
        final arch = meta.architecture.toLowerCase();
        if (_embeddingArchitectures.contains(arch) || arch.contains('bert')) {
          continue;
        }
        final baseName = file.uri.pathSegments.last;
        // Prefer balanced non-reasoning chat instruct models (`centella` / `qwen` / `gemma` / `llama`)
        // for instant conversational VR latency, while still supporting `fugaz` / `semilla`.
        var score = (size ~/ (1024 * 1024));
        final lowerName = baseName.toLowerCase();
        if (lowerName.contains('centella') || lowerName.contains('qwen2.5-3b')) {
          score += 1200;
        } else if (lowerName.contains('gemma') || lowerName.contains('llama')) {
          score += 900;
        } else if (lowerName.contains('fugaz')) {
          score += 700;
        }
        if (best == null || score > best.score) {
          best = (
            path: file.path,
            label: 'saia_gguf:$baseName',
            score: score,
          );
        }
      } catch (_) {}
    }
    return best == null ? null : (path: best.path, label: best.label);
  }

  Future<({IaService service, String label})?> _tryResolveDesktopOllama() async {
    if (kIsWeb || !(Platform.isMacOS || Platform.isLinux || Platform.isWindows)) {
      return null;
    }
    final now = DateTime.now();
    if (_lastOllamaProbeAt != null &&
        now.difference(_lastOllamaProbeAt!) < const Duration(seconds: 20)) {
      return null;
    }
    _lastOllamaProbeAt = now;
    final client = OllamaClient();
    try {
      final models = await client
          .listModels()
          .timeout(const Duration(milliseconds: 850));
      final chatModels = models
          .where((m) => !m.name.toLowerCase().contains('embed'))
          .toList(growable: false);
      if (chatModels.isEmpty) return null;
      final chosen = chatModels.firstWhere(
        (m) =>
            m.name.toLowerCase().contains('qwen') ||
            m.name.toLowerCase().contains('gemma') ||
            m.name.toLowerCase().contains('llama'),
        orElse: () => chatModels.first,
      );
      final service = HttpLlmIaService(
        providerConfig: HttpLlmProviderConfig.ollama(
          model: chosen.name,
          host: 'http://127.0.0.1:11434',
        ),
      );
      await service.initialize();
      return (service: service, label: 'neom_ollama:${chosen.name}');
    } catch (_) {
      return null;
    }
  }

  /// Resolves (and caches) the optimal local [IaService] for this device role.
  Future<({IaService service, String label})> resolveLocalEngine({
    required bool isDesktopFaro,
    required bool isActiveVrVisor,
  }) async {
    if (_cachedLocalService != null &&
        _cachedLocalService!.isReady &&
        (_cachedIsDesktopRole == null ||
            (_cachedIsDesktopRole == isDesktopFaro &&
                _cachedIsVisorRole == isActiveVrVisor))) {
      return (
        service: _cachedLocalService!,
        label: _cachedEngineLabel ?? 'saia_embedded',
      );
    }

    // 1. Desktop Faro: prefer running local Ollama daemon if models are loaded.
    if (isDesktopFaro) {
      final ollama = await _tryResolveDesktopOllama();
      if (ollama != null) {
        _cachedLocalService = ollama.service;
        _cachedEngineLabel = ollama.label;
        _cachedIsDesktopRole = isDesktopFaro;
        _cachedIsVisorRole = isActiveVrVisor;
        return ollama;
      }
    }

    // 2. Desktop Faro, 2D Companion Phone, or capable 1D Smartphone: `saia_gguf` (`fllama`).
    final canRunGguf = isDesktopFaro ||
        canSmartphoneSustainGguf(isActiveVrVisor: isActiveVrVisor);
    if (canRunGguf) {
      final ramMb = detectRamMb();
      final gguf = await findBestLocalGgufModel(
        ramMb: ramMb,
        isActiveVrVisor: isActiveVrVisor,
        isDesktopFaro: isDesktopFaro,
      );
      if (gguf != null) {
        try {
          // On mobile Android Visor, keep GPU layers = 0 so Vulkan GPU stays
          // 100% dedicated to 60–120 Hz stereo rendering; Apple Silicon uses Metal.
          final useGpuLayers =
              (!kIsWeb && (Platform.isMacOS || Platform.isIOS)) ? 99 : 0;
          final service = GgufIaService(
            modelPath: gguf.path,
            contextSize: isDesktopFaro ? 4096 : 2048,
            nParallel: 1,
            numGpuLayers: useGpuLayers,
            maxTokens: 220,
            temperature: 0.45,
            systemInstruction:
                'Eres un guía y habitante espacial de VRlizate impulsado por SAIA local. '
                'Responde siempre en español natural, cálido y breve (máximo 2 o 3 oraciones).',
          );
          await service.initialize();
          _cachedLocalService = service;
          _cachedEngineLabel = gguf.label;
          _cachedIsDesktopRole = isDesktopFaro;
          _cachedIsVisorRole = isActiveVrVisor;
          return (service: service, label: gguf.label);
        } catch (_) {
          // Fall through cleanly to zero-RAM SaiaContextualMicroIaService.
        }
      }
    }

    // 3. Always-available 0-RAM local SAIA micro-engine (`neom_ia` + `saia_core`).
    final micro = SaiaContextualMicroIaService();
    await micro.initialize();
    _cachedLocalService = micro;
    _cachedEngineLabel = 'saia_micro_local';
    _cachedIsDesktopRole = isDesktopFaro;
    _cachedIsVisorRole = isActiveVrVisor;
    return (service: micro, label: 'saia_micro_local');
  }

  /// Executes a stateless local prompt on this device.
  Future<({bool ok, String text, String engineLabel})> inferLocal({
    required String prompt,
    String? systemPrompt,
    int maxTokens = 200,
    bool isDesktopFaro = false,
    bool isActiveVrVisor = true,
  }) async {
    final resolved = await resolveLocalEngine(
      isDesktopFaro: isDesktopFaro,
      isActiveVrVisor: isActiveVrVisor,
    );
    resolved.service.clearHistory();
    final fullPrompt = (systemPrompt != null && systemPrompt.trim().isNotEmpty)
        ? '${systemPrompt.trim()}\n\n$prompt'
        : prompt;
    try {
      final msg = await resolved.service
          .sendMessage(fullPrompt)
          .timeout(const Duration(seconds: 22));
      final cleaned = cleanSlmOutput(msg.text);
      if (cleaned.isNotEmpty && !msg.isError) {
        return (ok: true, text: cleaned, engineLabel: resolved.label);
      }
    } catch (_) {}
    // Ensure local micro fallback if a heavy GGUF/Ollama run failed mid-turn.
    final fallback = SaiaContextualMicroIaService();
    await fallback.initialize();
    final text = await fallback.generateContent(fullPrompt) ?? '';
    return (
      ok: text.isNotEmpty,
      text: text,
      engineLabel: 'saia_micro_local',
    );
  }

  /// Handler registered on `VrDesktopBeaconStation.defaultAiInferenceHandler`
  /// so any **Estación Faro (`3D`)** serves embedded SAIA/Ollama/GGUF over LAN.
  Future<Map<String, Object?>> handleDesktopFaroRequest(
    Map<String, Object?> payload,
  ) async {
    final prompt = (payload['prompt'] as String?)?.trim() ?? '';
    final sys = (payload['systemPrompt'] as String?)?.trim();
    final maxTok = (payload['maxTokens'] as num?)?.toInt() ?? 200;
    if (prompt.isEmpty || prompt.length > 16384) {
      return {'ok': false, 'error': 'invalid_prompt'};
    }
    final res = await inferLocal(
      prompt: prompt,
      systemPrompt: sys,
      maxTokens: maxTok.clamp(32, 512),
      isDesktopFaro: true,
      isActiveVrVisor: false,
    );
    return <String, Object?>{
      'ok': res.ok,
      'text': res.text,
      'engine': res.engineLabel,
      'topology': '3D',
    };
  }

  /// Co-processor registered on `VrJoystickAiCoProcessor.defaultCoProcessor`
  /// so a **2º Smartphone (`2D` Joystick)** supports the Visor when capable.
  VrJoystickAiCoProcessor buildJoystickCoProcessor() => VrJoystickAiCoProcessor(
    probeCapabilities: () async {
      final ramMb = detectRamMb();
      final thermal = detectThermalLevel();
      // A secondary phone with >= 3.8 GB RAM & healthy thermals can offload AI
      // for the Visor (either via local GGUF or SAIA micro co-processing).
      final supported = !kIsWeb && ramMb >= minCompanionPhoneGgufRamMb && thermal < 2;
      if (!supported) {
        return (supported: false, engineLabel: 'low_ram', ramMb: ramMb);
      }
      final gguf = await findBestLocalGgufModel(
        ramMb: ramMb,
        isActiveVrVisor: false,
        isDesktopFaro: false,
      );
      return (
        supported: true,
        engineLabel: gguf?.label ?? 'saia_companion_local',
        ramMb: ramMb,
      );
    },
    infer: ({required prompt, systemPrompt, maxTokens = 180}) => inferLocal(
      prompt: prompt,
      systemPrompt: systemPrompt,
      maxTokens: maxTokens,
      isDesktopFaro: false,
      isActiveVrVisor: false,
    ),
  );
}

/// Distributed Sovereign AI provider (`1D` Smartphone / `2D` Companion Joystick /
/// `3D` Desktop Faro) implementing [VrAssistantProvider] via `saia_gguf`,
/// `saia_core`, `neom_ia`, and `neom_ollama` — with **zero dependency on Itzli Cloud**.
class VrEmbeddedSaiaProvider implements VrAssistantProvider {
  VrEmbeddedSaiaProvider({
    VrEmbeddedSaiaRuntime? runtime,
    this.beaconClientResolver,
    this.remoteControllerResolver,
  }) : runtime = runtime ?? VrEmbeddedSaiaRuntime.instance;

  final VrEmbeddedSaiaRuntime runtime;
  final VrDesktopBeaconClient? Function()? beaconClientResolver;
  final VrRemoteControllerService? Function()? remoteControllerResolver;

  bool _disposed = false;
  String _lastEngineUsed = 'saia_local';

  String get lastEngineUsed => _lastEngineUsed;

  /// Dynamically resolves the active `1D` / `2D` / `3D` embedded AI topology.
  VrEmbeddedAiTopology get activeTopology {
    final beacon = beaconClientResolver?.call();
    if (beacon != null && beacon.isConnected) {
      return VrEmbeddedAiTopology.threeDevicesFaro;
    }
    final remote = remoteControllerResolver?.call();
    if (remote != null && remote.peerSupportsEmbeddedAi) {
      return VrEmbeddedAiTopology.twoDevicesCompanionPhone;
    }
    return VrEmbeddedAiTopology.oneDeviceSmartphone;
  }

  @override
  Future<VrAssistantReply> respond(VrAssistantRequest request) async {
    if (_disposed) {
      return VrAssistantReply(text: 'Asistente cerrado.', isError: true);
    }
    final userText = request.text.trim();
    if (userText.isEmpty || userText.length > 4096) {
      return VrAssistantReply(
        text: 'Escribe o di una consulta más breve.',
        isError: true,
      );
    }

    final requiresActionJson = request.context.allowedActions.isNotEmpty;
    final fullPrompt = _buildLocalPrompt(request, requiresActionJson: requiresActionJson);
    final compactPeerPrompt = _buildCompactPeerPrompt(request);

    // 1. Tier 3D — Offload to Estación Faro Computer (`neom_ollama` / `saia_gguf` Metal/CPU)
    final beacon = beaconClientResolver?.call();
    if (beacon != null && beacon.isConnected) {
      final faroRes = await beacon.requestDesktopAiInference(<String, Object?>{
        'prompt': fullPrompt,
        'maxTokens': 220,
      });
      final faroText = faroRes?['text'];
      if (faroRes?['ok'] == true &&
          faroText is String &&
          faroText.trim().isNotEmpty) {
        _lastEngineUsed = (faroRes?['engine'] as String?) ?? 'faro_3d_saia';
        return _parseReply(faroText, request.context.allowedActions);
      }
    }

    // 2. Tier 2D — Offload to 2nd Smartphone (`PhoneControllerPage` Support Co-Processor)
    final remote = remoteControllerResolver?.call();
    if (remote != null && remote.peerSupportsEmbeddedAi) {
      final peerRes = await remote.requestPeerAiInference(
        prompt: compactPeerPrompt,
        systemPrompt:
            'Guía espacial VRlizate (SAIA 2D). Responde en español breve (2 oraciones).',
        maxTokens: 160,
      );
      if (peerRes != null && peerRes.text.trim().isNotEmpty) {
        _lastEngineUsed = '2d_peer:${peerRes.engine}';
        return _parseReply(peerRes.text, request.context.allowedActions);
      }
    }

    // 3. Tier 1D — Run embedded SAIA directly on this Smartphone (or Desktop standalone)
    final isDesktopHost = !kIsWeb &&
        (Platform.isMacOS || Platform.isLinux || Platform.isWindows);
    final localRes = await runtime.inferLocal(
      prompt: fullPrompt,
      maxTokens: 200,
      isDesktopFaro: isDesktopHost,
      isActiveVrVisor: !isDesktopHost,
    );
    _lastEngineUsed = '1d_local:${localRes.engineLabel}';
    if (!localRes.ok || localRes.text.trim().isEmpty) {
      return VrAssistantReply(
        text: 'SAIA local no pudo generar respuesta en este momento.',
        isError: true,
      );
    }
    return _parseReply(localRes.text, request.context.allowedActions);
  }

  String _buildCompactPeerPrompt(VrAssistantRequest request) {
    final details = request.context.details;
    final npc = details['npc'];
    final plaza = details['plaza'] ?? request.context.title;
    if (npc is Map) {
      final name = npc['name'] ?? 'Visitante';
      final role = npc['role'] ?? 'Explorador VR';
      final near = npc['nearestRoom'];
      return '[Plaza: $plaza${near != null ? " · Cerca de: $near" : ""} · '
          'Personaje: $name ($role)] ${request.text.trim()}';
    }
    return '[Sala: $plaza] ${request.text.trim()}';
  }

  String _buildLocalPrompt(
    VrAssistantRequest request, {
    required bool requiresActionJson,
  }) {
    final payload = jsonEncode(<String, Object?>{
      'experienceId': request.context.experienceId,
      'title': request.context.title,
      'details': request.context.details,
      'allowedActions': request.context.allowedActions.toList()..sort(),
      'userRequest': request.text.trim(),
    });
    if (!requiresActionJson) {
      return 'Responde en español natural, cálido y conciso (2 a 3 oraciones) '
          'usando únicamente los datos de este contexto espacial VRlizate. '
          'No devuelvas bloques de código ni JSON:\n$payload';
    }
    return 'Eres el asistente espacial local SAIA de VRlizate. Responde en español breve. '
        'Si corresponde ejecutar una acción de allowedActions, devuelve exactamente JSON '
        '{"text":"respuesta","action":"nombreAccion","arguments":{"id":"..."}}; '
        'si es solo conversación usa {"text":"respuesta","action":null,"arguments":{}}.\n'
        '$payload';
  }

  VrAssistantReply _parseReply(String raw, Set<String> allowedActions) {
    final cleaned = VrEmbeddedSaiaRuntime.cleanSlmOutput(raw);
    // Try structured JSON first if present.
    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        final decoded = jsonDecode(cleaned.substring(start, end + 1));
        if (decoded is Map) {
          final txt = decoded['text'];
          final act = decoded['action'];
          final args = decoded['arguments'];
          if (txt is String && txt.trim().isNotEmpty) {
            final validAction =
                (act is String && allowedActions.contains(act)) ? act : null;
            final validArgs = (validAction != null && args is Map)
                ? Map<String, Object?>.from(args)
                : const <String, Object?>{};
            return VrAssistantReply(
              text: txt.trim(),
              action: validAction,
              arguments: validArgs,
            );
          }
        }
      } catch (_) {}
    }
    // Conversational plain-text reply from local SLM / micro-engine:
    final bounded = cleaned.length <= 1600
        ? cleaned
        : '${cleaned.substring(0, 1599)}…';
    return VrAssistantReply(text: bounded);
  }

  @override
  void dispose() {
    _disposed = true;
  }
}
