import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/utils/gamepad_nav.dart';
import 'package:provider/provider.dart';
import '../../providers/retro_achievements_provider.dart';
import '../../providers/file_provider.dart';
import '../../providers/sqlite_config_provider.dart';
import '../../repositories/retro_achievements_repository.dart';
import '../../widgets/confirm_action_dialog.dart';
import '../../widgets/custom_notification.dart';
import '../../responsive.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/gestures.dart';
import '../../services/game_service.dart' show GamepadNavigationManager;
import '../app_screen.dart' show AppNavigation;
import 'package:flutter_localization/flutter_localization.dart';
import 'package:neostation/l10n/app_locale.dart';
import '../../utils/login_form_selection.dart';
import '../../models/retro_achievements_dashboard_models.dart';
import '../../models/romm_rom.dart';
import '../../models/system_model.dart';
import '../../providers/romm_provider.dart';
import '../game_screen/my_games_list.dart';
import '../game_screen/game_details_card/detail_tab.dart';
import 'ra_dashboard.dart';
import 'ra_tab_strip.dart';
import 'ra_unlocks_tab.dart';
import 'ra_games_tab.dart';
import 'ra_leaderboards_tab.dart';

part 'ra_content/dashboard_host.dart';
part 'ra_content/gamepad_nav.dart';
part 'ra_content/login_form.dart';
part 'ra_content/drill_down_host.dart';

class RAContent extends StatefulWidget {
  const RAContent({super.key});

  @override
  State<RAContent> createState() => _RAContentState();
}

class _RAContentState extends State<RAContent>
    with LoginFormSelection<RAContent> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final FocusNode _usernameFocus = FocusNode();
  final FocusNode _apiKeyFocus = FocusNode();
  final ScrollController _dashboardScrollController = ScrollController();

  /// Connected dashboard: whether the cursor is parked on the header's logout
  /// button. Nothing is selected at rest — Right parks on it, and Left steps
  /// back along the axis onto the week card.
  bool _logoutSelected = false;

  /// The dashboard's one actionable content card. It is selectable when the
  /// weekly game is local or has a matched RomM download.
  bool _weekCardSelected = false;
  final GlobalKey<RADashboardHubState> _dashboardKey =
      GlobalKey<RADashboardHubState>();

  /// The see-all Unlocks sub-tab, addressed by the input handlers the same
  /// way the dashboard is.
  final GlobalKey<RaUnlocksTabState> _unlocksKey =
      GlobalKey<RaUnlocksTabState>();

  /// The see-all Games sub-tab, same treatment.
  final GlobalKey<RaGamesTabState> _gamesKey = GlobalKey<RaGamesTabState>();
  final GlobalKey<RaLeaderboardsTabState> _leaderboardsKey =
      GlobalKey<RaLeaderboardsTabState>();

  /// Set while a row's drill-down (local resolve → RomM → notice) is between
  /// presses, so a double-tap can't start two downloads or push two routes.
  bool _gameActivationInFlight = false;

  /// Set while a selection is scrolling the header back into view, so the
  /// scroll listener doesn't read that movement as the user leaving the
  /// selection it just made.
  bool _scrollingToHeader = false;

  /// Matches the ScreenScraper login's password field, which the RA card sits
  /// next to: an API key is as worth hiding as a password, and as easy to
  /// mistype without being able to check it.
  bool _obscureApiKey = true;
  GamepadNavigation? _gamepadNav;

  /// Which sub-tab mini-app is open.
  RaSubTab _activeSubTab = RaSubTab.dashboard;

  /// Whether the D-pad cursor is parked on the sub-tab strip rather than in
  /// the active sub-tab's content. The strip is a *zone* of this tab's one
  /// `ra_content` gamepad layer — switching between zones (or sub-tabs) never
  /// pushes or pops a layer.
  bool _stripFocused = false;

  /// Bridges [State.setState] for the part-file extensions: `setState` is
  /// `@protected` and can't be invoked from an extension, but this public
  /// method can.
  void rebuild(VoidCallback fn) => setState(fn);

  @override
  List<FocusNode?> get selectionSlots => [
    _usernameFocus,
    _apiKeyFocus,
    null,
    null,
  ];

  @override
  void initState() {
    super.initState();
    attachFocusSelectionListeners();
    _dashboardScrollController.addListener(_releaseSelectionOnScroll);
    _initControllerNavigation();
    _prefillUsername();
  }

  @override
  void dispose() {
    GamepadNavigationManager.popLayer('ra_content');
    _gamepadNav?.dispose();
    detachFocusSelectionListeners();
    _usernameController.dispose();
    _apiKeyController.dispose();
    _usernameFocus.dispose();
    _apiKeyFocus.dispose();
    _dashboardScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RetroAchievementsProvider>(
      builder: (context, raProvider, child) {
        return Responsive(
          handheldXS: _buildLandscapeLayout(context, raProvider),
          handheldSmall: _buildLandscapeLayout(context, raProvider),
          handheldMedium: _buildLandscapeLayout(context, raProvider),
          handheldLarge: _buildLandscapeLayout(context, raProvider),
          handheldXL: _buildLandscapeLayout(context, raProvider),
        );
      },
    );
  }

  Widget _buildLandscapeLayout(
    BuildContext context,
    RetroAchievementsProvider raProvider,
  ) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 64.r), // Space for header (32.r + margin)
          // Main content
          if (!raProvider.isConnected) ...[
            Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.r),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        constraints: BoxConstraints(maxWidth: 260.r),
                        child: _buildLandscapeConnectionForm(
                          context,
                          raProvider,
                        ),
                      ),
                      SizedBox(width: 16.r),
                      SizedBox(width: 300.r, child: _buildInfoBox(context)),
                    ],
                  ),
                ),
              ),
            ),
          ] else ...[
            if (raProvider.isOffline) _buildOfflineBanner(context),
            // The sub-tab strip: always on screen above the content, so
            // parking the D-pad on it can never highlight something the user
            // has scrolled out of view (the trap the dashboard's header
            // selection needed [_releaseSelectionOnScroll] for).
            RaTabStrip(
              currentTab: _activeSubTab,
              focused: _stripFocused,
              onTabChanged: _onSubTabTapped,
            ),
            SizedBox(height: 8.r),
            // IndexedStack so a sub-tab keeps its state — cursor, scroll
            // position — while another one is open. Children sit in RaSubTab
            // order, matching the strip.
            Expanded(
              child: IndexedStack(
                index: RaSubTab.values.indexOf(_activeSubTab),
                children: [
                  RepaintBoundary(
                    child: RADashboardHub(
                      key: _dashboardKey,
                      scrollController: _dashboardScrollController,
                      logoutSelected: _logoutSelected,
                      weekCardSelected: _weekCardSelected,
                      onDisconnectRequested: _requestDisconnect,
                      onOwnedWeekGameSelected: _openOwnedWeekGame,
                      onBack: _handleBack,
                      onSelect: _selectCurrent,
                      active: _activeSubTab == RaSubTab.dashboard,
                    ),
                  ),
                  RepaintBoundary(
                    child: RaUnlocksTab(
                      key: _unlocksKey,
                      active: _activeSubTab == RaSubTab.unlocks,
                      onActivate: _activateUnlock,
                      onBack: _handleBack,
                      onSelect: _selectCurrent,
                    ),
                  ),
                  RepaintBoundary(
                    child: RaGamesTab(
                      key: _gamesKey,
                      active: _activeSubTab == RaSubTab.games,
                      onActivate: _activateGame,
                      onBack: _handleBack,
                      onSelect: _selectCurrent,
                    ),
                  ),
                  RepaintBoundary(
                    child: RaLeaderboardsTab(
                      key: _leaderboardsKey,
                      active: _activeSubTab == RaSubTab.leaderboards,
                      onActivate: _activateGame,
                      onBack: _handleBack,
                      onSelect: _selectCurrent,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
