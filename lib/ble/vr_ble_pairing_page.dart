import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:vrlizate/vrlizate.dart';
import 'package:vrlizate_joystick/vrlizate_joystick.dart';

import 'vr_ble_transport.dart';
import 'vr_controller_pairing_store.dart';

Widget buildVrPairedController(
  BuildContext context,
  VrPairingPayload payload, {
  VrControllerPairingStore? pairingStore,
}) {
  final store = pairingStore ?? VrControllerPairingStore.instance;
  if (payload.transportType != VrTransportType.bluetoothLe) {
    return const VrControllerPairingPage(
      supportedTransports: {VrTransportType.bluetoothLe},
      controllerBuilder: buildVrPairedController,
    );
  }
  bool matchesOriginal(VrControllerConnectionTarget? target) {
    // BLE links report no socket target. A foreign destination cannot save or
    // invalidate this authenticated invitation.
    return target == null;
  }

  void remember(VrControllerConnectionTarget? target) {
    if (matchesOriginal(target)) unawaited(store.remember(payload));
  }

  void expired(VrControllerConnectionTarget? target) {
    if (matchesOriginal(target)) unawaited(store.forget(matching: payload));
  }

  return VrBleControllerPage(
    payload: payload,
    onConnected: remember,
    onSessionExpired: expired,
  );
}

class VrBleControllerPage extends StatefulWidget {
  const VrBleControllerPage({
    super.key,
    required this.payload,
    this.connector,
    this.prepareBluetooth,
    this.onConnected,
    this.onSessionExpired,
  });
  final VrPairingPayload payload;
  final VrBleControllerConnector? connector;
  final Future<void> Function()? prepareBluetooth;
  final ValueChanged<VrControllerConnectionTarget?>? onConnected;
  final ValueChanged<VrControllerConnectionTarget?>? onSessionExpired;
  @override
  State<VrBleControllerPage> createState() => _BleControllerPageState();
}

class _BleControllerPageState extends State<VrBleControllerPage>
    with WidgetsBindingObserver {
  late final _connector = widget.connector ?? VrBleControllerConnector();
  // Preserve callback identity across background/resume rebuilds.
  late final Future<VrControllerLink> Function() _connect = _connectToViewer;
  Future<VrControllerLink> _connectToViewer() =>
      _connector.connect(widget.payload);
  bool _prepared = false;
  bool _preparing = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  Future<void> _prepare() async {
    if (!mounted || _preparing) return;
    setState(() {
      _preparing = true;
      _error = null;
    });
    try {
      await (widget.prepareBluetooth ?? prepareVrBleController)();
      if (mounted) setState(() => _prepared = true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Activa Bluetooth y permite Dispositivos cercanos. '
              'En Android 11 o anterior, permite y activa también Ubicación para buscar el visor.',
        );
      }
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Do not cancel on inactive: an Android permission dialog is inactive too.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _connector.cancel();
    }
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connector.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !_prepared
      ? Scaffold(
          appBar: AppBar(title: const Text('Conectar mando Bluetooth')),
          body: Center(
            child: _error == null
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!),
                      ),
                      FilledButton(
                        onPressed: _prepare,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
          ),
        )
      : PhoneControllerPage(
          allowWifiConnection: false,
          sessionToken: widget.payload.sessionToken,
          transportType: VrTransportType.bluetoothLe,
          autoConnect: true,
          isChildRole: true,
          connectionTimeout: const Duration(seconds: 40),
          connectionLabel: 'Bluetooth LE · Visor',
          linkConnector: _connect,
          onConnected: widget.onConnected,
          onSessionExpired: widget.onSessionExpired,
        );
}

/// A single pre-headset setup route. An authenticated link completes this route
/// alone and leaves Home/service alive. Pairing uses Bluetooth exclusively.
class VrDevicePairingPage extends StatefulWidget {
  const VrDevicePairingPage({
    super.key,
    required this.service,
    required this.startBluetooth,
    required this.onCompleted,
    this.autoStart = false,
    this.hasRegisteredPeer = false,
  });

  final VrRemoteControllerService service;
  final Future<VrPairingPayload> Function() startBluetooth;
  final ValueChanged<bool> onCompleted;
  final bool autoStart;
  final bool hasRegisteredPeer;

  static Future<bool> show(
    BuildContext context, {
    required VrRemoteControllerService service,
    required VrBleHost bluetooth,
    bool autoStart = true,
  }) {
    final navigator = Navigator.of(context);
    unawaited(
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]),
    );
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    late final MaterialPageRoute<bool> route;
    var finished = false;
    void complete(bool connected) {
      if (connected) {
        unawaited(VrVisorBleIdentityStore.instance.markPeerRegistered());
      }
      if (finished || !navigator.mounted || !route.isActive) return;
      finished = true;
      if (route.isCurrent) {
        navigator.pop(connected);
      } else {
        navigator.removeRoute(route, connected);
      }
    }

    route = MaterialPageRoute<bool>(
      builder: (_) => VrDevicePairingPage(
        service: service,
        startBluetooth: bluetooth.start,
        onCompleted: complete,
        autoStart: autoStart,
        hasRegisteredPeer: VrVisorBleIdentityStore.instance.hasRegisteredPeer,
      ),
    );
    return navigator
        .push(route)
        .then((value) {
          finished = true;
          return value ?? false;
        })
        .whenComplete(() {
          if (navigator.mounted) {
            unawaited(
              SystemChrome.setPreferredOrientations([
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]),
            );
            unawaited(
              SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
            );
          }
        });
  }

  @override
  State<VrDevicePairingPage> createState() => _VrDevicePairingPageState();
}

class _VrDevicePairingPageState extends State<VrDevicePairingPage> {
  StreamSubscription<bool>? _connection;
  bool _busy = false;
  bool _completed = false;
  VrPairingPayload? _invitation;
  String? _error;

  @override
  void initState() {
    super.initState();
    _connection = widget.service.onConnectionChanged.listen(
      (_) => _checkConnected(),
    );
    _checkConnected();
    if (widget.autoStart && !widget.service.isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_completed && _invitation == null && !_busy) {
          unawaited(_start());
        }
      });
    }
  }

  void _checkConnected() {
    if (!widget.service.isConnected || _completed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _completed || !widget.service.isConnected) return;
      _completed = true;
      widget.onCompleted(true);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _start() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final invitation = await widget.startBluetooth();
      parseVrControllerPairingCode(
        invitation.toUri().toString(),
        supportedTransports: const {VrTransportType.bluetoothLe},
      );
      if (mounted) setState(() => _invitation = invitation);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'No se pudo iniciar Bluetooth. Actívalo y permite Dispositivos cercanos '
              'en Ajustes y vuelve a intentarlo.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _connection?.cancel();
    super.dispose();
  }

  Widget _buildQrArea(Size qrBoxSize) {
    return Center(
      child: _invitation == null
          ? _busy
                ? const CircularProgressIndicator()
                : FilledButton.icon(
                    onPressed: _start,
                    icon: const Icon(Icons.bluetooth_searching),
                    label: const Text('Activar vínculo Bluetooth'),
                  )
          : Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: QrImageView(
                key: const ValueKey('ble-invitation-qr'),
                data: _invitation!.toUri().toString(),
                backgroundColor: Colors.white,
                size: math.max(
                  1,
                  math.min(qrBoxSize.width - 28, qrBoxSize.height - 28),
                ),
              ),
            ),
    );
  }

  Widget _buildInstructions({required bool compact}) {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: compact ? 8 : 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: const Color(0x1F00E5FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0x6600E5FF)),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.qr_code_scanner_rounded,
                  color: Colors.cyanAccent,
                  size: 18,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'PASO PREVIO AL VISOR · SINCRONIZACIÓN MUTUA CON EL JOYSTICK',
                    style: TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (widget.hasRegisteredPeer) ...[
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: const Color(0x2200E5FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x8800E5FF)),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.bluetooth_connected_rounded,
                    color: Colors.cyanAccent,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Smartphone registrado detectado · Conectando en automático para pasar al Home…',
                      style: TextStyle(
                        color: Colors.cyanAccent,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Text(
            '1. Abre VRlizate en el otro teléfono.\n'
            '2. Elige «Usar como mando» y escanea este QR.\n'
            '3. Al conectar, la pantalla pasará sola al modo Visor VR.',
            style: TextStyle(fontSize: compact ? 14.5 : 17, height: 1.42),
          ),
          const SizedBox(height: 8),
          Text(
            'Al confirmar la conexión, este visor vuelve automáticamente al Home. '
            'Colócatelo: A elige y B cierra paneles o detiene el recorrido.',
            style: TextStyle(
              color: Colors.white70,
              fontSize: compact ? 12.5 : 13.5,
              height: 1.35,
            ),
          ),
          if (_invitation != null)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Esperando al mando… No requiere red ni internet.',
                style: TextStyle(
                  color: Colors.cyanAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.orangeAccent),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF080E1D),
    appBar: AppBar(
      title: const Text('Sincronizar Visor con Joystick'),
      actions: [
        TextButton(
          onPressed: () => widget.onCompleted(false),
          child: const Text('Volver al visor'),
        ),
      ],
    ),
    body: LayoutBuilder(
      builder: (context, constraints) {
        final isPortrait = constraints.maxWidth < 560;
        if (isPortrait) {
          final qrHeight = math.min(
            constraints.maxWidth - 32,
            constraints.maxHeight * 0.45,
          );
          return Column(
            children: [
              SizedBox(
                height: qrHeight,
                width: constraints.maxWidth,
                child: _buildQrArea(Size(constraints.maxWidth - 32, qrHeight)),
              ),
              Expanded(child: _buildInstructions(compact: true)),
            ],
          );
        }
        return Row(
          children: [
            Expanded(
              child: _buildQrArea(
                Size(constraints.maxWidth / 2, constraints.maxHeight),
              ),
            ),
            Expanded(child: _buildInstructions(compact: false)),
          ],
        );
      },
    ),
  );
}
