import 'package:neom_core/utils/enums/app_in_use.dart';

enum NeomHeyInstructionDomain {
  general,
  locomotionStop,
  locomotionTurn,
  locomotionWalk,
  spatialPointNavigation,
}

enum NeomHeyDirection {
  forward,
  backward,
  left,
  right,
  around,
}

class NeomHeyAppProfile {
  final AppInUse app;
  final String canonicalWakePhrase;
  final String greetingEs;

  const NeomHeyAppProfile({
    required this.app,
    this.canonicalWakePhrase = 'Hey VR',
    this.greetingEs = 'Hola, soy VR. ¿A dónde quieres ir?',
  });
}

class NeomHeyInstructionSpec {
  final String id;
  final String descriptionEs;

  const NeomHeyInstructionSpec({
    required this.id,
    required this.descriptionEs,
  });
}

class NeomHeyWakeMatch {
  final bool addressed;
  final String matchedWakePhrase;
  final String commandText;

  const NeomHeyWakeMatch({
    required this.addressed,
    required this.matchedWakePhrase,
    required this.commandText,
  });

  bool get isWakeOnly => addressed && commandText.isEmpty;
}

class NeomHeyParsedInstruction {
  final NeomHeyWakeMatch wake;
  final bool asksCapabilities;
  final NeomHeyInstructionDomain domain;
  final NeomHeyDirection? direction;
  final double? angleDegrees;
  final double? durationSeconds;
  final double? distanceMeters;
  final String? targetPointQuery;
  final double? targetX;
  final double? targetZ;
  final bool useGazeTarget;

  const NeomHeyParsedInstruction({
    required this.wake,
    this.asksCapabilities = false,
    this.domain = NeomHeyInstructionDomain.general,
    this.direction,
    this.angleDegrees,
    this.durationSeconds,
    this.distanceMeters,
    this.targetPointQuery,
    this.targetX,
    this.targetZ,
    this.useGazeTarget = false,
  });
}

class NeomHeyProtocol {
  static const List<String> _vrWakePhrases = <String>[
    'hey vr',
    'hey ve erre',
    'hey viar',
    'vr',
  ];

  static const List<String> _pakalWakePhrases = <String>[
    'hey pakal',
    'oye pakal',
    'hey pacal',
    'oye pacal',
    'ok pakal',
    'hey pakhal',
    'pakal',
    'pacal',
  ];

  static NeomHeyAppProfile profileFor(AppInUse app) {
    if (app == AppInUse.b) {
      return const NeomHeyAppProfile(
        app: AppInUse.b,
        canonicalWakePhrase: 'Hey Pakal',
        greetingEs: 'Pakal listo. Indica modo, frecuencia, potencia o silencio.',
      );
    }
    return NeomHeyAppProfile(app: app);
  }

  static List<String> wakePhrasesFor(AppInUse? app) {
    if (app == AppInUse.b) {
      return _pakalWakePhrases;
    }
    return _vrWakePhrases;
  }

  static List<NeomHeyInstructionSpec> capabilitiesFor(AppInUse app) {
    if (app == AppInUse.b) {
      return const <NeomHeyInstructionSpec>[
        NeomHeyInstructionSpec(
          id: 'daal_activate',
          descriptionEs:
              'Activar topología DAAL 4×4, DAAM 3×3, DAAC 2×2, Centinela, Tinaco o Escudo con frecuencia en Hz.',
        ),
        NeomHeyInstructionSpec(
          id: 'daal_frequency',
          descriptionEs:
              'Sintonizar portadora acústica en Hz (ej. "activa DAAL a 1000 Hz" o "frecuencia 432 Hz").',
        ),
        NeomHeyInstructionSpec(
          id: 'daal_power_steer',
          descriptionEs:
              'Ajustar potencia en porcentaje y dirección del haz (izquierda, derecha, centro).',
        ),
        NeomHeyInstructionSpec(
          id: 'daal_mute',
          descriptionEs:
              'Corte de emergencia inmediato ("corte", "silencio", "apagar", "mute").',
        ),
      ];
    }
    return const [];
  }

  static String capabilitiesSummaryEs(AppInUse app) {
    if (app == AppInUse.b) {
      return 'Di "Hey Pakal, activa DAAL a 1000 Hz", "Hey Pakal, modo Centinela", "potencia 80" o "corte".';
    }
    return 'Puedes pedirme abrir experiencias, cambiar de sala o moverte en el espacio.';
  }

  static NeomHeyWakeMatch detectWakeCall(String rawSpeech, {AppInUse? app}) {
    final normalized = rawSpeech
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'^[¡¿\s]+'), '')
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u');
    final phrases = wakePhrasesFor(app);
    for (final phrase in phrases) {
      if (normalized == phrase) {
        return NeomHeyWakeMatch(
          addressed: true,
          matchedWakePhrase: phrase,
          commandText: '',
        );
      }
      if (normalized.startsWith(phrase) && normalized.length > phrase.length) {
        final nextChar = normalized[phrase.length];
        if (RegExp(r'[\s,:;.!?-]').hasMatch(nextChar)) {
          final rest = normalized
              .substring(phrase.length)
              .replaceFirst(RegExp(r'^[\s,:;.!?-]+'), '')
              .trim();
          return NeomHeyWakeMatch(
            addressed: true,
            matchedWakePhrase: phrase,
            commandText: rest,
          );
        }
      }
    }
    return NeomHeyWakeMatch(
      addressed: false,
      matchedWakePhrase: '',
      commandText: normalized,
    );
  }

  static NeomHeyParsedInstruction parseInstruction(
    String rawSpeech, {
    AppInUse? app,
  }) {
    final wake = detectWakeCall(rawSpeech, app: app);
    return NeomHeyParsedInstruction(wake: wake);
  }
}
