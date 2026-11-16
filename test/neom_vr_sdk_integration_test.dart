import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neom_ble/gatt/neom_gatt_server.dart';
import 'package:neom_vr/neom_vr.dart';
import 'package:vrlizate_joystick/vrlizate_joystick.dart';

class _FakeNeomGattServer extends NeomGattServer {
  final incoming = StreamController<GattServerEvent>.broadcast(sync: true);
  bool published = false;
  bool advertising = false;

  @override
  Future<bool> isSupported() async => true;

  @override
  Stream<GattServerEvent> get events => incoming.stream;

  @override
  Future<bool> startDuplexService({
    required String serviceUuid,
    required String rxCharUuid,
    required String txCharUuid,
  }) async {
    published = true;
    return true;
  }

  @override
  Future<bool> startConnectableAdvertising({required String serviceUuid}) async {
    advertising = true;
    return true;
  }

  @override
  Future<void> stopAdvertising() async => advertising = false;

  @override
  Future<void> stopDuplexService() async => published = false;
}

void main() {
  test('NeomVrHostBindings bridges ItzliVrAssistant and NeomGattServer into SDK', () async {
    NeomVrHostBindings.registerSdkIntegrations();
    final station = VrDesktopBeaconStation();
    addTearDown(station.dispose);
    final guidance = station.submitVoiceCommand('llévame a Ciudad Solar');
    expect(guidance, isA<ItzliVrGuidance>());
    expect(guidance.actionType, ItzliActionType.launchExperience);
    expect(guidance.targetDemoId, 'ecosystems_solar_city');

    final neomServer = _FakeNeomGattServer();
    final controller = VrRemoteControllerService();
    final adapter = StreamController<BluetoothAdapterState>.broadcast(sync: true);
    final host = VrBleHost(
      controller,
      gatt: NeomBleGattPeripheralAdapter(neomServer),
      adapterStates: adapter.stream,
      prepareBluetooth: () async {},
    );
    addTearDown(() async {
      await host.dispose();
      controller.dispose();
      await adapter.close();
      await neomServer.incoming.close();
    });
    await host.start();
    expect(neomServer.published, isTrue);
    expect(neomServer.advertising, isTrue);
  });
}
