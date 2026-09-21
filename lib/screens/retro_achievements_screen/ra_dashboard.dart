import '../../widgets/ra_earned_badge.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_locale.dart';
import '../../models/retro_achievements_dashboard_models.dart';
import '../../models/retro_achievements_gotw.dart';
import '../../models/romm_rom.dart';
import '../../providers/file_provider.dart';
import '../../providers/retro_achievements_provider.dart';
import '../../providers/romm_provider.dart';
import '../../providers/sqlite_config_provider.dart';
import '../../widgets/custom_notification.dart';

part 'ra_dashboard/data_loading.dart';
part 'ra_dashboard/profile_header.dart';
part 'ra_dashboard/section_lists.dart';
part 'ra_dashboard/shared_helpers.dart';
part 'ra_dashboard/week_card.dart';

class RADashboardHub extends StatefulWidget {
  final ScrollController? scrollController;
  final bool logoutSelected;
  final bool weekCardSelected;
  final bool eventsSelected;
  final bool recentUnlocksSelected;
  final bool gamesSelected;
  final bool awardsSelected;
  final bool recentUnlocksPreviewSelected;
  final bool gamesPreviewSelected;
  final GlobalKey? aotwFocusKey;
  final GlobalKey? recentUnlocksFocusKey;
  final GlobalKey? gamesPreviewFocusKey;
  final VoidCallback onDisconnectRequested;
  final ValueChanged<OwnedWeekGameResolution> onOwnedWeekGameSelected;
  final ValueChanged<RetroAchievementRecentUnlockItem>? onUnlockSelected;
  final void Function(int gameId, String title)? onGameSelected;
  final VoidCallback? onOpenUnlocks;
  final VoidCallback? onOpenGames;
  final VoidCallback? onOpenEvents;
  final VoidCallback? onOpenAwards;
  final VoidCallback? onOpenRomm;
  final VoidCallback? onBack;
  final VoidCallback? onSelect;

  /// Whether the dashboard is currently visible. Dedicated collection pages
  /// mount separately, so this flag gates dashboard refresh work.
  final bool active;

  const RADashboardHub({
    super.key,
    this.scrollController,
    required this.logoutSelected,
    required this.weekCardSelected,
    this.eventsSelected = false,
    this.recentUnlocksSelected = false,
    this.gamesSelected = false,
    this.awardsSelected = false,
    this.recentUnlocksPreviewSelected = false,
    this.gamesPreviewSelected = false,
    this.aotwFocusKey,
    this.recentUnlocksFocusKey,
    this.gamesPreviewFocusKey,
    required this.onDisconnectRequested,
    required this.onOwnedWeekGameSelected,
    this.onUnlockSelected,
    this.onGameSelected,
    this.onOpenUnlocks,
    this.onOpenGames,
    this.onOpenEvents,
    this.onOpenAwards,
    this.onOpenRomm,
    this.onBack,
    this.onSelect,
    this.active = true,
  });

  @override
  State<RADashboardHub> createState() => RADashboardHubState();
}

class RADashboardHubState extends State<RADashboardHub> {
  /// Timer used to avoid starting heavy dashboard network loads when the user
  /// is just quickly passing through this tab.
  Timer? _dashboardLoadTimer;

  /// The provider this hub is subscribed to, and the invalidation generation
  /// it has already acted on. Watching the generation is what makes a refresh
  /// work while the hub is mounted: [didChangeDependencies] runs once, so a
  /// finished game session (or the refresh button) would otherwise drop the
  /// loaded flags with nothing left to notice.
  RetroAchievementsProvider? _provider;
  int _seenCacheGeneration = 0;
  String? _rommLookupKey;
  RommRom? _rommWeekGame;
  bool _rommWeekGameLoading = false;
  bool _rommWeekGameLookupFailed = false;
  bool _forceRommWeekLookup = false;
  RommDownload? _weekDownload;
  bool _weekDownloadIndexing = false;
  int _seenRommLibraryRevision = 0;

  /// Bridges [State.setState] for the part-file extensions: `setState` is
  /// `@protected` and can't be invoked from an extension, but this public
  /// method can.
  void rebuild(VoidCallback fn) => setState(fn);

  /// Invoked by the parent gamepad navigator when the AOTW card has focus.
  /// A local game opens its library entry; a matched RomM game downloads.
  void selectWeekCard() {
    final raProvider = context.read<RetroAchievementsProvider>();
    final owned = raProvider.ownedWeekGame;
    if (owned != null) {
      widget.onOwnedWeekGameSelected(owned);
      return;
    }
    if (_weekDownloadIndexing) return;
    final remote = _rommWeekGame;
    if (remote != null) {
      _downloadWeekGame(remote, raProvider);
    } else if (!context.read<RommProvider>().isConnected) {
      widget.onOpenRomm?.call();
    }
  }

  bool get weekCardSelectable =>
      context.read<RetroAchievementsProvider>().gotw != null;

  bool get gamesSelectable =>
      context.read<RetroAchievementsProvider>().recentlyPlayedGames.isNotEmpty;

  void selectRecentUnlockPreview() {
    widget.onOpenUnlocks?.call();
  }

  void selectGamesPreview() {
    widget.onOpenGames?.call();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<RetroAchievementsProvider>();
    if (!identical(provider, _provider)) {
      _provider?.removeListener(_onProviderChanged);
      _provider = provider;
      _seenCacheGeneration = provider.cacheGeneration;
      provider.addListener(_onProviderChanged);
    }
    _resolveRommWeekGame(provider);
    _maybeScheduleInitialLoad(provider);
  }

  @override
  void didUpdateWidget(RADashboardHub oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Route changes can leave this hub mounted, so visibility changes arrive
    // here rather than through dependency changes.
    if (widget.active && !oldWidget.active) {
      _maybeScheduleInitialLoad(
        _provider ?? context.read<RetroAchievementsProvider>(),
      );
    }
  }

  /// Re-reads anything past its staleness window when the dashboard becomes
  /// visible. This keeps cached sections fresh after returning from a
  /// dedicated collection page.
  ///
  /// Re-checked on every activation rather than once per mount so a dedicated
  /// page can be visited and dismissed without making the dashboard stale.
  void _maybeScheduleInitialLoad(RetroAchievementsProvider provider) {
    if (!widget.active || !provider.isConnected) return;
    if (provider.isDashboardLoading) return;
    if (provider.dashboardLoaded && !provider.dashboardIsStale) return;
    _dashboardLoadTimer?.cancel();
    _dashboardLoadTimer = Timer(const Duration(milliseconds: 300), () {
      // A route change while the dwell is still running must not let a hidden
      // dashboard fire its load off-stage; the next activation retries it.
      if (mounted && widget.active) _loadDashboard(provider);
    });
  }

  @override
  void dispose() {
    _dashboardLoadTimer?.cancel();
    _provider?.removeListener(_onProviderChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RetroAchievementsProvider>(
      builder: (context, raProvider, child) {
        final user = raProvider.user;
        if (user == null) return const SizedBox.shrink();

        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                controller: widget.scrollController,
                padding: EdgeInsets.only(bottom: 16.r),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context, raProvider),
                    SizedBox(height: 8.r),
                    _buildDestinationRail(context),
                    SizedBox(height: 8.r),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        // constraints.maxWidth is already in logical pixels (the same
                        // space .r resolves to), so the breakpoint is a raw value — a
                        // .r here double-scales it and forces stacked mode on wide
                        // landscape screens, wasting the right half of every card.
                        final twoColumn = constraints.maxWidth >= 720;
                        final weekCard = KeyedSubtree(
                          key: widget.aotwFocusKey,
                          child: _buildWeekCard(context, raProvider),
                        );
                        final unlocksCard = KeyedSubtree(
                          key: widget.recentUnlocksFocusKey,
                          child: _buildRecentUnlocksCard(context, raProvider),
                        );
                        final playedCard = KeyedSubtree(
                          key: widget.gamesPreviewFocusKey,
                          child: _buildRecentlyPlayedSection(
                            context,
                            raProvider,
                          ),
                        );

                        if (!twoColumn) {
                          return Column(
                            children: [
                              weekCard,
                              SizedBox(height: 12.r),
                              unlocksCard,
                              SizedBox(height: 12.r),
                              playedCard,
                            ],
                          );
                        }
                        return Column(
                          children: [
                            weekCard,
                            SizedBox(height: 12.r),
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(child: unlocksCard),
                                  SizedBox(width: 12.r),
                                  Expanded(child: playedCard),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
