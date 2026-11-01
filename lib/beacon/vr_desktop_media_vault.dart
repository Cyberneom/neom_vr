import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:vrlizate_apps/vrlizate_apps.dart';

import 'vr_desktop_beacon_models.dart';
import 'vr_desktop_capabilities.dart';
import 'vr_fiducial_tag_codec.dart';

/// Content category hosted in the **VRlizate Desktop Bóveda LAN (`3D-VR`)**.
enum VrVaultMediaKind {
  /// Dual-eye stereo web scene with real-time 3-node holographic parallax.
  holographic3dWeb,

  /// Multi-GB local 360° / 180° SBS / VR Cinema movie streamed via HTTP Range.
  video360OrCinema,

  /// Large `.vrlw` world streamed lazily via HTTP 206 byte ranges.
  vrlwWorld,

  /// Verified `.vrlz` package (retro, NES, worlds, scene, webgame) on PC disk;
  /// playable immediately over LAN or pinnable for `Two-Devices VR (2D-VR)`.
  vrlzPackage,

  /// Local Open-Source WebVR / Three.js / A-Frame / Godot HTML5 folder on PC.
  webVrProject,

  /// Local `.glb` / `.gltf` 3D object projected in holographic stereo.
  glbHologram;

  String get labelEs => switch (this) {
    VrVaultMediaKind.holographic3dWeb => 'Holograma Web 3D-VR (Doble Ojo)',
    VrVaultMediaKind.video360OrCinema => 'Video 360° / Cine VR (LAN Stream)',
    VrVaultMediaKind.vrlwWorld => 'Mundo .vrlw (Range Streaming)',
    VrVaultMediaKind.vrlzPackage => 'Cartucho .vrlz (LAN / Pin 2D-VR)',
    VrVaultMediaKind.webVrProject => 'Proyecto WebVR Libre (PC Local)',
    VrVaultMediaKind.glbHologram => 'Objeto 3D .glb Holográfico',
  };

  static VrVaultMediaKind fromWire(String? raw) =>
      VrVaultMediaKind.values.firstWhere(
        (v) => v.name == raw,
        orElse: () => VrVaultMediaKind.holographic3dWeb,
      );
}

/// Stereoscopic / spatial projection layout used when streaming to the Visor.
enum VrVaultStereoFormat {
  /// Asymmetric left/right frustum + 3-node Faro head/hand holographic parallax.
  holographicOffAxis3d,

  /// 360° equirectangular Side-by-Side stereo (`Left | Right`).
  equirect360Sbs,

  /// 360° equirectangular Over-Under stereo (`Top / Bottom`).
  equirect360TopBottom,

  /// 360° monoscopic equirectangular dome with stereo head tracking.
  equirect360Mono,

  /// 180° immersive Side-by-Side stereo (`VR180`).
  vr180Sbs,

  /// Side-by-Side 3D movie projected on a floating holographic cinema screen.
  cinemaSbs3d,

  /// Standard movie projected inside a 3D holographic auditorium with parallax.
  cinemaFlatIn3dRoom;

  String get labelEs => switch (this) {
    VrVaultStereoFormat.holographicOffAxis3d =>
      'Estéreo Holográfico Off-Axis (3D-VR)',
    VrVaultStereoFormat.equirect360Sbs => '360° Estéreo SBS',
    VrVaultStereoFormat.equirect360TopBottom => '360° Estéreo Top-Bottom',
    VrVaultStereoFormat.equirect360Mono => 'Domo 360° Esférico',
    VrVaultStereoFormat.vr180Sbs => 'VR 180° Estéreo SBS',
    VrVaultStereoFormat.cinemaSbs3d => 'Cine 3D SBS Holográfico',
    VrVaultStereoFormat.cinemaFlatIn3dRoom => 'Sala de Cine 3D con Paralaje',
  };

  static VrVaultStereoFormat fromWire(String? raw) =>
      VrVaultStereoFormat.values.firstWhere(
        (v) => v.name == raw,
        orElse: () => VrVaultStereoFormat.holographicOffAxis3d,
      );

  static VrVaultStereoFormat inferFromFileName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.contains('180') &&
        (lower.contains('sbs') || lower.contains('lr'))) {
      return VrVaultStereoFormat.vr180Sbs;
    }
    if (lower.contains('360') &&
        (lower.contains('tb') || lower.contains('ou'))) {
      return VrVaultStereoFormat.equirect360TopBottom;
    }
    if (lower.contains('360') &&
        (lower.contains('sbs') || lower.contains('lr'))) {
      return VrVaultStereoFormat.equirect360Sbs;
    }
    if (lower.contains('360')) {
      return VrVaultStereoFormat.equirect360Mono;
    }
    if (lower.contains('sbs') || lower.contains('3d')) {
      return VrVaultStereoFormat.cinemaSbs3d;
    }
    return VrVaultStereoFormat.cinemaFlatIn3dRoom;
  }
}

/// Immutable descriptor of one experience or media asset hosted in the PC Vault.
@immutable
class VrVaultMediaItem {
  const VrVaultMediaItem({
    required this.id,
    required this.title,
    required this.description,
    required this.kind,
    required this.stereoFormat,
    required this.requiredTier,
    required this.sizeBytes,
    required this.etag,
    required this.stereoWebUrl,
    this.streamUrl,
    this.sha256,
    this.packageId,
    this.canPinForTwoDevices2dVr = false,
  });

  final String id;
  final String title;
  final String description;
  final VrVaultMediaKind kind;
  final VrVaultStereoFormat stereoFormat;

  /// Indicates whether this item requires `Three-Devices VR (3D-VR)` (live PC
  /// holographic/LAN stream) or can also be pinned to `Two-Devices VR (2D-VR)`.
  final VrEcosystemDeviceTier requiredTier;
  final int sizeBytes;
  final String etag;

  /// Direct capability URL for the Dual-Eye Stereo Web Projector (`/stereo/<id>`).
  final Uri stereoWebUrl;

  /// Optional raw byte-range capability URL (`/files/<id>`) for `.vrlw`, `.vrlz`,
  /// `.glb`, or video files.
  final Uri? streamUrl;

  /// Hex SHA-256 when precomputed (e.g. `.vrlz` packages for verified catalog).
  final String? sha256;

  /// Canonical `.vrlz` package ID when [kind] is [VrVaultMediaKind.vrlzPackage].
  final String? packageId;

  /// True when the Smartphone Visor can copy this package locally for portable
  /// `Two-Devices VR (2D-VR)` sessions away from the Computer.
  final bool canPinForTwoDevices2dVr;

  String get formattedSize {
    if (sizeBytes <= 0) return 'Web 3D en vivo';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
    }
    if (sizeBytes < 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'kind': kind.name,
    'stereoFormat': stereoFormat.name,
    'requiredTier': requiredTier.shortCode,
    'sizeBytes': sizeBytes,
    'etag': etag,
    'stereoWebUrl': stereoWebUrl.toString(),
    if (streamUrl != null) 'streamUrl': streamUrl.toString(),
    if (sha256 != null) 'sha256': sha256,
    if (packageId != null) 'packageId': packageId,
    'canPin2dVr': canPinForTwoDevices2dVr,
  };

  static VrVaultMediaItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'] as String?;
    final title = raw['title'] as String?;
    final stereoRaw = raw['stereoWebUrl'] as String?;
    if (id == null ||
        id.isEmpty ||
        title == null ||
        title.isEmpty ||
        stereoRaw == null) {
      return null;
    }
    final stereoUri = Uri.tryParse(stereoRaw);
    if (stereoUri == null) return null;
    final streamRaw = raw['streamUrl'] as String?;
    return VrVaultMediaItem(
      id: id,
      title: title,
      description: (raw['description'] as String?) ?? '',
      kind: VrVaultMediaKind.fromWire(raw['kind'] as String?),
      stereoFormat: VrVaultStereoFormat.fromWire(
        raw['stereoFormat'] as String?,
      ),
      requiredTier: VrEcosystemDeviceTier.fromWire(
        raw['requiredTier'] as String?,
      ),
      sizeBytes: ((raw['sizeBytes'] as num?)?.toInt() ?? 0).clamp(
        0,
        1 << 42,
      ),
      etag: (raw['etag'] as String?) ?? '"v1"',
      stereoWebUrl: stereoUri,
      streamUrl: streamRaw != null ? Uri.tryParse(streamRaw) : null,
      sha256: raw['sha256'] as String?,
      packageId: raw['packageId'] as String?,
      canPinForTwoDevices2dVr: raw['canPin2dVr'] == true,
    );
  }
}

/// Complete catalog snapshot returned by the Desktop Bóveda LAN (`3D-VR`).
@immutable
class VrVaultCatalogSnapshot {
  const VrVaultCatalogSnapshot({
    required this.stationId,
    required this.stationName,
    required this.ecosystemTier,
    required this.desktopTier,
    required this.webLibraryUrl,
    required this.vrlzIndexUrl,
    required this.poseApiUrl,
    required this.items,
  });

  final String stationId;
  final String stationName;
  final VrEcosystemDeviceTier ecosystemTier;
  final VrDesktopComputeTier desktopTier;
  final Uri webLibraryUrl;
  final Uri vrlzIndexUrl;
  final Uri poseApiUrl;
  final List<VrVaultMediaItem> items;

  Map<String, Object?> toJson() => {
    'formatVersion': 1,
    'stationId': stationId,
    'stationName': stationName,
    'ecosystemTier': ecosystemTier.shortCode,
    'desktopTier': desktopTier.name,
    'webLibraryUrl': webLibraryUrl.toString(),
    'vrlzIndexUrl': vrlzIndexUrl.toString(),
    'poseApiUrl': poseApiUrl.toString(),
    'items': [for (final item in items) item.toJson()],
  };

  static VrVaultCatalogSnapshot? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final stationId = raw['stationId'] as String?;
    final stationName = raw['stationName'] as String?;
    final webRaw = raw['webLibraryUrl'] as String?;
    final vrlzRaw = raw['vrlzIndexUrl'] as String?;
    final poseRaw = raw['poseApiUrl'] as String?;
    final rawItems = raw['items'];
    if (stationId == null ||
        stationName == null ||
        webRaw == null ||
        vrlzRaw == null ||
        poseRaw == null ||
        rawItems is! List) {
      return null;
    }
    final webUri = Uri.tryParse(webRaw);
    final vrlzUri = Uri.tryParse(vrlzRaw);
    final poseUri = Uri.tryParse(poseRaw);
    if (webUri == null || vrlzUri == null || poseUri == null) return null;
    final parsedItems = <VrVaultMediaItem>[];
    for (final entry in rawItems) {
      final item = VrVaultMediaItem.fromJson(entry);
      if (item != null) parsedItems.add(item);
    }
    final tierRaw = raw['desktopTier'] as String?;
    final desktopTier = VrDesktopComputeTier.values.firstWhere(
      (t) => t.name == tierRaw,
      orElse: () => VrDesktopComputeTier.sensorAndAiBridge,
    );
    return VrVaultCatalogSnapshot(
      stationId: stationId,
      stationName: stationName,
      ecosystemTier: VrEcosystemDeviceTier.fromWire(
        raw['ecosystemTier'] as String?,
      ),
      desktopTier: desktopTier,
      webLibraryUrl: webUri,
      vrlzIndexUrl: vrlzUri,
      poseApiUrl: poseUri,
      items: List.unmodifiable(parsedItems),
    );
  }
}

class _VaultStoredRecord {
  _VaultStoredRecord({
    required this.id,
    required this.title,
    required this.description,
    required this.kind,
    required this.stereoFormat,
    required this.requiredTier,
    required this.sizeBytes,
    required this.etag,
    this.filePath,
    this.projectDirPath,
    this.mimeType = 'application/octet-stream',
    this.sha256,
    this.packageId,
    this.builtInSceneKey,
    this.canPinForTwoDevices2dVr = false,
  });

  final String id;
  final String title;
  final String description;
  final VrVaultMediaKind kind;
  final VrVaultStereoFormat stereoFormat;
  final VrEcosystemDeviceTier requiredTier;
  final int sizeBytes;
  final String etag;
  final String? filePath;
  final String? projectDirPath;
  final String mimeType;
  final String? sha256;
  final String? packageId;
  final String? builtInSceneKey;
  final bool canPinForTwoDevices2dVr;
}

/// Authenticated LAN Media Vault & Dual-Eye Holographic Web Projector running on
/// **VRlizate Desktop (`Three-Devices VR · 3D-VR`)**.
///
/// Serves:
/// - Multi-GB `360°` / `180° SBS` / Cinema videos via zero-copy HTTP `206`
///   byte-range streaming (`0 MB` used on the Smartphone Visor).
/// - `.vrlw` worlds via strong-ETag HTTP `206` ranges ([VrlwHttpSource]-ready).
/// - `.vrlz` packages via verified SHA-256 catalog (`/api/vrlz-index.json`),
///   playable over LAN or pinnable for portable `Two-Devices VR (2D-VR)` trips.
/// - Local Web Library (`/web`) & Dual-Eye Holographic Stereo Stream
///   (`/stereo/<id>`) with real-time 60 Hz 3-node head/hand parallax!
class VrDesktopMediaVaultServer extends ChangeNotifier {
  VrDesktopMediaVaultServer({
    this.stationId = 'faro_vault',
    this.stationName = 'VRlizate Desktop Faro',
    this.bindPort = 0,
    this.vaultDirectoryPath,
    this.poseProvider,
    this.capabilitiesProvider,
    this.coordinatorTelemetryProvider,
    this.onPushToVisor,
    this.onVoiceCommandApi,
    this.onSimulateExpressionApi,
  }) : _vaultToken = _generateCapabilityToken();

  final String stationId;
  final String stationName;
  final int bindPort;
  final String? vaultDirectoryPath;
  final VrTriNodeDepthSolution? Function()? poseProvider;
  final VrDesktopCapabilities? Function()? capabilitiesProvider;
  final Map<String, Object?> Function()? coordinatorTelemetryProvider;
  final void Function(VrVaultMediaItem item)? onPushToVisor;
  final Map<String, Object?> Function(String text, String source)?
  onVoiceCommandApi;
  final Map<String, Object?> Function(String expressionName)?
  onSimulateExpressionApi;

  HttpServer? _server;
  StreamSubscription<HttpRequest>? _sub;
  String _vaultToken;
  String _preferredLanHost = '127.0.0.1';
  bool _disposed = false;
  String? _activeVaultDirectory;
  String? _lastPushedItemId;
  int _pushedSeq = 0;

  final Map<String, _VaultStoredRecord> _records = {};

  bool get isRunning => _server != null;
  int? get boundPort => _server?.port;
  String get vaultToken => _vaultToken;
  String? get activeVaultDirectory => _activeVaultDirectory;
  String? get lastPushedItemId => _lastPushedItemId;
  int get pushedSequence => _pushedSeq;

  /// Capability base URI reachable from the Smartphone Visor on the same LAN.
  Uri? get lanBaseUri {
    final port = boundPort;
    if (port == null) return null;
    return Uri.parse('http://$_preferredLanHost:$port/$_vaultToken/');
  }

  /// Localhost capability URI for opening the Desktop Web Library on the PC.
  Uri? get localWebLibraryUri {
    final port = boundPort;
    if (port == null) return null;
    return Uri.parse('http://127.0.0.1:$port/$_vaultToken/web');
  }

  Uri? get lanCatalogUri => lanBaseUri?.resolve('api/catalog.json');
  Uri? get lanVrlzIndexUri => lanBaseUri?.resolve('api/vrlz-index.json');
  Uri? get lanWebLibraryUri => lanBaseUri?.resolve('web');
  Uri? get lanPrintableTagsUri => lanBaseUri?.resolve('tags');

  /// Localhost capability URI for printing the 1:1 millimeter 6-DoF tag sheet.
  Uri? get localPrintableTagsUri {
    final port = boundPort;
    if (port == null) return null;
    return Uri.parse('http://127.0.0.1:$port/$_vaultToken/tags');
  }

  List<VrVaultMediaItem> get items {
    final base =
        lanBaseUri ?? Uri.parse('http://127.0.0.1:0/$_vaultToken/');
    return List.unmodifiable([
      for (final rec in _records.values) _toPublicItem(rec, base),
    ]);
  }

  void updatePreferredLanHost(String host) {
    final trimmed = host.trim();
    if (trimmed.isEmpty || trimmed == _preferredLanHost) return;
    _preferredLanHost = trimmed;
    if (!_disposed) notifyListeners();
  }

  /// Rotates the capability path token (e.g. when regenerating the Faro PIN).
  void rotateToken() {
    _vaultToken = _generateCapabilityToken();
    if (!_disposed) notifyListeners();
  }

  static String _generateCapabilityToken() {
    final rng = math.Random.secure();
    final bytes = List<int>.generate(24, (_) => rng.nextInt(256));
    return 'vlt_${base64UrlEncode(bytes).replaceAll('=', '')}';
  }

  Future<void> start({String? preferredLanHost}) async {
    if (_disposed || _server != null || kIsWeb) return;
    if (preferredLanHost != null && preferredLanHost.trim().isNotEmpty) {
      _preferredLanHost = preferredLanHost.trim();
    }
    _installBuiltIn3dVrExperiences();

    final configuredDir = vaultDirectoryPath ?? _defaultDesktopVaultDirPath();
    if (configuredDir != null) {
      _activeVaultDirectory = configuredDir;
      await scanDirectory(configuredDir, notify: false);
    }

    _server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      bindPort,
      shared: false,
    );
    _sub = _server!.listen((req) => unawaited(_handleRequest(req)));
    if (!_disposed) notifyListeners();
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await _server?.close(force: true);
    _server = null;
    if (!_disposed) notifyListeners();
  }

  static String? _defaultDesktopVaultDirPath() {
    if (kIsWeb) return null;
    try {
      final home =
          Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      if (home == null || home.trim().isEmpty) return null;
      return Uri.directory(home)
          .resolve('Documents/VRlizate/Boveda/')
          .toFilePath();
    } catch (_) {
      return null;
    }
  }

  void _installBuiltIn3dVrExperiences() {
    _records['holo_prism_chamber_3d'] = _VaultStoredRecord(
      id: 'holo_prism_chamber_3d',
      title: 'Cámara Holográfica 3D-VR (Paralaje Faro)',
      description:
          'Escena volumétrica en doble ojo con paralaje off-axis guiado en vivo por tu cabeza y manos frente a la PC.',
      kind: VrVaultMediaKind.holographic3dWeb,
      stereoFormat: VrVaultStereoFormat.holographicOffAxis3d,
      requiredTier: VrEcosystemDeviceTier.threeDevices3dVr,
      sizeBytes: 0,
      etag: '"builtin-holo-prism-v1"',
      builtInSceneKey: 'prism',
    );
    _records['holo_solar_orrery_3d'] = _VaultStoredRecord(
      id: 'holo_solar_orrery_3d',
      title: 'Planetario Volumétrico Open-Source (3D-VR)',
      description:
          'Sistema planetario holográfico donde acercarte o moverte frente al monitor desplaza la profundidad binocular en el Visor.',
      kind: VrVaultMediaKind.holographic3dWeb,
      stereoFormat: VrVaultStereoFormat.holographicOffAxis3d,
      requiredTier: VrEcosystemDeviceTier.threeDevices3dVr,
      sizeBytes: 0,
      etag: '"builtin-holo-orrery-v1"',
      builtInSceneKey: 'orrery',
    );
    _records['holo_cinema_dome_3d'] = _VaultStoredRecord(
      id: 'holo_cinema_dome_3d',
      title: 'Domo Holográfico IMAX & Calibrador 360°',
      description:
          'Auditorio estéreo curvo 3D-VR proyectado desde la computadora hacia ambos ojos del Smartphone Visor.',
      kind: VrVaultMediaKind.holographic3dWeb,
      stereoFormat: VrVaultStereoFormat.holographicOffAxis3d,
      requiredTier: VrEcosystemDeviceTier.threeDevices3dVr,
      sizeBytes: 0,
      etag: '"builtin-holo-dome-v1"',
      builtInSceneKey: 'dome',
    );
  }

  /// Scans a directory on the Computer for `.mp4`/`.webm`/`.mov`/`.mkv` 360° &
  /// Cinema videos, `.vrlw` worlds, `.vrlz`/`.vrz` packages, `.glb` holograms,
  /// and WebVR project subdirectories containing `index.html`.
  Future<int> scanDirectory(String? directoryPath, {bool notify = true}) async {
    if (kIsWeb) return 0;
    final targetPath = directoryPath ?? _activeVaultDirectory;
    if (targetPath == null || targetPath.trim().isEmpty) return 0;
    _activeVaultDirectory = targetPath;
    final dir = Directory(targetPath);
    if (!await dir.exists()) {
      if (notify && !_disposed) notifyListeners();
      return 0;
    }

    var added = 0;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File) {
        final item = await registerLocalFile(entity.path, notify: false);
        if (item != null) added++;
      } else if (entity is Directory) {
        final indexHtml = File(
          Uri.directory(entity.path).resolve('index.html').toFilePath(),
        );
        if (await indexHtml.exists()) {
          final item = await registerWebProjectDirectory(
            entity.path,
            notify: false,
          );
          if (item != null) added++;
        }
      }
    }
    if (notify && !_disposed) notifyListeners();
    return added;
  }

  /// Registers a single local file from the Computer's disk without copying it
  /// into memory (supports multi-GB `4K`/`8K` 360° movies and `.vrlw` worlds).
  Future<VrVaultMediaItem?> registerLocalFile(
    String filePath, {
    String? title,
    String? description,
    VrVaultStereoFormat? stereoFormatOverride,
    bool notify = true,
  }) async {
    if (kIsWeb) return null;
    final file = File(filePath);
    if (!await file.exists()) return null;
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file || stat.size <= 0) return null;

    final fileName = file.uri.pathSegments.lastWhere(
      (s) => s.isNotEmpty,
      orElse: () => 'item',
    );
    final lower = fileName.toLowerCase();
    final stem = _humanTitleFromFileName(fileName);
    final idSlug = _stableSlug('${file.path}:${stat.size}');
    final strongEtag =
        '"${_shortHexHash('${file.path}:${stat.size}:${stat.modified.millisecondsSinceEpoch}')}"';

    _VaultStoredRecord? record;

    if (lower.endsWith('.mp4') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.mkv')) {
      final fmt =
          stereoFormatOverride ?? VrVaultStereoFormat.inferFromFileName(fileName);
      record = _VaultStoredRecord(
        id: 'vid_$idSlug',
        title: title ?? stem,
        description:
            description ??
            '${fmt.labelEs} · Streaming directo desde disco de PC sin ocupar espacio en el celular.',
        kind: VrVaultMediaKind.video360OrCinema,
        stereoFormat: fmt,
        requiredTier: VrEcosystemDeviceTier.threeDevices3dVr,
        sizeBytes: stat.size,
        etag: strongEtag,
        filePath: file.path,
        mimeType: _videoMimeType(lower),
      );
    } else if (lower.endsWith('.vrlw')) {
      record = _VaultStoredRecord(
        id: 'vrlw_$idSlug',
        title: title ?? stem,
        description:
            description ??
            'Mundo .vrlw alojado en PC · lectura selectiva por HTTP 206 Range.',
        kind: VrVaultMediaKind.vrlwWorld,
        stereoFormat: VrVaultStereoFormat.holographicOffAxis3d,
        requiredTier: VrEcosystemDeviceTier.threeDevices3dVr,
        sizeBytes: stat.size,
        etag: strongEtag,
        filePath: file.path,
        mimeType: 'application/octet-stream',
      );
    } else if (lower.endsWith('.vrlz') || lower.endsWith('.vrz')) {
      if (stat.size <= VrlzPackage.maxBytes) {
        try {
          final bytes = await file.readAsBytes();
          final digest = crypto.sha256.convert(bytes).toString();
          final pkg = VrlzPackage.decode(bytes);
          record = _VaultStoredRecord(
            id: 'pkg_$idSlug',
            title: title ?? pkg.title,
            description: description ??
                (pkg.description.isNotEmpty
                    ? pkg.description
                    : 'Paquete .vrlz verificado en Bóveda PC · jugable en LAN o fijable para 2D-VR.'),
            kind: VrVaultMediaKind.vrlzPackage,
            stereoFormat: VrVaultStereoFormat.holographicOffAxis3d,
            requiredTier: VrEcosystemDeviceTier.twoDevices2dVr,
            sizeBytes: bytes.length,
            etag: '"$digest"',
            filePath: file.path,
            mimeType: 'application/octet-stream',
            sha256: digest,
            packageId: pkg.id,
            canPinForTwoDevices2dVr: true,
          );
        } catch (_) {
          return null;
        }
      }
    } else if (lower.endsWith('.glb') || lower.endsWith('.gltf')) {
      record = _VaultStoredRecord(
        id: 'glb_$idSlug',
        title: title ?? stem,
        description:
            description ??
            'Modelo 3D proyectado con paralaje holográfico en doble ojo hacia el Visor.',
        kind: VrVaultMediaKind.glbHologram,
        stereoFormat: VrVaultStereoFormat.holographicOffAxis3d,
        requiredTier: VrEcosystemDeviceTier.threeDevices3dVr,
        sizeBytes: stat.size,
        etag: strongEtag,
        filePath: file.path,
        mimeType: lower.endsWith('.glb')
            ? 'model/gltf-binary'
            : 'model/gltf+json',
      );
    }

    if (record == null) return null;
    _records[record.id] = record;
    if (notify && !_disposed) notifyListeners();
    final base =
        lanBaseUri ?? Uri.parse('http://127.0.0.1:0/$_vaultToken/');
    return _toPublicItem(record, base);
  }

  /// Registers a local WebVR / HTML5 / Three.js / Godot Web export folder on PC.
  Future<VrVaultMediaItem?> registerWebProjectDirectory(
    String directoryPath, {
    String? title,
    String? description,
    bool notify = true,
  }) async {
    if (kIsWeb) return null;
    final dir = Directory(directoryPath);
    if (!await dir.exists()) return null;
    final indexFile = File(
      Uri.directory(dir.path).resolve('index.html').toFilePath(),
    );
    if (!await indexFile.exists()) return null;

    final folderName = dir.uri.pathSegments.lastWhere(
      (s) => s.isNotEmpty,
      orElse: () => 'webvr_project',
    );
    final idSlug = _stableSlug(dir.path);
    final record = _VaultStoredRecord(
      id: 'web_$idSlug',
      title: title ?? _humanTitleFromFileName(folderName),
      description:
          description ??
          'Proyecto WebVR Open-Source servido desde la computadora en modo 3D-VR.',
      kind: VrVaultMediaKind.webVrProject,
      stereoFormat: VrVaultStereoFormat.holographicOffAxis3d,
      requiredTier: VrEcosystemDeviceTier.threeDevices3dVr,
      sizeBytes: 0,
      etag: '"${_shortHexHash(dir.path)}"',
      projectDirPath: dir.path,
      mimeType: 'text/html; charset=utf-8',
    );
    _records[record.id] = record;
    if (notify && !_disposed) notifyListeners();
    final base =
        lanBaseUri ?? Uri.parse('http://127.0.0.1:0/$_vaultToken/');
    return _toPublicItem(record, base);
  }

  /// Commands the paired Smartphone Visor to immediately open [itemId] in
  /// Dual-Eye `Three-Devices VR (3D-VR)` mode.
  bool pushItemToVisor(String itemId) {
    final record = _records[itemId];
    if (record == null) return false;
    _lastPushedItemId = itemId;
    _pushedSeq++;
    final base =
        lanBaseUri ?? Uri.parse('http://127.0.0.1:0/$_vaultToken/');
    onPushToVisor?.call(_toPublicItem(record, base));
    if (!_disposed) notifyListeners();
    return true;
  }

  VrVaultMediaItem _toPublicItem(_VaultStoredRecord rec, Uri base) {
    final hasRawFile = rec.filePath != null;
    return VrVaultMediaItem(
      id: rec.id,
      title: rec.title,
      description: rec.description,
      kind: rec.kind,
      stereoFormat: rec.stereoFormat,
      requiredTier: rec.requiredTier,
      sizeBytes: rec.sizeBytes,
      etag: rec.etag,
      stereoWebUrl: base.resolve('stereo/${rec.id}'),
      streamUrl: hasRawFile ? base.resolve('files/${rec.id}') : null,
      sha256: rec.sha256,
      packageId: rec.packageId,
      canPinForTwoDevices2dVr: rec.canPinForTwoDevices2dVr,
    );
  }

  VrVaultCatalogSnapshot buildCatalogSnapshot({Uri? requestBaseOverride}) {
    final base =
        requestBaseOverride ??
        lanBaseUri ??
        Uri.parse('http://127.0.0.1:${boundPort ?? 0}/$_vaultToken/');
    final caps = capabilitiesProvider?.call();
    return VrVaultCatalogSnapshot(
      stationId: stationId,
      stationName: stationName,
      ecosystemTier: VrEcosystemDeviceTier.threeDevices3dVr,
      desktopTier: caps?.computeTier ?? VrDesktopComputeTier.sensorAndAiBridge,
      webLibraryUrl: base.resolve('web'),
      vrlzIndexUrl: base.resolve('api/vrlz-index.json'),
      poseApiUrl: base.resolve('api/pose.json'),
      items: [for (final rec in _records.values) _toPublicItem(rec, base)],
    );
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    try {
      _applyCorsHeaders(response);
      if (request.method == 'OPTIONS') {
        response.statusCode = HttpStatus.noContent;
        return;
      }

      final segments = request.uri.pathSegments
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
      if (segments.isEmpty || segments.first != _vaultToken) {
        response.statusCode = HttpStatus.forbidden;
        response.write('Acceso denegado: token de Bóveda LAN inválido.');
        return;
      }

      final hostHeader =
          request.headers.value(HttpHeaders.hostHeader) ??
          '$_preferredLanHost:${boundPort ?? 0}';
      final requestBase = Uri.parse('http://$hostHeader/$_vaultToken/');
      final sub = segments.sublist(1);

      if (sub.isEmpty || (sub.length == 1 && sub.first == 'web')) {
        _serveWebLibraryHtml(response, requestBase);
        return;
      }

      if (sub.length == 1 && sub.first == 'tags') {
        final html = VrFiducialTagCodec.buildPrintableSheetHtml(
          stationName: stationName,
        );
        final bytes = utf8.encode(html);
        response.statusCode = HttpStatus.ok;
        response.headers.set(
          HttpHeaders.contentTypeHeader,
          'text/html; charset=utf-8',
        );
        response.contentLength = bytes.length;
        if (request.method == 'GET') {
          response.add(bytes);
        }
        return;
      }

      if (sub.length == 2 && sub[0] == 'api' && sub[1] == 'catalog.json') {
        final snapshot = buildCatalogSnapshot(requestBaseOverride: requestBase);
        _sendJson(response, snapshot.toJson());
        return;
      }

      if (sub.length == 2 && sub[0] == 'api' && sub[1] == 'vrlz-index.json') {
        final packages = <Map<String, Object?>>[];
        for (final rec in _records.values) {
          if (rec.kind == VrVaultMediaKind.vrlzPackage &&
              rec.packageId != null &&
              rec.sha256 != null) {
            packages.add({
              'id': rec.packageId!,
              'title': rec.title.length <= 80
                  ? rec.title
                  : rec.title.substring(0, 80),
              'url': requestBase.resolve('files/${rec.id}').toString(),
              'sha256': rec.sha256!,
            });
          }
        }
        _sendJson(response, {'formatVersion': 1, 'packages': packages});
        return;
      }

      if (sub.length == 2 && sub[0] == 'api' && sub[1] == 'pose.json') {
        final sol = poseProvider?.call();
        final caps = capabilitiesProvider?.call();
        final coord = coordinatorTelemetryProvider?.call();
        _sendJson(response, {
          'ecosystemTier': '3D-VR',
          'desktopTier': (caps?.computeTier ??
                  VrDesktopComputeTier.sensorAndAiBridge)
              .name,
          if (coord != null) ...coord,
          if (sol != null) ...{
            'seq': sol.sequence,
            'head': {
              'x': sol.visorRoomPosition.x,
              'y': sol.visorRoomPosition.y,
              'z': sol.visorRoomPosition.z,
            },
            'deskClearanceM': sol.deskClearanceMeters,
            'gesture': sol.gesture.name,
            'facialExpression': sol.facialExpression.name,
            'facialConfidence': double.parse(
              sol.facialConfidence.toStringAsFixed(2),
            ),
            'visorFiducialLocked': sol.visorFiducialLocked,
            'joystickFiducialLocked': sol.joystickFiducialLocked,
            if (sol.estimatedUserIpdMeters != null)
              'estimatedIpdMm': double.parse(
                (sol.estimatedUserIpdMeters! * 1000.0).toStringAsFixed(1),
              ),
            'leftHand': {
              'visible': sol.leftHandConfidence >= 0.25,
              'x': sol.leftHandRelHead.x,
              'y': sol.leftHandRelHead.y,
              'z': sol.leftHandRelHead.z,
              'pinch': sol.leftPinchStrength >= 0.65,
            },
            'rightHand': {
              'visible': sol.rightHandConfidence >= 0.25,
              'x': sol.rightHandRelHead.x,
              'y': sol.rightHandRelHead.y,
              'z': sol.rightHandRelHead.z,
              'pinch': sol.rightPinchStrength >= 0.65,
            },
          } else ...{
            'seq': 0,
            'head': {'x': 0.0, 'y': 1.60, 'z': 0.0},
            'deskClearanceM': 1.35,
            'gesture': 'none',
          },
        });
        return;
      }

      if (sub.length == 3 &&
          sub[0] == 'api' &&
          sub[1] == 'push' &&
          request.method == 'POST') {
        final ok = pushItemToVisor(sub[2]);
        _sendJson(
          response,
          {'ok': ok, 'pushedItemId': sub[2], 'seq': _pushedSeq},
          status: ok ? HttpStatus.ok : HttpStatus.notFound,
        );
        return;
      }

      if (sub.length == 2 &&
          sub[0] == 'api' &&
          sub[1] == 'voice' &&
          request.method == 'POST') {
        var text = (request.uri.queryParameters['text'] ?? '').trim();
        var source = (request.uri.queryParameters['source'] ?? 'http_api')
            .trim();
        if (text.isEmpty) {
          final rawBody = await utf8.decoder
              .bind(request)
              .join()
              .timeout(const Duration(seconds: 2), onTimeout: () => '');
          if (rawBody.trim().isNotEmpty) {
            try {
              final decoded = jsonDecode(rawBody);
              if (decoded is Map) {
                text = ((decoded['text'] as String?) ?? '').trim();
                source = ((decoded['source'] as String?) ?? source).trim();
              }
            } catch (_) {
              text = rawBody.trim();
            }
          }
        }
        if (text.isEmpty || onVoiceCommandApi == null) {
          _sendJson(
            response,
            {'ok': false, 'error': 'missing_text_or_handler'},
            status: HttpStatus.badRequest,
          );
          return;
        }
        final result = onVoiceCommandApi!(text, source);
        _sendJson(response, result);
        return;
      }

      if (sub.length == 2 &&
          sub[0] == 'api' &&
          sub[1] == 'expression' &&
          request.method == 'POST') {
        var expr = (request.uri.queryParameters['expression'] ?? '').trim();
        if (expr.isEmpty) {
          final rawBody = await utf8.decoder
              .bind(request)
              .join()
              .timeout(const Duration(seconds: 2), onTimeout: () => '');
          if (rawBody.trim().isNotEmpty) {
            try {
              final decoded = jsonDecode(rawBody);
              if (decoded is Map) {
                expr = ((decoded['expression'] as String?) ?? '').trim();
              }
            } catch (_) {
              expr = rawBody.trim();
            }
          }
        }
        if (onSimulateExpressionApi == null) {
          _sendJson(
            response,
            {'ok': false, 'error': 'missing_handler'},
            status: HttpStatus.badRequest,
          );
          return;
        }
        final result = onSimulateExpressionApi!(expr);
        _sendJson(response, result);
        return;
      }

      if (sub.length == 2 && sub[0] == 'stereo') {
        final rec = _records[sub[1]];
        if (rec == null) {
          response.statusCode = HttpStatus.notFound;
          return;
        }
        _serveDualEyeStereoHtml(response, rec, requestBase);
        return;
      }

      if (sub.length == 2 && sub[0] == 'files') {
        final rec = _records[sub[1]];
        if (rec == null || rec.filePath == null) {
          response.statusCode = HttpStatus.notFound;
          return;
        }
        await _serveFileWithByteRanges(request, response, rec);
        return;
      }

      if (sub.length >= 2 && sub[0] == 'projects') {
        final rec = _records[sub[1]];
        if (rec == null || rec.projectDirPath == null) {
          response.statusCode = HttpStatus.notFound;
          return;
        }
        final relParts = sub.length > 2 ? sub.sublist(2) : const ['index.html'];
        await _serveProjectAsset(request, response, rec.projectDirPath!, relParts);
        return;
      }

      response.statusCode = HttpStatus.notFound;
    } catch (_) {
      try {
        response.statusCode = HttpStatus.internalServerError;
      } catch (_) {}
    } finally {
      try {
        await response.close();
      } catch (_) {}
    }
  }

  Future<void> _serveFileWithByteRanges(
    HttpRequest request,
    HttpResponse response,
    _VaultStoredRecord rec,
  ) async {
    if (request.method != 'GET' && request.method != 'HEAD') {
      response.statusCode = HttpStatus.methodNotAllowed;
      return;
    }
    final file = File(rec.filePath!);
    if (!await file.exists()) {
      response.statusCode = HttpStatus.notFound;
      return;
    }
    final total = await file.length();
    if (total <= 0) {
      response.statusCode = HttpStatus.notFound;
      return;
    }

    final ifMatch = request.headers.value(HttpHeaders.ifMatchHeader)?.trim();
    if (ifMatch != null && ifMatch != '*' && ifMatch != rec.etag) {
      response.statusCode = HttpStatus.preconditionFailed;
      return;
    }

    response.headers
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..set(HttpHeaders.etagHeader, rec.etag)
      ..set(HttpHeaders.contentEncodingHeader, 'identity')
      ..set(HttpHeaders.contentTypeHeader, rec.mimeType)
      ..set(HttpHeaders.cacheControlHeader, 'private, no-transform');

    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader)?.trim();
    if (rangeHeader == null || rangeHeader.isEmpty) {
      response.statusCode = HttpStatus.ok;
      response.contentLength = total;
      if (request.method == 'GET') {
        await response.addStream(file.openRead());
      }
      return;
    }

    final match = RegExp(r'^bytes=([0-9]+)-([0-9]*)$').firstMatch(rangeHeader);
    if (match == null) {
      response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
      return;
    }
    final start = int.tryParse(match.group(1)!);
    final endRaw = match.group(2)!;
    final end = endRaw.isEmpty ? (total - 1) : int.tryParse(endRaw);
    if (start == null ||
        end == null ||
        start < 0 ||
        end < start ||
        start >= total) {
      response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
      return;
    }
    final clampedEnd = math.min(end, total - 1);
    final sliceLength = clampedEnd - start + 1;

    response.statusCode = HttpStatus.partialContent;
    response.headers.set(
      HttpHeaders.contentRangeHeader,
      'bytes $start-$clampedEnd/$total',
    );
    response.contentLength = sliceLength;
    if (request.method == 'GET') {
      await response.addStream(file.openRead(start, clampedEnd + 1));
    }
  }

  Future<void> _serveProjectAsset(
    HttpRequest request,
    HttpResponse response,
    String rootDirPath,
    List<String> relParts,
  ) async {
    if (request.method != 'GET' && request.method != 'HEAD') {
      response.statusCode = HttpStatus.methodNotAllowed;
      return;
    }
    if (relParts.any(
      (part) => part.isEmpty || part == '.' || part == '..' || part.contains('\\'),
    )) {
      response.statusCode = HttpStatus.forbidden;
      return;
    }
    final rootDir = Directory(rootDirPath).absolute;
    final candidatePath = Uri.directory(
      rootDir.path,
    ).resolve(relParts.join('/')).toFilePath();
    final candidate = File(candidatePath).absolute;
    if (!candidate.path.startsWith(rootDir.path) || !await candidate.exists()) {
      response.statusCode = HttpStatus.notFound;
      return;
    }
    final len = await candidate.length();
    response.statusCode = HttpStatus.ok;
    response.headers
      ..set(HttpHeaders.contentTypeHeader, _projectAssetMime(candidate.path))
      ..set('Cross-Origin-Opener-Policy', 'same-origin')
      ..set('Cross-Origin-Embedder-Policy', 'require-corp');
    response.contentLength = len;
    if (request.method == 'GET') {
      await response.addStream(candidate.openRead());
    }
  }

  void _applyCorsHeaders(HttpResponse response) {
    response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, HEAD, POST, OPTIONS')
      ..set('Access-Control-Allow-Headers', 'Range, If-Match, Content-Type')
      ..set(
        'Access-Control-Expose-Headers',
        'Content-Range, Content-Encoding, ETag, Accept-Ranges, Content-Length',
      );
  }

  void _sendJson(
    HttpResponse response,
    Map<String, Object?> payload, {
    int status = HttpStatus.ok,
  }) {
    final bytes = utf8.encode(jsonEncode(payload));
    response.statusCode = status;
    response.headers
      ..set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8')
      ..set(HttpHeaders.cacheControlHeader, 'no-store');
    response.contentLength = bytes.length;
    response.add(bytes);
  }

  void _serveWebLibraryHtml(HttpResponse response, Uri requestBase) {
    final snapshot = buildCatalogSnapshot(requestBaseOverride: requestBase);
    final initialJson = jsonEncode(snapshot.toJson())
        .replaceAll('</', '<\\/');
    final html = '''<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>VRlizate Bóveda LAN · 2D-VR ↔ 3D-VR</title>
<style>
  :root{color-scheme:dark;--bg:#070b14;--card:#0e1729;--cyan:#00e5ff;--purple:#9e77ed;--green:#12b76a;--txt:#e8f1ff;--muted:#93a8c9;}
  *{box-sizing:border-box;margin:0;padding:0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;}
  body{background:radial-gradient(circle at top right,#132347,#070b14 60%);color:var(--txt);padding:24px;min-height:100vh;}
  .top{display:flex;flex-wrap:wrap;gap:14px;align-items:center;justify-content:space-between;background:rgba(14,23,41,.88);border:1px solid rgba(0,229,255,.28);border-radius:16px;padding:18px 22px;margin-bottom:20px;}
  .badge{display:inline-flex;align-items:center;gap:8px;padding:5px 12px;border-radius:99px;font-size:12px;font-weight:700;background:rgba(0,229,255,.14);border:1px solid var(--cyan);color:var(--cyan);}
  .tier-row{display:flex;gap:10px;flex-wrap:wrap;margin-top:8px;font-size:13px;color:var(--muted);}
  .pose-pill{font-family:ui-monospace,monospace;font-size:12px;background:#09101f;padding:10px 14px;border-radius:12px;border:1px solid rgba(158,119,237,.35);color:#d6bbfb;}
  .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(310px,1fr));gap:16px;}
  .card{background:var(--card);border:1px solid rgba(255,255,255,.09);border-radius:16px;padding:18px;display:flex;flex-direction:column;gap:10px;}
  .kind{font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.6px;color:var(--cyan);}
  .title{font-size:17px;font-weight:700;}
  .desc{font-size:13px;color:var(--muted);line-height:1.45;flex:1;}
  .meta{font-size:11.5px;color:#b8c8e6;display:flex;justify-content:space-between;}
  .actions{display:flex;gap:8px;margin-top:6px;}
  button,a.btn{flex:1;text-align:center;text-decoration:none;padding:9px 12px;border-radius:10px;font-size:12.5px;font-weight:700;cursor:pointer;border:none;}
  .btn-primary{background:linear-gradient(135deg,#00b8d4,#7c4dff);color:#fff;}
  .btn-sec{background:rgba(255,255,255,.08);color:var(--txt);border:1px solid rgba(255,255,255,.15);}
  #toast{position:fixed;bottom:20px;right:20px;background:#12b76a;color:#fff;padding:10px 16px;border-radius:10px;font-weight:700;display:none;}
</style>
</head>
<body>
  <div class="top">
    <div>
      <span class="badge">THREE-DEVICES VR · 3D-VR ACTIVO</span>
      <h1 style="font-size:21px;margin-top:8px;">Bóveda LAN & Proyector Web Doble · ${ _escapeHtml(stationName) }</h1>
      <div class="tier-row">
        <span><b>2D-VR (Two-Devices):</b> Smartphone Visor + Joystick portátil</span>
        <span>•</span>
        <span><b>3D-VR (Three-Devices):</b> PC + Visor + Joystick con profundidad holográfica y streaming doble</span>
      </div>
      <div style="margin-top:10px;display:flex;gap:10px;flex-wrap:wrap;">
        <a class="btn btn-sec" style="flex:0 0 auto;padding:7px 14px;" target="_blank" href="tags">Imprimir Marcadores 6-DoF (&lt; 3 mm · 1:1 mm)</a>
      </div>
    </div>
    <div class="pose-pill" id="poseBox">Conectando telemetría Faro 60 Hz…</div>
  </div>
  <div class="grid" id="catalogGrid"></div>
  <div id="toast"></div>
<script>
const INITIAL = $initialJson;
const grid = document.getElementById('catalogGrid');
const toast = document.getElementById('toast');
function showToast(msg){toast.textContent=msg;toast.style.display='block';setTimeout(()=>toast.style.display='none',2600);}
async function pushVisor(id,title){
  const res = await fetch('api/push/'+encodeURIComponent(id),{method:'POST'});
  if(res.ok) showToast('Proyectando en Smartphone Visor (3D-VR): '+title);
}
function render(items){
  grid.innerHTML = '';
  for(const it of items){
    const div = document.createElement('div');
    div.className = 'card';
    div.innerHTML = `
      <div class="kind">\${it.requiredTier} · \${it.stereoFormat}</div>
      <div class="title"></div>
      <div class="desc"></div>
      <div class="meta"><span>\${it.kind}</span><span>\${it.sizeBytes>0?(it.sizeBytes/1048576).toFixed(1)+' MB':'Web 3D en vivo'}</span></div>
      <div class="actions">
        <a class="btn btn-sec" target="_blank" href="\${it.stereoWebUrl}">Abrir Stream Doble (SBS)</a>
        <button class="btn btn-primary">Mandar al Visor 3D-VR</button>
      </div>`;
    div.querySelector('.title').textContent = it.title;
    div.querySelector('.desc').textContent = it.description;
    div.querySelector('button').onclick = () => pushVisor(it.id, it.title);
    grid.appendChild(div);
  }
}
render(INITIAL.items || []);
setInterval(async()=>{
  try{
    const r = await fetch(INITIAL.poseApiUrl);
    if(!r.ok) return;
    const p = await r.json();
    const h = p.head || {x:0,y:1.55,z:-1.35};
    document.getElementById('poseBox').textContent =
      `3D-VR Pose · X:\${h.x.toFixed(2)}m Y:\${h.y.toFixed(2)}m Z:\${h.z.toFixed(2)}m · Gesto:\${p.gesture||'none'}`;
  }catch(_){}
}, 180);
</script>
</body>
</html>''';
    final bytes = utf8.encode(html);
    response.statusCode = HttpStatus.ok;
    response.headers.set(HttpHeaders.contentTypeHeader, 'text/html; charset=utf-8');
    response.contentLength = bytes.length;
    response.add(bytes);
  }

  void _serveDualEyeStereoHtml(
    HttpResponse response,
    _VaultStoredRecord rec,
    Uri requestBase,
  ) {
    final poseUrl = requestBase.resolve('api/pose.json').toString();
    final fileUrl = rec.filePath != null
        ? requestBase.resolve('files/${rec.id}').toString()
        : '';
    final projectEntryUrl = rec.projectDirPath != null
        ? requestBase.resolve('projects/${rec.id}/index.html').toString()
        : '';
    final configJson = jsonEncode({
      'id': rec.id,
      'title': rec.title,
      'kind': rec.kind.name,
      'stereoFormat': rec.stereoFormat.name,
      'sceneKey': rec.builtInSceneKey ?? 'prism',
      'poseUrl': poseUrl,
      'fileUrl': fileUrl,
      'projectEntryUrl': projectEntryUrl,
    }).replaceAll('</', '<\\/');

    final html = '''<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<title>3D-VR · ${_escapeHtml(rec.title)}</title>
<style>
  html,body{margin:0;padding:0;width:100%;height:100%;overflow:hidden;background:#000;color:#e8f1ff;font-family:system-ui,sans-serif;user-select:none;}
  #stage{position:fixed;inset:0;width:100vw;height:100vh;display:block;}
  #splitFrames{position:fixed;inset:0;display:none;width:100vw;height:100vh;}
  #splitFrames iframe{width:50vw;height:100vh;border:none;background:#000;}
  #hud{position:fixed;top:8px;left:50%;transform:translateX(-50%);background:rgba(7,11,20,.72);border:1px solid rgba(0,229,255,.35);border-radius:99px;padding:4px 14px;font-size:11px;pointer-events:none;z-index:10;white-space:nowrap;}
  #divider{position:fixed;top:0;bottom:0;left:50%;width:2px;background:rgba(0,229,255,.22);pointer-events:none;z-index:9;}
</style>
</head>
<body>
<canvas id="stage"></canvas>
<div id="splitFrames"><iframe id="eyeL"></iframe><iframe id="eyeR"></iframe></div>
<div id="divider"></div>
<div id="hud">3D-VR Holográfico · Cargando…</div>
<video id="srcVideo" crossorigin="anonymous" playsinline loop style="display:none"></video>
<script>
const CFG = $configJson;
const canvas = document.getElementById('stage');
const ctx = canvas.getContext('2d');
const hud = document.getElementById('hud');
const video = document.getElementById('srcVideo');

let ipd = 0.064;
let yaw = 0, pitch = 0, yawOffset = 0;
let stickX = 0, stickY = 0;
let lensVignette = true;
let pose = {
  head: {x: 0, y: 1.60, z: 0},
  leftHand: {visible: false, x: -0.22, y: -0.20, z: -0.55, pinch: false},
  rightHand: {visible: false, x: 0.22, y: -0.20, z: -0.55, pinch: false},
  gesture: 'none',
  nativePush: false
};

// Direct 60 Hz pose injection from VRlizate Smartphone Visor (zero polling overhead)
window.__vrlizatePushPose = function(nextPose) {
  if (!nextPose) return;
  pose = Object.assign({}, pose, nextPose, {nativePush: true});
};

// Direct Joystick command bridge from Smartphone Joystick -> Visor -> Web 3D-VR
window.__vrlizateVaultInput = function(cmd) {
  if (!cmd) return;
  if (typeof cmd.stickX === 'number') stickX = cmd.stickX;
  if (typeof cmd.stickY === 'number') stickY = cmd.stickY;
  if (cmd.action === 'togglePlay' && video.src) {
    if (video.paused) video.play().catch(()=>{}); else video.pause();
  } else if (cmd.action === 'recenter') {
    yawOffset = yaw;
  } else if (cmd.action === 'toggleLens') {
    lensVignette = !lensVignette;
  } else if (cmd.action === 'seekForward' && video.src) {
    video.currentTime = Math.min(video.duration || 999999, video.currentTime + 10);
  } else if (cmd.action === 'seekBack' && video.src) {
    video.currentTime = Math.max(0, video.currentTime - 10);
  }
};

window.addEventListener('deviceorientation', (e) => {
  if (typeof e.alpha === 'number') yaw = (e.alpha * Math.PI) / 180;
  if (typeof e.beta === 'number') pitch = ((e.beta - 90) * Math.PI) / 360;
});

function resize() {
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  canvas.width = Math.floor(window.innerWidth * dpr);
  canvas.height = Math.floor(window.innerHeight * dpr);
}
window.addEventListener('resize', resize);
resize();

if (CFG.kind === 'webVrProject' && CFG.projectEntryUrl) {
  canvas.style.display = 'none';
  const sf = document.getElementById('splitFrames');
  sf.style.display = 'flex';
  document.getElementById('eyeL').src = CFG.projectEntryUrl + '?eye=left';
  document.getElementById('eyeR').src = CFG.projectEntryUrl + '?eye=right';
} else if (CFG.kind === 'video360OrCinema' && CFG.fileUrl) {
  video.src = CFG.fileUrl;
  video.muted = false;
  video.play().catch(() => { video.muted = true; video.play().catch(()=>{}); });
  window.addEventListener('pointerdown', () => { video.muted = false; video.play().catch(()=>{}); });
}

// Fallback LAN pose polling when opened in a standalone browser outside VRlizate app
setInterval(async () => {
  if (pose.nativePush) return;
  try {
    const r = await fetch(CFG.poseUrl);
    if (r.ok) {
      const p = await r.json();
      pose = Object.assign({}, pose, p);
    }
  } catch (_) {}
}, 50);

function project3D(px, py, pz, camX, camY, camZ, rYaw, rPitch, vpW, vpH, offAxisShift) {
  let dx = px - camX;
  let dy = py - camY;
  let dz = pz - camZ;
  const cy = Math.cos(rYaw), sy = Math.sin(rYaw);
  const rx = dx * cy - dz * sy;
  const rz = dx * sy + dz * cy;
  const cp = Math.cos(rPitch), sp = Math.sin(rPitch);
  const ry = dy * cp - rz * sp;
  const fz = -(dy * sp + rz * cp);
  if (fz <= 0.12) return null;
  const fov = vpH * 0.92;
  const sx = (vpW * 0.5) + ((rx / fz) * fov) + offAxisShift * vpW;
  const syScreen = (vpH * 0.5) - ((ry / fz) * fov);
  return {x: sx, y: syScreen, z: fz, scale: fov / fz};
}

function renderEye(eyeIndex, tSec) {
  const vpW = canvas.width * 0.5;
  const vpH = canvas.height;
  const ox = eyeIndex * vpW;
  const eyeSign = eyeIndex === 0 ? -0.5 : 0.5;

  ctx.save();
  ctx.beginPath();
  ctx.rect(ox, 0, vpW, vpH);
  ctx.clip();
  ctx.translate(ox, 0);

  // Holographic 3-Node head parallax from Desktop Faro + Smartphone Visor gyro
  const hx = (pose.head ? pose.head.x : 0) + stickX * 0.35;
  const hy = (pose.head ? pose.head.y : 1.60) - 1.60;
  const hz = (pose.head ? pose.head.z : 0);
  const camX = hx + eyeSign * ipd;
  const camY = hy;
  const camZ = hz;
  const offAxis = -(camX * 0.085);
  const lookYaw = (yaw - yawOffset) + stickX * 0.45;
  const lookPitch = pitch + stickY * 0.25;

  const grad = ctx.createRadialGradient(
    vpW * (0.5 + offAxis), vpH * 0.45, vpH * 0.05,
    vpW * 0.5, vpH * 0.5, vpW * 0.85
  );
  grad.addColorStop(0, '#102246');
  grad.addColorStop(1, '#04070f');
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, vpW, vpH);

  // Holographic depth tunnel grid (proves binocular & motion parallax immediately)
  ctx.strokeStyle = 'rgba(0, 229, 255, 0.22)';
  ctx.lineWidth = 1.3;
  for (let ring = 1; ring <= 6; ring++) {
    const zDepth = -0.8 - ring * 0.75;
    const corners = [
      [-1.3, -0.9, zDepth], [1.3, -0.9, zDepth],
      [1.3, 0.9, zDepth], [-1.3, 0.9, zDepth]
    ].map(c => project3D(c[0], c[1], c[2], camX, camY, camZ, lookYaw, lookPitch, vpW, vpH, offAxis));
    if (corners.every(Boolean)) {
      ctx.beginPath();
      ctx.moveTo(corners[0].x, corners[0].y);
      for (let i = 1; i < 4; i++) ctx.lineTo(corners[i].x, corners[i].y);
      ctx.closePath();
      ctx.stroke();
    }
  }

  if (CFG.kind === 'video360OrCinema' && video.readyState >= 2) {
    const vw = video.videoWidth || 1920;
    const vh = video.videoHeight || 1080;
    let sx = 0, sy = 0, sw = vw, sh = vh;
    if (CFG.stereoFormat === 'equirect360Sbs' || CFG.stereoFormat === 'vr180Sbs' || CFG.stereoFormat === 'cinemaSbs3d') {
      sw = vw * 0.5;
      sx = eyeIndex === 0 ? 0 : sw;
    } else if (CFG.stereoFormat === 'equirect360TopBottom') {
      sh = vh * 0.5;
      sy = eyeIndex === 0 ? 0 : sh;
    }
    if (CFG.stereoFormat.startsWith('equirect360') || CFG.stereoFormat === 'vr180Sbs') {
      const panU = (((lookYaw / (Math.PI * 2)) % 1) + 1) % 1;
      const cropW = sw * 0.55;
      const cropH = sh * 0.65;
      const uStart = sx + Math.max(0, Math.min(sw - cropW, panU * (sw - cropW)));
      const vStart = sy + Math.max(0, Math.min(sh - cropH, (0.5 - lookPitch) * (sh - cropH)));
      ctx.drawImage(video, uStart, vStart, cropW, cropH, 0, 0, vpW, vpH);
    } else {
      const center = project3D(0, 0, -2.6, camX, camY, camZ, lookYaw, lookPitch, vpW, vpH, offAxis);
      if (center) {
        const w = center.scale * 2.5;
        const h = w * (9 / 16);
        ctx.strokeStyle = '#00e5ff';
        ctx.lineWidth = 3;
        ctx.strokeRect(center.x - w * 0.5 - 3, center.y - h * 0.5 - 3, w + 6, h + 6);
        ctx.drawImage(video, sx, sy, sw, sh, center.x - w * 0.5, center.y - h * 0.5, w, h);
      }
    }
  } else {
    // Volumetric 3D-VR Hologram (polyhedra / solar orrery / dome)
    const count = CFG.sceneKey === 'orrery' ? 18 : 14;
    for (let i = 0; i < count; i++) {
      const angle = tSec * (0.55 + (i % 5) * 0.14) + i * 0.85;
      const radius = CFG.sceneKey === 'orrery' ? (0.28 + i * 0.09) : (0.55 + (i % 3) * 0.35);
      const px = Math.cos(angle) * radius;
      const py = Math.sin(angle * 1.3 + i) * 0.38;
      const pz = -1.9 - Math.sin(angle) * 0.65 - (i % 4) * 0.25;
      const p = project3D(px, py, pz, camX, camY, camZ, lookYaw, lookPitch, vpW, vpH, offAxis);
      if (!p) continue;
      const r = Math.max(4, p.scale * (CFG.sceneKey === 'orrery' ? 0.075 : 0.11));
      ctx.beginPath();
      ctx.arc(p.x, p.y, r, 0, Math.PI * 2);
      ctx.fillStyle = i % 2 === 0 ? 'rgba(0, 229, 255, 0.86)' : 'rgba(158, 119, 237, 0.86)';
      ctx.fill();
      ctx.strokeStyle = '#ffffff';
      ctx.lineWidth = 1.4;
      ctx.stroke();
    }
  }

  // Render Desktop AI Holographic Hands in both stereo eyes!
  for (const [hand, color] of [[pose.leftHand, '#00e5ff'], [pose.rightHand, '#ffb300']]) {
    if (hand && hand.visible) {
      const hp = project3D(
        hx + hand.x, hy + hand.y, hz + hand.z,
        camX, camY, camZ, lookYaw, lookPitch, vpW, vpH, offAxis
      );
      if (hp) {
        ctx.beginPath();
        ctx.arc(hp.x, hp.y, hand.pinch ? 18 : 12, 0, Math.PI * 2);
        ctx.fillStyle = color;
        ctx.fill();
      }
    }
  }

  if (lensVignette) {
    const vig = ctx.createRadialGradient(vpW * 0.5, vpH * 0.5, vpW * 0.36, vpW * 0.5, vpH * 0.5, vpW * 0.56);
    vig.addColorStop(0, 'rgba(0,0,0,0)');
    vig.addColorStop(1, 'rgba(0,0,0,0.88)');
    ctx.fillStyle = vig;
    ctx.fillRect(0, 0, vpW, vpH);
  }
  ctx.restore();
}

function loop(nowMs) {
  const tSec = nowMs * 0.001;
  if (CFG.kind !== 'webVrProject') {
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    renderEye(0, tSec);
    renderEye(1, tSec);
  }
  const h = pose.head || {x: 0, y: 1.55, z: -1.35};
  hud.textContent = `3D-VR · \${CFG.title} · Paralaje (\${h.x.toFixed(2)}, \${h.y.toFixed(2)}, \${h.z.toFixed(2)}m)`;
  requestAnimationFrame(loop);
}
requestAnimationFrame(loop);
</script>
</body>
</html>''';
    final bytes = utf8.encode(html);
    response.statusCode = HttpStatus.ok;
    response.headers.set(HttpHeaders.contentTypeHeader, 'text/html; charset=utf-8');
    response.contentLength = bytes.length;
    response.add(bytes);
  }

  static String _videoMimeType(String lowerName) {
    if (lowerName.endsWith('.webm')) return 'video/webm';
    if (lowerName.endsWith('.mov')) return 'video/quicktime';
    if (lowerName.endsWith('.mkv')) return 'video/x-matroska';
    return 'video/mp4';
  }

  static String _projectAssetMime(String filePath) {
    final lower = filePath.toLowerCase();
    if (lower.endsWith('.html')) return 'text/html; charset=utf-8';
    if (lower.endsWith('.js') || lower.endsWith('.mjs')) {
      return 'text/javascript; charset=utf-8';
    }
    if (lower.endsWith('.wasm')) return 'application/wasm';
    if (lower.endsWith('.css')) return 'text/css; charset=utf-8';
    if (lower.endsWith('.json') || lower.endsWith('.gltf')) {
      return 'application/json; charset=utf-8';
    }
    if (lower.endsWith('.glb')) return 'model/gltf-binary';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.ogg')) return 'audio/ogg';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    return 'application/octet-stream';
  }

  static String _humanTitleFromFileName(String name) {
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final cleaned = base
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? name : cleaned;
  }

  static String _stableSlug(String input) =>
      crypto.sha256.convert(utf8.encode(input)).toString().substring(0, 12);

  static String _shortHexHash(String input) =>
      crypto.sha256.convert(utf8.encode(input)).toString().substring(0, 24);

  static String _escapeHtml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }
}

/// Client used by the Smartphone Visor to query an authenticated private-LAN
/// **VRlizate Desktop Bóveda (`Three-Devices VR · 3D-VR`)**.
class VrDesktopVaultClient {
  VrDesktopVaultClient({
    http.Client? client,
    this.timeout = const Duration(seconds: 8),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;

  static bool isValidVaultUri(Uri uri) =>
      uri.scheme == 'http' &&
      isPrivateLanOrLoopbackHost(uri.host) &&
      uri.userInfo.isEmpty &&
      !uri.hasFragment &&
      uri.port >= 1 &&
      uri.port <= 65535 &&
      uri.pathSegments.where((s) => s.isNotEmpty).isNotEmpty;

  Future<VrVaultCatalogSnapshot> fetchCatalog(Uri catalogUri) async {
    if (!isValidVaultUri(catalogUri)) {
      throw const FormatException(
        'La URL de Bóveda LAN debe pertenecer a una red local privada válida.',
      );
    }
    final response = await _client
        .get(catalogUri, headers: const {'Accept': 'application/json'})
        .timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'La Bóveda LAN respondió HTTP ${response.statusCode}.',
        uri: catalogUri,
      );
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final snapshot = VrVaultCatalogSnapshot.fromJson(decoded);
    if (snapshot == null) {
      throw const FormatException('Catálogo de Bóveda LAN inválido.');
    }
    return snapshot;
  }

  /// Downloads a verified `.vrlz` package from the PC Vault so the user can pin
  /// it locally on the Smartphone Visor for portable `Two-Devices VR (2D-VR)`.
  Future<Uint8List> downloadPackageBytes(
    Uri streamUri, {
    int maxBytes = VrlzPackage.maxBytes,
    String? expectedSha256,
  }) async {
    if (!isValidVaultUri(streamUri)) {
      throw const FormatException('URL de paquete LAN no válida.');
    }
    final request = http.Request('GET', streamUri)
      ..followRedirects = false
      ..headers['Accept'] = 'application/octet-stream';
    final streamed = await _client.send(request).timeout(timeout);
    if (streamed.statusCode != HttpStatus.ok &&
        streamed.statusCode != HttpStatus.partialContent) {
      await streamed.stream.drain<void>();
      throw HttpException(
        'No se pudo descargar el paquete LAN (HTTP ${streamed.statusCode}).',
      );
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in streamed.stream.timeout(timeout)) {
      if (builder.length + chunk.length > maxBytes) {
        throw const FormatException(
          'El paquete de Bóveda LAN excede el límite de tamaño.',
        );
      }
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    if (expectedSha256 != null &&
        crypto.sha256.convert(bytes).toString() != expectedSha256) {
      throw const FormatException(
        'La huella SHA-256 del paquete LAN no coincide.',
      );
    }
    return bytes;
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
