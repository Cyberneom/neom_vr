import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:vrlizate_apps/vrlizate_apps.dart';

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

  String _kindLabel(VrlzPackage package) => switch (package.kind) {
    VrlzPackageKind.scene =>
      package.sceneBundle?.manifest.isV2 == true
          ? 'Escena portable v2 (PBR / KTX2 / Animación)'
          : 'Escena portable v1',
    VrlzPackageKind.worlds =>
      package.worldBundle?.manifest.isV2 == true
          ? 'Experiencia de mundos v2 (${package.worldBundle!.manifest.worlds.length} mundo(s))'
          : 'Experiencia de mundos v1 (${package.worldBundle!.manifest.worlds.length} mundo(s))',
    VrlzPackageKind.retro => 'Nivel retro 2.5D portable',
    VrlzPackageKind.builtin => 'Referencia a un demo incluido en la plataforma',
    VrlzPackageKind.nes => 'Cartucho NES local (no publicable)',
    VrlzPackageKind.webgame => 'Índice WebGame externo (no publicable)',
  };

  String _budgetSummary(VrCreatorPackage selected) {
    final b = selected.budget;
    final archiveKib = (b.archiveBytes / 1024).toStringAsFixed(1);
    final maxArchiveMib = (b.maxArchiveBytes / (1024 * 1024)).toStringAsFixed(
      b.maxArchiveBytes < 1024 * 1024 ? 2 : 0,
    );
    if (!selected.package.isCreatorSubmittable) {
      return '$archiveKib KiB · Sin presupuesto de subida';
    }
    final vramMib = (b.estimatedVramBytes / (1024 * 1024)).toStringAsFixed(2);
    final maxVramMib = (b.maxEstimatedVramBytes / (1024 * 1024))
        .toStringAsFixed(0);
    if (b.maxTrianglesLimit > 0) {
      return '$archiveKib KiB / $maxArchiveMib MiB · VRAM est. $vramMib / $maxVramMib MiB · ${b.maxTriangles} / ${b.maxTrianglesLimit} triángulos';
    }
    return '$archiveKib KiB / $maxArchiveMib MiB · VRAM est. $vramMib / $maxVramMib MiB';
  }

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
              'No se pudo validar este paquete (.vrlz / .vrlw). Revisa el formato, el presupuesto de memoria/triángulos y la compatibilidad con el SDK.',
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
    final canSubmit =
        widget.service.configured &&
        (selected?.package.isCreatorSubmittable ?? false) &&
        (selected?.budget.withinLimits ?? false) &&
        !_busy &&
        !_received;
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
                'Comparte un mundo o escena propia',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              const Text(
                'Selecciona un paquete .vrlz o mundo .vrlw compatible con VRlizate (escenas v1/v2, mundos portables o niveles retro dentro del presupuesto de archivo, VRAM y geometría). Revisaremos su contenido antes de que aparezca en el catálogo.',
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _busy ? null : _choose,
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('Seleccionar .vrlz / .vrlw'),
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
                        if (!selected.package.isCreatorSubmittable)
                          const Text(
                            'Este paquete no contiene una obra portable propia dentro del presupuesto de subida. Exporta una escena, mundo .vrlw/.vrlz o nivel retro desde el SDK.',
                          ),
                        if (selected.package.description.isNotEmpty)
                          Text(selected.package.description),
                        const SizedBox(height: 12),
                        Text(_budgetSummary(selected)),
                        Text(_kindLabel(selected.package)),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'Distribución inicial: paquetes con presupuesto verificado. Las ventas directas requieren habilitación comercial del backend.',
              ),
              if (!widget.service.configured) ...[
                const SizedBox(height: 12),
                const Text(
                  'Puedes comprobar tu archivo y su presupuesto localmente. La recepción en servidor aún no está configurada.',
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: canSubmit ? _submit : null,
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
