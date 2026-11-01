import 'dart:convert';

import 'package:qr_flutter/qr_flutter.dart';

/// Target hardware node tracked by a printable 1:1 millimeter fiducial tag.
enum VrFiducialNodeKind {
  visor('visor', 48.0),
  joystick('joystick', 38.0);

  const VrFiducialNodeKind(this.wireName, this.defaultSizeMm);
  final String wireName;
  final double defaultSizeMm;

  static VrFiducialNodeKind? fromWire(String? raw) => switch (raw
      ?.trim()
      .toLowerCase()) {
    'visor' || 'hmd' || 'head' => VrFiducialNodeKind.visor,
    'joystick' || 'controller' || 'hand' => VrFiducialNodeKind.joystick,
    _ => null,
  };
}

/// Decoded specification of a `vrlizate://tag?node=<visor|joystick>&mm=<size>`
/// planar fiducial marker used for millimeter `6-DoF` PnP tracking.
class VrFiducialTagSpec {
  const VrFiducialTagSpec({
    required this.node,
    required this.markerSizeMm,
  }) : assert(markerSizeMm >= minSizeMm && markerSizeMm <= maxSizeMm);

  static const double minSizeMm = 18.0;
  static const double maxSizeMm = 180.0;

  final VrFiducialNodeKind node;

  /// Exact side length in millimeters of the dark QR module matrix (excluding
  /// the surrounding white quiet zone), matching `VNDetectBarcodesRequest`
  /// corner bounds 1:1.
  final double markerSizeMm;

  double get markerSizeMeters => markerSizeMm / 1000.0;

  Uri toUri() {
    final mmText = (markerSizeMm - markerSizeMm.roundToDouble()).abs() < 1e-3
        ? '${markerSizeMm.round()}'
        : markerSizeMm.toStringAsFixed(1);
    return Uri(
      scheme: 'vrlizate',
      host: 'tag',
      queryParameters: <String, String>{
        'node': node.wireName,
        'mm': mmText,
      },
    );
  }

  static VrFiducialTagSpec? tryParse(String? raw) {
    if (raw == null || raw.isEmpty || raw.length > 256) return null;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        uri.scheme.toLowerCase() != 'vrlizate' ||
        uri.host.toLowerCase() != 'tag') {
      return null;
    }
    final node = VrFiducialNodeKind.fromWire(uri.queryParameters['node']);
    if (node == null) return null;
    final mmRaw = uri.queryParameters['mm'];
    final parsedMm = mmRaw == null
        ? node.defaultSizeMm
        : double.tryParse(mmRaw);
    if (parsedMm == null ||
        !parsedMm.isFinite ||
        parsedMm < minSizeMm ||
        parsedMm > maxSizeMm) {
      return null;
    }
    return VrFiducialTagSpec(node: node, markerSizeMm: parsedMm);
  }
}

/// Generates high-redundancy (`ECC-H`) fiducial QR matrices sized to exact
/// physical millimeters (`width="<mm>mm" height="<mm>mm"`) and a print-ready
/// 1:1 calibration sheet for `Three-Devices VR (3D-VR)` PnP tracking.
abstract final class VrFiducialTagCodec {
  static const VrFiducialTagSpec defaultVisorTag = VrFiducialTagSpec(
    node: VrFiducialNodeKind.visor,
    markerSizeMm: 48.0,
  );

  static const VrFiducialTagSpec defaultJoystickTag = VrFiducialTagSpec(
    node: VrFiducialNodeKind.joystick,
    markerSizeMm: 38.0,
  );

  /// Builds a crisp vector `<svg>` whose outer `viewBox` matches the exact
  /// dark QR module grid (`0 .. moduleCount`) at `[sizeMm] × [sizeMm]` mm.
  ///
  /// Because barcode detectors (`VNDetectBarcodesRequest`) report `topLeft`,
  /// `topRight`, `bottomRight`, `bottomLeft` at the outer boundary of the QR
  /// finder patterns (excluding quiet zone), keeping the quiet zone as external
  /// CSS padding guarantees `0.0%` scale bias in `VrVisualMarkerPoseSolver`.
  static String buildExactQrSvg({
    required String data,
    required double sizeMm,
  }) {
    final validation = QrValidator.validate(
      data: data,
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.H,
    );
    if (!validation.isValid || validation.qrCode == null) {
      throw ArgumentError.value(data, 'data', 'Invalid QR fiducial payload.');
    }
    final qr = validation.qrCode!;
    final image = QrImage(qr);
    final n = qr.moduleCount;
    final path = StringBuffer();
    for (var y = 0; y < n; y++) {
      var x = 0;
      while (x < n) {
        if (!image.isDark(y, x)) {
          x++;
          continue;
        }
        var run = 1;
        while (x + run < n && image.isDark(y, x + run)) {
          run++;
        }
        path.write('M$x,${y}h${run}v1h-${run}z');
        x += run;
      }
    }
    final mm = sizeMm.toStringAsFixed(1);
    return '<svg xmlns="http://www.w3.org/2000/svg" '
        'width="${mm}mm" height="${mm}mm" '
        'viewBox="0 0 $n $n" shape-rendering="crispEdges">'
        '<rect width="$n" height="$n" fill="#ffffff"/>'
        '<path d="$path" fill="#000000"/>'
        '</svg>';
  }

  /// Generates a complete HTML sheet ready to print at `100%` scale (`1:1 mm`)
  /// with Visor (`48 mm`), Joystick (`38 mm`), and a `50 mm` verification ruler.
  static String buildPrintableSheetHtml({
    String stationName = 'VRlizate Desktop Faro',
    double visorSizeMm = 48.0,
    double joystickSizeMm = 38.0,
  }) {
    final visorSpec = VrFiducialTagSpec(
      node: VrFiducialNodeKind.visor,
      markerSizeMm: visorSizeMm.clamp(
        VrFiducialTagSpec.minSizeMm,
        VrFiducialTagSpec.maxSizeMm,
      ),
    );
    final joySpec = VrFiducialTagSpec(
      node: VrFiducialNodeKind.joystick,
      markerSizeMm: joystickSizeMm.clamp(
        VrFiducialTagSpec.minSizeMm,
        VrFiducialTagSpec.maxSizeMm,
      ),
    );
    final visorSvg = buildExactQrSvg(
      data: visorSpec.toUri().toString(),
      sizeMm: visorSpec.markerSizeMm,
    );
    final joySvg = buildExactQrSvg(
      data: joySpec.toUri().toString(),
      sizeMm: joySpec.markerSizeMm,
    );
    final escapedStation = const HtmlEscape().convert(stationName);
    final vMm = visorSpec.markerSizeMm.toStringAsFixed(0);
    final jMm = joySpec.markerSizeMm.toStringAsFixed(0);

    return '''<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<title>Marcadores Fiduciales 6-DoF (1:1 mm) · $escapedStation</title>
<style>
  @page { size: auto; margin: 12mm; }
  * { box-sizing: border-box; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
  body {
    margin: 0;
    padding: 16px;
    background: #f5f7fb;
    color: #0b1222;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  }
  .toolbar {
    max-width: 190mm;
    margin: 0 auto 14px auto;
    padding: 14px 18px;
    background: #0b1222;
    color: #e8f1ff;
    border-radius: 12px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
  }
  .toolbar button {
    background: #00e5ff;
    color: #06101f;
    border: none;
    border-radius: 8px;
    padding: 10px 16px;
    font-weight: 800;
    cursor: pointer;
    font-size: 13px;
  }
  .sheet {
    width: 190mm;
    margin: 0 auto;
    background: #ffffff;
    border: 1px solid #d0d7e6;
    border-radius: 8px;
    padding: 12mm;
  }
  h1 { font-size: 16pt; margin: 0 0 2mm 0; }
  .sub { font-size: 9.5pt; color: #364152; margin-bottom: 6mm; line-height: 1.4; }
  .ruler-box {
    border: 1px solid #0b1222;
    border-radius: 6px;
    padding: 4mm 5mm;
    margin-bottom: 8mm;
    background: #fafcff;
  }
  .tags-row {
    display: flex;
    gap: 12mm;
    align-items: flex-start;
    flex-wrap: wrap;
  }
  .tag-card {
    border: 1.5px dashed #475467;
    padding: 6mm;
    background: #ffffff;
    display: inline-flex;
    flex-direction: column;
    align-items: center;
  }
  .qr-quiet-zone {
    padding: 6mm;
    background: #ffffff;
    border: 0.3mm solid #e4e7ec;
    line-height: 0;
  }
  .tag-meta {
    margin-top: 3mm;
    font-size: 8.5pt;
    font-weight: 700;
    text-align: center;
    letter-spacing: 0.2px;
  }
  .tag-uri {
    font-family: ui-monospace, monospace;
    font-size: 7pt;
    color: #475467;
    margin-top: 1mm;
  }
  .tips {
    margin-top: 8mm;
    font-size: 9pt;
    color: #1d2939;
    line-height: 1.45;
    border-top: 1px solid #e4e7ec;
    padding-top: 4mm;
  }
  @media print {
    body { background: #ffffff; padding: 0; }
    .toolbar { display: none !important; }
    .sheet { border: none; padding: 0; width: auto; }
  }
</style>
</head>
<body>
  <div class="toolbar">
    <div>
      <b>Marcadores Ópticos 6-DoF (&lt; 3 mm) · $escapedStation</b><br>
      <span style="font-size:12px;color:#93a8c9;">En el diálogo de impresión elige <b>Escala: 100% (Tamaño real)</b> sin ajustar a página.</span>
    </div>
    <button onclick="window.print()">Imprimir Hoja 1:1 (mm)</button>
  </div>
  <div class="sheet">
    <h1>VRlizate 3D-VR · Marcadores Fiduciales 6-DoF (PnP Métrico)</h1>
    <div class="sub">
      Recorta por la línea punteada conservando el margen blanco exterior (<i>quiet zone</i>).
      La matriz negra interna mide exactamente <b>$vMm mm × $vMm mm</b> (Visor) y <b>$jMm mm × $jMm mm</b> (Joystick) para triangulación homográfica sub-milimétrica sin costo adicional.
    </div>

    <div class="ruler-box">
      <div style="font-size:8.5pt;font-weight:700;margin-bottom:2mm;">Regla Física de Verificación 1:1 (debe medir exactamente 50.0 mm con regla real):</div>
      <svg xmlns="http://www.w3.org/2000/svg" width="54mm" height="9mm" viewBox="0 0 54 9">
        <line x1="2" y1="6" x2="52" y2="6" stroke="#000" stroke-width="0.4"/>
        <line x1="2" y1="2" x2="2" y2="6" stroke="#000" stroke-width="0.45"/>
        <line x1="12" y1="3" x2="12" y2="6" stroke="#000" stroke-width="0.35"/>
        <line x1="22" y1="3" x2="22" y2="6" stroke="#000" stroke-width="0.35"/>
        <line x1="32" y1="3" x2="32" y2="6" stroke="#000" stroke-width="0.35"/>
        <line x1="42" y1="3" x2="42" y2="6" stroke="#000" stroke-width="0.35"/>
        <line x1="52" y1="2" x2="52" y2="6" stroke="#000" stroke-width="0.45"/>
        <text x="1" y="8.6" font-size="2.3" font-family="sans-serif">0 mm</text>
        <text x="20" y="8.6" font-size="2.3" font-family="sans-serif">20</text>
        <text x="48" y="8.6" font-size="2.3" font-family="sans-serif">50 mm</text>
      </svg>
    </div>

    <div class="tags-row">
      <div class="tag-card">
        <div style="font-size:8pt;font-weight:800;margin-bottom:2mm;">▲ ARRIBA · FRENTE DEL VISOR ▲</div>
        <div class="qr-quiet-zone">$visorSvg</div>
        <div class="tag-meta">NODO VISOR · MATRIZ $vMm×$vMm mm</div>
        <div class="tag-uri">${visorSpec.toUri()}</div>
      </div>

      <div class="tag-card">
        <div style="font-size:8pt;font-weight:800;margin-bottom:2mm;">▲ ARRIBA · MANDO JOYSTICK ▲</div>
        <div class="qr-quiet-zone">$joySvg</div>
        <div class="tag-meta">NODO JOYSTICK · MATRIZ $jMm×$jMm mm</div>
        <div class="tag-uri">${joySpec.toUri()}</div>
      </div>
    </div>

    <div class="tips">
      <b>Instrucciones rápidas:</b><br>
      1. Imprime en papel blanco mate (evita cinta brillante encima del código para no generar reflejos especulares).<br>
      2. Pega el marcador <b>VISOR ($vMm mm)</b> centrado en la tapa frontal de tu carcasa VR mirando hacia la webcam de tu PC.<br>
      3. En <b>Estación Faro Desktop</b> activa «Webcam IA en vivo»: el solver detectará automáticamente las 4 esquinas orientadas, activará <b>PnP 6-DoF (&lt; 3 mm)</b> y auto-calibrará tu escala corporal y tu IPD óptico real.
    </div>
  </div>
</body>
</html>''';
  }
}
