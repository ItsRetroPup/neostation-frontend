import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/retro_achievements_dashboard_models.dart';
import 'package:neostation/models/retro_achievements_summary.dart';
import 'package:neostation/models/retro_achievements_user.dart';
import 'package:neostation/providers/file_provider.dart';
import 'package:neostation/providers/retro_achievements_provider.dart';
import 'package:neostation/providers/romm_provider.dart';
import 'package:neostation/providers/sqlite_config_provider.dart';
import 'package:neostation/screens/retro_achievements_screen/ra_content.dart';
import 'package:neostation/screens/retro_achievements_screen/ra_dashboard.dart';
import 'package:neostation/screens/retro_achievements_screen/ra_tab_strip.dart';
import 'package:neostation/screens/retro_achievements_screen/ra_collection_tab.dart';
import 'package:neostation/models/retro_achievements_game_info.dart';
import 'package:neostation/screens/retro_achievements_screen/ra_games_tab.dart';
import 'package:neostation/services/gamepad/gamepad_navigation_manager.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/widgets/core_footer.dart';
import 'package:neostation/widgets/ra_refresh_action.dart';
import 'package:neostation/widgets/ra_subtab_footer.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A signed-in (by default) provider with the five dashboard fetches stubbed
/// to recorders: the hub's dwell timer fires in these tests, so the real
/// fetches must never run, and the call log is exactly what the REFRESH test
/// wants to observe.
class _ShellProvider extends RetroAchievementsProvider {
  _ShellProvider({
    bool connected = true,
    RetroAchievementsUserSummary? summary,
    List<RetroAchievementRecentUnlockItem> unlocksItems = const [],
    List<RaGamesListItem> gamesListItems = const [],
  }) : _connected = connected,
       _summary = summary,
       _unlocksItems = unlocksItems,
       _gamesListItems = gamesListItems;

  final bool _connected;
  final RetroAchievementsUserSummary? _summary;

  /// See-all rows for the Unlocks sub-tab. Empty by default so every other
  /// shell test sees exactly the pre-tab behaviour.
  final List<RetroAchievementRecentUnlockItem> _unlocksItems;
  final List<RaGamesListItem> _gamesListItems;
  final List<String> fetchLog = [];
  bool _dashboardLoading = false;

  void setDashboardLoading(bool value) {
    _dashboardLoading = value;
    notifyListeners();
  }

  @override
  Future<Map<String, dynamic>> getEventCatalogue(int year) async => {
    'year': year,
    'source': 'https://retroachievements.org/event/196',
    'weeks': [],
  };
  @override
  Future<GameInfoAndUserProgress?> getAnnualEventProgress(int year) async {
    fetchLog.add('events-progress');
    return null;
  }

  @override
  Future<List<RetroAchievementCompletionProgressItem>>
  getAwardProgress() async => [];

  @override
  bool get isConnected => _connected;

  @override
  bool get isDashboardLoading => _dashboardLoading;

  @override
  bool get summaryLoaded => true;

  @override
  RetroAchievementsUserSummary? get userSummary => _summary;

  @override
  List<RaGamesListItem> get gamesListItems => _gamesListItems;

  @override
  bool get gamesListLoaded => true;

  @override
  bool get gamesListIsStale => false;

  @override
  bool get gamesListLoading => false;

  @override
  bool get gamesListHasMore => false;

  @override
  String? get gamesListError => null;

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

  @override
  List<RetroAchievementRecentUnlockItem> get unlocksListItems => _unlocksItems;

  @override
  Future<bool> loadUnlocksPage({bool reset = false}) async {
    fetchLog.add('unlocks-page${reset ? '-reset' : ''}');
    // Enough of the real bookkeeping for the tab's staleness checks to see a
    // completed load: the attempt stamp is public, the loaded flag has to be
    // shadowed because the real one is library-private.
    markUnlocksListAttempted();
    _unlocksListLoaded = true;
    return true;
  }

  bool _unlocksListLoaded = false;

  @override
  bool get unlocksListLoaded => _unlocksListLoaded;
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
    RommProvider? romm,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<RetroAchievementsProvider>.value(
            value: provider,
          ),
          // The Unlocks drill-down reads the app's config and file providers
          // on its way to the library; the real ones are inert in a test
          // tree until something asks them for data.
          ChangeNotifierProvider(create: (_) => SqliteConfigProvider()),
          ChangeNotifierProvider(create: (_) => FileProvider()),
          if (romm != null)
            ChangeNotifierProvider<RommProvider>.value(value: romm)
          else
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

    // Flush the post-frame chain that creates the unlocks tab's 100ms
    // initial-centering timer (it starts from a post-frame callback, so it
    // may only be *created* on the next frame), then advance past the timer
    // itself — an anonymous timer dispose cannot cancel.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  RetroAchievementsUserSummary summary(int rank, int total) =>
      RetroAchievementsUserSummary.fromJson({
        'Rank': rank,
        'TotalRanked': total,
      });

  Future<void> disposeShell(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('profile shows rank and percentile from the user summary', (
    tester,
  ) async {
    await pumpShell(tester, _ShellProvider(summary: summary(1234, 22025)));

    expect(find.text('Rank #1,234 · Top 5.6%'), findsOneWidget);
    await disposeShell(tester);
  });

  testWidgets('profile shows Unranked without a rank', (tester) async {
    await pumpShell(tester, _ShellProvider(summary: summary(0, 22025)));

    expect(find.text('Unranked'), findsOneWidget);
    await disposeShell(tester);
  });

  testWidgets(
    'profile omits an inconsistent percentile and rounds tiny values',
    (tester) async {
      await pumpShell(tester, _ShellProvider(summary: summary(2, 1)));
      expect(find.text('Rank: 2'), findsOneWidget);
      expect(find.textContaining('Top '), findsNothing);
      await disposeShell(tester);

      await pumpShell(tester, _ShellProvider(summary: summary(1, 2001)));
      expect(find.text('Rank #1 · Top <0.1%'), findsOneWidget);
      await disposeShell(tester);
    },
  );

  testWidgets('signed in: the strip renders the four sub-tab pills', (
    tester,
  ) async {
    await pumpShell(tester, _ShellProvider());

    expect(find.byType(RaTabStrip), findsOneWidget);
    expect(find.byType(RADashboardHub), findsOneWidget);
    // The IndexedStack hosts all four sub-tabs from the start; only the
    // dashboard is showing, and the other three wait off-stage at their dwell
    // gates. (skipOffstage: IndexedStack parks non-showing children in an
    // Offstage wrapper, which the default finders skip.)
    expect(find.byType(RaCollectionTab, skipOffstage: false), findsNWidgets(2));
    expect(find.byType(RaGamesTab, skipOffstage: false), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.label == 'Profile' &&
            w.properties.selected == true,
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.label == 'AOTW' &&
            w.properties.selected == false,
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.label == 'Games' &&
            w.properties.selected == false,
      ),
      findsOneWidget,
    );

    // Flush the post-frame chain that creates the unlocks tab's 100ms
    // initial-centering timer (it starts from a post-frame callback, so it
    // may only be *created* on the next frame), then advance past the timer
    // itself — an anonymous timer dispose cannot cancel.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
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
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(
      tester
          .widget<RADashboardHub>(find.byType(RADashboardHub))
          .recentUnlocksSelected,
      isTrue,
    );

    // Flush the post-frame chain that creates the unlocks tab's 100ms
    // initial-centering timer (it starts from a post-frame callback, so it
    // may only be *created* on the next frame), then advance past the timer
    // itself — an anonymous timer dispose cannot cancel.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
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

      // Flush the post-frame chain that creates the unlocks tab's 100ms
      // initial-centering timer (it starts from a post-frame callback, so it
      // may only be *created* on the next frame), then advance past the timer
      // itself — an anonymous timer dispose cannot cancel.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'Left/Right on the strip switch sub-tabs, wrapping at both ends',
    (tester) async {
      final provider = _ShellProvider();
      await pumpShell(tester, provider);
      await settleInput(tester);

      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(stripOf(tester).focused, isTrue);
      final depth = GamepadNavigationManager.stackDepth;
      // skipOffstage: the hub is found across the whole test, including while
      // the Unlocks sub-tab is the one showing (IndexedStack parks the other
      // child off-stage, where default finders don't look).
      final hubBefore = tester.state<RADashboardHubState>(
        find.byType(RADashboardHub, skipOffstage: false),
      );

      // Right steps onto Unlocks, then Games; the dashboard's State survives
      // underneath throughout.
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(stripOf(tester).currentTab, RaSubTab.events);
      expect(stripOf(tester).focused, isTrue);
      // The active flag follows the strip: the tab being shown is the one
      // that may fetch and animate.
      expect(
        tester
            .widget<RaGamesTab>(find.byType(RaGamesTab, skipOffstage: false))
            .active,
        isFalse,
      );

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(stripOf(tester).currentTab, RaSubTab.games);
      expect(
        tester
            .widget<RaGamesTab>(find.byType(RaGamesTab, skipOffstage: false))
            .active,
        isTrue,
      );

      // Right wraps from Games back around to Dashboard — three pills, both
      // directions live, no dead press at either end.
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(stripOf(tester).currentTab, RaSubTab.awards);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(stripOf(tester).currentTab, RaSubTab.profile);

      // Left wraps to the cabinet.
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(stripOf(tester).currentTab, RaSubTab.awards);
      expect(
        tester.state<RADashboardHubState>(
          find.byType(RADashboardHub, skipOffstage: false),
        ),
        same(hubBefore),
      );
      // Sub-tab switching is zone movement, never a layer push/pop.
      expect(GamepadNavigationManager.stackDepth, depth);

      // Flush the post-frame chain that creates the unlocks tab's 100ms
      // initial-centering timer (it starts from a post-frame callback, so it
      // may only be *created* on the next frame), then advance past the timer
      // itself — an anonymous timer dispose cannot cancel.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

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

      // Flush the post-frame chain that creates the unlocks tab's 100ms
      // initial-centering timer (it starts from a post-frame callback, so it
      // may only be *created* on the next frame), then advance past the timer
      // itself — an anonymous timer dispose cannot cancel.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
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

    await tester.tap(
      find.descendant(
        of: find.byType(RaRefreshAction),
        matching: find.text('Refresh'),
      ),
    );
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
    // Flush the post-frame chain that creates the unlocks tab's 100ms
    // initial-centering timer (it starts from a post-frame callback, so it
    // may only be *created* on the next frame), then advance past the timer
    // itself — an anonymous timer dispose cannot cancel.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('Y refreshes the active RA sub-tab without changing tabs', (
    tester,
  ) async {
    final provider = _ShellProvider();
    await pumpShell(tester, provider);
    await settleInput(tester);

    final generationBefore = provider.cacheGeneration;
    await press(tester, LogicalKeyboardKey.keyY);

    expect(provider.cacheGeneration, generationBefore + 1);
    expect(stripOf(tester).currentTab, RaSubTab.profile);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'entering the Unlocks sub-tab fetches after the dwell, and only then',
    (tester) async {
      final provider = _ShellProvider();
      await pumpShell(tester, provider);
      await settleInput(tester);

      // The dashboard's own dwell fires its five sections; the parked Unlocks
      // sub-tab fetches nothing while another sub-tab is showing.
      await tester.pump(const Duration(milliseconds: 400));
      final dashboardFetches = provider.fetchLog.length;
      expect(provider.fetchLog, isNot(contains('events-progress')));

      // Up from the top of the Unlocks content parks on the strip the same
      // way it does on the dashboard; Right steps onto Unlocks.
      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(stripOf(tester).currentTab, RaSubTab.events);
      await tester.pump(const Duration(milliseconds: 400));
      expect(provider.fetchLog, contains('events-progress'));

      // The parked dashboard kept still through all of that.
      // Events also makes sure the current AotW metadata is available for
      // its header when the dashboard fixture has not loaded it yet.
      expect(provider.fetchLog.length, dashboardFetches + 2);

      // Away and back within the staleness window: the list is fresh, so the
      // re-activation re-reads nothing (and the dashboard's own pending
      // dwell, scheduled by the brief stop-over, stays gated while parked).
      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(stripOf(tester).currentTab, RaSubTab.profile);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(stripOf(tester).currentTab, RaSubTab.events);
      await tester.pump(const Duration(milliseconds: 400));
      expect(provider.fetchLog.where((e) => e == 'events-progress').length, 1);
      expect(provider.fetchLog.length, dashboardFetches + 2);

      // Advance the fake clock past the unlocks tab's initial-centering timer
      // (an anonymous 100ms timer its scroll controller cannot cancel), so the
      // binding's timers-pending invariant is satisfied at disposal.
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'REFRESH on the Unlocks sub-tab reloads its list, not the dashboard',
    (tester) async {
      final provider = _ShellProvider();
      await pumpShell(tester, provider, header: const RaRefreshAction());
      await settleInput(tester);

      // Initial dashboard load, then step onto Unlocks and let its dwell fire.
      await tester.pump(const Duration(milliseconds: 400));
      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(stripOf(tester).currentTab, RaSubTab.events);
      await tester.pump(const Duration(milliseconds: 400));

      final fetchesBefore = provider.fetchLog.length;
      final generationBefore = provider.cacheGeneration;
      expect(provider.fetchLog.where((e) => e == 'events-progress').length, 1);

      await tester.tap(
        find.descendant(
          of: find.byType(RaRefreshAction),
          matching: find.text('Refresh'),
        ),
      );
      await tester.pump();

      expect(provider.cacheGeneration, generationBefore + 1);
      // The sub-tab on screen re-read its first page…
      expect(provider.fetchLog.where((e) => e == 'events-progress').length, 2);
      // …and the parked dashboard added nothing to the same bump.
      expect(provider.fetchLog.length, fetchesBefore + 2);

      // Advance the fake clock past the unlocks tab's initial-centering timer
      // (an anonymous 100ms timer its scroll controller cannot cancel), so the
      // binding's timers-pending invariant is satisfied at disposal.
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('the complete RA shell fits a narrow landscape viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 360);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final overflowMessages = <String>[];
    final previousErrorHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (message.contains('overflow')) overflowMessages.add(message);
    };
    addTearDown(() => FlutterError.onError = previousErrorHandler);

    await pumpShell(tester, _ShellProvider());
    await settleInput(tester);

    expect(find.byType(RaSubTabFooter), findsNothing);
    expect(find.byType(RaSubTabFooter, skipOffstage: false), findsNothing);

    // The strip remains the shared focus zone while each active sub-tab gets
    // a full paint at the handheld-class width.
    await press(tester, LogicalKeyboardKey.arrowUp);
    for (var i = 0; i < RaSubTab.values.length - 1; i++) {
      await press(tester, LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(RaSubTabFooter), findsNothing);
    }

    expect(overflowMessages, isEmpty);
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
