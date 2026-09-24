import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_lens_mobile/drive/drive_engine.dart';
import 'package:kiwi_lens_mobile/widgets/navigation_overlay.dart';

void main() {
  test('navigation distances never show negative metres', () {
    expect(navigationDistanceLabel(-25), '0 m');
    expect(navigationDistanceLabel(1500), '1.5 km');
  });
  testWidgets('compact navigation layout fits a small iPhone and expands', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final engine = DriveEngine();
    addTearDown(engine.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: NavigationOverlay(
                  engine: engine,
                  destinationTitle:
                      'Te Whatu Stardome Observatory & Planetarium',
                  gpsAccuracy: 18,
                  voiceEnabled: true,
                  lanesEnabled: true,
                  onEnd: () {},
                  onRecenter: () {},
                  onOverview: () {},
                  northUp: false,
                  onCompassToggle: () {},
                  onReport: () {},
                  onSearchAlongRoute: () {},
                  onDirections: () {},
                  onShare: () {},
                  onSettings: () {},
                  onLayers: () {},
                  onVoiceToggle: () {},
                  onLanesToggle: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('End navigation'), findsOneWidget);
    expect(find.text('GPS ±18 m'), findsOneWidget);
    expect(find.text('Add a report'), findsNothing);

    await tester.tap(find.byKey(const Key('navigationSheetHandle')));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Add a report'), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('navigationSheetSurface')),
      const Offset(0, 170),
    );
    await tester.pumpAndSettle();
    expect(find.text('Add a report'), findsNothing);
  });
}
