import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/retro_achievements_dashboard_models.dart';
import 'package:neostation/models/retro_achievements_leaderboard.dart';
import 'package:neostation/providers/retro_achievements_provider.dart';
import 'package:neostation/utils/centered_scroll_controller.dart';
import 'package:provider/provider.dart';

import '../../widgets/ra_subtab_footer.dart';

/// The RA mini-app's leaderboards sub-tab: the signed-in user's standing, the
/// site's top-ten feed, and games from the user's own activity that can open
/// the per-game leaderboard view in the game details card.
class RaLeaderboardsTab extends StatefulWidget {
  final bool active;
  final ValueChanged<RaGamesListItem> onActivate;
  final VoidCallback? onBack;
  final VoidCallback? onSelect;

  const RaLeaderboardsTab({
    super.key,
    required this.active,
    required this.onActivate,
    this.onBack,
    this.onSelect,
  });

  @override
  State<RaLeaderboardsTab> createState() => RaLeaderboardsTabState();
}

class RaLeaderboardsTabState extends State<RaLeaderboardsTab> {
  final CenteredScrollController _scrollController = CenteredScrollController(
    centerPosition: 0.5,
  );
  RetroAchievementsProvider? _provider;
  Timer? _loadTimer;
  int _seenCacheGeneration = 0;
  int _selectedIndex = 0;

  double get _rowExtent => 54.r;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scrollController.initialize(
          context: context,
          initialIndex: 0,
          totalItems: 0,
        );
      }
    });
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
    if (widget.active) _scheduleLoad(provider);
  }

  @override
  void didUpdateWidget(RaLeaderboardsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _scheduleLoad(_provider ?? context.read<RetroAchievementsProvider>());
    }
  }

  @override
  void dispose() {
    _loadTimer?.cancel();
    _provider?.removeListener(_onProviderChanged);
    _scrollController.dispose();
    super.dispose();
  }

  /// Moves through selectable top-ten and own-game rows. The standing card and
  /// the section label are informational, so they do not consume cursor steps.
  bool moveSelection(int delta) {
    final provider = context.read<RetroAchievementsProvider>();
    final rowCount = _selectableRowCount(provider);
    if (rowCount == 0) return false;
    final current = _selectedIndex.clamp(0, rowCount - 1);
    final target = current + delta;
    if (target < 0) return false;
    if (target >= rowCount) {
      if (provider.gamesListHasMore && !provider.gamesListLoading) {
        unawaited(provider.loadGamesPage());
        return true;
      }
      return false;
    }
    _selectedIndex = target;
    _scrollToSelected(provider);
    setState(() {});
    if (target >= rowCount - 6 &&
        provider.gamesListHasMore &&
        !provider.gamesListLoading) {
      unawaited(provider.loadGamesPage());
    }
    return true;
  }

  void activateCurrent() {
    final provider = context.read<RetroAchievementsProvider>();
    final games = provider.gamesListItems;
    final topCount = provider.topTenUsers.length;
    final gameIndex = _selectedIndex - topCount;
    if (gameIndex < 0 || gameIndex >= games.length) return;
    widget.onActivate(games[gameIndex]);
  }

  int _selectableRowCount(RetroAchievementsProvider provider) =>
      provider.topTenUsers.length + provider.gamesListItems.length;

  void _scrollToSelected(RetroAchievementsProvider provider) {
    final topCount = provider.topTenUsers.length;
    final visualIndex = _selectedIndex >= topCount
        ? _selectedIndex + 1
        : _selectedIndex;
    _scrollController.updateSelectedIndex(visualIndex);
    _scrollController.scrollToIndex(visualIndex);
  }

  void _scheduleLoad(RetroAchievementsProvider provider) {
    _loadTimer?.cancel();
    _loadTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted && widget.active) unawaited(_load(provider));
    });
  }

  Future<void> _load(RetroAchievementsProvider provider) async {
    if (!widget.active) return;
    // Keep the three reads sequential: top-ten is a small feed, while the
    // user's games are two paginated endpoints and can otherwise trigger a
    // burst of requests on a rate-limited key.
    if (!provider.summaryLoaded) await provider.loadUserSummary();
    if (!mounted || !widget.active) return;
    if (!provider.topTenUsersLoaded) await provider.loadTopTenUsers();
    if (!mounted || !widget.active) return;
    if (!provider.gamesListLoaded || provider.gamesListIsStale) {
      _selectedIndex = 0;
      await provider.loadGamesPage(reset: true);
    }
  }

  void _onProviderChanged() {
    final provider = _provider;
    if (provider == null || !mounted) return;
    if (provider.cacheGeneration == _seenCacheGeneration) return;
    _seenCacheGeneration = provider.cacheGeneration;
    if (widget.active) {
      _scheduleLoad(provider);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TickerMode(
      enabled: widget.active,
      child: Consumer<RetroAchievementsProvider>(
        builder: (context, provider, child) {
          final topTen = provider.topTenUsers;
          final games = provider.gamesListItems;
          final visualCount = topTen.length + games.length + 1;
          _scrollController.updateTotalItems(visualCount);
          _scrollController.setItemExtent(_rowExtent);
          final rowCount = topTen.length + games.length;
          _selectedIndex = rowCount == 0
              ? 0
              : _selectedIndex.clamp(0, rowCount - 1);
          final theme = Theme.of(context);

          return Column(
            children: [
              Expanded(
                child: Container(
                  decoration: _cardDecoration(theme),
                  padding: EdgeInsets.all(14.r),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(context),
                      SizedBox(height: 10.r),
                      _buildStandingCard(context, provider),
                      SizedBox(height: 12.r),
                      Expanded(
                        child: rowCount == 0
                            ? _buildEmptyOrError(context, provider)
                            : _buildRows(context, provider, topTen, games),
                      ),
                    ],
                  ),
                ),
              ),
              RaSubTabFooter(
                label: _footerLabel(context, topTen, games),
                onRefresh: () => provider.invalidateCachedReads(),
                onBack: widget.onBack,
                onSelect: widget.onSelect,
              ),
            ],
          );
        },
      ),
    );
  }

  String _footerLabel(
    BuildContext context,
    List<RaTopTenUser> topTen,
    List<RaGamesListItem> games,
  ) {
    if (topTen.isEmpty && games.isEmpty) {
      return AppLocale.raSubtabLeaderboards.getString(context);
    }
    if (_selectedIndex < topTen.length) {
      return topTen[_selectedIndex].username;
    }
    final gameIndex = _selectedIndex - topTen.length;
    if (gameIndex >= 0 && gameIndex < games.length) {
      return games[gameIndex].title;
    }
    return AppLocale.raSubtabLeaderboards.getString(context);
  }

  BoxDecoration _cardDecoration(ThemeData theme) {
    return BoxDecoration(
      color: theme.cardColor.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(12.r),
      border: Border.all(
        color: theme.colorScheme.primary.withValues(alpha: 0.15),
        width: 1.r,
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          Symbols.leaderboard_rounded,
          size: 18.r,
          color: theme.colorScheme.primary,
        ),
        SizedBox(width: 8.r),
        Expanded(
          child: Text(
            AppLocale.raSubtabLeaderboards.getString(context),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
              fontSize: 11.r,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStandingCard(
    BuildContext context,
    RetroAchievementsProvider provider,
  ) {
    final theme = Theme.of(context);
    final user = provider.user;
    final summary = provider.userSummary;
    final rank = summary?.rank ?? 0;
    final typeKey = user?.isCasual == true
        ? AppLocale.raCasual
        : AppLocale.raHardcore;
    final type = AppLocale.raUserType
        .getString(context)
        .replaceFirst('{type}', typeKey.getString(context));

    return Container(
      padding: EdgeInsets.all(10.r),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Symbols.person_celebrate_rounded,
            size: 24.r,
            color: theme.colorScheme.primary,
          ),
          SizedBox(width: 10.r),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocale.raStanding.getString(context),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 11.r,
                  ),
                ),
                SizedBox(height: 3.r),
                Text(
                  AppLocale.raYourRank
                      .getString(context)
                      .replaceFirst('{rank}', rank > 0 ? '$rank' : '—'),
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 9.r),
                ),
                Text(
                  AppLocale.raYourPoints
                      .getString(context)
                      .replaceFirst('{points}', '${user?.totalPoints ?? 0}'),
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 9.r),
                ),
              ],
            ),
          ),
          Text(
            type,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
              fontSize: 8.r,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRows(
    BuildContext context,
    RetroAchievementsProvider provider,
    List<RaTopTenUser> topTen,
    List<RaGamesListItem> games,
  ) {
    final theme = Theme.of(context);
    final topCount = topTen.length;
    final itemCount = topTen.length + 1 + games.length;
    return ListView.builder(
      controller: _scrollController.scrollController,
      itemExtent: _rowExtent,
      itemCount: itemCount,
      itemBuilder: (context, visualIndex) {
        if (visualIndex < topCount) {
          final user = topTen[visualIndex];
          final selected = _selectedIndex == visualIndex;
          return _buildSelectableRow(
            context: context,
            selected: selected,
            onTap: () {
              setState(() => _selectedIndex = visualIndex);
            },
            leading: Text(
              '#${visualIndex + 1}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 10.r,
              ),
            ),
            title: user.username,
            subtitle:
                '${user.totalPoints} ${AppLocale.raPointsAbbrev.getString(context)}',
            trailing: const SizedBox.shrink(),
          );
        }
        if (visualIndex == topCount) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Text(
              AppLocale.raYourGamesLeaderboards.getString(context),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 9.r,
              ),
            ),
          );
        }
        final gameIndex = visualIndex - topCount - 1;
        final game = games[gameIndex];
        final selected = _selectedIndex == topCount + gameIndex;
        final progress = AppLocale.raAchievementProgress
            .getString(context)
            .replaceFirst('{earned}', '${game.numAwarded}')
            .replaceFirst('{total}', '${game.maxPossible}');
        return _buildSelectableRow(
          context: context,
          selected: selected,
          onTap: () {
            setState(() => _selectedIndex = topCount + gameIndex);
            widget.onActivate(game);
          },
          leading: Icon(
            Symbols.sports_esports_rounded,
            size: 18.r,
            color: theme.colorScheme.secondary,
          ),
          title: game.title,
          subtitle: '${game.consoleName} · $progress',
          trailing: Icon(
            Symbols.chevron_right_rounded,
            size: 18.r,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
          ),
        );
      },
    );
  }

  Widget _buildSelectableRow({
    required BuildContext context,
    required bool selected,
    required VoidCallback onTap,
    required Widget leading,
    required String title,
    required String subtitle,
    required Widget trailing,
  }) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10.r),
        child: Container(
          margin: EdgeInsets.symmetric(vertical: 3.r),
          padding: EdgeInsets.symmetric(horizontal: 8.r),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10.r),
            border: selected
                ? Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.5),
                  )
                : null,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 34.r,
                child: Center(child: leading),
              ),
              SizedBox(width: 8.r),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 10.r,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.62,
                        ),
                        fontSize: 8.r,
                      ),
                    ),
                  ],
                ),
              ),
              trailing,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyOrError(
    BuildContext context,
    RetroAchievementsProvider provider,
  ) {
    final theme = Theme.of(context);
    final message =
        provider.topTenUsersError ??
        provider.gamesListError ??
        (provider.topTenUsersLoading || provider.gamesListLoading
            ? null
            : AppLocale.raNoLeaderboardGames.getString(context));
    if (message == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color:
              provider.topTenUsersError != null ||
                  provider.gamesListError != null
              ? theme.colorScheme.error
              : theme.colorScheme.onSurface.withValues(alpha: 0.7),
          fontSize: 9.r,
        ),
      ),
    );
  }
}
