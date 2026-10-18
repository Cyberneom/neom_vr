import 'package:flutter/material.dart';

import 'vr_ecosystem_session.dart';

/// Gates direct routes as well as room entry. The protected subtree is destroyed
/// on logout or profile/account change, so its cached state cannot survive.
class VrEcosystemRouteGuard extends StatelessWidget {
  const VrEcosystemRouteGuard({
    super.key,
    required this.session,
    required this.builder,
    this.onSignIn,
  });

  final VrEcosystemSession session;
  final Widget Function(BuildContext context, VrEcosystemIdentity identity)
  builder;
  final VoidCallback? onSignIn;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: session,
    builder: (context, _) {
      final identity = session.captureIdentity();
      if (identity != null) {
        return KeyedSubtree(
          key: ValueKey(
            '${identity.uid}:${identity.profileId}:${identity.revision}',
          ),
          child: builder(context, identity),
        );
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Acceso a tu cuenta')),
        body: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    session.backendReady
                        ? 'Inicia sesión para entrar a esta sala.'
                        : session.unavailableMessage ??
                              'Esta sala de cuenta todavía no está disponible.',
                    textAlign: TextAlign.center,
                  ),
                  if (session.backendReady && onSignIn != null) ...[
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: onSignIn,
                      child: const Text('Iniciar sesión'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
