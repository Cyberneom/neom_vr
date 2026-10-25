import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neom_vr/neom_vr_sessions.dart';

class _PendingCalibration extends Fake
    implements VrSpatialTrackingPlatform, VrCameraCalibrationPlatform {
  final pending = Completer<Map<dynamic, dynamic>>();
  @override
  Future<Map<dynamic, dynamic>> cameraCalibration({String? cameraId}) =>
      pending.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('vrlizate/spatial_tracking');
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'static optical metadata never starts capture or certifies a live frame',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return {
              'status': 'available',
              'metricPoseReady': true,
              'frameMappingKnown': true,
              'previewCalibrationVerified': true,
              'cameras': [
                {
                  'id': '0',
                  'intrinsicCalibration': [100.0, 100.0, 50.0, 50.0, 0.0],
                },
              ],
            };
          });
      final service = VrSpatialTrackingService(observeLifecycle: false);
      final result = await service.readCameraCalibrationDiagnostics(
        cameraId: '0',
      );
      expect(calls.map((c) => c.method), ['cameraCalibration']);
      expect(calls.single.arguments, {'cameraId': '0'});
      expect(result['cameras'], hasLength(1));
      expect(result['metricPoseReady'], isFalse);
      expect(result['frameMappingKnown'], isFalse);
      expect(result['previewCalibrationVerified'], isFalse);
      expect(service.enabled, isFalse);
      expect(service.tracking, isFalse);
      expect(service.spaceMapper.objects, isEmpty);
      service.dispose();
    },
  );

  test(
    'missing host and invalid camera IDs preserve an unavailable result',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final service = VrSpatialTrackingService(observeLifecycle: false);
      final invalid = await service.readCameraCalibrationDiagnostics(
        cameraId: '',
      );
      expect(invalid['reason'], 'invalid_camera_id');
      final missing = await service.readCameraCalibrationDiagnostics();
      expect(missing['reason'], 'missing_plugin');
      expect(missing['metricPoseReady'], isFalse);
      service.dispose();
    },
  );

  test('optical metadata timeout is bounded and does not turn into a pose', () {
    fakeAsync((time) {
      final platform = _PendingCalibration();
      final service = VrSpatialTrackingService(
        platform: platform,
        observeLifecycle: false,
      );
      Map<dynamic, dynamic>? response;
      service.readCameraCalibrationDiagnostics().then(
        (value) => response = value,
      );
      time.flushMicrotasks();
      expect(response, isNull);
      time.elapse(const Duration(seconds: 2));
      time.flushMicrotasks();
      expect(response?['reason'], 'timeout');
      expect(response?['metricPoseReady'], isFalse);
      platform.pending.complete({'metricPoseReady': true});
      time.flushMicrotasks();
      expect(response?['reason'], 'timeout');
      service.dispose();
      time.flushMicrotasks();
    });
  });
}
