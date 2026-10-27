import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show ValueListenable, ValueNotifier, VoidCallback;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:neom_ble/gatt/neom_gatt_server.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vrlizate/vrlizate.dart';
import 'package:vrlizate_joystick/vrlizate_joystick.dart';

import 'vr_ble_session.dart';
import 'vr_hybrid_udp_link.dart';

export 'vr_hybrid_udp_link.dart';

const vrBleRxUuid = 'e0862f81-6d24-44dc-90c1-64f278674ce1';
const vrBleTxUuid = 'e0862f82-6d24-44dc-90c1-64f278674ce1';

/// Request permissions before mounting PhoneControllerPage: system permission
/// dialogs otherwise cancel that page's pending connection on inactive.
Future<void> prepareVrBleController() => _prepareBluetooth(peripheral: false);

/// Sanitizes provider failures and opts only known temporary failures into the
/// controller page's bounded reconnect cycle. Permissions, disabled adapters,
/// authentication/configuration errors and unknown native codes need user action.
VrControllerConnectionException classifyVrBleControllerFailure(Object error) {
  if (error is VrControllerConnectionException) return error;
  var retry = error is TimeoutException;
  if (error is FlutterBluePlusException) {
    if (error.platform == ErrorPlatform.fbp) {
      retry =
          error.code == FbpErrorCode.timeout.index ||
          error.code == FbpErrorCode.deviceIsDisconnected.index;
    } else if (error.platform == ErrorPlatform.android) {
      // flutter_blue_plus_android 7.0.4 FlutterBluePlusPlugin.java maps connect
      // status via hciStatusString, but GATT operations via gattErrorString.
      // In particular, 0x08 means link timeout for connect and insufficient
      // authorization for GATT; never classify native codes without the method.
      if (error.function == 'connect') {
        retry = const {
          0x04, // PAGE_TIMEOUT
          0x08, // LINK_SUPERVISION_TIMEOUT
          0x3e, // CONNECTION_FAILED_ESTABLISHMENT
          0x85, // ANDROID_SPECIFIC_ERROR (common GATT 133 failure)
          0x8f, // GATT_CONNECTION_CONGESTED
          0x93, // GATT_CONNECTION_TIMEOUT
        }.contains(error.code);
      } else if (const {
        'discoverServices',
        'setNotifyValue',
        'readCharacteristic',
        'writeCharacteristic',
        'readDescriptor',
        'writeDescriptor',
      }.contains(error.function)) {
        retry = const {
          0x84, // GATT_BUSY
          0x85, // GATT_ERROR
          0x8f, // GATT_CONNECTION_CONGESTED
        }.contains(error.code);
      }
    }
  }
  return VrControllerConnectionException(
    retry
        ? 'La conexión Bluetooth se interrumpió. Reintentando el vínculo.'
        : 'No se pudo conectar por Bluetooth. Revisa permisos y la configuración del visor.',
    canRetry: retry,
  );
}

/// Owns native work while the controller page is alive. Cancellation prevents
/// a late permission dialog/scan result from authenticating a dismissed page.
class VrBleControllerConnector {
  _BleAttempt? _active;
  Future<void> _previous = Future.value();
  Future<VrControllerLink> connect(VrPairingPayload invitation) {
    cancel();
    final attempt = _BleAttempt();
    _active = attempt;
    final previous = _previous;
    final future = () async {
      await previous;
      attempt.check();
      try {
        final link = await _connectVrBleController(invitation, attempt);
        if (attempt.cancelled) {
          await link.close();
          attempt.check();
        }
        // Ownership transfers to PhoneControllerPage. Pausing may cancel a
        // pending scan, but must never disconnect an authenticated link.
        attempt.onCancel = null;
        return link;
      } catch (error, stack) {
        Error.throwWithStackTrace(classifyVrBleControllerFailure(error), stack);
      } finally {
        if (identical(_active, attempt)) _active = null;
      }
    }();
    _previous = future.then<void>((_) {}, onError: (Object _) {});
    return future;
  }

  void cancel() {
    _active?.cancel();
    _active = null;
  }
}

class _BleAttempt {
  bool cancelled = false;
  void Function()? onCancel;
  void cancel() {
    cancelled = true;
    onCancel?.call();
  }

  void check() {
    if (cancelled) throw StateError('Conexión Bluetooth cancelada.');
  }
}

Future<void> _prepareBluetooth({required bool peripheral}) async {
  if (!Platform.isAndroid && !Platform.isIOS) {
    throw StateError(
      'El mando Bluetooth requiere un teléfono Android o iOS compatible.',
    );
  }
  if (Platform.isAndroid) {
    await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      if (peripheral) Permission.bluetoothAdvertise,
    ].request();
    // Declared only up to API 30. Modern Android uses Nearby Devices instead.
    if (!peripheral) await Permission.locationWhenInUse.request();
  }
  if (!await FlutterBluePlus.isSupported) {
    throw StateError('Este teléfono no dispone de Bluetooth LE.');
  }
  final state = await FlutterBluePlus.adapterState
      .firstWhere((s) => s != BluetoothAdapterState.unknown)
      .timeout(const Duration(seconds: 4));
  if (state != BluetoothAdapterState.on) {
    throw StateError(
      'Activa Bluetooth y permite Dispositivos cercanos para conectar el mando.',
    );
  }
}

/// Persists the Visor's BLE service UUID and session token across sessions so
/// a previously registered controller smartphone can detect and reconnect
/// automatically over Bluetooth LE without scanning a new QR code.
class VrVisorBleIdentityStore {
  VrVisorBleIdentityStore._();
  static final VrVisorBleIdentityStore instance = VrVisorBleIdentityStore._();

  static const _serviceUuidKey = 'vrlizate_visor_ble_service_uuid_v1';
  static const _sessionTokenKey = 'vrlizate_visor_ble_session_token_v1';
  static const _hasRegisteredPeerKey = 'vrlizate_visor_has_registered_peer_v1';

  String? _serviceUuid;
  String? _sessionToken;
  bool _hasRegisteredPeer = false;

  String? get serviceUuid => _serviceUuid;
  String? get sessionToken => _sessionToken;
  bool get hasRegisteredPeer => _hasRegisteredPeer;

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var uuid = prefs.getString(_serviceUuidKey);
      var token = prefs.getString(_sessionTokenKey);
      final registered = prefs.getBool(_hasRegisteredPeerKey) ?? false;
      if (uuid == null || !isVrBleServiceUuid(uuid)) {
        uuid = newVrBleServiceUuid();
        await prefs.setString(_serviceUuidKey, uuid);
      }
      if (token == null || token.length < 16) {
        final temp = VrRemoteControllerService();
        token = temp.sessionToken;
        temp.dispose();
        await prefs.setString(_sessionTokenKey, token);
      }
      _serviceUuid = uuid;
      _sessionToken = token;
      _hasRegisteredPeer = registered;
    } catch (_) {
      // Fallback to in-memory credentials when SharedPreferences is unavailable.
    }
  }

  Future<void> markPeerRegistered() async {
    _hasRegisteredPeer = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_hasRegisteredPeerKey, true);
      if (_serviceUuid != null) {
        await prefs.setString(_serviceUuidKey, _serviceUuid!);
      }
      if (_sessionToken != null) {
        await prefs.setString(_sessionTokenKey, _sessionToken!);
      }
    } catch (_) {}
  }
}

/// The viewer owns a persistent peripheral service, following Blup's native
/// GATT + connectable-advertising path. No mesh relay or periodic disconnects.
class VrBleHost {
  VrBleHost(
    this.controller, {
    NeomGattServer? gatt,
    Future<void> Function()? prepareBluetooth,
    this.adapterStates,
    String? serviceUuid,
  }) : _gatt = gatt ?? NeomGattServer(),
       _prepare =
           prepareBluetooth ?? (() => _prepareBluetooth(peripheral: true)),
       serviceUuid =
           (serviceUuid != null && isVrBleServiceUuid(serviceUuid))
           ? serviceUuid
           : newVrBleServiceUuid();
  final VrRemoteControllerService controller;
  final NeomGattServer _gatt;
  final Future<void> Function() _prepare;
  final Stream<BluetoothAdapterState>? adapterStates;
  final String serviceUuid;
  final _peers = <String, VrBleHostPeer>{};
  final _peerMtus = <String, int>{};
  VrHybridBleUdpHostLink? _activeHybridHost;
  VoidCallback? _hybridQualityRelay;
  final ValueNotifier<bool> _syncingPeer = ValueNotifier<bool>(false);
  final ValueNotifier<VrControllerLinkQuality?> _activeLinkQuality =
      ValueNotifier<VrControllerLinkQuality?>(null);
  ValueListenable<bool> get syncingPeerListenable => _syncingPeer;
  ValueListenable<VrControllerLinkQuality?> get activeLinkQualityListenable =>
      _activeLinkQuality;
  StreamSubscription<GattServerEvent>? _events;
  StreamSubscription<BluetoothAdapterState>? _adapter;
  Future<void> _resetting = Future.value();
  Future<VrPairingPayload>? _starting;
  bool _started = false;
  bool _disposed = false;
  bool _shouldRun = false;
  BluetoothAdapterState? _adapterState;
  int _adapterGeneration = 0;

  Future<VrPairingPayload> start() {
    _shouldRun = true;
    return _beginStart(prepare: true);
  }

  Future<VrPairingPayload> _beginStart({required bool prepare}) => _starting ??=
      _start(prepare: prepare).whenComplete(() => _starting = null);

  VrPairingPayload get invitation => VrPairingPayload(
    host: 'ble',
    port: 1, // Legacy payload requires a port; not used by BLE.
    sessionToken: controller.sessionToken,
    role: VrDeviceRole.child,
    transportType: VrTransportType.bluetoothLe,
    deviceName: 'VRlizate Visor',
    bleServiceUuid: serviceUuid,
  );

  Future<VrPairingPayload> _start({required bool prepare}) async {
    if (_disposed) throw StateError('El visor ya se cerró.');
    // An adapter event can queue teardown while permission preparation waits.
    // That teardown waits for this start; never await its newly queued future
    // or adopt its generation, which would deadlock or publish a stale service.
    final resetting = _resetting;
    final generation = _adapterGeneration;
    if (prepare) await _prepare();
    if (_disposed) throw StateError('El visor ya se cerró.');
    await resetting;
    if (_started) return invitation;
    _adapter ??= (adapterStates ?? FlutterBluePlus.adapterState).listen(
      _onAdapterState,
    );
    _events ??= _gatt.events.listen(
      _onEvent,
      onError: (_) {
        _started = false;
        _closePeers();
      },
    );
    try {
      _checkAdapterGeneration(generation);
      if (!await _gatt.startDuplexService(
        serviceUuid: serviceUuid,
        rxCharUuid: vrBleRxUuid,
        txCharUuid: vrBleTxUuid,
      )) {
        throw StateError(
          'No se pudo iniciar el visor Bluetooth. Revisa sus permisos.',
        );
      }
      _checkAdapterGeneration(generation);
      if (!await _gatt.startConnectableAdvertising(serviceUuid: serviceUuid)) {
        throw StateError(
          'Este teléfono no pudo anunciar el visor Bluetooth. Comprueba su compatibilidad BLE.',
        );
      }
      _checkAdapterGeneration(generation);
      _started = true;
      return invitation;
    } catch (_) {
      await _gatt.stopAdvertising();
      await _gatt.stopDuplexService();
      rethrow;
    }
  }

  void _checkAdapterGeneration(int generation) {
    if (_disposed ||
        generation != _adapterGeneration ||
        (_adapterState != null &&
            _adapterState != BluetoothAdapterState.on &&
            _adapterState != BluetoothAdapterState.unknown)) {
      throw StateError('Bluetooth del visor dejó de estar disponible.');
    }
  }

  void _onAdapterState(BluetoothAdapterState state) {
    if (_disposed || state == BluetoothAdapterState.unknown) return;
    if (_adapterState == state) return;
    _adapterState = state;
    if (state == BluetoothAdapterState.on) {
      // Keep the same QR secret/service UUID after a temporary adapter reset.
      // A saved controller invitation can then reconnect without another tap.
      unawaited(_resumeHost());
      return;
    }
    _adapterGeneration++;
    _started = false;
    _closePeers();
    final starting = _starting;
    _resetting = _resetting.then((_) async {
      // Do not remove a replacement service while an old native start is still
      // returning. Its generation check prevents it from becoming live again.
      try {
        await starting;
      } catch (_) {
        /* The interrupted start owns its failure cleanup. */
      }
      await _stopNative();
    });
  }

  Future<void> _resumeHost() async {
    try {
      await _starting;
    } catch (_) {
      /* Adapter restoration may follow an interrupted initial start. */
    }
    if (_disposed ||
        !_shouldRun ||
        _started ||
        _adapterState != BluetoothAdapterState.on) {
      return;
    }
    try {
      // Already authorized by start(); restoring the radio must not open a new
      // permission dialog. Explicit start() remains available after failure.
      await _beginStart(prepare: false);
    } catch (_) {
      /* A native/permission failure still requires an explicit retry. */
    }
  }

  void _updateSyncingPeer() {
    if (_disposed) return;
    _syncingPeer.value = _peers.isNotEmpty;
  }

  void _bindHybridQuality(VrHybridBleUdpHostLink? next) {
    final prev = _activeHybridHost;
    final relay = _hybridQualityRelay;
    if (prev != null && relay != null) {
      prev.linkQualityListenable.removeListener(relay);
    }
    _activeHybridHost = next;
    _hybridQualityRelay = null;
    if (_disposed) return;
    if (next == null) {
      _activeLinkQuality.value = null;
      return;
    }
    void sync() {
      if (!_disposed && identical(_activeHybridHost, next)) {
        _activeLinkQuality.value = next.linkQualityListenable.value;
      }
    }

    _hybridQualityRelay = sync;
    next.linkQualityListenable.addListener(sync);
    sync();
  }

  void _onEvent(GattServerEvent event) {
    if (_disposed) return;
    final id = event.deviceId;
    if (id == null) return;
    switch (event.type) {
      case GattServerEventType.duplexMtuChanged:
        final mtu = event.mtu;
        if (mtu != null) {
          _peerMtus[id] = mtu;
          if (mtu >= 28) {
            _peers[id]?.link.enableSinglePacketState();
          }
        }
      case GattServerEventType.duplexClientSubscribed:
        if (_peers.containsKey(id)) return;
        if (_peers.length >= 4) {
          unawaited(_gatt.disconnectDuplexClient(deviceId: id));
          return;
        }
        late final VrBlePacketLink link;
        VrHybridBleUdpHostLink? hybrid;
        link = VrBlePacketLink(
          writeChunk: (chunk) async {
            // Native busy/backpressure is retried, never silently dropped.
            for (var attempt = 0; attempt < 8; attempt++) {
              if (!link.isOpen || _disposed) throw StateError('BLE closed');
              if (await _gatt.notifyDuplex(deviceId: id, data: chunk)) return;
              await Future<void>.delayed(const Duration(milliseconds: 8));
            }
            throw StateError('Bluetooth TX ocupado. Reconecta el mando.');
          },
          onClose: () async {
            if (hybrid != null && identical(_activeHybridHost, hybrid)) {
              _bindHybridQuality(null);
            }
            if (!identical(_peers[id]?.link, link)) return;
            _peers.remove(id);
            _updateSyncingPeer();
            await _gatt.disconnectDuplexClient(deviceId: id);
          },
        );
        final negotiatedMtu = event.mtu ?? _peerMtus[id] ?? 23;
        if (negotiatedMtu >= 28 || (event.maxNotificationBytes ?? 20) >= 25) {
          link.enableSinglePacketState();
        }
        _peers[id] = VrBleHostPeer(
          link: link,
          sessionToken: controller.sessionToken,
          onAuthenticated: (bleLink) {
            if (_disposed) return false;
            final wrapped = VrHybridBleUdpHostLink(
              bleLink: bleLink,
              sessionToken: controller.sessionToken,
            );
            hybrid = wrapped;
            final attached = controller.attachControllerLink(
              wrapped,
              sessionToken: controller.sessionToken,
            );
            if (!attached) {
              unawaited(wrapped.close());
              return false;
            }
            _bindHybridQuality(wrapped);
            return true;
          },
        );
        _updateSyncingPeer();
      case GattServerEventType.duplexData:
        final data = event.data;
        if (data != null) _peers[id]?.link.receive(data);
      case GattServerEventType.duplexClientUnsubscribed:
        final peer = _peers.remove(id);
        _updateSyncingPeer();
        if (peer != null) unawaited(peer.link.close());
      case GattServerEventType.clientDisconnected:
        _peerMtus.remove(id);
        final peer = _peers.remove(id);
        _updateSyncingPeer();
        if (peer != null) unawaited(peer.link.close());
      default:
        break;
    }
  }

  void _closePeers() {
    _bindHybridQuality(null);
    _peerMtus.clear();
    final peers = _peers.values.toList();
    for (final peer in peers) {
      unawaited(peer.link.close());
    }
    _peers.clear();
    _updateSyncingPeer();
  }

  Future<void> _stopNative() async {
    try {
      await _gatt.stopAdvertising();
      await _gatt.stopDuplexService();
    } catch (_) {
      /* Adapter/engine may already be gone. */
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _shouldRun = false;
    _closePeers();
    _syncingPeer.dispose();
    _activeLinkQuality.dispose();
    await _events?.cancel();
    await _adapter?.cancel();
    await _resetting;
    // If start is awaiting a permission/native callback, it cleans itself up.
    try {
      if (_started) {
        await _gatt.stopAdvertising();
        await _gatt.stopDuplexService();
      }
    } catch (_) {
      /* Native engine may already be detached. */
    }
    _started = false;
  }
}

/// Central role on the old phone: scan exactly the QR session, subscribe, then
/// prove both endpoints know its secret. The caller owns the returned link.
Future<VrControllerLink> _connectVrBleController(
  VrPairingPayload invitation,
  _BleAttempt attempt,
) async {
  if (invitation.transportType != VrTransportType.bluetoothLe ||
      invitation.role != VrDeviceRole.child ||
      !isVrBleServiceUuid(invitation.bleServiceUuid)) {
    throw const FormatException('El QR Bluetooth del visor no es válido.');
  }
  await _prepareBluetooth(peripheral: false);
  attempt.check();
  BluetoothDevice? device;
  StreamSubscription<List<ScanResult>>? scan;
  StreamSubscription<List<int>>? values;
  StreamSubscription<BluetoothConnectionState>? connection;
  VrBlePacketLink? link;
  Completer<BluetoothDevice>? discovery;
  attempt.onCancel = () {
    if (discovery != null && !discovery.isCompleted) {
      discovery.completeError(StateError('Búsqueda Bluetooth cancelada.'));
    }
    if (link != null) {
      unawaited(link.close());
    } else if (device != null) {
      unawaited(device.disconnect());
    }
  };
  try {
    final found = Completer<BluetoothDevice>();
    discovery = found;
    // Observe early scan/cancellation failures before native startScan returns.
    unawaited(found.future.then<void>((_) {}, onError: (Object _) {}));
    final uuid = Guid(invitation.bleServiceUuid!);
    scan = FlutterBluePlus.onScanResults.listen(
      (results) {
        for (final result in results) {
          if (result.advertisementData.serviceUuids.contains(uuid) &&
              !found.isCompleted) {
            found.complete(result.device);
          }
        }
      },
      onError: (Object e) {
        if (!found.isCompleted) found.completeError(e);
      },
    );
    await FlutterBluePlus.startScan(
      withServices: [uuid],
      timeout: const Duration(seconds: 8),
    );
    device = await found.future.timeout(
      const Duration(seconds: 9),
      onTimeout: () {
        throw const VrControllerConnectionException(
          'No se encontró el visor. Acerca los teléfonos, abre su QR Bluetooth y comprueba permisos (Ubicación en Android 11 o anterior).',
        );
      },
    );
    attempt.check();
    await FlutterBluePlus.stopScan();
    await scan.cancel();
    scan = null;
    await device.connect(timeout: const Duration(seconds: 8), mtu: null);
    attempt.check();
    final services = await device.discoverServices(timeout: 5);
    attempt.check();
    BluetoothCharacteristic? rx, tx;
    for (final service in services.where((s) => s.uuid == uuid)) {
      for (final characteristic in service.characteristics) {
        if (characteristic.uuid == Guid(vrBleRxUuid)) rx = characteristic;
        if (characteristic.uuid == Guid(vrBleTxUuid)) tx = characteristic;
      }
    }
    if (rx == null ||
        tx == null ||
        !tx.properties.notify ||
        (!rx.properties.write && !rx.properties.writeWithoutResponse)) {
      throw const VrControllerConnectionException(
        'El visor no ofrece el protocolo BLE de VRlizate. Actualiza ambos teléfonos.',
        canRetry: false,
      );
    }
    final target = device;
    final receive = rx;
    final channel = VrBlePacketLink(
      writeChunk: (chunk) => receive.write(
        chunk,
        withoutResponse: !receive.properties.write,
        timeout: 3,
      ),
      writeChunkWithReliability: (chunk, {required reliable}) => receive.write(
        chunk,
        // Single-PDU continuous analog samples use WRITE_NO_RESPONSE (~10 ms,
        // 60 Hz); discrete button edges and multi-chunk control messages keep
        // peripheral ATT acknowledgement.
        withoutResponse: !reliable && receive.properties.writeWithoutResponse
            ? true
            : !receive.properties.write,
        timeout: 3,
      ),
      onClose: () async {
        await values?.cancel();
        await connection?.cancel();
        await target.disconnect();
      },
    );
    link = channel;
    final peer = VrBleClientPeer(
      link: channel,
      sessionToken: invitation.sessionToken,
    );
    // Attach the error handler immediately, before setNotifyValue can fail.
    final ready = peer.ready.timeout(const Duration(seconds: 8));
    unawaited(ready.then<void>((_) {}, onError: (Object _) {}));
    values = tx.onValueReceived.listen(
      (bytes) => channel.receive(Uint8List.fromList(bytes)),
      onError: (_) => channel.close(),
    );
    connection = target.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        unawaited(channel.close());
      }
    });
    if (Platform.isAndroid) {
      try {
        await target.requestConnectionPriority(
          connectionPriorityRequest: ConnectionPriority.high,
        );
      } catch (_) {
        /* Optional optimization, not required for correctness. */
      }
      try {
        final mtu = await target.requestMtu(64, timeout: 2);
        if (mtu >= 28) channel.enableSinglePacketState();
      } catch (_) {
        /* Falls back safely to 20-byte fragmented states if refused. */
      }
    } else if (Platform.isIOS) {
      if (target.mtuNow >= 28) channel.enableSinglePacketState();
    }
    attempt.check();
    if (!await tx.setNotifyValue(true, timeout: 5)) {
      throw const VrControllerConnectionException(
        'No se pudo activar la recepción BLE.',
      );
    }
    final authenticated = await ready;
    attempt.check();
    return VrHybridBleUdpClientLink(
      bleLink: authenticated,
      sessionToken: invitation.sessionToken,
    );
  } catch (_) {
    if (link != null) {
      await link.close();
    } else {
      await device?.disconnect();
    }
    rethrow;
  } finally {
    if (scan != null) {
      await FlutterBluePlus.stopScan();
      await scan.cancel();
    }
  }
}
