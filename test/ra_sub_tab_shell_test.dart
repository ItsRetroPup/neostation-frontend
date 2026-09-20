import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/database_game_model.dart';
import 'package:neostation/models/retro_achievements_dashboard_models.dart';
import 'package:neostation/models/retro_achievements_user.dart';
import 'package:neostation/models/romm_rom.dart';
import 'package:neostation/providers/file_provider.dart';
import 'package:neostation/providers/retro_achievements_provider.dart';
import 'package:neostation/providers/romm_provider.dart';
import 'package:neostation/providers/sqlite_config_provider.dart';
import 'package:neostation/screens/retro_achievements_screen/ra_content.dart';
import 'package:neostation/screens/retro_achievements_screen/ra_dashboard.dart';
import 'package:neostation/screens/retro_achievements_screen/ra_tab_strip.dart';
import 'package:neostation/screens/retro_achievements_screen/ra_unlocks_tab.dart';
import 'package:neostation/services/gamepad/gamepad_navigation_manager.dart';
import 'package:neostation/services/global_notification_service.dart';
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
  _ShellProvider({
    bool connected = true,
    List<RetroAchievementRecentUnlockItem> unlocksItems = const [],
  }) : _connected = connected,
       _unlocksItems = unlocksItems;

  final bool _connected;

  /// See-all rows for the Unlocks sub-tab. Empty by default so every other
  /// shell test sees exactly the pre-tab behaviour.
  final List<RetroAchievementRecentUnlockItem> _unlocksItems;
  final List<String> fetchLog = [];
  bool _dashboardLoading = false;

  /// Test seam for the shell's local-library resolution — the drill-down's
  /// first branch. Every ask is recorded, and the answer comes from the
  /// callback (null when unset, matching "not in the library").
  Future<OwnedWeekGameResolution?> Function(int raGameId)? resolveLocal;
  final List<int> resolvedGameIds = [];

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

  @override
  List<RetroAchievementRecentUnlockItem> get unlocksListItems => _unlocksItems;

  @override
  Future<OwnedWeekGameResolution?> resolveLocalGameForRaId(int raGameId) async {
    resolvedGameIds.add(raGameId);
    final handler = resolveLocal;
    if (handler == null) return null;
    return handler(raGameId);
  }

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

/// RomM stub for the Unlocks drill-down tests: records every lookup it was
/// asked for and answers from fields, so the branches never touch a server.
/// A download's tracker comes back already completed and pre-indexed —
/// standing in for the library scan that lands the file in the local
/// database, which is what the drill-down waits on after the transfer.
class _RommStub extends RommProvider {
  _RommStub({this.remoteRom});

  final RommRom? remoteRom;
  final List<String> log = [];

  @override
  bool get isConnected => true;

  @override
  Future<RommRom?> findRomByRaGameId(int gameId, String gameTitle) async {
    log.add('find:$gameId:$gameTitle');
    return remoteRom;
  }

  @override
  RommDownload? downloadFor(int romId) => null;

  @override
  Future<RommDownload> downloadRom(
    RommRom rom, {
    required List<String> romFolders,
    FileProvider? fileProvider,
  }) async {
    log.add('download:${rom.id}');
    final tracker = RommDownload(romId: rom.id)
      ..status = RommDownloadStatus.completed;
    tracker.markIndexed();
    return tracker;
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

  setUp(() {
    // The drill-down asserts read the global notification center — a plain
    // singleton — so it resets between tests like any other shared service.
    GlobalNotificationService().notifier.value = [];
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

  testWidgets('signed in: the strip renders the Dashboard and Unlocks pills', (
    tester,
  ) async {
    await pumpShell(tester, _ShellProvider());

    expect(find.byType(RaTabStrip), findsOneWidget);
    expect(find.byType(RADashboardHub), findsOneWidget);
    // The IndexedStack hosts both sub-tabs from the start; only the dashboard
    // is showing, and the unlocks tab waits off-stage at its dwell gate.
    // (skipOffstage: IndexedStack parks non-showing children in an Offstage
    // wrapper, which the default finders skip.)
    expect(find.byType(RaUnlocksTab, skipOffstage: false), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.label == 'Dashboard' &&
            w.properties.selected == true,
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.label == 'Unlocks' &&
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

      // Right steps onto Unlocks; the dashboard's State survives underneath.
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(stripOf(tester).currentTab, RaSubTab.unlocks);
      expect(stripOf(tester).focused, isTrue);

      // Right again wraps around to the Dashboard — two pills, both directions
      // live, no dead press at either end.
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(stripOf(tester).currentTab, RaSubTab.dashboard);

      // And Left wraps the other way, straight back onto Unlocks.
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(stripOf(tester).currentTab, RaSubTab.unlocks);
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
    'entering the Unlocks sub-tab fetches after the dwell, and only then',
    (tester) async {
      final provider = _ShellProvider();
      await pumpShell(tester, provider);
      await settleInput(tester);

      // The dashboard's own dwell fires its five sections; the parked Unlocks
      // sub-tab fetches nothing while another sub-tab is showing.
      await tester.pump(const Duration(milliseconds: 400));
      final dashboardFetches = provider.fetchLog.length;
      expect(provider.fetchLog, isNot(contains('unlocks-page-reset')));

      // Up from the top of the Unlocks content parks on the strip the same
      // way it does on the dashboard; Right steps onto Unlocks.
      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(stripOf(tester).currentTab, RaSubTab.unlocks);
      await tester.pump(const Duration(milliseconds: 400));
      expect(provider.fetchLog, contains('unlocks-page-reset'));

      // The parked dashboard kept still through all of that.
      expect(provider.fetchLog.length, dashboardFetches + 1);

      // Away and back within the staleness window: the list is fresh, so the
      // re-activation re-reads nothing (and the dashboard's own pending
      // dwell, scheduled by the brief stop-over, stays gated while parked).
      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(stripOf(tester).currentTab, RaSubTab.dashboard);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(stripOf(tester).currentTab, RaSubTab.unlocks);
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        provider.fetchLog.where((e) => e == 'unlocks-page-reset').length,
        1,
      );
      expect(provider.fetchLog.length, dashboardFetches + 1);

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
      expect(stripOf(tester).currentTab, RaSubTab.unlocks);
      await tester.pump(const Duration(milliseconds: 400));

      final fetchesBefore = provider.fetchLog.length;
      final generationBefore = provider.cacheGeneration;
      expect(
        provider.fetchLog.where((e) => e == 'unlocks-page-reset').length,
        1,
      );

      await tester.tap(find.text('Refresh'));
      await tester.pump();

      expect(provider.cacheGeneration, generationBefore + 1);
      // The sub-tab on screen re-read its first page…
      expect(
        provider.fetchLog.where((e) => e == 'unlocks-page-reset').length,
        2,
      );
      // …and the parked dashboard added nothing to the same bump.
      expect(provider.fetchLog.length, fetchesBefore + 1);

      // Advance the fake clock past the unlocks tab's initial-centering timer
      // (an anonymous 100ms timer its scroll controller cannot cancel), so the
      // binding's timers-pending invariant is satisfied at disposal.
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  /// Steps onto the Unlocks sub-tab, enters its content, and presses A on the
  /// first row — the full path a player takes to the drill-down. The dashboard
  /// must already have had its dwell fired (a `pump(400ms)` before this).
  Future<void> pressAOnFirstUnlockRow(WidgetTester tester) async {
    await press(tester, LogicalKeyboardKey.arrowUp);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 400));
    // The select chord dispatches its tap on a 400ms timer; the sub-tab's own
    // dwell fires on the same advance.
    await press(tester, LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 450));
    // The drill-down chain is all microtasks off the tap.
    await tester.pump();
  }

  List<String> notificationMessages() =>
      GlobalNotificationService().notifier.value.map((n) => n.message).toList();

  testWidgets(
    'A on a row with a local match opens the local game without RomM',
    (tester) async {
      final provider = _ShellProvider(unlocksItems: List.generate(3, _unlock))
        ..resolveLocal = (gameId) async => OwnedWeekGameResolution(
          raGameId: gameId,
          game: DatabaseGameModel(
            filename: 'owned.nes',
            romPath: '/x/owned.nes',
          ),
        );
      final romm = _RommStub();
      await pumpShell(tester, provider, romm: romm);
      await settleInput(tester);
      await tester.pump(const Duration(milliseconds: 400));
      await pressAOnFirstUnlockRow(tester);

      // The local library answered, so RomM was never consulted… (the row
      // fixtures use their index as the gameId: the cursor is on row 0.)
      expect(provider.resolvedGameIds, [0]);
      expect(romm.log, isEmpty);
      // …and the open path ran as far as its system resolution: the fixture's
      // game carries no system folder, and the mismatch is reported rather
      // than pushed — the push itself is production-tested, never pumped.
      expect(notificationMessages(), [
        'Could not resolve the local system for this game',
      ]);

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

  testWidgets('A on a row RomM has downloads it, then opens it once indexed', (
    tester,
  ) async {
    var resolves = 0;
    final provider = _ShellProvider(unlocksItems: List.generate(3, _unlock))
      ..resolveLocal = (gameId) async {
        resolves++;
        // First ask: not owned locally. After the transfer lands and
        // indexing completes, the re-resolve finds it in the library.
        return resolves == 1
            ? null
            : OwnedWeekGameResolution(
                raGameId: gameId,
                game: DatabaseGameModel(
                  filename: 'indexed.nes',
                  romPath: '/x/indexed.nes',
                ),
              );
      };
    final romm = _RommStub(
      remoteRom: RommRom(
        id: 7,
        name: 'Remote game',
        platformId: 1,
        platformSlug: 'nes',
        fsName: 'remote.nes',
        fsNameNoExt: 'remote',
        fsExtension: '.nes',
      ),
    );
    await pumpShell(tester, provider, romm: romm);
    await settleInput(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await pressAOnFirstUnlockRow(tester);

    // Not local, found on RomM, downloaded; the pre-indexed tracker stands
    // in for the library scan, so the same press re-resolves and carries
    // on into the open path. (Row fixtures use their index as the gameId.)
    expect(romm.log, ['find:0:Game 0', 'download:7']);
    expect(resolves, 2);
    expect(notificationMessages(), [
      'Download complete',
      'Could not resolve the local system for this game',
    ]);

    // Flush the post-frame chain that creates the unlocks tab's 100ms
    // initial-centering timer (it starts from a post-frame callback, so it
    // may only be *created* on the next frame), then advance past the timer
    // itself — an anonymous timer dispose cannot cancel.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets("A on a row nobody owns says so instead of doing nothing", (
    tester,
  ) async {
    final provider = _ShellProvider(unlocksItems: List.generate(3, _unlock))
      ..resolveLocal = (_) async => null;
    final romm = _RommStub();
    await pumpShell(tester, provider, romm: romm);
    await settleInput(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await pressAOnFirstUnlockRow(tester);

    expect(romm.log, ['find:0:Game 0']);
    expect(notificationMessages(), ["This game isn't in your library or RomM"]);

    // Flush the post-frame chain that creates the unlocks tab's 100ms
    // initial-centering timer (it starts from a post-frame callback, so it
    // may only be *created* on the next frame), then advance past the timer
    // itself — an anonymous timer dispose cannot cancel.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
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
