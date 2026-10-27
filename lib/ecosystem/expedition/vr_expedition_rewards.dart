import 'package:vrlizate_apps/vrlizate_apps_expedition.dart';
import 'package:vrlizate_avatar/vrlizate_avatar.dart';

import '../auth/vr_ecosystem_session.dart';
import 'vr_expedition_store.dart';

/// Reads the existing durable passport. No second inventory, reward flags,
/// network calls or account service are created by this adapter.
abstract final class NeomVrExpeditionRewards {
  static Future<Set<String>> read({
    required VrlzExpeditionDefinition definition,
    VrEcosystemSession? session,
  }) async {
    final store = await NeomVrExpeditionStore.open(session: session);
    final controller = VrlzExpeditionController(
      definition: definition,
      store: store,
    );
    try {
      await controller.restore();
      if (!store.isCurrent) throw StateError('Expedition session changed.');
      final earned = controller.rewardIds;
      return Set<String>.unmodifiable({
        for (final cosmetic in VrAvatarCosmeticCatalog.all)
          if (earned.contains(cosmetic.id)) cosmetic.id,
      });
    } finally {
      controller.dispose();
      store.dispose();
    }
  }
}
