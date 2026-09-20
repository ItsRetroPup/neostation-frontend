import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/retro_achievements_dashboard_models.dart';
import 'package:neostation/models/retro_achievements_leaderboard.dart';
import 'package:neostation/models/retro_achievements_user.dart';
import 'package:neostation/providers/retro_achievements_provider.dart';
import 'package:neostation/screens/retro_achievements_screen/ra_leaderboards_tab.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _LeaderboardsProvider extends RetroAchievementsProvider {
  final List<RaTopTenUser> users;
  final List<RaGamesListItem> games;

  _LeaderboardsProvider({required this.users, required this.games});

  @override
  bool get isConnected => true;

  @override
  bool get summaryLoaded => true;

  @override
  bool get topTenUsersLoaded => true;

  @override
  bool get topTenUsersLoading => false;

  @override
  List<RaTopTenUser> get topTenUsers => users;

  @override
  String? get topTenUsersError => null;

  @override
  bool get gamesListLoaded => true;

  @override
  bool get gamesListIsStale => false;

  @override
  bool get gamesListLoading => false;

  @override
  bool get gamesListHasMore => false;

  @override
  List<RaGamesListItem> get gamesListItems => games;

  @override
  String? get gamesListError => null;

  @override
  RetroAchievementsUser? get user => RetroAchievementsUser(
    user: 'Player',
    ulid: '01PLAYER',
    userPic: '',
    memberSince: '',
    richPresenceMsg: '',
    lastGameId: 0,
    contribCount: 0,
    contribYield: 0,
    totalPoints: 1234,
    totalCasualPoints: 0,
    totalTruePoints: 0,
    permissions: 0,
    untracked: 0,
    id: 1,
    userWallActive: false,
    motto: '',
  );

  @override
  Future<bool> loadUserSummary() async => true;

  @override
  Future<bool> loadTopTenUsers() async => true;

  @override
  Future<bool> loadGamesPage({bool reset = false}) async => true;
}

RaGamesListItem _game() => RaGamesListItem(
  gameId: 42,
  title: 'Leaderboard Game',
  consoleId: 1,
  consoleName: 'NES',
  imageIcon: '',
  imageBoxArt: '',
  maxPossible: 20,
  numAwarded: 5,
  numAwardedHardcore: 4,
  highestAwardKind: null,
  lastPlayed: DateTime.utc(2026, 9, 1),
  mostRecentAwardedDate: null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    SfxService().setEnabled(false);
    await FlutterLocalization.instance.ensureInitialized();
    FlutterLocalization.instance.init(
      mapLocales: [MapLocale('en', AppLocale.en)],
      initLanguageCode: 'en',
    );
  });

  testWidgets('shows standing, top ten, and own games', (tester) async {
    final provider = _LeaderboardsProvider(
      users: const [
        RaTopTenUser(
          username: 'TopPlayer',
          totalPoints: 999,
          totalRatioPoints: 1000,
          ulid: '01TOP',
        ),
      ],
      games: [_game()],
    );
    RaGamesListItem? selected;

    await tester.pumpWidget(
      ChangeNotifierProvider<RetroAchievementsProvider>.value(
        value: provider,
        child: ScreenUtilInit(
          designSize: const Size(1280, 720),
          builder: (context, _) => MaterialApp(
            localizationsDelegates:
                FlutterLocalization.instance.localizationsDelegates,
            supportedLocales: FlutterLocalization.instance.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                height: 620,
                child: RaLeaderboardsTab(
                  active: true,
                  onActivate: (game) => selected = game,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('My standing'), findsOneWidget);
    expect(find.text('TopPlayer'), findsOneWidget);
    expect(find.text('Your games\' leaderboards'), findsOneWidget);
    expect(find.text('Leaderboard Game'), findsOneWidget);

    await tester.tap(find.text('Leaderboard Game'));
    expect(selected?.gameId, 42);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
  });
}
