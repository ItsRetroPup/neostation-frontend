import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/models/secondary_display_state.dart';
import 'package:neostation/screens/secondary_screen/widgets/now_playing_panel.dart';

void main() {
  final panelState = SecondaryDisplayStateData(
    systemName: 'Nintendo Game Boy Color',
    gameTitle: "John Romero's Daikatana",
    playTimeSeconds: 420,
    lastPlayedMillis: DateTime.now().millisecondsSinceEpoch,
    screenshotAccessEnabled: true,
    dockEnabled: true,
  );

  Future<void> pumpPanel(
    WidgetTester tester,
    Size size, {
    required bool dockEnabled,
  }) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NowPlayingPanel(
            value: panelState.copyWith(dockEnabled: dockEnabled),
            sessionRunning: true,
            sessionTime: '01:23:45',
            onRequestScreenshot: () {},
          ),
        ),
      ),
    );
  }

  testWidgets('fits a wide swapped secondary display', (tester) async {
    await pumpPanel(tester, const Size(1280, 720), dockEnabled: true);

    expect(tester.takeException(), isNull);
    expect(find.text('SCREENSHOT'), findsOneWidget);
  });

  testWidgets('fits a 4:3 secondary display', (tester) async {
    await pumpPanel(tester, const Size(640, 480), dockEnabled: true);

    expect(tester.takeException(), isNull);
    expect(find.text('SCREENSHOT'), findsOneWidget);
  });

  testWidgets('dock visibility does not shift Now Playing content', (
    tester,
  ) async {
    const size = Size(1280, 720);

    await pumpPanel(tester, size, dockEnabled: true);
    final dockVisiblePosition = tester.getTopLeft(find.text('NOW PLAYING'));

    await pumpPanel(tester, size, dockEnabled: false);
    final dockHiddenPosition = tester.getTopLeft(find.text('NOW PLAYING'));

    expect(dockVisiblePosition, dockHiddenPosition);
  });
}
