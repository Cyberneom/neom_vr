import 'package:flutter/material.dart';

import '../auth/vr_ecosystem_session.dart';

/// Reads the verified shared UserService; it never loads another account or
/// stores a duplicate profile and delegates logout to the session owner.
class VrEcosystemProfilePage extends StatefulWidget {
  const VrEcosystemProfilePage({
    super.key,
    required this.session,
    required this.identity,
  });
  final VrEcosystemSession session;
  final VrEcosystemIdentity identity;

  @override
  State<VrEcosystemProfilePage> createState() => _VrEcosystemProfilePageState();
}

class _VrEcosystemProfilePageState extends State<VrEcosystemProfilePage> {
  bool _busy = false;
  String? _error;

  Future<void> _signOut() async {
    if (_busy || !widget.identity.isCurrent()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.signOut();
    } catch (_) {
      if (mounted) _error = 'La sesión local se cerró. Revisa tu conexión.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.session,
    builder: (context, _) {
      final current = widget.identity.isCurrent();
      final profile = current ? widget.session.userService?.profile : null;
      return Scaffold(
        appBar: AppBar(title: const Text('Mi perfil')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.account_circle_outlined, size: 76),
              const SizedBox(height: 24),
              if (profile == null)
                const Text('La sesión cambió. Vuelve a entrar a esta sala.')
              else ...[
                Text(
                  profile.name,
                  key: const ValueKey('profile_name'),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  profile.aboutMe.isEmpty
                      ? 'Tu espacio personal en VRlizate.'
                      : profile.aboutMe,
                ),
                const SizedBox(height: 24),
                Text(
                  '${profile.posts?.length ?? 0} publicaciones · ${profile.followers?.length ?? 0} seguidores',
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  key: const ValueKey('profile_sign_out'),
                  onPressed: _busy ? null : _signOut,
                  child: Text(_busy ? 'Cerrando sesión…' : 'Cerrar sesión'),
                ),
              ],
              if (_error != null) Text(_error!),
            ],
          ),
        ),
      );
    },
  );
}
