import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/models/secondary_display_state.dart';
import 'package:neostation/screens/secondary_screen/now_playing_helpers.dart';
import 'package:neostation/screens/secondary_screen/widgets/now_playing_panel.dart';

void main() {
  group('secondary dock reservation', () {
    test('matches 4:3 and wide secondary display dock heights', () {
      expect(
        secondaryDockReservedHeight(screenHeight: 480, dockEnabled: true),
        96,
      );
      expect(
        secondaryDockReservedHeight(screenHeight: 720, dockEnabled: true),
        144,
      );
      expect(
        secondaryDockReservedHeight(screenHeight: 720, dockEnabled: false),
        0,
      );
    });
  });

  final panelState = SecondaryDisplayStateData(
    systemName: 'Nintendo Game Boy Color',
    gameTitle: "John Romero's Daikatana",
    playTimeSeconds: 420,
    lastPlayedMillis: DateTime.now().millisecondsSinceEpoch,
    screenshotAccessEnabled: true,
    dockEnabled: true,
  );

  Future<void> pumpPanel(WidgetTester tester, Size size) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NowPlayingPanel(
            value: panelState,
            sessionRunning: true,
            sessionTime: '01:23:45',
            onRequestScreenshot: () {},
          ),
        ),
      ),
    );
  }

  testWidgets('fits a wide swapped secondary display', (tester) async {
    await pumpPanel(tester, const Size(1280, 720));

    expect(tester.takeException(), isNull);
    expect(find.text('SCREENSHOT'), findsOneWidget);
  });

  testWidgets('fits a 4:3 secondary display', (tester) async {
    await pumpPanel(tester, const Size(640, 480));

    expect(tester.takeException(), isNull);
    expect(find.text('SCREENSHOT'), findsOneWidget);
  });
}
