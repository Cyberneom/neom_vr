import 'dart:async';

import 'package:flutter/material.dart';

import 'vr_content_playback.dart';
import 'vr_content_provider.dart';

/// A host route; Home only launches it. Account services, endpoint configuration
/// and the shared audio player remain owned by the official application.
class VrContentRoomPage extends StatefulWidget {
  const VrContentRoomPage({
    super.key,
    required this.provider,
    required this.captureIdentity,
    required this.sessionChanges,
    required this.playback,
    this.ownsProvider = false,
  });
  final VrContentProvider provider;
  final VrContentIdentity? Function() captureIdentity;
  final Listenable sessionChanges;
  final VrContentPlayback playback;
  final bool ownsProvider;

  @override
  State<VrContentRoomPage> createState() => _VrContentRoomPageState();
}

class _VrContentRoomPageState extends State<VrContentRoomPage>
    with WidgetsBindingObserver {
  List<VrContentItem> _items = const [];
  String? _error;
  bool _busy = false;
  bool _visible = true;
  int _generation = 0;
  VrContentIdentity? _identity;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.sessionChanges.addListener(_sessionChanged);
    unawaited(_load());
  }

  void _stop() => unawaited(widget.playback.pause().catchError((Object _) {}));

  void _sessionChanged() {
    if (!mounted) return;
    // Unrelated account UI notifications do not interrupt an unchanged session.
    if (_identity?.isCurrent() == true) return;
    _generation++;
    _stop();
    setState(() {
      _items = const [];
      _busy = false;
      _error = 'La sesión cambió. Actualiza la sala para continuar.';
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.isCurrentOf(context) ?? true;
    if (_visible && !current) _stop();
    _visible = current;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _generation++;
      _stop();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    if (!widget.provider.configured) {
      setState(() => _error = widget.provider.unavailableReason);
      return;
    }
    final identity = widget.captureIdentity();
    _identity = identity;
    if (identity == null) {
      setState(
        () => _error = 'Inicia sesión con un perfil para entrar a esta sala.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final items = await widget.provider.catalog(identity);
      if (!mounted || generation != _generation || !identity.isCurrent()) {
        return;
      }
      setState(() => _items = items);
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = _message(error));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _open(VrContentItem item) async {
    if (_busy || !_visible) return;
    final identity = _identity;
    if (identity == null || !identity.isCurrent()) return _load();
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final content = await widget.provider.authorize(item, identity);
      if (!mounted ||
          !_visible ||
          generation != _generation ||
          !content.isCurrent) {
        return;
      }
      await widget.playback.open(content);
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = _message(error));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  static String _message(Object error) => error is VrContentUnavailable
      ? error.message
      : 'No se pudo abrir el contenido. Inténtalo de nuevo.';

  @override
  void dispose() {
    _generation++;
    widget.sessionChanges.removeListener(_sessionChanged);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.playback.close().catchError((Object _) {}));
    if (widget.ownsProvider) widget.provider.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.provider.source.title),
      actions: [
        IconButton(
          onPressed: _busy ? null : _load,
          tooltip: 'Actualizar',
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          onPressed: _stop,
          tooltip: 'Detener audio',
          icon: const Icon(Icons.stop),
        ),
      ],
    ),
    body: Column(
      children: [
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(_error!, textAlign: TextAlign.center),
          ),
        if (_error == null && !_busy && _items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'El proveedor no tiene contenido disponible para este perfil.',
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: _items.length,
            itemBuilder: (_, index) {
              final item = _items[index];
              final supported = widget.playback.supports(item);
              return ListTile(
                leading: Icon(
                  item.kind == VrContentKind.book
                      ? Icons.menu_book
                      : Icons.headphones,
                ),
                title: Text(item.title),
                subtitle: Text(
                  !supported
                      ? 'Este lector o reproductor todavía no está conectado.'
                      : item.paid
                      ? 'Requiere acceso autorizado por el proveedor.'
                      : 'El proveedor verificará el acceso al abrir.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _busy || !supported ? null : () => _open(item),
              );
            },
          ),
        ),
      ],
    ),
  );
}
