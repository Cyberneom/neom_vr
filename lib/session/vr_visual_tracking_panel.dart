import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'vr_spatial_tracking_service.dart';
import 'vr_passthrough_camera_feed.dart';

class VrVisualTrackingPanel extends StatefulWidget {
  const VrVisualTrackingPanel({super.key, required this.service});
  final VrSpatialTrackingService service;
  @override
  State<VrVisualTrackingPanel> createState() => _PanelState();
}

class _PanelState extends State<VrVisualTrackingPanel> {
  final _distance = TextEditingController();
  String? _error;
  bool _showFraming = false;
  int? _savedView;
  int? _savedAtResetCount;

  void _captureView() {
    _act(() {
      final visual = widget.service.visualTracking;
      visual.captureCalibrationView();
      _savedView = visual.calibrationViews;
      _savedAtResetCount = visual.calibrationResetCount;
    });
  }

  String _messageFor(Object error) {
    final message = error.toString();
    if (message.contains('marker_not_visible')) {
      return 'No se guardó la vista: el QR completo no está visible. '
          'Activa el encuadre, centra el QR y mantenlo quieto antes de guardar.';
    }
    if (message.contains('mirrored_frame_calibration_not_supported')) {
      return 'No se guardó la vista: usa la cámara trasera sin reflejo.';
    }
    return 'No se completó la operación: $message';
  }

  void _act(VoidCallback action) {
    try {
      action();
      setState(() => _error = null);
    } catch (error) {
      setState(() => _error = _messageFor(error));
    }
  }

  @override
  void dispose() {
    _distance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visual = widget.service.visualTracking;
    return ListenableBuilder(
      listenable: Listenable.merge([visual, widget.service]),
      builder: (context, _) => VrOpticalTrackingCameraLease(
        service: widget.service,
        enabled: widget.service.controllerOpticalTrackingEnabled,
        child: ExpansionTile(
          initiallyExpanded: true,
          title: const Text('Registro visual visor–mando'),
          subtitle: const Text(
            'QR público, calibración del flujo y pose relativa experimental',
          ),
          children: [
            SwitchListTile(
              key: const ValueKey('visual-tracking-enabled'),
              title: const Text('Seguimiento óptico del mando'),
              subtitle: const Text(
                'Usa la cámara trasera aunque el passthrough esté en 0. '
                'Busca solo el QR vinculado; no muestra la imagen en VR. '
                'Es una opción de esta sesión, independiente de la cámara auxiliar del mando.',
              ),
              value: widget.service.controllerOpticalTrackingEnabled,
              onChanged: widget.service.setControllerOpticalTrackingEnabled,
            ),
            SwitchListTile(
              key: const ValueKey('visor-body-detection-enabled'),
              title: const Text('Detección corporal en visor'),
              subtitle: const Text(
                'Detector local · frecuencia adaptativa hasta 2 análisis/s. '
                'Exige confianza y continuidad; puede omitir cuerpos parciales.',
              ),
              value: visual.bodyDetectionEnabled,
              onChanged: (value) {
                if (value) {
                  widget.service.setVisorCameraPreviewEnabled(true);
                }
                visual.setBodyDetectionEnabled(value);
              },
            ),
            if (visual.bodyDetectionEnabled)
              Text(
                visual.bodyResult == null
                    ? 'Cuerpo: esperando inferencia actual'
                    : visual.bodyResult!['status'] == 'thermal_backoff'
                    ? 'IA pausada por temperatura del dispositivo'
                    : 'Cuerpo: ${visual.bodyResult!["status"]} · '
                          '${visual.bodyResult!["present"] == true ? "propuesta estable; falta validar" : "propuesta no aceptada"} · '
                          '${visual.bodyResult!["acceptanceReason"]} · '
                          '${visual.bodyResult!["rawLandmarkCount"] ?? 0} puntos originales',
                key: const ValueKey('visor-body-detection-status'),
              ),
            Text(visual.status, key: const ValueKey('visual-tracking-status')),
            Text(
              visual.controllerPositionStatus,
              key: const ValueKey('controller-optical-position-status'),
            ),
            Text(
              'Inferencias: ${visual.inferenceCount} · '
              '${visual.inferenceMs?.toStringAsFixed(1) ?? "—"} ms · '
              'límite ${visual.analysisMaxHz.toStringAsFixed(1)} Hz · '
              'respuestas aceptadas ${visual.acceptedBodyProposals} / no aceptadas ${visual.rejectedBodyProposals}',
            ),
            Text(
              visual.marker == null
                  ? 'Abre «Marcador de calibración» en el mando vinculado.'
                  : visual.marker!.hasMeasuredScale
                  ? 'Ancho manual: ${(visual.marker!.widthMeters! * 100).toStringAsFixed(2)} cm'
                  : 'Marcador vinculado sin ancho medido; no hay escala métrica.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Guarda al menos seis vistas con el QR completo e inclinado '
              'en distintos ángulos y zonas. Mantén fija la cámara y su zoom. '
              'Después calcula K y contrasta una distancia independiente con regla. '
              'La distorsión no se estima; el ajuste pinhole es experimental.',
            ),
            SwitchListTile(
              key: const ValueKey('calibration-framing-enabled'),
              title: const Text('Ver encuadre de calibración'),
              subtitle: const Text(
                'Muestra la cámara completa solo en estos ajustes. '
                'No cambia la mezcla de passthrough de la experiencia.',
              ),
              value:
                  _showFraming &&
                  widget.service.controllerOpticalTrackingEnabled,
              onChanged: widget.service.controllerOpticalTrackingEnabled
                  ? (value) => setState(() => _showFraming = value)
                  : null,
            ),
            if (_showFraming &&
                widget.service.controllerOpticalTrackingEnabled &&
                (ModalRoute.isCurrentOf(context) ?? true))
              const SizedBox(height: 4),
            if (_showFraming &&
                widget.service.controllerOpticalTrackingEnabled &&
                (ModalRoute.isCurrentOf(context) ?? true))
              SizedBox(
                width: 320,
                height: 200,
                child: VrPassthroughCameraFeed(
                  key: const ValueKey('calibration-camera-framing'),
                  service: widget.service,
                  enableHardwareCamera: true,
                  showLensBadge: true,
                  fit: BoxFit.contain,
                ),
              ),
            const SizedBox(height: 8),
            Semantics(
              identifier: 'marker-calibration-progress',
              container: true,
              liveRegion: true,
              label: 'Vistas guardadas: ${visual.calibrationViews}. Mínimo 6.',
              excludeSemantics: true,
              child: Text(
                'Vistas guardadas: ${visual.calibrationViews} / mínimo 6',
                key: const ValueKey('marker-calibration-progress'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (_error == null &&
                _savedView == visual.calibrationViews &&
                _savedAtResetCount == visual.calibrationResetCount &&
                visual.calibrationViews > 0)
              Text(
                'Vista $_savedView guardada. Cambia el ángulo y la posición '
                'del mando antes de guardar otra.',
                key: const ValueKey('marker-calibration-capture-confirmation'),
              ),
            if (visual.calibrationViews == 0 &&
                visual.lastCalibrationResetReason != null)
              Text(
                'Se reinició la calibración: '
                '${visual.lastCalibrationResetReason}',
                key: const ValueKey('marker-calibration-reset-reason'),
                style: const TextStyle(color: Colors.amber),
              ),
            if (!visual.markerVisible)
              const Text(
                'QR no disponible para guardar: mantenlo completo dentro '
                'del encuadre y espera a que se detecte.',
              ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  key: const ValueKey('capture-marker-calibration-view'),
                  onPressed:
                      widget.service.controllerOpticalTrackingEnabled &&
                          visual.marker != null
                      ? _captureView
                      : null,
                  child: const Text('Guardar vista'),
                ),
                OutlinedButton(
                  key: const ValueKey('calculate-marker-intrinsics'),
                  onPressed: visual.calibrationViews >= 6
                      ? () => _act(visual.calibrate)
                      : null,
                  child: const Text('Calcular K'),
                ),
                TextButton(
                  onPressed: () => _act(visual.resetCalibration),
                  child: const Text('Reiniciar calibración'),
                ),
              ],
            ),
            if (visual.profile != null)
              Text(
                'K experimental · RMS ${visual.profile!.reprojectionRmsPixels.toStringAsFixed(2)} px',
              ),
            if (visual.markerVisible && !visual.orientationVerified)
              const Text(
                'Orientación del QR aún ambigua; acerca el marcador o mejora su nitidez.',
              ),
            if (visual.pose != null) ...[
              Text(
                visual.metricCameraMarkerTranslation != null
                    ? 'Centro QR respecto a cámara: '
                          '${_vector(visual.metricCameraMarkerTranslation!)} m · escala contrastada. '
                          'Ejes de imagen: X derecha, Y abajo, Z delante.'
                    : 'Pose geométrica experimental sin escala contrastada; '
                          'todavía no se publica una posición métrica.',
              ),
              Text(
                'Transformación inversa disponible: cámara respecto al QR. '
                'No es la posición de los ojos ni un mapa compartido del mundo.',
              ),
              TextField(
                key: const ValueKey('independent-marker-distance-cm'),
                controller: _distance,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Distancia independiente cámara–centro QR (cm)',
                ),
              ),
              OutlinedButton(
                onPressed: () => _act(() {
                  final cm = double.parse(_distance.text.replaceAll(',', '.'));
                  visual.validateMeasuredDistance(cm / 100);
                }),
                child: const Text('Contrastar distancia'),
              ),
            ],
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.amber)),
            const SizedBox(height: 8),
            const Text(
              'Al perder la referencia se invalida la pose. Cambiar lente, '
              'orientación, cerrar cámara o salir de la app elimina la calibración '
              'de esta sesión. No modifica la locomoción ni sustituye VIO.',
            ),
          ],
        ),
      ),
    );
  }

  String _vector(vm.Vector3 p) =>
      '(${p.x.toStringAsFixed(3)}, ${p.y.toStringAsFixed(3)}, ${p.z.toStringAsFixed(3)})';
}
