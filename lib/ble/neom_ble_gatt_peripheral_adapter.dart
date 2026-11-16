import 'dart:typed_data';

import 'package:neom_ble/gatt/neom_gatt_server.dart';
import 'package:vrlizate_ble/vrlizate_ble.dart';

/// Typed Open Neom adapter bridging [NeomGattServer] (`package:neom_ble`) to
/// VRlizate SDK's [VrBleGattPeripheralAdapter].
class NeomBleGattPeripheralAdapter implements VrBleGattPeripheralAdapter {
  NeomBleGattPeripheralAdapter([NeomGattServer? server])
    : server = server ?? NeomGattServer();

  final NeomGattServer server;

  static VrBleGattEvent _mapEvent(GattServerEvent event) {
    final type = switch (event.type) {
      GattServerEventType.started => VrBleGattEventType.started,
      GattServerEventType.stopped => VrBleGattEventType.stopped,
      GattServerEventType.clientConnected => VrBleGattEventType.clientConnected,
      GattServerEventType.clientDisconnected =>
        VrBleGattEventType.clientDisconnected,
      GattServerEventType.duplexData => VrBleGattEventType.duplexData,
      GattServerEventType.duplexClientSubscribed =>
        VrBleGattEventType.duplexClientSubscribed,
      GattServerEventType.duplexClientUnsubscribed =>
        VrBleGattEventType.duplexClientUnsubscribed,
      GattServerEventType.duplexMtuChanged =>
        VrBleGattEventType.duplexMtuChanged,
      GattServerEventType.advertisingStarted =>
        VrBleGattEventType.advertisingStarted,
      GattServerEventType.advertisingFailed =>
        VrBleGattEventType.advertisingFailed,
      GattServerEventType.chunkServed ||
      GattServerEventType.beaconClientSubscribed ||
      GattServerEventType.beaconClientUnsubscribed ||
      GattServerEventType.beaconData => VrBleGattEventType.other,
      GattServerEventType.error => VrBleGattEventType.error,
    };
    return VrBleGattEvent(
      type: type,
      deviceId: event.deviceId,
      offset: event.offset,
      length: event.length,
      message: event.message,
      data: event.data,
      mtu: event.mtu,
      maxNotificationBytes: event.maxNotificationBytes,
    );
  }

  @override
  Stream<VrBleGattEvent> get events => server.events.map(_mapEvent);

  @override
  Future<bool> isSupported() => server.isSupported();

  @override
  Future<bool> startDuplexService({
    required String serviceUuid,
    required String rxCharUuid,
    required String txCharUuid,
  }) => server.startDuplexService(
    serviceUuid: serviceUuid,
    rxCharUuid: rxCharUuid,
    txCharUuid: txCharUuid,
  );

  @override
  Future<void> stopDuplexService() => server.stopDuplexService();

  @override
  Future<bool> notifyDuplex({
    required String deviceId,
    required Uint8List data,
  }) => server.notifyDuplex(deviceId: deviceId, data: data);

  @override
  Future<bool> disconnectDuplexClient({required String deviceId}) =>
      server.disconnectDuplexClient(deviceId: deviceId);

  @override
  Future<bool> startConnectableAdvertising({required String serviceUuid}) =>
      server.startConnectableAdvertising(serviceUuid: serviceUuid);

  @override
  Future<void> stopAdvertising() => server.stopAdvertising();
}
