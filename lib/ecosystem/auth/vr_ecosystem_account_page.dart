import 'package:flutter/material.dart';
import 'package:neom_auth/ui/login/login_controller.dart';
import 'package:neom_auth/utils/enums/login_method.dart';

import 'vr_ecosystem_login_controller.dart';
import 'vr_ecosystem_session.dart';

/// A small host view for the shared LoginController, without its application
/// menus, automatic onboarding routes or unconfigured OAuth providers.
class VrEcosystemAccountPage extends StatefulWidget {
  const VrEcosystemAccountPage({
    super.key,
    required this.session,
    this.onContinue,
  });
  final VrEcosystemSession session;
  final VoidCallback? onContinue;

  @override
  State<VrEcosystemAccountPage> createState() => _VrEcosystemAccountPageState();
}

class _VrEcosystemAccountPageState extends State<VrEcosystemAccountPage> {
  final _formKey = GlobalKey<FormState>();
  bool _submitting = false;
  String? _error;

  void _continue() {
    if (widget.onContinue != null) {
      widget.onContinue!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _submit(LoginController login) async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await login.handleLogin(LoginMethod.email);
      widget.session.refresh();
    } catch (_) {
      if (mounted) _error = 'No pudimos iniciar sesión. Inténtalo de nuevo.';
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _signOut() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.session.signOut();
    } catch (_) {
      if (mounted) {
        _error =
            'La sesión local se cerró. Revisa tu conexión para completar '
            'el cierre de sesión.';
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.session,
    builder: (context, _) {
      final session = widget.session;
      final service = session.loginService;
      final login = service is LoginController ? service : null;
      final message = service is VrEcosystemLoginController
          ? service.message
          : null;
      final busy = _submitting || (login?.isLoading.value ?? false);
      return Scaffold(
        appBar: AppBar(title: const Text('Tu cuenta en VRlizate')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.account_circle_outlined, size: 64),
                    const SizedBox(height: 20),
                    if (!session.backendReady || login == null) ...[
                      Text(
                        session.unavailableMessage ??
                            'Las cuentas todavía no están disponibles. '
                                'Puedes explorar como invitado.',
                        textAlign: TextAlign.center,
                      ),
                    ] else if (session.isAuthenticated) ...[
                      Text(
                        session.userService!.profile.name,
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Tu sesión está lista para las salas de tu cuenta.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      OutlinedButton(
                        onPressed: busy ? null : _signOut,
                        child: const Text('Cerrar sesión'),
                      ),
                    ] else ...[
                      const Text(
                        'Inicia sesión con una cuenta existente para acceder '
                        'a tu perfil y publicar.',
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: login.emailController,
                        enabled: !busy,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.username],
                        decoration: const InputDecoration(labelText: 'Correo'),
                        validator: (value) => value?.trim().isNotEmpty == true
                            ? null
                            : 'Escribe tu correo.',
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: login.passwordController,
                        enabled: !busy,
                        obscureText: true,
                        autofillHints: const [AutofillHints.password],
                        decoration: const InputDecoration(
                          labelText: 'Contraseña',
                        ),
                        validator: (value) => value?.isNotEmpty == true
                            ? null
                            : 'Escribe tu contraseña.',
                        onFieldSubmitted: (_) => _submit(login),
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: busy ? null : () => _submit(login),
                        child: Text(busy ? 'Conectando…' : 'Iniciar sesión'),
                      ),
                    ],
                    if (_error ?? message case final String text) ...[
                      const SizedBox(height: 12),
                      Text(text, textAlign: TextAlign.center),
                    ],
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _continue,
                      child: Text(
                        session.isAuthenticated
                            ? 'Volver a las salas'
                            : 'Seguir explorando como invitado',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
