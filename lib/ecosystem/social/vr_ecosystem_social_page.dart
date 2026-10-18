import 'dart:async';

import 'package:flutter/material.dart';
import 'package:neom_core/domain/model/post.dart';

import '../auth/vr_ecosystem_session.dart';
import 'vr_ecosystem_social_source.dart';

class VrEcosystemSocialPage extends StatefulWidget {
  const VrEcosystemSocialPage({
    super.key,
    required this.session,
    required this.identity,
    this.sourceFactory,
  });
  final VrEcosystemSession session;
  final VrEcosystemIdentity identity;
  final VrEcosystemSocialSource Function()? sourceFactory;

  @override
  State<VrEcosystemSocialPage> createState() => _VrEcosystemSocialPageState();
}

class _VrEcosystemSocialPageState extends State<VrEcosystemSocialPage> {
  final _text = TextEditingController();
  late final VrEcosystemSocialSource _source;
  bool _busy = false, _expired = false;
  String? _message;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _source =
        widget.sourceFactory?.call() ??
        NeomVrEcosystemSocialSource(
          session: widget.session,
          identity: widget.identity,
        );
    _source.addListener(_changed);
    widget.session.addListener(_sessionChanged);
    unawaited(_load(initial: true));
  }

  bool get _current => mounted && !_expired && widget.identity.isCurrent();
  void _changed() {
    if (_current) setState(() {});
  }

  void _sessionChanged() {
    if (!mounted || widget.identity.isCurrent() || _expired) return;
    _generation++;
    _source.invalidate();
    _text.clear();
    setState(() {
      _expired = true;
      _busy = false;
      _message = null;
    });
  }

  Future<void> _load({bool initial = false}) async {
    if (!_current || _busy) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      widget.identity.requireCurrent();
      if (initial) {
        await _source.initialize();
      } else {
        await _source.refresh();
      }
    } catch (_) {
      if (_current && generation == _generation) {
        setState(
          () => _message = 'No se pudo abrir el muro. Inténtalo de nuevo.',
        );
      }
    } finally {
      if (_current && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (!_current || _busy || _text.text.trim().isEmpty) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      widget.identity.requireCurrent();
      final saved = await _source.submitText(_text.text);
      if (!_current || generation != _generation) return;
      setState(() {
        if (saved) _text.clear();
        _message = saved
            ? 'Publicación guardada en esta cuenta. El muro muestra si sigue pendiente de envío.'
            : 'No se pudo guardar. Tu texto sigue aquí para reintentar.';
      });
    } catch (_) {
      if (_current && generation == _generation) {
        setState(() => _message = 'No se pudo guardar. Inténtalo de nuevo.');
      }
    } finally {
      if (_current && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _generation++;
    widget.session.removeListener(_sessionChanged);
    _source.removeListener(_changed);
    _source.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Muro social'),
      actions: [
        IconButton(
          key: const ValueKey('social_refresh'),
          tooltip: 'Actualizar y reintentar envío',
          onPressed: !_current || _busy ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: !_current
        ? const Center(
            child: Text('La sesión cambió. Vuelve a entrar a esta sala.'),
          )
        : ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text('Comparte una publicación de texto con la comunidad.'),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('social_caption'),
                controller: _text,
                enabled: !_busy,
                minLines: 3,
                maxLines: 8,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: '¿Qué quieres compartir?',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const ValueKey('social_submit'),
                onPressed: _busy ? null : _submit,
                icon: const Icon(Icons.send_outlined),
                label: Text(_busy ? 'Procesando…' : 'Guardar publicación'),
              ),
              const SizedBox(height: 16),
              if (_message != null) Text(_message!),
              if (_source.loadMessage != null) Text(_source.loadMessage!),
              if (_source.offline)
                const Text(
                  'Mostrando contenido guardado. El envío requiere conexión.',
                ),
              const Text(
                'Usa Actualizar para reintentar las publicaciones pendientes.',
              ),
              if (_busy) const LinearProgressIndicator(),
              const SizedBox(height: 24),
              if (_source.posts.isEmpty && !_busy)
                const Text('Todavía no hay publicaciones para mostrar.'),
              for (final post in _source.posts) _post(post),
            ],
          ),
  );

  Widget _post(Post post) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            post.profileName.isEmpty ? 'Comunidad' : post.profileName,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(post.caption),
          if (post.id.startsWith('pending_')) ...[
            const SizedBox(height: 10),
            const Text(
              'Pendiente de envío',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
    ),
  );
}
