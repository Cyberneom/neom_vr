import 'dart:convert';
import 'package:vrlizate_scene/vrlizate_scene.dart';

import 'itzli_vr_assistant.dart';

/// Prompt/JSON adapter for a future local inference backend.
/// [inferIntentLocally] currently uses keyword rules, not an installed SLM.
class SaiaSpatialInferenceBridge {
  static const String systemInstruction = '''
You are Itzli, the intelligent spatial AI assistant of the VRlizate virtual reality ecosystem.
The user speaks in natural Spanish. Your job is to extract their spatial navigation intent and return a JSON object with:
- "action": One of ["jumpToWing", "launchExperience", "changeLook", "changeResolution", "recenter", "conversationalGuidance"]
- "targetWingId": One of ["north_games", "east_prod", "west_media", "south_labs", "center"] (optional)
- "targetDemoId": The demo identifier if the user wants to play/open an experience (e.g. "cosmic_chess", "vr_cinema", "vr_kanban", "holographic_hands", etc.)
- "targetLook": One of ["cyberpunk", "stellar", "cinematic", "night"] (optional)
- "speechResponse": A warm, helpful, short response in Spanish with emojis.
''';

  /// Builds a structured prompt for local SLM execution.
  static String buildPrompt(String userSpeech) {
    return '''
$systemInstruction

User said: "$userSpeech"
Return only valid JSON.
''';
  }

  /// Parses the raw JSON response emitted by an on-device local SLM into [ItzliVrGuidance].
  static ItzliVrGuidance? parseJsonResponse(String rawResponse) {
    try {
      final cleanJson = _extractJsonBlock(rawResponse);
      final map = jsonDecode(cleanJson) as Map<String, dynamic>;

      final actionStr = map['action'] as String? ?? 'conversationalGuidance';
      final speechResponse =
          map['speechResponse'] as String? ?? 'Te ayudo con gusto ✨';
      final targetWingId = map['targetWingId'] as String?;
      final targetDemoId = map['targetDemoId'] as String?;
      final targetLookStr = map['targetLook'] as String?;

      ItzliActionType actionType;
      switch (actionStr) {
        case 'jumpToWing':
          actionType = ItzliActionType.jumpToWing;
          break;
        case 'launchExperience':
          actionType = ItzliActionType.launchExperience;
          break;
        case 'changeLook':
          actionType = ItzliActionType.changeLook;
          break;
        case 'changeResolution':
          actionType = ItzliActionType.changeResolution;
          break;
        case 'recenter':
          actionType = ItzliActionType.recenter;
          break;
        default:
          actionType = ItzliActionType.conversationalGuidance;
      }

      VrLook? look;
      if (targetLookStr == 'cyberpunk') look = VrLook.cyberpunk;
      if (targetLookStr == 'stellar') look = VrLook.stellar;
      if (targetLookStr == 'cinematic') look = VrLook.cinematic;
      if (targetLookStr == 'night') look = VrLook.night;

      return ItzliVrGuidance(
        actionType: actionType,
        speechResponse: speechResponse,
        targetWingId: targetWingId,
        targetDemoId: targetDemoId,
        targetLook: look,
        confidence: 0.92,
      );
    } catch (_) {
      return null;
    }
  }

  /// Rule-based fallback. No model weights or inference runtime are loaded.
  static Future<ItzliVrGuidance?> inferIntentLocally(String userSpeech) async {
    final lower = userSpeech.toLowerCase().trim();

    // Contextual mood/intent mapping handled by the edge inference bridge
    if (lower.contains('cansado') ||
        lower.contains('distraerme') ||
        lower.contains('aburrido')) {
      return const ItzliVrGuidance(
        actionType: ItzliActionType.jumpToWing,
        speechResponse:
            'Te recomiendo descansar un rato en el Ala Multimedia con Cine VR 360° o la Galería PBR 🎬',
        targetWingId: 'west_media',
        confidence: 0.90,
      );
    }

    if (lower.contains('concentrarme') ||
        lower.contains('estudiar') ||
        lower.contains('apuntes')) {
      return const ItzliVrGuidance(
        actionType: ItzliActionType.jumpToWing,
        speechResponse:
            'Vamos al Ala de Productividad para revisar tus Notas Espaciales y tablero Kanban 📊',
        targetWingId: 'east_prod',
        confidence: 0.90,
      );
    }

    if (lower.contains('competir') ||
        lower.contains('reto') ||
        lower.contains('desafío')) {
      return const ItzliVrGuidance(
        actionType: ItzliActionType.jumpToWing,
        speechResponse:
            'Para un buen reto mental, te llevo al Ala Norte para jugar Ajedrez Cósmico ♟️',
        targetWingId: 'north_games',
        confidence: 0.90,
      );
    }

    return null;
  }

  static String _extractJsonBlock(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      return text.substring(start, end + 1);
    }
    return text;
  }
}
