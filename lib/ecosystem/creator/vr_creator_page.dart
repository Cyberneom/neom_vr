import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:vrlizate_apps/vrlizate_apps.dart';

import 'vr_creator_service.dart';

/// Validates locally; only an authorized server can accept and publish a work.
class VrCreatorPage extends StatefulWidget {
  const VrCreatorPage({super.key, required this.service});
  final VrCreatorService service;

  @override
  State<VrCreatorPage> createState() => _VrCreatorPageState();
}

class _VrCreatorPageState extends State<VrCreatorPage> {
  VrCreatorPackage? _selected;
  String? _message;
  bool _busy = false;
  bool _received = false;

  Future<void> _choose() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
      _received = false;
      _selected = null;
    });
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['vrlz', 'vrlw'],
        allowMultiple: false,
        withData: false,
        withReadStream: true,
      );
      if (result == null || !mounted) return;
      final file = result.files.single;
      final ext = file.extension?.toLowerCase();
      if ((ext != 'vrlz' && ext != 'vrlw') ||
          file.size > VrlzPackage.maxBytes) {
        throw const FormatException(
          'Elige un archivo .vrlz o .vrlw de hasta 32 MiB.',
        );
      }
      final stream = file.readStream ?? file.xFile.openRead();
      final builder = BytesBuilder(copy: false);
      await for (final chunk in stream.timeout(const Duration(seconds: 30))) {
        if (!mounted) return;
        if (builder.length + chunk.length > VrlzPackage.maxBytes) {
          throw const FormatException('El archivo supera el límite de 32 MiB.');
        }
        builder.add(chunk);
      }
      final validated = VrCreatorPackage.validate(builder.takeBytes());
      if (mounted) setState(() => _selected = validated);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'No se pudo validar este .vrlz. Revisa el formato, el tamaño y la compatibilidad con el SDK.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_busy || _selected == null || _received) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.service.submit(_selected!);
      if (mounted) {
        setState(() {
          _received = true;
          _message =
              'Experiencia recibida para revisión. Todavía no está publicada.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'No se confirmó la recepción. Revisa tu sesión y conexión antes de reintentar.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    widget.service.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return Scaffold(
      appBar: AppBar(title: const Text('Estudio de creadores')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(
                Icons.view_in_ar_rounded,
                size: 64,
                color: Color(0xFFFFBE74),
              ),
              const SizedBox(height: 20),
              Text(
                'Comparte un mundo propio',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              const Text(
                'Selecciona una experiencia .vrlz compatible con VRlizate. Revisaremos su contenido antes de que aparezca en el catálogo.',
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _busy ? null : _choose,
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('Seleccionar .vrlz'),
              ),
              if (selected != null) ...[
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selected.package.title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (selected.package.kind == VrlzPackageKind.builtin)
                          const Text(
                            'Esta referencia abre un demo de la plataforma. Para publicar una obra propia, exporta una escena portable desde el SDK.',
                          ),
                        if (selected.package.description.isNotEmpty)
                          Text(selected.package.description),
                        const SizedBox(height: 12),
                        Text(
                          '${(selected.bytes.length / 1024).toStringAsFixed(1)} KiB · Archivo validado',
                        ),
                        Text(
                          selected.package.kind == VrlzPackageKind.scene
                              ? 'Escena portable'
                              : 'Referencia a un demo incluido en la plataforma',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'Distribución inicial: gratuita. Las ventas y los pagos a creadores todavía no están habilitados.',
              ),
              if (!widget.service.configured) ...[
                const SizedBox(height: 12),
                const Text(
                  'Puedes comprobar tu archivo. La recepción de nuevas experiencias aún no está disponible.',
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed:
                    widget.service.configured &&
                        selected?.package.kind == VrlzPackageKind.scene &&
                        !_busy &&
                        !_received
                    ? _submit
                    : null,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Enviar para revisión'),
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: LinearProgressIndicator(),
                ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(_message!, semanticsLabel: _message),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
