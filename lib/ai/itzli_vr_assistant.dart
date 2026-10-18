import 'package:vrlizate_scene/vrlizate_scene.dart';

import 'saia_spatial_inference_bridge.dart';

/// Spatial Action determined by Itzli AI Assistant.
enum ItzliActionType {
  jumpToWing,
  launchExperience,
  changeLook,
  changeResolution,
  recenter,
  switchCatalog2D,
  conversationalGuidance,
}

/// Structured response emitted by Itzli VR Assistant.
class ItzliVrGuidance {
  final ItzliActionType actionType;
  final String speechResponse;
  final String? targetWingId;
  final String? targetDemoId;
  final String? targetDemoTitle;
  final VrLook? targetLook;
  final VrQualityPreset? targetPreset;
  final double confidence;

  const ItzliVrGuidance({
    required this.actionType,
    required this.speechResponse,
    this.targetWingId,
    this.targetDemoId,
    this.targetDemoTitle,
    this.targetLook,
    this.targetPreset,
    this.confidence = 0.95,
  });
}

/// Metadata definition of an experience indexed by Itzli.
class _ItzliExperienceMetadata {
  final String id;
  final String title;
  final String wingId;
  final String wingName;
  final List<String> keywords;
  final String categoryDescription;

  const _ItzliExperienceMetadata({
    required this.id,
    required this.title,
    required this.wingId,
    required this.wingName,
    required this.keywords,
    required this.categoryDescription,
  });
}

/// Deterministic Spanish intent router for VRlizate.
///
/// Functions as the intelligent virtual guide and spatial copilot of the VRlizate ecosystem:
/// 1. Understands natural language requests in Spanish across all 19 spatial apps.
/// 2. Resolves intent to exact wings (Estrategia, Productividad, Cine, SOTA Labs).
/// 3. Recommends apps based on user mood ("quiero relajarme", "vamos a jugar", "tengo que trabajar").
/// 4. Adjusts visual looks, HDR bloom, and resolution on the fly.
class ItzliVrAssistant {
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
        'itzli',
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
  ];

  /// Interprets user natural language speech and resolves spatial guidance.
  ItzliVrGuidance interpretRequest(String naturalSpeech) {
    final text = _normalize(naturalSpeech);

    // 1. Navigation to Home / Plaza Central
    if (_matchesAny(text, [
      'home',
      'inicio',
      'casa',
      'plaza',
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

    // An explicit app launch takes precedence over words shared with looks
    // ("pon cine" opens the cinema; "estilo cine" changes the look).
    final bestMatch = _findExperience(text);
    final wantsLaunch = _matchesAny(text, [
      'jugar',
      'abrir',
      'abre',
      'entrar',
      'iniciar',
      'inicia',
      'pon',
      'cargar',
      'quiero ver',
      'quiero revisar',
      'ensename',
      'muestra',
      'vamos a',
    ]);
    if (wantsLaunch && bestMatch != null) {
      return ItzliVrGuidance(
        actionType: ItzliActionType.launchExperience,
        speechResponse: 'Mostrando la ficha de ${bestMatch.title}.',
        targetWingId: bestMatch.wingId,
        targetDemoId: bestMatch.id,
        targetDemoTitle: bestMatch.title,
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

    // 6. Natural Language App Search across the 19 experiences
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
    return ItzliVrGuidance(
      actionType: ItzliActionType.conversationalGuidance,
      speechResponse:
          'Soy Itzli, tu guía en VRlizate. Puedes pedirme "llévame a jugar ajedrez", "abre kanban", "pon cine 360", o "cambia a estilo cyberpunk" ✨',
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
