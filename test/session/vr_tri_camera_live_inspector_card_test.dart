import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neom_vr/neom_vr_sessions.dart';

void main() {
  testWidgets(
    'inspector reacts to its service without an inherited scope rebuild',
    (tester) async {
      final service = VrSpatialTrackingService(observeLifecycle: false);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: VrTriCameraLiveInspectorCard(service: service),
            ),
          ),
        ),
      );
      expect(find.text('Mezcla de vista de cámara · 0%'), findsOneWidget);
      service.setPassthroughMix(.65);
      await tester.pump();
      expect(find.text('Mezcla de vista de cámara · 65%'), findsOneWidget);
      expect(find.text('Mezcla de vista de cámara · 0%'), findsNothing);
      service.setPassthroughMix(.35);
      await tester.pump();
      expect(find.text('Mezcla de vista de cámara · 35%'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      service.dispose();
      await tester.pump();
    },
  );
}
