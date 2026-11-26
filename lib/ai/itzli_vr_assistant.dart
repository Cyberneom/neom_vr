import 'package:neom_core/app_config.dart';
import 'package:neom_core/utils/enums/app_in_use.dart';
import 'neom_hey_compat.dart';
import 'package:vrlizate_assistant/vrlizate_assistant.dart';
import 'package:vrlizate_scene/vrlizate_scene.dart';

import 'saia_spatial_inference_bridge.dart';

export 'package:vrlizate_assistant/vrlizate_assistant.dart'
    show
        VrVoiceActionType,
        VrVoiceGuidance,
        VrVoiceIntentRouter,
        VrVoiceMotionKind,
        VrVoiceUiCommand;

/// Spatial Action determined by VR / neom_hey Assistant (aliased to SDK [VrVoiceActionType]).
typedef ItzliActionType = VrVoiceActionType;

/// Structured response emitted by VR spatial assistant.
class ItzliVrGuidance implements VrVoiceGuidance {
  @override
  final ItzliActionType actionType;
  @override
  final String speechResponse;
  @override
  final String? targetWingId;
  @override
  final String? targetDemoId;
  @override
  final String? targetDemoTitle;
  final VrLook? targetLook;
  final VrQualityPreset? targetPreset;
  @override
  final VrVoiceMotionKind? motionKind;
  @override
  final double motionDurationSeconds;
  final double? distanceMeters;
  final double? turnDegrees;
  final String? targetPointQuery;
  final double? targetX;
  final double? targetZ;
  final bool useGazeTarget;
  @override
  final VrVoiceUiCommand? uiCommand;
  @override
  final double confidence;

  const ItzliVrGuidance({
    required this.actionType,
    required this.speechResponse,
    this.targetWingId,
    this.targetDemoId,
    this.targetDemoTitle,
    this.targetLook,
    this.targetPreset,
    this.motionKind,
    this.motionDurationSeconds = 2.2,
    this.distanceMeters,
    this.turnDegrees,
    this.targetPointQuery,
    this.targetX,
    this.targetZ,
    this.useGazeTarget = false,
    this.uiCommand,
    this.confidence = 0.95,
  });

  @override
  String get summaryEs => switch (actionType) {
    ItzliActionType.launchExperience =>
      'Abrir experiencia: ${targetDemoTitle ?? targetDemoId ?? ""}',
    ItzliActionType.jumpToWing =>
      'Ir a zona: ${targetWingId ?? "Plaza Central"}',
    ItzliActionType.moveInSpace =>
      'Movimiento 3D: ${motionKind?.name ?? ""} (${motionDurationSeconds.toStringAsFixed(1)}s)',
    ItzliActionType.goToPoint =>
      'Ir a punto: ${targetPointQuery ?? (targetX != null && targetZ != null ? "(${targetX!.toStringAsFixed(1)}, ${targetZ!.toStringAsFixed(1)})" : "frente a la mirada")}',
    ItzliActionType.uiCommand =>
      'Acción UI: ${uiCommand?.name ?? ""}',
    ItzliActionType.recenter => 'Recentrar horizonte',
    ItzliActionType.changeLook =>
      'Estilo visual: ${targetLook == VrLook.cyberpunk ? "Cyberpunk" : (targetLook == VrLook.stellar ? "Estelar" : (targetLook == VrLook.cinematic ? "Cinematográfico" : "Personalizado"))}',
    ItzliActionType.changeResolution =>
      'Calidad: ${targetPreset?.tier.name ?? "ultra"}',
    ItzliActionType.switchCatalog2D => 'Catálogo 2D',
    ItzliActionType.conversationalGuidance => 'Guía conversacional',
  };
}

/// Metadata definition of an experience indexed by Itzli.
class _ItzliExperienceMetadata {
  final String id;
  final String title;
  final String wingId;
  final String wingName;
  final List<String> keywords;
  final String categoryDescription;
  final bool directLaunchOnMention;

  const _ItzliExperienceMetadata({
    required this.id,
    required this.title,
    required this.wingId,
    required this.wingName,
    required this.keywords,
    required this.categoryDescription,
    this.directLaunchOnMention = false,
  });
}

/// Parsed wake-word result for spoken instructions addressed to the `VR`
/// spatial assistant (`"Hey VR"`, `"Hey ve erre"`, `"Hey viar"`, `"VR"`).
class VrWakeWordMatch {
  final bool addressed;
  final String matchedWakePhrase;
  final String commandText;

  const VrWakeWordMatch({
    required this.addressed,
    required this.matchedWakePhrase,
    required this.commandText,
  });

  /// True when the speaker only uttered the wake phrase (e.g. `"Hey VR"`,
  /// `"Hey ve erre"`, `"Hey viar"`) without a follow-up instruction yet.
  bool get isWakeOnly => addressed && commandText.isEmpty;
}

/// Deterministic Spanish intent router for VRlizate (`Hey VR`).
///
/// Functions as the intelligent virtual guide (`VR`) and spatial copilot of the VRlizate ecosystem:
/// 1. Understands natural language requests in Spanish across all spatial apps, with or without `"Hey VR"` (`"Hey ve erre"`, `"Hey viar"`, `"VR"`).
/// 2. Resolves intent to exact wings (Estrategia, Productividad, Cine, SOTA Labs).
/// 3. Recommends apps based on user mood ("quiero relajarme", "vamos a jugar", "tengo que trabajar").
/// 4. Adjusts visual looks, HDR bloom, and resolution on the fly.
class ItzliVrAssistant implements VrVoiceIntentRouter {
  ItzliVrAssistant() {
    VrVoiceIntentRouter.defaultFactory ??= ItzliVrAssistant.new;
  }
  /// Short user-facing assistant identity derived from `VRlizate -> VR`.
  static const String assistantName = 'VR';

  /// Canonical hands-free wake phrase shown across Visor HUD and Estación Faro.
  static const String wakeWordHint = 'Hey VR';

  /// Resolves the active [AppInUse] (`AppInUse.v` by default inside VRlizate
  /// when `AppConfig` has not been overridden yet).
  static AppInUse get activeVrAppInUse =>
      AppConfig.instance.appInUse == AppInUse.o
      ? AppInUse.v
      : AppConfig.instance.appInUse;

  /// Active voice profile discovered by `neom_hey` for [app].
  static NeomHeyAppProfile activeProfile([AppInUse? app]) =>
      NeomHeyProtocol.profileFor(app ?? activeVrAppInUse);

  /// Structured list of supported voice instructions from `neom_hey` for [app].
  static List<NeomHeyInstructionSpec> supportedCapabilities([AppInUse? app]) =>
      NeomHeyProtocol.capabilitiesFor(app ?? activeVrAppInUse);

  /// Parses wake-word calls via `NeomHeyProtocol` according to [AppInUse]
  /// (`AppInUse.v`: `"Hey VR"`, `"Hey ve erre"`, `"Hey viar"`, `"VR"`).
  static VrWakeWordMatch parseWakeWord(String rawSpeech, {AppInUse? app}) {
    final heyMatch = NeomHeyProtocol.detectWakeCall(
      rawSpeech,
      app: app ?? activeVrAppInUse,
    );
    return VrWakeWordMatch(
      addressed: heyMatch.addressed,
      matchedWakePhrase: heyMatch.matchedWakePhrase,
      commandText: heyMatch.commandText,
    );
  }

  static const List<_ItzliExperienceMetadata> _catalog = [
    // 🎮 Ala Norte: Estrategia & Juegos
    _ItzliExperienceMetadata(
      id: 'cosmic_chess',
      title: 'Ajedrez Cósmico',
      wingId: 'north_games',
      wingName: 'Ala Estrategia & Juegos',
      keywords: [
        'ajedrez',
        'chess',
        'jaque',
        'tablero',
        'estrategia',
        'peon',
        'reina',
        'rey',
        'piezas',
      ],
      categoryDescription:
          'Ajedrez espacial en 3D con materiales PBR y selección por mirada.',
    ),
    _ItzliExperienceMetadata(
      id: 'orbital_command',
      title: 'Comando Orbital',
      wingId: 'north_games',
      wingName: 'Ala Estrategia & Juegos',
      keywords: [
        'orbital',
        'naves',
        'espacio',
        'flota',
        'galaxia',
        'estelar',
        'combate',
        'planeta',
        'rts',
        'batalla espacial',
      ],
      categoryDescription:
          'Estrategia en tiempo real en gravedad espacial con flotas orbitales.',
    ),
    _ItzliExperienceMetadata(
      id: 'medieval_siege',
      title: 'Asedio Medieval',
      wingId: 'north_games',
      wingName: 'Ala Estrategia & Juegos',
      keywords: [
        'medieval',
        'asedio',
        'castillo',
        'torre',
        'catapulta',
        'guerra',
        'caballeros',
      ],
      categoryDescription:
          'Simulador táctico 3D de asedio a fortalezas medievales.',
    ),
    _ItzliExperienceMetadata(
      id: 'portal_maze',
      title: 'Laberinto Portal',
      wingId: 'north_games',
      wingName: 'Ala Estrategia & Juegos',
      keywords: [
        'laberinto',
        'portal',
        'portales',
        'puzle',
        'rompecabezas',
        'escapar',
        'caminos',
      ],
      categoryDescription:
          'Puzles espaciales con portales de teletransporte dimensional.',
    ),
    _ItzliExperienceMetadata(
      id: 'crystal_mines',
      title: 'Minas de Cristal',
      wingId: 'north_games',
      wingName: 'Ala Estrategia & Juegos',
      keywords: [
        'cristal',
        'cristales',
        'minas',
        'mineria',
        'gemas',
        'puzles',
        'recoleccion',
      ],
      categoryDescription:
          'Exploración subterránea y extracción de cristales energéticos.',
    ),
    _ItzliExperienceMetadata(
      id: 'tower_defense',
      title: 'Invasión Torres',
      wingId: 'north_games',
      wingName: 'Ala Estrategia & Juegos',
      keywords: [
        'torres',
        'tower defense',
        'invasion',
        'defensa',
        'oleadas',
        'enemigos',
      ],
      categoryDescription:
          'Defensa de bases espaciales contra oleadas de invasores.',
    ),
    _ItzliExperienceMetadata(
      id: 'treasure_hunt',
      title: 'Caza del Tesoro',
      wingId: 'north_games',
      wingName: 'Ala Estrategia & Juegos',
      keywords: [
        'tesoro',
        'caza',
        'buscar',
        'monedas',
        'cofre',
        'exploracion',
        'aventura',
      ],
      categoryDescription:
          'Búsqueda inmersiva de reliquias ocultas en ruinas antiguas.',
    ),

    // 📊 Ala Este: Productividad & Creatividad Espacial
    _ItzliExperienceMetadata(
      id: 'vr_dashboard',
      title: 'Dashboard VR',
      wingId: 'east_prod',
      wingName: 'Ala Productividad',
      keywords: [
        'dashboard',
        'metricas',
        'graficos',
        'analitica',
        'datos',
        'estadisticas',
        'finanzas',
        'kpi',
      ],
      categoryDescription:
          'Visualización de datos y gráficos 3D flotantes en espacio inmersivo.',
    ),
    _ItzliExperienceMetadata(
      id: 'vr_kanban',
      title: 'Kanban VR',
      wingId: 'east_prod',
      wingName: 'Ala Productividad',
      keywords: [
        'kanban',
        'tareas',
        'agile',
        'pendientes',
        'tablero',
        'trabajo',
        'productividad',
        'proyectos',
        'tarjetas',
      ],
      categoryDescription:
          'Gestión ágil de tareas y proyectos con tableros espaciales.',
    ),
    _ItzliExperienceMetadata(
      id: 'vr_notes',
      title: 'Notas VR',
      wingId: 'east_prod',
      wingName: 'Ala Productividad',
      keywords: [
        'notas',
        'apuntes',
        'escribir',
        'documentos',
        'recordatorios',
        'textos',
        'ideas',
      ],
      categoryDescription:
          'Muro espacial de notas y recordatorios flotantes en 3D.',
    ),
    _ItzliExperienceMetadata(
      id: 'wordsphere_vr',
      title: 'Wordsphere VR',
      wingId: 'east_prod',
      wingName: 'Ala Productividad',
      keywords: [
        'wordsphere',
        'teclado',
        'escribir con la mirada',
        'radial',
        'letras',
        'palabras',
        'tipeo',
        'typing',
      ],
      categoryDescription:
          'Teclado radial gestual operado puramente con el movimiento de la mirada.',
    ),
    _ItzliExperienceMetadata(
      id: 'ecosystem',
      title: 'Ecosistema Neom',
      wingId: 'east_prod',
      wingName: 'Ala Productividad',
      keywords: [
        'ecosistema',
        'neom',
        'emxi',
        'apps',
        'red',
        'modulos',
        'conexiones',
      ],
      categoryDescription:
          'Mapa topológico interactivo del ecosistema de aplicaciones Open Neom.',
    ),

    // 🎬 Ala Oeste: Multimedia & Artes Visuales
    _ItzliExperienceMetadata(
      id: 'vr_free_tv',
      title: 'TV & Cine Gratis 24/7',
      wingId: 'west_media',
      wingName: 'Ala Multimedia & Cine',
      keywords: [
        'tv gratis',
        'television gratis',
        'programacion gratuita',
        'pluto tv',
        'pluto',
        'tubi',
        'vix',
        'canela tv',
        'filmoteca unam',
        'cine en linea',
        'peliculas gratis',
        'series gratis',
        'canales en vivo',
        'streaming gratis',
        'multiplex',
      ],
      categoryDescription:
          'Multiplex FAST con canales 24/7 en vivo, cine UNAM/clásico, series y portales gratuitos.',
      directLaunchOnMention: true,
    ),
    _ItzliExperienceMetadata(
      id: 'vr_cinema',
      title: 'Cine VR 360°',
      wingId: 'west_media',
      wingName: 'Ala Multimedia & Cine',
      keywords: [
        'cine',
        'cinema',
        'pelicula',
        'video',
        '360',
        'pantalla',
        'ver video',
        'multimedia',
        'relajarme',
        'cineasta',
      ],
      categoryDescription:
          'Cine esférico inmersivo con pantalla curva gigante y audio envolvente.',
    ),
    _ItzliExperienceMetadata(
      id: 'vr_gallery',
      title: 'VR Galería',
      wingId: 'west_media',
      wingName: 'Ala Multimedia & Cine',
      keywords: [
        'galeria',
        'museo',
        'arte',
        'esculturas',
        'gemas',
        'pbr',
        'exposicion',
        'joyas',
      ],
      categoryDescription:
          'Museo virtual con exhibición de gemas y esculturas con materiales PBR.',
    ),
    _ItzliExperienceMetadata(
      id: 'openworld',
      title: 'Open World',
      wingId: 'west_media',
      wingName: 'Ala Multimedia & Cine',
      keywords: [
        'mundo abierto',
        'open world',
        'terreno',
        'dia y noche',
        'paisaje',
        'naturaleza',
        'cielo',
        'simulacion',
      ],
      categoryDescription:
          'Simulación de paisajes infinitos con ciclo dinámico de día y noche.',
    ),
    _ItzliExperienceMetadata(
      id: 'stereo_scene',
      title: 'Stereo Scene Showcase',
      wingId: 'west_media',
      wingName: 'Ala Multimedia & Cine',
      keywords: [
        'stereo scene',
        'gpu',
        'motor 3d',
        'render',
        'shaders',
        'iluminacion',
        'sombras',
      ],
      categoryDescription:
          'Demostración de alta gama del motor GPU estereoscópico de Flutter Scene.',
    ),

    // 🔬 Ala Sur: Laboratorio Sensorial & SOTA Labs
    _ItzliExperienceMetadata(
      id: 'holographic_hands',
      title: 'Manos 3D & Sónar',
      wingId: 'south_labs',
      wingName: 'Ala Laboratorio SOTA',
      keywords: [
        'sonar',
        'ultrasonido',
        'esculpir',
        'dibujar en el aire',
        'ondas',
        'microfono',
        'profundidad',
        'audio sonar',
      ],
      categoryDescription:
          'Sensado acústico por efecto Doppler a 19.2 kHz y escultura espacial en el aire.',
    ),
    _ItzliExperienceMetadata(
      id: 'wifi_sensing',
      title: 'WiFi Sensing',
      wingId: 'south_labs',
      wingName: 'Ala Laboratorio SOTA',
      keywords: [
        'wifi',
        'radar',
        'radiofrecuencia',
        'csi',
        'presencia',
        'rf',
        'respiracion',
        'ondas electromagenticas',
      ],
      categoryDescription:
          'Demostración del estándar de sensado por perturbaciones de radiofrecuencia Wi-Fi.',
    ),
    _ItzliExperienceMetadata(
      id: 'hand_tracking',
      title: 'Hand Tracking 26 Joints',
      wingId: 'south_labs',
      wingName: 'Ala Laboratorio SOTA',
      keywords: [
        'hand tracking',
        'dedos',
        'esqueleto',
        'articulaciones',
        'openxr',
        'camara',
        'gestos',
        'manos',
      ],
      categoryDescription:
          'Rastreo esquelético de manos de 26 articulaciones OpenXR en tiempo real.',
    ),
    _ItzliExperienceMetadata(
      id: 'gravity_zero',
      title: 'Gravedad Cero',
      wingId: 'south_labs',
      wingName: 'Ala Laboratorio SOTA',
      keywords: [
        'gravedad cero',
        'fisica',
        'flotar',
        'cero g',
        'espacio',
        'cinematica',
        'orbital',
      ],
      categoryDescription:
          'Simulador de colisiones y dinámicas de cuerpos rígidos en microgravedad.',
    ),

    // 🏛️ Plazas Famosas 360° & Centros Comerciales Distribuidos
    _ItzliExperienceMetadata(
      id: 'mall_plaza_artz_mx',
      title: 'Plaza Artz Pedregal 360°',
      wingId: 'center',
      wingName: 'Plazas Famosas 360°',
      keywords: [
        'plaza artz',
        'artz',
        'pedregal',
        'cdmx',
        'jardines abiertos',
        'plaza mexicana',
      ],
      categoryDescription:
          'Jardines abiertos de varios niveles con espejos de agua y locales espaciales.',
      directLaunchOnMention: true,
    ),
    _ItzliExperienceMetadata(
      id: 'mall_galleria_milano',
      title: 'Galleria Vittorio Emanuele II',
      wingId: 'center',
      wingName: 'Plazas Famosas 360°',
      keywords: [
        'galleria',
        'milano',
        'milan',
        'vittorio emanuele',
        'italia',
        'cupula de cristal',
      ],
      categoryDescription:
          'Crucero octogonal clásico en Milán con bóveda de hierro y cristal.',
      directLaunchOnMention: true,
    ),
    _ItzliExperienceMetadata(
      id: 'mall_dubai_atrium',
      title: 'Grand Dubai Atrium',
      wingId: 'center',
      wingName: 'Plazas Famosas 360°',
      keywords: [
        'dubai',
        'dubai mall',
        'atrio dubai',
        'acuario',
        'cascada monumental',
      ],
      categoryDescription:
          'Atrio monumental con cascada perlada y muro acuático panorámico.',
      directLaunchOnMention: true,
    ),
    _ItzliExperienceMetadata(
      id: 'mall_marina_canal',
      title: 'Marina Bay Canal Promenade',
      wingId: 'center',
      wingName: 'Plazas Famosas 360°',
      keywords: [
        'marina bay',
        'marina canal',
        'singapur',
        'canal interior',
        'promenade',
      ],
      categoryDescription:
          'Paseo junto a canal interior con puentes peatonales y domo de cristal.',
      directLaunchOnMention: true,
    ),

    // 🕹️ Juegos Insignia, Arcade & Calibración
    _ItzliExperienceMetadata(
      id: 'riviera_rush',
      title: 'Riviera Rush',
      wingId: 'north_games',
      wingName: 'Ala Estrategia & Juegos',
      keywords: [
        'riviera rush',
        'riviera',
        'carreras',
        'autos',
        'conducir',
        'velocidad',
        'manejar',
        'coche',
      ],
      categoryDescription:
          'Conducción costera de alta velocidad en primera persona VR.',
      directLaunchOnMention: true,
    ),
    _ItzliExperienceMetadata(
      id: 'legend_of_selma',
      title: 'Legend of Selma',
      wingId: 'north_games',
      wingName: 'Ala Estrategia & Juegos',
      keywords: [
        'legend of selma',
        'selma',
        'zelda',
        'espada',
        'calabozo',
        'rpg',
      ],
      categoryDescription:
          'Aventura de exploración y fantasía en tercera y primera persona.',
      directLaunchOnMention: true,
    ),
    _ItzliExperienceMetadata(
      id: 'doom_vr',
      title: 'DOOM Classic VR',
      wingId: 'north_games',
      wingName: 'Ala Estrategia & Juegos',
      keywords: [
        'doom',
        'doom vr',
        'fps',
        'disparos clasico',
      ],
      categoryDescription:
          'Motor clásico DOOM renderizado estereoscópicamente.',
      directLaunchOnMention: true,
    ),
    _ItzliExperienceMetadata(
      id: 'nes_vr',
      title: 'NES Emulator VR',
      wingId: 'north_games',
      wingName: 'Ala Estrategia & Juegos',
      keywords: [
        'nes',
        'nintendo',
        'emulador',
        'retro',
        '8 bits',
      ],
      categoryDescription: 'Sala retro con emulador NES en pantalla gigante.',
      directLaunchOnMention: true,
    ),
    _ItzliExperienceMetadata(
      id: 'open_source_flutterflip',
      title: 'FlutterFlip 3D',
      wingId: 'north_games',
      wingName: 'Ala Estrategia & Juegos',
      keywords: [
        'flutterflip',
        'pinball',
        'flipper',
      ],
      categoryDescription: 'Mesa de pinball espacial 3D open-source.',
      directLaunchOnMention: true,
    ),
    _ItzliExperienceMetadata(
      id: 'sunny_gardens',
      title: 'Jardines Soleados',
      wingId: 'west_media',
      wingName: 'Ala Multimedia & Cine',
      keywords: [
        'sunny gardens',
        'jardines soleados',
        'jardin',
        'flores',
        'invernadero',
      ],
      categoryDescription: 'Paseo contemplativo entre jardines soleados.',
      directLaunchOnMention: true,
    ),
    _ItzliExperienceMetadata(
      id: 'neon_bastion',
      title: 'Bastión Neón',
      wingId: 'north_games',
      wingName: 'Ala Estrategia & Juegos',
      keywords: [
        'neon bastion',
        'bastion neon',
        'bastion',
        'ciberdefensa',
      ],
      categoryDescription: 'Defensa táctica en fortaleza luminosa.',
      directLaunchOnMention: true,
    ),
    _ItzliExperienceMetadata(
      id: 'dungeon_architect',
      title: 'Arquitecto de Mazmorras',
      wingId: 'north_games',
      wingName: 'Ala Estrategia & Juegos',
      keywords: [
        'dungeon architect',
        'mazmorras',
        'mazmorra',
        'arquitecto',
      ],
      categoryDescription: 'Diseño y exploración de mazmorras modulares 3D.',
      directLaunchOnMention: true,
    ),
    _ItzliExperienceMetadata(
      id: 'fleet_admiral',
      title: 'Almirante de Flota',
      wingId: 'north_games',
      wingName: 'Ala Estrategia & Juegos',
      keywords: [
        'fleet admiral',
        'almirante',
      ],
      categoryDescription: 'Mando táctico naval y aeroespacial.',
      directLaunchOnMention: true,
    ),
    _ItzliExperienceMetadata(
      id: 'open_source_arcade',
      title: 'Galería Open Source',
      wingId: 'north_games',
      wingName: 'Ala Estrategia & Juegos',
      keywords: [
        'open source arcade',
        'galeria open source',
        'arcade open source',
      ],
      categoryDescription: 'Colección curada de juegos open-source adaptados a VR.',
      directLaunchOnMention: true,
    ),
    _ItzliExperienceMetadata(
      id: 'viewer_calibration',
      title: 'Calibración Óptica del Visor',
      wingId: 'south_labs',
      wingName: 'Ala Laboratorio SOTA',
      keywords: [
        'calibracion',
        'calibrar visor',
        'ipd',
        'lentes',
        'ajuste optico',
      ],
      categoryDescription: 'Ajuste de IPD, distorsión de lentes y horizonte del visor.',
      directLaunchOnMention: true,
    ),
    _ItzliExperienceMetadata(
      id: 'vr_store_pass',
      title: 'Tienda & VR Pass',
      wingId: 'east_prod',
      wingName: 'Ala Productividad',
      keywords: [
        'tienda',
        'tienda digital',
        'vr pass',
        'vrlizate pass',
        'membresia',
        'suscripcion',
        'comprar juegos',
        'telemetria',
      ],
      categoryDescription:
          'Showroom 3D de compras digitales, membresía VRlizate Pass, streaming PlayGo y telemetría.',
      directLaunchOnMention: true,
    ),
    _ItzliExperienceMetadata(
      id: 'quantum_planetarium',
      title: 'Planetario Cuántico 3D',
      wingId: 'west_media',
      wingName: 'Ala Multimedia & Cine',
      keywords: [
        'planetario',
        'planetario cuantico',
        'exoplanetas',
        'astronomia',
        'sistema estelar',
        'observatorio',
      ],
      categoryDescription:
          'Domo astronómico 3D con exoplanetas PBR, anillos armilares y mecánica celeste.',
      directLaunchOnMention: true,
    ),
    _ItzliExperienceMetadata(
      id: 'neon_synth_arena',
      title: 'Synthwave Pulse Arena',
      wingId: 'north_games',
      wingName: 'Ala Estrategia & Juegos',
      keywords: [
        'synthwave',
        'synthwave arena',
        'pulse arena',
        'juego de ritmo',
        'arena musical',
      ],
      categoryDescription:
          'Coliseo cyber-rítmico 3D con nodos armónicos, partículas y bloom HDR.',
      directLaunchOnMention: true,
    ),

    // 🌍 Mundos 224×224 m & Expedición Open Neom
    _ItzliExperienceMetadata(
      id: 'open_neom_expedition',
      title: 'Expedición Open Neom',
      wingId: 'west_media',
      wingName: 'Mundos & Expedición',
      keywords: [
        'expedicion',
        'expedicion neom',
        'open neom expedition',
        'gran expedicion',
      ],
      categoryDescription: 'Travesía abierta por el mundo insignia de Open Neom.',
      directLaunchOnMention: true,
    ),
    _ItzliExperienceMetadata(
      id: 'ecosystems_solar_city',
      title: 'Ciudad Solar 224m',
      wingId: 'west_media',
      wingName: 'Mundos 224×224 m',
      keywords: [
        'ciudad solar',
        'solar city',
        'solarpunk',
        'energia solar',
      ],
      categoryDescription: 'Metrópolis ecológica bañada por el sol de 224×224 metros.',
      directLaunchOnMention: true,
    ),
    _ItzliExperienceMetadata(
      id: 'ecosystems_rainforest',
      title: 'Selva Biodomo',
      wingId: 'west_media',
      wingName: 'Mundos 224×224 m',
      keywords: [
        'selva',
        'rainforest',
        'bosque tropical',
        'jungla',
        'amazonas',
      ],
      categoryDescription: 'Ecosistema selvático inmersivo con vegetación densa.',
      directLaunchOnMention: true,
    ),
    _ItzliExperienceMetadata(
      id: 'ecosystems_neon_city',
      title: 'Metrópolis Neón',
      wingId: 'west_media',
      wingName: 'Mundos 224×224 m',
      keywords: [
        'ciudad neon',
        'neon city',
        'metropolis neon',
      ],
      categoryDescription: 'Distrito urbano nocturno con avenidas holográficas.',
      directLaunchOnMention: true,
    ),
    _ItzliExperienceMetadata(
      id: 'ecosystems_lunar',
      title: 'Base Lunar',
      wingId: 'west_media',
      wingName: 'Mundos 224×224 m',
      keywords: [
        'base lunar',
        'luna',
        'crater lunar',
        'artemis',
      ],
      categoryDescription: 'Estación científica sobre el regolito lunar.',
      directLaunchOnMention: true,
    ),
    _ItzliExperienceMetadata(
      id: 'ecosystems_orbital_habitat',
      title: 'Hábitat Orbital',
      wingId: 'west_media',
      wingName: 'Mundos 224×224 m',
      keywords: [
        'habitat orbital',
        'estacion espacial',
      ],
      categoryDescription: 'Anillo orbital con vistas directas al planeta.',
      directLaunchOnMention: true,
    ),
    _ItzliExperienceMetadata(
      id: 'ecosystems_coral_station',
      title: 'Estación Arrecife de Coral',
      wingId: 'west_media',
      wingName: 'Mundos 224×224 m',
      keywords: [
        'arrecife',
        'coral',
        'submarino',
        'oceano',
        'bajo el agua',
      ],
      categoryDescription: 'Observatorio submarino rodeado de arrecifes vivos.',
      directLaunchOnMention: true,
    ),
    _ItzliExperienceMetadata(
      id: 'ecosystems_polar_station',
      title: 'Estación Polar Ártica',
      wingId: 'west_media',
      wingName: 'Mundos 224×224 m',
      keywords: [
        'estacion polar',
        'artico',
        'antartida',
        'hielo',
        'aurora boreal',
      ],
      categoryDescription: 'Base polar bajo auroras boreales.',
      directLaunchOnMention: true,
    ),
    _ItzliExperienceMetadata(
      id: 'ecosystems_sakura',
      title: 'Santuario Sakura',
      wingId: 'west_media',
      wingName: 'Mundos 224×224 m',
      keywords: [
        'sakura',
        'cerezos',
        'japon',
        'templo japones',
      ],
      categoryDescription: 'Jardín tradicional de cerezos en flor.',
      directLaunchOnMention: true,
    ),
    _ItzliExperienceMetadata(
      id: 'ecosystems_astral_library',
      title: 'Biblioteca Astral',
      wingId: 'east_prod',
      wingName: 'Mundos 224×224 m',
      keywords: [
        'biblioteca astral',
        'biblioteca cosmica',
        'libros flotantes',
      ],
      categoryDescription: 'Archivo monumental de conocimiento suspendido en el cosmos.',
      directLaunchOnMention: true,
    ),
    _ItzliExperienceMetadata(
      id: 'ecosystems_museum_court',
      title: 'Gran Atrio del Museo',
      wingId: 'west_media',
      wingName: 'Mundos 224×224 m',
      keywords: [
        'atrio del museo',
        'corte del museo',
        'escultura clasica',
      ],
      categoryDescription: 'Patio arquitectónico de exposiciones monumentales.',
      directLaunchOnMention: true,
    ),
    _ItzliExperienceMetadata(
      id: 'ecosystems_festival_park',
      title: 'Parque del Festival',
      wingId: 'west_media',
      wingName: 'Mundos 224×224 m',
      keywords: [
        'parque del festival',
        'festival',
        'concierto',
        'escenario musical',
      ],
      categoryDescription: 'Explanada cultural con escenarios y sonido espacial.',
      directLaunchOnMention: true,
    ),
  ];

  /// Interprets user natural language speech and resolves spatial guidance
  /// using the canonical `neom_hey` protocol for [app] (`AppInUse.v` by default).
  @override
  ItzliVrGuidance interpretRequest(String naturalSpeech, {AppInUse? app}) {
    final resolvedApp = app ?? activeVrAppInUse;
    final parsed = NeomHeyProtocol.parseInstruction(
      naturalSpeech,
      app: resolvedApp,
    );
    final profile = NeomHeyProtocol.profileFor(resolvedApp);

    if (parsed.wake.isWakeOnly) {
      return ItzliVrGuidance(
        actionType: ItzliActionType.uiCommand,
        speechResponse: profile.greetingEs,
        uiCommand: VrVoiceUiCommand.openMenu,
      );
    }

    final text = parsed.wake.commandText;
    if (text.isEmpty) {
      return ItzliVrGuidance(
        actionType: ItzliActionType.conversationalGuidance,
        speechResponse:
            'Te escucho. Di «${profile.canonicalWakePhrase}» seguido de a dónde quieres ir o qué abrir.',
      );
    }

    // 0a. Capability discovery query ("¿qué funciones puedes realizar?")
    if (parsed.asksCapabilities) {
      return ItzliVrGuidance(
        actionType: ItzliActionType.conversationalGuidance,
        speechResponse: NeomHeyProtocol.capabilitiesSummaryEs(resolvedApp),
      );
    }

    // 0b. Immediate Stop / Freeze Locomotion
    if (parsed.domain == NeomHeyInstructionDomain.locomotionStop) {
      return const ItzliVrGuidance(
        actionType: ItzliActionType.moveInSpace,
        speechResponse: 'Movimiento detenido.',
        motionKind: VrVoiceMotionKind.stop,
        motionDurationSeconds: 0,
      );
    }

    // 0c. Hands-free UI & Menu Commands (no joystick needed)
    if (text == 'menu' ||
        _matchesAny(text, [
          'abre el menu',
          'abrir menu',
          'mostrar menu',
          'muestra el menu',
          'menu sutil',
          'menu rapido',
          'ver menu',
          'ver opciones',
        ])) {
      return const ItzliVrGuidance(
        actionType: ItzliActionType.uiCommand,
        speechResponse: 'Abriendo el menú sutil frente a tu mirada.',
        uiCommand: VrVoiceUiCommand.openMenu,
      );
    }
    if (_matchesAny(text, [
      'cierra el menu',
      'cerrar menu',
      'oculta el menu',
      'ocultar menu',
      'quita el menu',
    ])) {
      return const ItzliVrGuidance(
        actionType: ItzliActionType.uiCommand,
        speechResponse: 'Ocultando el menú.',
        uiCommand: VrVoiceUiCommand.closeMenu,
      );
    }
    if (_matchesAny(text, [
      'siguiente',
      'opcion siguiente',
      'siguiente opcion',
      'avanza opcion',
    ])) {
      return const ItzliVrGuidance(
        actionType: ItzliActionType.uiCommand,
        speechResponse: 'Siguiente opción.',
        uiCommand: VrVoiceUiCommand.nextItem,
      );
    }
    if (_matchesAny(text, [
      'anterior',
      'opcion anterior',
      'anterior opcion',
    ])) {
      return const ItzliVrGuidance(
        actionType: ItzliActionType.uiCommand,
        speechResponse: 'Opción anterior.',
        uiCommand: VrVoiceUiCommand.previousItem,
      );
    }
    if (_matchesAny(text, [
      'seleccionar',
      'selecciona',
      'confirmar',
      'confirma',
      'aceptar',
      'acepta',
      'entra ahi',
      'entrar ahi',
      'entra aqui',
      'entrar aqui',
      'abrir eso',
      'elige eso',
    ])) {
      return const ItzliVrGuidance(
        actionType: ItzliActionType.uiCommand,
        speechResponse: 'Confirmado.',
        uiCommand: VrVoiceUiCommand.confirmSelect,
      );
    }
    if (text == 'salir' ||
        _matchesAny(text, [
          'salir de la experiencia',
          'sal de aqui',
          'cerrar experiencia',
          'cerrar aplicacion',
          'volver atras',
          'regresa atras',
        ])) {
      return const ItzliVrGuidance(
        actionType: ItzliActionType.uiCommand,
        speechResponse: 'Saliendo de la vista actual.',
        uiCommand: VrVoiceUiCommand.goBack,
      );
    }

    // 0d. Specific Point Navigation ("ir a un punto específico": gaze, coords, booth, or room)
    final explicitOpenCatalogMatch =
        _matchesAny(text, ['abre ', 'abrir ', 'inicia ', 'iniciar '])
        ? _findExperience(text)
        : null;
    if (parsed.domain == NeomHeyInstructionDomain.spatialPointNavigation &&
        explicitOpenCatalogMatch == null) {
      final pointSpeech = parsed.targetX != null && parsed.targetZ != null
          ? 'Yendo al punto (${parsed.targetX!.toStringAsFixed(1)}, ${parsed.targetZ!.toStringAsFixed(1)}).'
          : (parsed.targetPointQuery != null
                ? 'Dirigiéndote hacia ${parsed.targetPointQuery}.'
                : 'Saltando al punto frente a tu mirada.');
      return ItzliVrGuidance(
        actionType: ItzliActionType.goToPoint,
        speechResponse: pointSpeech,
        targetPointQuery: parsed.targetPointQuery,
        targetX: parsed.targetX,
        targetZ: parsed.targetZ,
        useGazeTarget: parsed.useGazeTarget,
        distanceMeters: parsed.distanceMeters,
      );
    }

    // 0e. 3D Turn & Walk Locomotion from NeomHeyProtocol
    if (parsed.domain == NeomHeyInstructionDomain.locomotionTurn) {
      final deg = parsed.angleDegrees ?? 90.0;
      final dur = parsed.durationSeconds ?? 1.05;
      if (parsed.direction == NeomHeyDirection.around) {
        return ItzliVrGuidance(
          actionType: ItzliActionType.moveInSpace,
          speechResponse: 'Dando media vuelta.',
          motionKind: VrVoiceMotionKind.turnAround,
          motionDurationSeconds: dur,
          turnDegrees: 180,
        );
      }
      final isLeft = parsed.direction == NeomHeyDirection.left;
      final sideEs = isLeft ? 'la izquierda' : 'la derecha';
      return ItzliVrGuidance(
        actionType: ItzliActionType.moveInSpace,
        speechResponse: 'Girando ${deg.round()}° a $sideEs.',
        motionKind: isLeft
            ? VrVoiceMotionKind.turnLeft
            : VrVoiceMotionKind.turnRight,
        motionDurationSeconds: dur,
        turnDegrees: deg,
      );
    }

    if (parsed.domain == NeomHeyInstructionDomain.locomotionWalk) {
      final dur = parsed.durationSeconds ?? 2.2;
      final dist = parsed.distanceMeters;
      return switch (parsed.direction) {
        NeomHeyDirection.backward => ItzliVrGuidance(
          actionType: ItzliActionType.moveInSpace,
          speechResponse: 'Retrocediendo con suavidad.',
          motionKind: VrVoiceMotionKind.walkBackward,
          motionDurationSeconds: dur,
          distanceMeters: dist,
        ),
        NeomHeyDirection.left => ItzliVrGuidance(
          actionType: ItzliActionType.moveInSpace,
          speechResponse: 'Desplazándote a la izquierda.',
          motionKind: VrVoiceMotionKind.strafeLeft,
          motionDurationSeconds: dur,
          distanceMeters: dist,
        ),
        NeomHeyDirection.right => ItzliVrGuidance(
          actionType: ItzliActionType.moveInSpace,
          speechResponse: 'Desplazándote a la derecha.',
          motionKind: VrVoiceMotionKind.strafeRight,
          motionDurationSeconds: dur,
          distanceMeters: dist,
        ),
        _ => ItzliVrGuidance(
          actionType: ItzliActionType.moveInSpace,
          speechResponse: 'Avanzando hacia adelante.',
          motionKind: VrVoiceMotionKind.walkForward,
          motionDurationSeconds: dur,
          distanceMeters: dist,
        ),
      };
    }

    // Generic Famous Malls / Plazas 360° request before generic "plaza" home check
    if (_matchesAny(text, [
      'plazas famosas',
      'plazas 360',
      'centros comerciales',
      'centro comercial',
      'malls famosos',
      'locales en renta',
      'tiendas en renta',
    ])) {
      return const ItzliVrGuidance(
        actionType: ItzliActionType.launchExperience,
        speechResponse:
            'Entrando a las Plazas Famosas 360° con locales interactivos.',
        targetWingId: 'center',
        targetDemoId: 'mall_plaza_artz_mx',
        targetDemoTitle: 'Plaza Artz Pedregal 360°',
      );
    }

    // An explicit app launch takes precedence over words shared with looks
    // ("pon cine" opens the cinema; "cambia el estilo a cine" changes the look).
    final bestMatch = _findExperience(text);
    final wantsStyleChange = _matchesAny(text, [
      'estilo',
      'look',
      'tema',
      'atmosfera',
      'perfil',
    ]);
    final wantsLaunch = _matchesAny(text, [
      'jugar',
      'juega',
      'abrir',
      'abre',
      'entrar',
      'entra',
      'iniciar',
      'inicia',
      'pon',
      'poner',
      'cargar',
      'carga',
      'quiero ver',
      'quiero revisar',
      'quiero ir',
      'ensename',
      'muestra',
      'muestrame',
      'vamos a',
      'ir a',
      've a',
      'llevame a',
      'llevame al',
      'visitar',
      'visita',
      'explorar',
      'explora',
      'recorrer',
      'recorre',
    ]);
    if (!wantsStyleChange &&
        bestMatch != null &&
        (wantsLaunch || bestMatch.directLaunchOnMention)) {
      return ItzliVrGuidance(
        actionType: ItzliActionType.launchExperience,
        speechResponse: 'Abriendo ${bestMatch.title}.',
        targetWingId: bestMatch.wingId,
        targetDemoId: bestMatch.id,
        targetDemoTitle: bestMatch.title,
      );
    }

    // 1. Navigation to Home / Plaza Central
    if (text == 'plaza' ||
        _matchesAny(text, [
          'home',
          'inicio',
          'casa',
          'plaza central',
          'regresar',
          'volver',
          'centro',
          'sacame de aqui',
          'principal',
        ])) {
      return const ItzliVrGuidance(
        actionType: ItzliActionType.jumpToWing,
        speechResponse: 'Te llevo de regreso a la Plaza Central ✨',
        targetWingId: 'center',
      );
    }

    // 1b. Direct Cardinal Wing Jumps
    if (_matchesAny(text, [
      'ala norte',
      'zona norte',
      'ala de juegos',
      'ala estrategia',
    ])) {
      return const ItzliVrGuidance(
        actionType: ItzliActionType.jumpToWing,
        speechResponse: 'Saltando al Ala Norte de Estrategia y Juegos 🎮',
        targetWingId: 'north_games',
      );
    }
    if (_matchesAny(text, [
      'ala este',
      'zona este',
      'ala de productividad',
    ])) {
      return const ItzliVrGuidance(
        actionType: ItzliActionType.jumpToWing,
        speechResponse: 'Saltando al Ala Este de Productividad 📊',
        targetWingId: 'east_prod',
      );
    }
    if (_matchesAny(text, [
      'ala oeste',
      'zona oeste',
      'ala multimedia',
      'ala de cine',
    ])) {
      return const ItzliVrGuidance(
        actionType: ItzliActionType.jumpToWing,
        speechResponse: 'Saltando al Ala Oeste de Multimedia y Cine 🎬',
        targetWingId: 'west_media',
      );
    }
    if (_matchesAny(text, [
      'ala sur',
      'zona sur',
      'ala laboratorio',
      'laboratorio sota',
    ])) {
      return const ItzliVrGuidance(
        actionType: ItzliActionType.jumpToWing,
        speechResponse: 'Saltando al Ala Sur de Laboratorio Sensorial 🔬',
        targetWingId: 'south_labs',
      );
    }

    // 2. Visual Style / Theme Requests
    if (_matchesAny(text, [
      'cyberpunk',
      'neon',
      'luces',
      'futurista',
      'electrico',
      'oscuro con color',
    ])) {
      return const ItzliVrGuidance(
        actionType: ItzliActionType.changeLook,
        speechResponse:
            'Activando estilo Cyberpunk Neón con negros puros y brillo radiante ⚡',
        targetLook: VrLook.cyberpunk,
      );
    }
    if (_matchesAny(text, [
      'estrellas',
      'nebulosa',
      'espacio',
      'galactico',
      'estelar',
      'cosmico',
    ])) {
      return ItzliVrGuidance(
        actionType: ItzliActionType.changeLook,
        speechResponse:
            'Activando atmósfera de Nebulosa Estelar con niebla cósmica 🌌',
        targetLook: VrLook.stellar,
      );
    }
    if (_matchesAny(text, [
      'cine',
      'cinematografico',
      'realista',
      'hdr',
      'sombras',
    ])) {
      return const ItzliVrGuidance(
        actionType: ItzliActionType.changeLook,
        speechResponse:
            'Configurando perfil Cinematográfico con oclusión ambiental 🎬',
        targetLook: VrLook.cinematic,
      );
    }

    // 3. Resolution / Quality Requests
    if (_matchesAny(text, [
      'nitidez',
      'resolucion',
      'ultra',
      'hd',
      'borroso',
      'mas nitido',
      'alta definicion',
      'supersampling',
    ])) {
      return const ItzliVrGuidance(
        actionType: ItzliActionType.changeResolution,
        speechResponse:
            'Ajustando resolución a Ultra HD con supersampling 1.15x para máxima claridad 💎',
        targetPreset: VrQualityPreset.ultra,
      );
    }

    // 4. Recenter View
    if (_matchesAny(text, [
      'centrar',
      'recentrar',
      'alinear',
      'horizonte',
      'me desvie',
    ])) {
      return const ItzliVrGuidance(
        actionType: ItzliActionType.recenter,
        speechResponse: 'Recentrado tu vista y horizonte al punto cero 🎯',
      );
    }

    // 5. 2D Catalog Mode
    if (_matchesAny(text, [
      'catalogo',
      '2d',
      'lista',
      'menu plano',
      'cuadricula',
    ])) {
      return const ItzliVrGuidance(
        actionType: ItzliActionType.switchCatalog2D,
        speechResponse: 'Cambiando a la vista de Catálogo 2D 📱',
      );
    }

    // 6. Natural Language App Search across all indexed experiences
    if (bestMatch != null) {
      return ItzliVrGuidance(
        actionType: ItzliActionType.jumpToWing,
        speechResponse:
            'Saltando hacia el ${bestMatch.wingName}. Aquí tienes ${bestMatch.title} 📍',
        targetWingId: bestMatch.wingId,
        targetDemoId: bestMatch.id,
        targetDemoTitle: bestMatch.title,
      );
    }

    // 7. Mood / Category based Semantic Routing
    if (_matchesAny(text, [
      'jugar',
      'juego',
      'videojuego',
      'divertirme',
      'entretenimiento',
      'batalla',
    ])) {
      return const ItzliVrGuidance(
        actionType: ItzliActionType.jumpToWing,
        speechResponse:
            'Te llevo al Ala de Estrategia & Juegos. Aquí tienes Ajedrez Cósmico y Comando Orbital 🎮',
        targetWingId: 'north_games',
      );
    }
    if (_matchesAny(text, [
      'trabajar',
      'organizar',
      'productividad',
      'tareas',
      'oficina',
      'pendientes',
    ])) {
      return const ItzliVrGuidance(
        actionType: ItzliActionType.jumpToWing,
        speechResponse:
            'Dirigiéndote al Ala de Productividad con tableros Kanban, Dashboard y Notas VR 📊',
        targetWingId: 'east_prod',
      );
    }
    if (_matchesAny(text, [
      'relajarme',
      'ver algo',
      'pelicula',
      'descansar',
      'videos',
      'paisaje',
    ])) {
      return const ItzliVrGuidance(
        actionType: ItzliActionType.jumpToWing,
        speechResponse:
            'Vamos al Ala Multimedia para disfrutar de Cine VR 360° o la Galería de Arte 🎬',
        targetWingId: 'west_media',
      );
    }
    if (_matchesAny(text, [
      'sensores',
      'sonar',
      'camara',
      'tecnologia',
      'experimento',
      'laboratorio',
      'sota',
    ])) {
      return const ItzliVrGuidance(
        actionType: ItzliActionType.jumpToWing,
        speechResponse:
            'Te llevo al Ala de Laboratorio Sensorial SOTA para experimentar Sónar y Hand Tracking 🔬',
        targetWingId: 'south_labs',
      );
    }

    // 8. General conversational fallback
    return const ItzliVrGuidance(
      actionType: ItzliActionType.conversationalGuidance,
      speechResponse:
          'Soy VR, tu guía manos libres de VRlizate. Di «Hey VR» y pide "camina adelante", "gira a la derecha", "abre TV gratis", "abre Plaza Artz" o "abre el menú" ✨',
    );
  }

  /// Asynchronously interprets user request with local on-device SLM inference fallback.
  Future<ItzliVrGuidance> processVoiceInputAsync(String naturalSpeech) async {
    final quickResult = interpretRequest(naturalSpeech);
    if (quickResult.actionType != ItzliActionType.conversationalGuidance) {
      return quickResult;
    }

    final localModelResult =
        await SaiaSpatialInferenceBridge.inferIntentLocally(naturalSpeech);
    if (localModelResult != null) {
      return localModelResult;
    }

    return quickResult;
  }

  static bool _matchesAny(String text, List<String> terms) {
    for (final term in terms) {
      if (RegExp(
        '(^|[^a-z0-9])${RegExp.escape(_normalize(term))}([^a-z0-9]|\$)',
      ).hasMatch(text)) {
        return true;
      }
    }
    return false;
  }

  static _ItzliExperienceMetadata? _findExperience(String text) {
    _ItzliExperienceMetadata? bestMatch;
    var bestScore = 0;
    for (final experience in _catalog) {
      var score = _matchesAny(text, [experience.title]) ? 10 : 0;
      for (final keyword in experience.keywords) {
        if (_matchesAny(text, [keyword])) score += 3;
      }
      if (score > bestScore) {
        bestScore = score;
        bestMatch = experience;
      }
    }
    return bestMatch;
  }

  static String _normalize(String text) {
    var result = text.toLowerCase().trim();
    const accented = 'áéíóúüñ';
    const plain = 'aeiouun';
    for (var i = 0; i < accented.length; i++) {
      result = result.replaceAll(accented[i], plain[i]);
    }
    return result;
  }
}
