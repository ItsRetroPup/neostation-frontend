import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_locale.dart';
import '../../models/retro_achievements_dashboard_models.dart';
import '../../models/retro_achievements_gotw.dart';
import '../../models/retro_achievements_user_awards.dart';
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
  final VoidCallback onDisconnectRequested;
  final ValueChanged<OwnedWeekGameResolution> onOwnedWeekGameSelected;

  const RADashboardHub({
    super.key,
    this.scrollController,
    required this.logoutSelected,
    required this.weekCardSelected,
    required this.onDisconnectRequested,
    required this.onOwnedWeekGameSelected,
  });

  @override
  State<RADashboardHub> createState() => RADashboardHubState();
}

class RADashboardHubState extends State<RADashboardHub> {
  bool _requestedInitialLoad = false;

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
  RommDownload? _weekDownload;
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
    final remote = _rommWeekGame;
    if (remote != null) _downloadWeekGame(remote, raProvider);
  }

  bool get weekCardSelectable =>
      context.read<RetroAchievementsProvider>().ownedWeekGame != null ||
      _rommWeekGame != null;

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
    // Entering the tab re-reads anything past its staleness window, which is
    // what stands in for a refresh control: leaving and coming back is the
    // gesture. Without it the dashboard was a once-per-app-session snapshot —
    // a section that failed, an unlock earned on another device, or the
    // offline banner from a launch with no network, all stuck until restart.
    if (!_requestedInitialLoad &&
        provider.isConnected &&
        (!provider.dashboardLoaded || provider.dashboardIsStale) &&
        !provider.isDashboardLoading) {
      _requestedInitialLoad = true;
      _dashboardLoadTimer?.cancel();
      _dashboardLoadTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted) _loadDashboard(provider);
      });
    }
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

        return SingleChildScrollView(
          controller: widget.scrollController,
          padding: EdgeInsets.only(bottom: 16.r),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context, raProvider),
              SizedBox(height: 12.r),
              LayoutBuilder(
                builder: (context, constraints) {
                  // constraints.maxWidth is already in logical pixels (the same
                  // space .r resolves to), so the breakpoint is a raw value — a
                  // .r here double-scales it and forces stacked mode on wide
                  // landscape screens, wasting the right half of every card.
                  final twoColumn = constraints.maxWidth >= 720;
                  final weekCard = _buildWeekCard(context, raProvider);
                  final unlocksCard = _buildRecentUnlocksCard(
                    context,
                    raProvider,
                  );
                  final masteriesCard = _buildRecentMasteriesSection(
                    context,
                    raProvider,
                  );
                  final playedCard = _buildRecentlyPlayedSection(
                    context,
                    raProvider,
                  );

                  if (!twoColumn) {
                    return Column(
                      children: [
                        weekCard,
                        SizedBox(height: 12.r),
                        unlocksCard,
                        SizedBox(height: 12.r),
                        masteriesCard,
                        SizedBox(height: 12.r),
                        playedCard,
                      ],
                    );
                  }
                  // Split the two long lists (Recent Unlocks / Recently Played)
                  // across columns and pair each with a shorter card, so neither
                  // column runs far longer than the other and leaves a tall gap.
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            weekCard,
                            SizedBox(height: 12.r),
                            playedCard,
                          ],
                        ),
                      ),
                      SizedBox(width: 12.r),
                      Expanded(
                        child: Column(
                          children: [
                            unlocksCard,
                            SizedBox(height: 12.r),
                            masteriesCard,
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
