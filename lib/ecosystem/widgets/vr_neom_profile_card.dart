import 'package:flutter/material.dart';
import 'package:neom_commons/ui/widgets/profile_stats_card.dart';

import '../auth/vr_ecosystem_session.dart';

/// The existing NEOM profile presentation, sized for a world-space surface.
/// Account ownership remains with [session]; this widget never loads a profile.
class VrNeomProfileCard extends StatelessWidget {
  const VrNeomProfileCard({
    super.key,
    required this.session,
    required this.identity,
  });

  static const logicalSize = Size(720, 300);

  final VrEcosystemSession session;
  final VrEcosystemIdentity identity;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: session,
    builder: (context, _) {
      if (!identity.isCurrent()) {
        return const Center(
          child: Text(
            'La sesión cambió. Vuelve a abrir tu perfil.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 24),
          ),
        );
      }
      final profile = session.userService!.profile;
      return ExcludeFocus(
        child: IgnorePointer(
          child: Material(
            color: Colors.transparent,
            child: Center(
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: 440,
                  child: ProfileStatsCard(
                    profile: profile,
                    // Do not turn an absent avatar into another network load.
                    showAvatar: profile.photoUrl.isNotEmpty,
                    customStats: [
                      ProfileStatConfig(
                        label: 'Publicaciones',
                        value: '${profile.posts?.length ?? 0}',
                        numericValue: profile.posts?.length ?? 0,
                        icon: Icons.grid_on_rounded,
                      ),
                      ProfileStatConfig(
                        label: 'Seguidores',
                        value: '${profile.followers?.length ?? 0}',
                        numericValue: profile.followers?.length ?? 0,
                        icon: Icons.people_outline,
                      ),
                      ProfileStatConfig(
                        label: 'Siguiendo',
                        value: '${profile.following?.length ?? 0}',
                        numericValue: profile.following?.length ?? 0,
                        icon: Icons.person_add_outlined,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
