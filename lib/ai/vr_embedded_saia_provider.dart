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

/// Discovered local causal `.gguf` candidate on disk (excluding embedding-only models).
@immutable
class VrLocalGgufCandidate {
  const VrLocalGgufCandidate({
    required this.path,
    required this.fileName,
    required this.sizeBytes,
    required this.architecture,
    required this.quantization,
    this.mmprojPath,
  });

  final String path;
  final String fileName;
  final int sizeBytes;
  final String architecture;
  final String quantization;
  final String? mmprojPath;

  String get label => 'saia_gguf:$fileName';
  double get sizeGb => sizeBytes / (1024 * 1024 * 1024);
  bool get supportsVision => mmprojPath != null;
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
    final plaza =
        (details['plaza'] as String?) ??
        (ctx?['title'] as String?) ??
        'esta plaza VR';
    final zone = details['zone'] as String?;
    final hasImage = ctx?['hasImage'] == true;
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

    if (hasImage) {
      final zonePart = zone != null && zone.isNotEmpty ? ' en la zona $zone' : '';
      final rec = expTitles.isNotEmpty
          ? ' También tienes cerca «${expTitles.first}».'
          : '';
      return 'Estás mirando $plaza$zonePart.$rec '
          'Para análisis visual detallado 100 % local, instala un modelo VLM en '
          'tu Estación Faro (p. ej. qwen2.5vl:3b en Ollama) o un archivo mmproj.gguf.';
    }

    if (npc != null) {
      final name = (npc['name'] as String?) ?? 'Visitante';
      final role = (npc['role'] as String?) ?? 'Explorador VR';
      final nearest = npc['nearestRoom'] as String?;
      final pickA = expTitles.isNotEmpty
          ? '«${expTitles.first}»'
          : (nearest != null ? '«$nearest»' : 'la galería central');
      final pickB = expTitles.length > 1 ? ' o «${expTitles[1]}»' : '';
      final turns = ctx?['recentTurns'];
      final hasHistory = turns is List && turns.isNotEmpty;

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
      if (hasHistory) {
        return 'Siguiendo nuestra charla como $name ($role): aquí en $plaza '
            'puedes explorar $pickA$pickB o escribirme otra duda con WordSphere.';
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
/// (`fllama` / `llama.cpp` GGUF + `GgufGbnfGrammar` + `GgufModelScheduler`),
/// **`neom_ollama`** + **`neom_ia`** (`HttpLlmIaService` + local Ollama VLM),
/// and **`SaiaContextualMicroIaService`** across Smartphone (`1D`), Companion
/// Joystick (`2D`), and Desktop Faro (`3D`).
class VrEmbeddedSaiaRuntime extends ChangeNotifier {
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

  static const List<String> _visionModelNeedles = <String>[
    'vl',
    'llava',
    'moondream',
    'minicpm-v',
    'gemma3',
    'vision',
    'pixtral',
  ];

  /// Minimum smartphone RAM (`5.5 GB`) to run in-process GGUF weights alongside
  /// an active stereoscopic 3D Impeller scene (`1D`).
  static const int minVisorSmartphoneGgufRamMb = 5500;

  /// Minimum secondary smartphone RAM (`3.8 GB`) to sustain GGUF weights when
  /// acting solely as a `2D` Joystick / AI Support Co-Processor.
  static const int minCompanionPhoneGgufRamMb = 3800;

  /// Recommended tiny multilingual `.gguf` (Qwen2.5-0.5B-Instruct Q4_K_M, ~398 MB)
  /// safe for capable 1D/2D smartphones over Wi-Fi.
  static final Uri recommendedMobileGgufUri = Uri.parse(
    'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf',
  );
  static const String recommendedMobileGgufFileName =
      'qwen2.5-0.5b-instruct-q4_k_m.gguf';

  final int Function()? ramMbProbe;
  final int Function()? thermalLevelProbe;
  final List<String> Function()? extraModelDirectories;

  IaService? _cachedLocalService;
  String? _cachedEngineLabel;
  String? _cachedModelPath;
  bool? _cachedIsDesktopRole;
  bool? _cachedIsVisorRole;
  DateTime? _lastOllamaProbeAt;
  String? _selectedModelPathOverride;
  int _thermalEvictionsCount = 0;
  DateTime? _thermalCooldownUntil;
  String? _lastEvictionReason;
  int _localInferencesServed = 0;
  int _lastInferenceLatencyMs = 0;

  String? get activeEngineLabel => _cachedEngineLabel;
  String? get activeModelPath => _cachedModelPath;
  String? get selectedModelPathOverride => _selectedModelPathOverride;
  int get thermalEvictionsCount => _thermalEvictionsCount;
  String? get lastEvictionReason => _lastEvictionReason;
  int get localInferencesServed => _localInferencesServed;
  int get lastInferenceLatencyMs => _lastInferenceLatencyMs;
  bool get hasLoadedGgufInRam => _cachedLocalService is GgufIaService;

  /// Sets (or clears with `null`) an explicit preferred local `.gguf` path and
  /// unloads any previously resident model so the next turn loads the new one.
  void setPreferredGgufModel(String? path) {
    final clean = path?.trim();
    final next = (clean != null && clean.isNotEmpty) ? clean : null;
    if (next == _selectedModelPathOverride) return;
    _selectedModelPathOverride = next;
    unloadLocalModel(reason: 'model_switch');
  }

  /// Immediately unloads any resident local `GgufIaService` weights from RAM
  /// and unregisters them from [GgufModelScheduler], preserving 100 % memory
  /// for 60–120 Hz VR rendering.
  void unloadLocalModel({String reason = 'manual_unload'}) {
    final service = _cachedLocalService;
    final path = _cachedModelPath;
    _cachedLocalService = null;
    _cachedEngineLabel = null;
    _cachedModelPath = null;
    _cachedIsDesktopRole = null;
    _cachedIsVisorRole = null;
    _lastEvictionReason = reason;
    if (service is GgufIaService) {
      try {
        service.dispose();
      } catch (_) {}
      if (path != null) {
        GgufModelScheduler.instance.unregister(path);
      }
    }
    notifyListeners();
  }

  /// Hook invoked automatically by `StereoSceneView.onGlobalQualityStepDown`
  /// and `VrThermalGovernor.onGlobalThermalEvent` whenever VR frame rate or OS
  /// thermals degrade, evicting resident `.gguf` weights on mobile devices.
  void notifyThermalStepDown({
    int? thermalSeverity,
    bool steppedDownToLow = false,
  }) {
    if (kIsWeb) return;
    final isDesktop =
        Platform.isMacOS || Platform.isLinux || Platform.isWindows;
    if (isDesktop) return;
    final severity = thermalSeverity ?? detectThermalLevel();
    if (!steppedDownToLow && severity < 2) return;
    _thermalCooldownUntil = DateTime.now().add(const Duration(minutes: 3));
    if (_cachedLocalService is GgufIaService) {
      _thermalEvictionsCount++;
      unloadLocalModel(
        reason: steppedDownToLow
            ? 'vr_quality_step_down_low'
            : 'thermal_severity_$severity',
      );
    } else {
      notifyListeners();
    }
  }

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
    final cooldown = _thermalCooldownUntil;
    if (cooldown != null && DateTime.now().isBefore(cooldown)) {
      return false;
    }
    final thermal = detectThermalLevel();
    if (thermal >= 2) return false;
    final ramMb = detectRamMb();
    final minRequired = isActiveVrVisor
        ? minVisorSmartphoneGgufRamMb
        : minCompanionPhoneGgufRamMb;
    return ramMb >= minRequired;
  }

  /// Builds a strict JSON Schema constraining VR spatial assistant actions.
  static Map<String, dynamic> buildActionJsonSchema(
    Set<String> allowedActions,
  ) {
    final sorted = allowedActions.toList()..sort();
    return <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'text': <String, dynamic>{'type': 'string'},
        'action': sorted.isEmpty
            ? <String, dynamic>{'type': 'string'}
            : <String, dynamic>{
                'type': 'string',
                'enum': <String>['none', ...sorted],
              },
        'arguments': <String, dynamic>{'type': 'object'},
      },
    };
  }

  /// Compiles a native `llama.cpp` GBNF grammar via `saia_gguf`'s
  /// [GgufGbnfGrammar] so 1.5B–3B SLMs cannot emit malformed action JSON.
  static String buildActionGbnfGrammar(
    Set<String> allowedActions, {
    bool allowThinking = false,
  }) {
    final base = GgufGbnfGrammar.fromJsonSchema(
      buildActionJsonSchema(allowedActions),
    );
    if (!allowThinking) return base;
    return GgufGbnfGrammar.thinkingGrammar(const <String>['</think>'], base);
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

  /// Cleans partial streaming output while hiding unclosed `<think>...` tokens
  /// until `</think>` arrives so users never see raw chain-of-thought tags.
  static String cleanStreamingSlmOutput(String rawAccumulated) {
    final lower = rawAccumulated.toLowerCase();
    final openIdx = lower.indexOf('<think>');
    if (openIdx >= 0) {
      final closeIdx = lower.indexOf('</think>', openIdx);
      if (closeIdx < 0) {
        return rawAccumulated.substring(0, openIdx).trim();
      }
    }
    return cleanSlmOutput(rawAccumulated);
  }

  Future<List<Directory>> _candidateModelDirectories() async {
    final dirs = <Directory>[];
    final extra = extraModelDirectories?.call() ?? const <String>[];
    for (final path in extra) {
      if (path.trim().isNotEmpty) dirs.add(Directory(path.trim()));
    }
    if (kIsWeb) return dirs;

    final envDir =
        Platform.environment['SAIA_MODELS_DIR'] ??
        Platform.environment['ITZLI_MODELS_DIR'];
    if (envDir != null && envDir.trim().isNotEmpty) {
      dirs.add(Directory(envDir.trim()));
    }

    if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      final home =
          Platform.environment['HOME'] ??
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

  /// Resolves the writable per-app directory where downloaded/imported `.gguf`
  /// weights live on smartphones (`1D` / `2D`) and desktop (`3D`).
  Future<Directory?> resolveWritableModelsDirectory() async {
    if (kIsWeb) return null;
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final target = Directory('${docDir.path}/saia_edge_models');
      if (!target.existsSync()) {
        target.createSync(recursive: true);
      }
      return target;
    } catch (_) {
      return null;
    }
  }

  /// Streams a `.gguf` model from [url] into `saia_edge_models/` with strict
  /// 4-byte `'GGUF'` header validation and atomic rename on completion.
  Future<File?> downloadGgufModel(
    Uri url, {
    required String fileName,
    void Function(double progress)? onProgress,
    int maxBytes = 2500 * 1024 * 1024,
  }) async {
    if (kIsWeb || url.scheme != 'https') return null;
    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    if (!safeName.toLowerCase().endsWith('.gguf')) return null;
    final dir = await resolveWritableModelsDirectory();
    if (dir == null) return null;

    final finalFile = File('${dir.path}/$safeName');
    final tempFile = File('${dir.path}/.$safeName.part');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    IOSink? sink;
    try {
      final req = await client.getUrl(url);
      final res = await req.close();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        await res.drain<void>();
        return null;
      }
      final expected = res.contentLength;
      if (expected > maxBytes) {
        await res.drain<void>();
        return null;
      }
      sink = tempFile.openWrite();
      var received = 0;
      var headerChecked = false;
      final headerBuf = <int>[];
      await for (final chunk in res) {
        if (!headerChecked) {
          headerBuf.addAll(chunk);
          if (headerBuf.length >= 4) {
            // Verify 'GGUF' magic bytes (0x47 0x47 0x55 0x46).
            if (headerBuf[0] != 0x47 ||
                headerBuf[1] != 0x47 ||
                headerBuf[2] != 0x55 ||
                headerBuf[3] != 0x46) {
              throw const FormatException('El archivo no tiene cabecera GGUF.');
            }
            headerChecked = true;
          }
        }
        received += chunk.length;
        if (received > maxBytes) {
          throw const FormatException('El modelo excede el límite permitido.');
        }
        sink.add(chunk);
        if (expected > 0 && onProgress != null) {
          onProgress((received / expected).clamp(0.0, 1.0));
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (!headerChecked || received < 20 * 1024 * 1024) {
        if (tempFile.existsSync()) tempFile.deleteSync();
        return null;
      }
      if (finalFile.existsSync()) finalFile.deleteSync();
      final moved = await tempFile.rename(finalFile.path);
      setPreferredGgufModel(moved.path);
      return moved;
    } catch (_) {
      try {
        await sink?.close();
      } catch (_) {}
      if (tempFile.existsSync()) {
        try {
          tempFile.deleteSync();
        } catch (_) {}
      }
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Lists all valid causal `.gguf` chat models found across candidate dirs
  /// (skipping embedding-only `bert`/`nomic-bert` and standalone `mmproj` files),
  /// pairing any sibling `mmproj*.gguf` automatically for local vision.
  Future<List<VrLocalGgufCandidate>> listAvailableGgufModels() async {
    if (kIsWeb) return const <VrLocalGgufCandidate>[];
    final seenPaths = <String>{};
    final files = <File>[];
    const definedPath = String.fromEnvironment('VRLIZATE_GGUF_MODEL_PATH');
    if (definedPath.isNotEmpty && File(definedPath).existsSync()) {
      files.add(File(definedPath));
    }
    if (_selectedModelPathOverride != null &&
        File(_selectedModelPathOverride!).existsSync()) {
      files.add(File(_selectedModelPathOverride!));
    }
    for (final dir in await _candidateModelDirectories()) {
      if (!dir.existsSync()) continue;
      try {
        for (final entity in dir.listSync(followLinks: false)) {
          if (entity is File && entity.path.toLowerCase().endsWith('.gguf')) {
            files.add(entity);
          }
        }
      } catch (_) {}
    }

    // Index any sibling `mmproj*.gguf` projectors by parent directory.
    final mmprojByDir = <String, String>{};
    for (final f in files) {
      final lower = f.uri.pathSegments.last.toLowerCase();
      if (lower.contains('mmproj')) {
        mmprojByDir[f.parent.path] = f.path;
      }
    }

    final results = <VrLocalGgufCandidate>[];
    for (final file in files) {
      if (!seenPaths.add(file.path)) continue;
      final baseName = file.uri.pathSegments.last;
      if (baseName.toLowerCase().contains('mmproj')) continue;
      try {
        final size = file.lengthSync();
        if (size < 20 * 1024 * 1024) continue;
        final meta = GgufHeaderParser.parseFile(file.path);
        if (meta == null) continue;
        final arch = meta.architecture.toLowerCase();
        if (_embeddingArchitectures.contains(arch) || arch.contains('bert')) {
          continue;
        }
        results.add(
          VrLocalGgufCandidate(
            path: file.path,
            fileName: baseName,
            sizeBytes: size,
            architecture: meta.architecture,
            quantization: meta.quantizationType,
            mmprojPath: mmprojByDir[file.parent.path],
          ),
        );
      } catch (_) {}
    }
    results.sort((a, b) => a.sizeBytes.compareTo(b.sizeBytes));
    return results;
  }

  /// Selects the best causal chat `.gguf` file on disk that fits [ramMb],
  /// skipping embedding-only models (`nomic-bert` / `bert`).
  Future<VrLocalGgufCandidate?> findBestLocalGgufModel({
    required int ramMb,
    required bool isActiveVrVisor,
    required bool isDesktopFaro,
  }) async {
    final candidates = await listAvailableGgufModels();
    if (candidates.isEmpty) return null;

    // Max model file budget so OS + VR scene keep generous headroom.
    final int maxModelBytes;
    if (isDesktopFaro) {
      maxModelBytes = ramMb >= 14000
          ? 6 * 1024 * 1024 * 1024
          : 3 * 1024 * 1024 * 1024;
    } else if (isActiveVrVisor) {
      maxModelBytes = ramMb >= 10000
          ? 2400 * 1024 * 1024
          : 1400 * 1024 * 1024;
    } else {
      maxModelBytes = ramMb >= 7500
          ? 2500 * 1024 * 1024
          : 1400 * 1024 * 1024;
    }

    // Honor explicit user model override if it exists and fits RAM budget.
    if (_selectedModelPathOverride != null) {
      for (final c in candidates) {
        if (c.path == _selectedModelPathOverride &&
            c.sizeBytes <= maxModelBytes) {
          return c;
        }
      }
    }

    ({VrLocalGgufCandidate candidate, int score})? best;
    for (final c in candidates) {
      if (c.sizeBytes > maxModelBytes) continue;
      var score = (c.sizeBytes ~/ (1024 * 1024));
      final lowerName = c.fileName.toLowerCase();
      if (lowerName.contains('centella') || lowerName.contains('qwen2.5-3b')) {
        score += 1200;
      } else if (lowerName.contains('qwen2.5-0.5b') ||
          lowerName.contains('qwen2.5-1.5b')) {
        score += isActiveVrVisor ? 1300 : 1000;
      } else if (lowerName.contains('gemma') || lowerName.contains('llama')) {
        score += 900;
      } else if (lowerName.contains('fugaz')) {
        score += 700;
      }
      if (c.supportsVision) score += 250;
      if (best == null || score > best.score) {
        best = (candidate: c, score: score);
      }
    }
    return best?.candidate;
  }

  Future<List<OllamaModel>> _listDesktopOllamaModels() async {
    if (kIsWeb ||
        !(Platform.isMacOS || Platform.isLinux || Platform.isWindows)) {
      return const <OllamaModel>[];
    }
    final client = OllamaClient();
    try {
      return await client
          .listModels()
          .timeout(const Duration(milliseconds: 900));
    } catch (_) {
      return const <OllamaModel>[];
    }
  }

  Future<({IaService service, String label})?> _tryResolveDesktopOllama() async {
    if (kIsWeb ||
        !(Platform.isMacOS || Platform.isLinux || Platform.isWindows)) {
      return null;
    }
    final now = DateTime.now();
    if (_lastOllamaProbeAt != null &&
        now.difference(_lastOllamaProbeAt!) < const Duration(seconds: 20)) {
      return null;
    }
    _lastOllamaProbeAt = now;
    final models = await _listDesktopOllamaModels();
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
    try {
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

  /// Calls a local desktop Ollama VLM (`qwen2.5vl` / `llava` / `moondream` /
  /// `gemma3`) with a base64 screenshot for `«Qué estoy viendo»` in `3D` Faro.
  Future<({String text, String engine})?> _tryDesktopOllamaVision({
    required String prompt,
    required String imageBase64,
    int maxTokens = 200,
  }) async {
    final models = await _listDesktopOllamaModels();
    if (models.isEmpty) return null;
    OllamaModel? vlm;
    for (final m in models) {
      final lower = m.name.toLowerCase();
      if (_visionModelNeedles.any(lower.contains)) {
        vlm = m;
        break;
      }
    }
    if (vlm == null) return null;

    final httpClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 4);
    try {
      final req = await httpClient.postUrl(
        Uri.parse('http://127.0.0.1:11434/api/chat'),
      );
      req.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json; charset=utf-8',
      );
      req.add(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'model': vlm.name,
            'stream': false,
            'options': {'num_predict': maxTokens.clamp(64, 320)},
            'messages': [
              {
                'role': 'system',
                'content':
                    'Eres el guía espacial visual de VRlizate. Describe en español claro y breve (2 a 3 oraciones) lo que ve el usuario en la escena VR.',
              },
              {
                'role': 'user',
                'content': prompt,
                'images': [imageBase64],
              },
            ],
          }),
        ),
      );
      final res = await req.close().timeout(const Duration(seconds: 22));
      if (res.statusCode != HttpStatus.ok) {
        await res.drain<void>();
        return null;
      }
      final raw = await utf8.decoder.bind(res).join();
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['message'] is Map) {
        final content = (decoded['message'] as Map)['content'];
        if (content is String && content.trim().isNotEmpty) {
          return (
            text: cleanSlmOutput(content),
            engine: 'neom_ollama_vlm:${vlm.name}',
          );
        }
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      httpClient.close(force: true);
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
        _cachedModelPath = null;
        _cachedIsDesktopRole = isDesktopFaro;
        _cachedIsVisorRole = isActiveVrVisor;
        notifyListeners();
        return ollama;
      }
    }

    // 2. Desktop Faro, 2D Companion Phone, or capable 1D Smartphone: `saia_gguf` (`fllama`).
    final canRunGguf =
        isDesktopFaro ||
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
            mmprojPath: gguf.mmprojPath,
            contextSize: isDesktopFaro ? 4096 : 2048,
            nParallel: 1,
            numGpuLayers: useGpuLayers,
            maxTokens: 220,
            temperature: 0.45,
            keepAlive: isDesktopFaro
                ? const Duration(minutes: 8)
                : const Duration(minutes: 2),
            systemInstruction:
                'Eres un guía y habitante espacial de VRlizate impulsado por SAIA local. '
                'Responde siempre en español natural, cálido y breve (máximo 2 o 3 oraciones).',
          );
          await service.initialize();
          _cachedLocalService = service;
          _cachedEngineLabel = gguf.label;
          _cachedModelPath = gguf.path;
          _cachedIsDesktopRole = isDesktopFaro;
          _cachedIsVisorRole = isActiveVrVisor;
          notifyListeners();
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
    _cachedModelPath = null;
    _cachedIsDesktopRole = isDesktopFaro;
    _cachedIsVisorRole = isActiveVrVisor;
    notifyListeners();
    return (service: micro, label: 'saia_micro_local');
  }

  /// Executes a local prompt on this device with optional:
  /// - [conversationHistory]: stateless multi-turn memory (`GgufIaService.generateConversation`)
  /// - [contextJson]: structured JSON reference context for `GgufIaService`
  /// - [actionJsonSchema]: native `GgufGbnfGrammar` enforcement for spatial actions
  /// - [onPartialText]: live `<think>`-filtered progressive token streaming
  Future<({bool ok, String text, String engineLabel})> inferLocal({
    required String prompt,
    String? systemPrompt,
    int maxTokens = 200,
    bool isDesktopFaro = false,
    bool isActiveVrVisor = true,
    List<IaChatMessage> conversationHistory = const <IaChatMessage>[],
    String? contextJson,
    Map<String, dynamic>? actionJsonSchema,
    void Function(String partialCleanText)? onPartialText,
  }) async {
    final sw = Stopwatch()..start();
    final resolved = await resolveLocalEngine(
      isDesktopFaro: isDesktopFaro,
      isActiveVrVisor: isActiveVrVisor,
    );
    final service = resolved.service;
    final fullPrompt = (systemPrompt != null && systemPrompt.trim().isNotEmpty)
        ? '${systemPrompt.trim()}\n\n$prompt'
        : prompt;

    try {
      // A. Native GBNF structured JSON action output on local GGUF!
      if (actionJsonSchema != null && service is GgufIaService) {
        final raw = await service
            .generateStructuredContent(fullPrompt, actionJsonSchema)
            .timeout(const Duration(seconds: 22));
        final cleaned = cleanSlmOutput(raw ?? '');
        if (cleaned.isNotEmpty) {
          _recordLocalMetric(sw.elapsedMilliseconds);
          onPartialText?.call(cleaned);
          return (ok: true, text: cleaned, engineLabel: resolved.label);
        }
      }

      // B. Stateless multi-turn streaming conversation on local GGUF!
      if (service is GgufIaService && conversationHistory.isNotEmpty) {
        final acc = StringBuffer();
        var lastEmitMs = 0;
        final raw = await service
            .generateConversation(
              [...conversationHistory, IaChatMessage.user(prompt)],
              contextData: contextJson,
              onDelta: onPartialText == null
                  ? null
                  : (delta) {
                      acc.write(delta);
                      final nowMs = sw.elapsedMilliseconds;
                      if (nowMs - lastEmitMs >= 110) {
                        lastEmitMs = nowMs;
                        final clean = cleanStreamingSlmOutput(acc.toString());
                        if (clean.isNotEmpty) onPartialText(clean);
                      }
                    },
            )
            .timeout(const Duration(seconds: 24));
        final cleaned = cleanSlmOutput(raw ?? acc.toString());
        if (cleaned.isNotEmpty) {
          _recordLocalMetric(sw.elapsedMilliseconds);
          onPartialText?.call(cleaned);
          return (ok: true, text: cleaned, engineLabel: resolved.label);
        }
      }

      // C. Streaming chat on any IaService (GgufIaService, HttpLlmIaService, Micro).
      service.clearHistory();
      if (onPartialText != null) {
        final acc = StringBuffer();
        var lastEmitMs = 0;
        await for (final chunk
            in service
                .sendMessageStream(fullPrompt)
                .timeout(const Duration(seconds: 24))) {
          acc.write(chunk);
          final nowMs = sw.elapsedMilliseconds;
          if (nowMs - lastEmitMs >= 110) {
            lastEmitMs = nowMs;
            final clean = cleanStreamingSlmOutput(acc.toString());
            if (clean.isNotEmpty) onPartialText(clean);
          }
        }
        final cleaned = cleanSlmOutput(acc.toString());
        if (cleaned.isNotEmpty) {
          _recordLocalMetric(sw.elapsedMilliseconds);
          onPartialText(cleaned);
          return (ok: true, text: cleaned, engineLabel: resolved.label);
        }
      } else {
        final msg = await service
            .sendMessage(fullPrompt)
            .timeout(const Duration(seconds: 22));
        final cleaned = cleanSlmOutput(msg.text);
        if (cleaned.isNotEmpty && !msg.isError) {
          _recordLocalMetric(sw.elapsedMilliseconds);
          return (ok: true, text: cleaned, engineLabel: resolved.label);
        }
      }
    } catch (_) {}

    // Ensure local micro fallback if a heavy GGUF/Ollama run failed mid-turn.
    final fallback = SaiaContextualMicroIaService();
    await fallback.initialize();
    final text = await fallback.generateContent(fullPrompt) ?? '';
    _recordLocalMetric(sw.elapsedMilliseconds);
    if (text.isNotEmpty) onPartialText?.call(text);
    return (
      ok: text.isNotEmpty,
      text: text,
      engineLabel: 'saia_micro_local',
    );
  }

  void _recordLocalMetric(int elapsedMs) {
    _localInferencesServed++;
    _lastInferenceLatencyMs = elapsedMs;
    notifyListeners();
  }

  /// Status payload exposed to `VrDesktopBeaconStation.defaultAiStatusProvider`
  /// (`GET /<token>/api/ai-status` and the Faro 3D dashboard card).
  Future<Map<String, Object?>> buildStatusSnapshot() async {
    final ramMb = detectRamMb();
    final thermal = detectThermalLevel();
    final ggufs = await listAvailableGgufModels();
    final ollamaModels = await _listDesktopOllamaModels();
    final modelNames = <String>[
      for (final m in ollamaModels.take(4)) 'ollama:${m.name}',
      for (final g in ggufs.take(4)) g.fileName,
    ];
    return <String, Object?>{
      'ok': true,
      'activeEngine': _cachedEngineLabel ?? 'saia_auto',
      'ramMb': ramMb,
      'ramGb': double.parse((ramMb / 1024.0).toStringAsFixed(1)),
      'thermalLevel': thermal,
      'visorGgufSustainable': canSmartphoneSustainGguf(isActiveVrVisor: true),
      'companionGgufSustainable': canSmartphoneSustainGguf(
        isActiveVrVisor: false,
      ),
      'hasLoadedGgufInRam': hasLoadedGgufInRam,
      'thermalEvictionsCount': _thermalEvictionsCount,
      'localInferencesServed': _localInferencesServed,
      'lastLatencyMs': _lastInferenceLatencyMs,
      'models': modelNames,
    };
  }

  /// Handler registered on `VrDesktopBeaconStation.defaultAiInferenceHandler`
  /// so any **Estación Faro (`3D`)** serves embedded SAIA/Ollama/GGUF (text +
  /// local VLM vision when `imageBase64` is supplied) over LAN.
  Future<Map<String, Object?>> handleDesktopFaroRequest(
    Map<String, Object?> payload,
  ) async {
    final prompt = (payload['prompt'] as String?)?.trim() ?? '';
    final sys = (payload['systemPrompt'] as String?)?.trim();
    final maxTok = (payload['maxTokens'] as num?)?.toInt() ?? 200;
    final imageB64 = (payload['imageBase64'] as String?)?.trim();
    if (prompt.isEmpty || prompt.length > 16384) {
      return {'ok': false, 'error': 'invalid_prompt'};
    }

    // Multimodal vision route (`«Qué estoy viendo»`) on local Ollama VLM first!
    if (imageB64 != null &&
        imageB64.isNotEmpty &&
        imageB64.length <= 280000) {
      final vlmRes = await _tryDesktopOllamaVision(
        prompt: prompt,
        imageBase64: imageB64,
        maxTokens: maxTok,
      );
      if (vlmRes != null && vlmRes.text.isNotEmpty) {
        return <String, Object?>{
          'ok': true,
          'text': vlmRes.text,
          'engine': vlmRes.engine,
          'topology': '3D',
          'vision': true,
        };
      }
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
      final supported =
          !kIsWeb && ramMb >= minCompanionPhoneGgufRamMb && thermal < 2;
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
/// `saia_core`, `neom_ia`, and `neom_ollama` — with **zero dependency on Itzli Cloud**,
/// per-NPC short-term memory, progressive streaming, GBNF actions & local vision.
class VrEmbeddedSaiaProvider implements VrAssistantProvider {
  VrEmbeddedSaiaProvider({
    VrEmbeddedSaiaRuntime? runtime,
    this.beaconClientResolver,
    this.remoteControllerResolver,
  }) : runtime = runtime ?? VrEmbeddedSaiaRuntime.instance;

  static const int maxTrackedConversations = 16;
  static const int maxTurnsPerConversation = 4; // 4 user + 4 agent = 8 msgs
  static const int maxFaroVisionImageBytes = 192 * 1024;

  final VrEmbeddedSaiaRuntime runtime;
  final VrDesktopBeaconClient? Function()? beaconClientResolver;
  final VrRemoteControllerService? Function()? remoteControllerResolver;

  final Map<String, List<IaChatMessage>> _conversations =
      <String, List<IaChatMessage>>{};

  bool _disposed = false;
  String _lastEngineUsed = 'saia_local';

  String get lastEngineUsed => _lastEngineUsed;

  /// Returns an unmodifiable view of the short-term memory turns for [key].
  List<IaChatMessage> conversationHistoryFor(String key) =>
      List.unmodifiable(_conversations[key] ?? const <IaChatMessage>[]);

  /// Clears short-term memory for one NPC/experience or all conversations.
  void clearConversationMemory([String? key]) {
    if (key == null) {
      _conversations.clear();
    } else {
      _conversations.remove(key);
    }
  }

  void _recordTurn(String key, String userText, String assistantText) {
    final cleanUser = userText.trim();
    final cleanReply = assistantText.trim();
    if (cleanUser.isEmpty || cleanReply.isEmpty) return;
    final list = _conversations.remove(key) ?? <IaChatMessage>[];
    list
      ..add(IaChatMessage.user(cleanUser))
      ..add(IaChatMessage.agent(cleanReply));
    final maxMessages = maxTurnsPerConversation * 2;
    if (list.length > maxMessages) {
      list.removeRange(0, list.length - maxMessages);
    }
    _conversations[key] = list;
    while (_conversations.length > maxTrackedConversations) {
      _conversations.remove(_conversations.keys.first);
    }
  }

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
  Future<VrAssistantReply> respond(VrAssistantRequest request) =>
      respondStreaming(request);

  /// Executes [request] across `3D` -> `2D` -> `1D` with live progressive
  /// [onPartialText] updates, per-NPC short-term memory, GBNF JSON actions,
  /// and local multimodal image forwarding (`request.imageBytes`).
  Future<VrAssistantReply> respondStreaming(
    VrAssistantRequest request, {
    void Function(String partialText)? onPartialText,
  }) async {
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

    final convKey = request.context.experienceId;
    final history = _conversations[convKey] ?? const <IaChatMessage>[];
    final requiresActionJson = request.context.allowedActions.isNotEmpty;
    final contextJson = _buildContextJson(request, history);
    final fullPrompt = _buildLocalPrompt(
      request,
      contextJson: contextJson,
      requiresActionJson: requiresActionJson,
    );
    final compactPeerPrompt = _buildCompactPeerPrompt(request, history);

    // 1. Tier 3D — Offload to Estación Faro Computer (`neom_ollama` / VLM / `saia_gguf`)
    final beacon = beaconClientResolver?.call();
    if (beacon != null && beacon.isConnected) {
      final faroPayload = <String, Object?>{
        'prompt': fullPrompt,
        'maxTokens': 220,
      };
      if (request.hasImage &&
          request.imageBytes!.length <= maxFaroVisionImageBytes) {
        faroPayload['imageBase64'] = base64Encode(request.imageBytes!);
        faroPayload['imageMimeType'] = request.imageMimeType;
      }
      final faroRes = await beacon.requestDesktopAiInference(faroPayload);
      final faroText = faroRes?['text'];
      if (faroRes?['ok'] == true &&
          faroText is String &&
          faroText.trim().isNotEmpty) {
        _lastEngineUsed = (faroRes?['engine'] as String?) ?? 'faro_3d_saia';
        final parsed = _parseReply(faroText, request.context.allowedActions);
        if (!parsed.isError) {
          onPartialText?.call(parsed.text);
          _recordTurn(convKey, userText, parsed.text);
        }
        return parsed;
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
        final parsed = _parseReply(peerRes.text, request.context.allowedActions);
        if (!parsed.isError) {
          onPartialText?.call(parsed.text);
          _recordTurn(convKey, userText, parsed.text);
        }
        return parsed;
      }
    }

    // 3. Tier 1D — Run embedded SAIA directly on this Smartphone (or Desktop standalone)
    final isDesktopHost =
        !kIsWeb &&
        (Platform.isMacOS || Platform.isLinux || Platform.isWindows);
    final localRes = await runtime.inferLocal(
      prompt: fullPrompt,
      maxTokens: 200,
      isDesktopFaro: isDesktopHost,
      isActiveVrVisor: !isDesktopHost,
      conversationHistory: requiresActionJson ? const <IaChatMessage>[] : history,
      contextJson: contextJson,
      actionJsonSchema: requiresActionJson
          ? VrEmbeddedSaiaRuntime.buildActionJsonSchema(
              request.context.allowedActions,
            )
          : null,
      onPartialText: requiresActionJson ? null : onPartialText,
    );
    _lastEngineUsed = '1d_local:${localRes.engineLabel}';
    if (!localRes.ok || localRes.text.trim().isEmpty) {
      return VrAssistantReply(
        text: 'SAIA local no pudo generar respuesta en este momento.',
        isError: true,
      );
    }
    final parsed = _parseReply(localRes.text, request.context.allowedActions);
    if (!parsed.isError) {
      onPartialText?.call(parsed.text);
      _recordTurn(convKey, userText, parsed.text);
    }
    return parsed;
  }

  String _buildCompactPeerPrompt(
    VrAssistantRequest request,
    List<IaChatMessage> history,
  ) {
    final details = request.context.details;
    final npc = details['npc'];
    final plaza = details['plaza'] ?? request.context.title;
    final lastReply = history.isNotEmpty ? history.last.text : null;
    final memSnippet = (lastReply != null && lastReply.isNotEmpty)
        ? ' [Antes: ${lastReply.length > 90 ? "${lastReply.substring(0, 89)}…" : lastReply}]'
        : '';
    if (npc is Map) {
      final name = npc['name'] ?? 'Visitante';
      final role = npc['role'] ?? 'Explorador VR';
      final near = npc['nearestRoom'];
      return '[Plaza: $plaza${near != null ? " · Cerca de: $near" : ""} · '
          'Personaje: $name ($role)]$memSnippet ${request.text.trim()}';
    }
    return '[Sala: $plaza]$memSnippet ${request.text.trim()}';
  }

  String _buildContextJson(
    VrAssistantRequest request,
    List<IaChatMessage> history,
  ) => jsonEncode(<String, Object?>{
    'experienceId': request.context.experienceId,
    'title': request.context.title,
    'details': request.context.details,
    'allowedActions': request.context.allowedActions.toList()..sort(),
    if (request.hasImage) 'hasImage': true,
    if (history.isNotEmpty)
      'recentTurns': [
        for (final m in history.take(6))
          {'role': m.role, 'text': m.text},
      ],
    'userRequest': request.text.trim(),
  });

  String _buildLocalPrompt(
    VrAssistantRequest request, {
    required String contextJson,
    required bool requiresActionJson,
  }) {
    if (!requiresActionJson) {
      return 'Responde en español natural, cálido y conciso (2 a 3 oraciones) '
          'usando únicamente los datos de este contexto espacial VRlizate. '
          'No devuelvas bloques de código ni JSON:\n$contextJson';
    }
    return 'Eres el asistente espacial local SAIA de VRlizate. Responde en español breve. '
        'Si corresponde ejecutar una acción de allowedActions, devuelve exactamente JSON '
        '{"text":"respuesta","action":"nombreAccion","arguments":{"id":"..."}}; '
        'si es solo conversación usa {"text":"respuesta","action":"none","arguments":{}}.\n'
        '$contextJson';
  }

  VrAssistantReply _parseReply(String raw, Set<String> allowedActions) {
    final cleaned = VrEmbeddedSaiaRuntime.cleanSlmOutput(raw);
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
                (act is String &&
                    act != 'none' &&
                    allowedActions.contains(act))
                ? act
                : null;
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
    final bounded = cleaned.length <= 1600
        ? cleaned
        : '${cleaned.substring(0, 1599)}…';
    return VrAssistantReply(text: bounded);
  }

  @override
  void dispose() {
    _disposed = true;
    _conversations.clear();
  }
}
