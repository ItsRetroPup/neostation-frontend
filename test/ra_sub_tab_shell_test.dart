import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/retro_achievements_dashboard_models.dart';
import 'package:neostation/models/retro_achievements_user.dart';
import 'package:neostation/providers/retro_achievements_provider.dart';
import 'package:neostation/providers/romm_provider.dart';
import 'package:neostation/screens/retro_achievements_screen/ra_content.dart';
import 'package:neostation/screens/retro_achievements_screen/ra_dashboard.dart';
import 'package:neostation/screens/retro_achievements_screen/ra_tab_strip.dart';
import 'package:neostation/services/gamepad/gamepad_navigation_manager.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/widgets/core_footer.dart';
import 'package:neostation/widgets/ra_refresh_action.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A signed-in (by default) provider with the five dashboard fetches stubbed
/// to recorders: the hub's dwell timer fires in these tests, so the real
/// fetches must never run, and the call log is exactly what the REFRESH test
/// wants to observe.
class _ShellProvider extends RetroAchievementsProvider {
  _ShellProvider({bool connected = true}) : _connected = connected;

  final bool _connected;
  final List<String> fetchLog = [];
  bool _dashboardLoading = false;

  void setDashboardLoading(bool value) {
    _dashboardLoading = value;
    notifyListeners();
  }

  @override
  bool get isConnected => _connected;

  @override
  bool get isDashboardLoading => _dashboardLoading;

  @override
  RetroAchievementsUser? get user => RetroAchievementsUser(
    user: 'Player',
    ulid: '',
    userPic: '',
    memberSince: '',
    richPresenceMsg: '',
    lastGameId: 0,
    contribCount: 0,
    contribYield: 0,
    totalPoints: 1,
    totalCasualPoints: 0,
    totalTruePoints: 0,
    permissions: 0,
    untracked: 0,
    id: 1,
    userWallActive: false,
    motto: '',
  );

  @override
  List<RetroAchievementRecentUnlockItem> get recentUnlocks =>
      List.generate(8, _unlock);

  @override
  List<RetroAchievementRecentlyPlayedGameItem> get recentlyPlayedGames =>
      List.generate(8, _played);

  @override
  Future<bool> fetchGOTW() async {
    fetchLog.add('gotw');
    return true;
  }

  @override
  Future<bool> fetchRecentUnlocks() async {
    fetchLog.add('unlocks');
    return true;
  }

  @override
  Future<bool> fetchRecentlyPlayedGames() async {
    fetchLog.add('played');
    return true;
  }

  @override
  Future<bool> fetchUserAwards() async {
    fetchLog.add('awards');
    return true;
  }

  @override
  Future<bool> fetchCompletionProgress() async {
    fetchLog.add('progress');
    return true;
  }
}

RetroAchievementRecentUnlockItem _unlock(int i) =>
    RetroAchievementRecentUnlockItem(
      date: '2026-09-01 00:00:00',
      hardcoreMode: true,
      achievementId: i,
      title: 'Achievement $i',
      description: 'Desc $i',
      badgeName: 'badge$i',
      badgeUrl: 'https://media.retroachievements.org/Badge/b$i.png',
      points: 5,
      trueRatio: 5,
      type: null,
      author: 'author',
      authorUlid: '',
      gameTitle: 'Game $i',
      gameIcon: '',
      gameId: i,
      consoleName: 'NES',
      gameUrl: '',
    );

RetroAchievementRecentlyPlayedGameItem _played(int i) =>
    RetroAchievementRecentlyPlayedGameItem(
      gameId: i,
      consoleId: 1,
      consoleName: 'NES',
      title: 'Played $i',
      imageIcon: '',
      imageTitle: '',
      imageIngame: '',
      imageBoxArt: '',
      lastPlayed: '2026-09-01 00:00:00',
      achievementsTotal: 10,
      numPossibleAchievements: 10,
      possibleScore: 50,
      numAchieved: 3,
      scoreAchieved: 15,
      numAchievedHardcore: 2,
      scoreAchievedHardcore: 10,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    // The SoLoud engine's native symbols do not exist in the test runner, so
    // any sound the input paths try to play would throw through them. Every
    // input-driving suite in the repo disables the service for this reason.
    SfxService().setEnabled(false);
    // Stub the gamepads plugin so GamepadNavigation.initialize() (run by the
    // tab's own layer) finds no devices and its event stream stays empty.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('xyz.luan/gamepads'),
          (call) async => <dynamic>[],
        );
    await FlutterLocalization.instance.ensureInitialized();
    FlutterLocalization.instance.init(
      mapLocales: [MapLocale('en', AppLocale.en)],
      initLanguageCode: 'en',
    );
  });

  /// The wall-clock parts of input (the inter-key throttle and the layer
  /// activation grace) do not run on the test's fake clock, so real time has
  /// to pass the way [systems_view_reuse_test]'s helpers do.
  Future<void> settleInput(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump();
  }

  /// Sends one key press and lets the navigator's inter-key throttle expire.
  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
  }

  /// Pumps the tab shell. [header] simulates the app header's per-tab slot
  /// (where the REFRESH chip lives) above the tab content.
  Future<void> pumpShell(
    WidgetTester tester,
    RetroAchievementsProvider provider, {
    Widget? header,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<RetroAchievementsProvider>.value(
            value: provider,
          ),
          ChangeNotifierProvider(create: (_) => RommProvider()),
        ],
        child: ScreenUtilInit(
          designSize: const Size(1280, 720),
          builder: (context, _) => MaterialApp(
            localizationsDelegates:
                FlutterLocalization.instance.localizationsDelegates,
            supportedLocales: FlutterLocalization.instance.supportedLocales,
            home: Scaffold(
              body: header != null
                  ? Column(
                      children: [
                        header,
                        const Expanded(child: RAContent()),
                      ],
                    )
                  : const RAContent(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  RaTabStrip stripOf(WidgetTester tester) =>
      tester.widget<RaTabStrip>(find.byType(RaTabStrip));

  testWidgets('signed out: the login card renders and no strip does', (
    tester,
  ) async {
    await pumpShell(tester, _ShellProvider(connected: false));

    expect(find.byType(RaTabStrip), findsNothing);
    expect(find.byType(RADashboardHub), findsNothing);
    // Username + API key fields of the unchanged login form.
    expect(find.byType(TextFormField), findsNWidgets(2));

    // Every new shell behavior sits behind the handlers' `isConnected`
    // guards, so signed-out input must land exactly where it did before the
    // shell: B routes through the new `_handleBack` wrapper to
    // `exitTextEntry` (a no-op with no field focused), and A focuses the
    // selected field — slot 0, the username.
    //
    // Deliberately *not* asserted: that Down walks the form's slots.
    // Keyboard-simulated arrows are double-dispatched in the test
    // environment — the focus system's directional traversal consumes them
    // too, and traversal focusing the username field makes the form's focus
    // listener (correctly) pull the highlight back to slot 0. A real D-pad
    // never touches the focus system, so the walk is verified on-device in
    // the smoke pass instead.
    await settleInput(tester);
    await press(tester, LogicalKeyboardKey.backspace);
    await press(tester, LogicalKeyboardKey.enter);
    final fields = find.byType(TextField);
    expect(tester.widget<TextField>(fields.at(0)).focusNode!.hasFocus, isTrue);

    // Directional input neither crashes nor grows a strip while signed out.
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(find.byType(RaTabStrip), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('signed in: the shell renders one Dashboard pill', (
    tester,
  ) async {
    await pumpShell(tester, _ShellProvider());

    expect(find.byType(RaTabStrip), findsOneWidget);
    expect(find.byType(RADashboardHub), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.label == 'Dashboard' &&
            w.properties.selected == true,
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('Up from the dashboard top parks on the strip; Down re-enters', (
    tester,
  ) async {
    final provider = _ShellProvider();
    await pumpShell(tester, provider);
    await settleInput(tester);

    final depth = GamepadNavigationManager.stackDepth;
    expect(stripOf(tester).focused, isFalse);

    // Fresh dashboard: scrolled to the top, nothing parked, so the first Up
    // has nothing finer to do inside the content and parks on the strip.
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(stripOf(tester).focused, isTrue);
    expect(GamepadNavigationManager.stackDepth, depth);

    // Down hands the cursor back to the content zone.
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(stripOf(tester).focused, isFalse);
    expect(GamepadNavigationManager.stackDepth, depth);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'B in the content reaches the strip; the dashboard survives the round-trip',
    (tester) async {
      final provider = _ShellProvider();
      await pumpShell(tester, provider);
      await settleInput(tester);

      // Scroll the dashboard so there is cursor state worth preserving, then
      // remember both it and the hub's State identity.
      await tester.drag(find.byType(RADashboardHub), const Offset(0, -400));
      await tester.pumpAndSettle();
      final controller = tester
          .widget<RADashboardHub>(find.byType(RADashboardHub))
          .scrollController!;
      final offsetBefore = controller.position.pixels;
      final hubStateBefore = tester.state<RADashboardHubState>(
        find.byType(RADashboardHub),
      );

      await press(tester, LogicalKeyboardKey.backspace);
      expect(stripOf(tester).focused, isTrue);

      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(stripOf(tester).focused, isFalse);

      // No remount, no scroll reset: zone switches tear nothing down.
      expect(
        tester.state<RADashboardHubState>(find.byType(RADashboardHub)),
        same(hubStateBefore),
      );
      expect(controller.position.pixels, offsetBefore);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('Left/Right on a one-pill strip leave the dashboard in place', (
    tester,
  ) async {
    final provider = _ShellProvider();
    await pumpShell(tester, provider);
    await settleInput(tester);

    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(stripOf(tester).focused, isTrue);
    final depth = GamepadNavigationManager.stackDepth;

    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(stripOf(tester).currentTab, RaSubTab.dashboard);
    expect(stripOf(tester).focused, isTrue);

    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(stripOf(tester).currentTab, RaSubTab.dashboard);
    expect(stripOf(tester).focused, isTrue);
    expect(GamepadNavigationManager.stackDepth, depth);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'the tab registers exactly one layer, and releases it on dispose',
    (tester) async {
      final base = GamepadNavigationManager.stackDepth;
      await pumpShell(tester, _ShellProvider());
      await settleInput(tester);

      // The whole shell — strip zone, content zone, sub-tab switches — is one
      // `ra_content` layer: one push on mount, nothing while it runs.
      expect(GamepadNavigationManager.stackDepth, base + 1);

      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.backspace);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(GamepadNavigationManager.stackDepth, base + 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(GamepadNavigationManager.stackDepth, base);
    },
  );

  testWidgets('REFRESH refetches in place without leaving the tab', (
    tester,
  ) async {
    final provider = _ShellProvider();
    await pumpShell(tester, provider, header: const RaRefreshAction());
    await settleInput(tester);

    // The hub's dwell timer fires the initial sequential load.
    await tester.pump(const Duration(milliseconds: 400));
    expect(provider.fetchLog, contains('gotw'));
    final initialFetches = provider.fetchLog.length;
    final generationBefore = provider.cacheGeneration;

    await tester.tap(find.text('Refresh'));
    await tester.pump();

    expect(provider.cacheGeneration, generationBefore + 1);
    // The mounted hub watched the generation bump and ran its sections again.
    expect(provider.fetchLog.length, greaterThan(initialFetches));
    expect(provider.fetchLog.length - initialFetches, greaterThanOrEqualTo(5));

    // While a load is in flight the chip says so and refuses a second tap.
    provider.setDashboardLoading(true);
    await tester.pump();
    expect(find.text('Refreshing...'), findsOneWidget);
    await tester.tap(find.text('Refreshing...'));
    await tester.pump();
    expect(provider.cacheGeneration, generationBefore + 1);

    provider.setDashboardLoading(false);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('the refresh chip stays off the signed-out tab', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<RetroAchievementsProvider>.value(
        value: _ShellProvider(connected: false),
        child: const MaterialApp(home: Scaffold(body: RaRefreshAction())),
      ),
    );
    await tester.pump();

    expect(find.byType(RaRefreshAction), findsOneWidget);
    expect(find.byType(GamepadControl), findsNothing);
  });
}
