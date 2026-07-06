import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../models/retro_achievements_dashboard_models.dart';
import '../../models/retro_achievements_user_awards.dart';
import '../../providers/file_provider.dart';
import '../../providers/retro_achievements_provider.dart';
import '../../providers/sqlite_config_provider.dart';
import '../../screens/game_screen/my_games_list.dart';
import '../../widgets/custom_notification.dart';
import '../../models/system_model.dart';

class RADashboardHub extends StatefulWidget {
  final ScrollController? scrollController;

  const RADashboardHub({super.key, this.scrollController});

  @override
  State<RADashboardHub> createState() => _RADashboardHubState();
}

class _RADashboardHubState extends State<RADashboardHub> {
  bool _requestedInitialLoad = false;

  Future<void> _loadDashboard(
    RetroAchievementsProvider provider,
  ) async {
    await Future.wait([
      provider.fetchRecentUnlocks(),
      provider.fetchRecentlyPlayedGames(),
      provider.fetchUserAwards(),
      provider.fetchCompletionProgress(),
      provider.fetchGOTW(),
    ]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<RetroAchievementsProvider>();
    if (!_requestedInitialLoad &&
        provider.isConnected &&
        !provider.dashboardLoaded &&
        !provider.recentUnlocksLoading &&
        !provider.recentlyPlayedLoading &&
        !provider.completionProgressLoading &&
        !provider.gotwLoading) {
      _requestedInitialLoad = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadDashboard(provider);
      });
    }
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
                  final stacked = constraints.maxWidth < 820.r;
                  if (stacked) {
                    return Column(
                      children: [
                        _buildWeekCard(context, raProvider),
                        SizedBox(height: 12.r),
                        _buildRecentUnlocksCard(context, raProvider),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildWeekCard(context, raProvider)),
                      SizedBox(width: 12.r),
                      Expanded(
                        child: _buildRecentUnlocksCard(context, raProvider),
                      ),
                    ],
                  );
                },
              ),
              SizedBox(height: 12.r),
              _buildRecentMasteriesSection(context, raProvider),
              SizedBox(height: 12.r),
              _buildRecentlyPlayedSection(context, raProvider),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(
    BuildContext context,
    RetroAchievementsProvider raProvider,
  ) {
    final theme = Theme.of(context);
    final user = raProvider.user!;
    final showCompletions = user.isSoftcore;
    final trackedGames = raProvider.completionProgress?.total ?? 0;
    final highlightColor = showCompletions
        ? const Color(0xFFC0C0C0)
        : const Color(0xFFFFD700);
    final highlightCount = showCompletions
        ? (raProvider.userAwards?.completionAwardsCount ?? 0)
        : (raProvider.userAwards?.masteryAwardsCount ?? 0);
    final highlightLabel = showCompletions ? 'Completions' : 'Masteries';

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.r, vertical: 12.r),
      decoration: _cardDecoration(theme),
      child: Row(
        children: [
          Container(
            width: 48.r,
            height: 48.r,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.28),
                width: 2.r,
              ),
            ),
            child: ClipOval(
              child: user.userPic.isNotEmpty
                  ? Image.network(
                      'https://retroachievements.org${user.userPic}',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Icon(
                        Symbols.account_circle_rounded,
                        color: theme.colorScheme.primary,
                        size: 28.r,
                      ),
                    )
                  : Icon(
                      Symbols.account_circle_rounded,
                      color: theme.colorScheme.primary,
                      size: 28.r,
                    ),
            ),
          ),
          SizedBox(width: 12.r),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.user,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 14.r,
                  ),
                ),
                SizedBox(height: 4.r),
                Wrap(
                  spacing: 8.r,
                  runSpacing: 6.r,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _buildPill(
                      context,
                      icon: Symbols.shield_rounded,
                      label: user.userType,
                      color: theme.colorScheme.primary,
                    ),
                    _buildPill(
                      context,
                      icon: Symbols.stars_rounded,
                      label: '${user.totalPoints} pts',
                      color: theme.colorScheme.tertiary,
                    ),
                    _buildPill(
                      context,
                      icon: Symbols.sports_esports_rounded,
                      label: '$trackedGames games played',
                      color: theme.colorScheme.secondary,
                    ),
                    _buildPill(
                      context,
                      icon: Symbols.workspace_premium_rounded,
                      label: '$highlightCount $highlightLabel',
                      color: highlightColor,
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              raProvider.disconnect(clearSavedUser: true);
              if (!context.mounted) return;
              AppNotification.showNotification(
                context,
                'Disconnected from RetroAchievements',
                type: NotificationType.info,
              );
            },
            icon: Icon(
              Symbols.logout_rounded,
              color: theme.colorScheme.error,
              size: 20.r,
            ),
            tooltip: 'Logout',
          ),
        ],
      ),
    );
  }

  Widget _buildWeekCard(
    BuildContext context,
    RetroAchievementsProvider raProvider,
  ) {
    final theme = Theme.of(context);
    final gotw = raProvider.gotw;
    final owned = raProvider.ownedWeekGame;
    final earned = raProvider.gotwEarned;
    final accent = earned
        ? const Color(0xFFFFD700)
        : owned != null
        ? theme.colorScheme.secondary
        : theme.colorScheme.primary;

    return InkWell(
      borderRadius: BorderRadius.circular(12.r),
      onTap: owned == null ? null : () => _openOwnedWeekGame(context, owned),
      child: Container(
        padding: EdgeInsets.all(14.r),
        decoration: _cardDecoration(
          theme,
          borderColor: accent.withValues(
            alpha: earned
                ? 0.55
                : owned != null
                ? 0.35
                : 0.15,
          ),
          background: theme.cardColor.withValues(
            alpha: earned
                ? 0.40
                : owned != null
                ? 0.34
                : 0.25,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Symbols.emoji_events_rounded,
                  size: 18.r,
                  color: accent,
                ),
                SizedBox(width: 8.r),
                Expanded(
                  child: Text(
                    'Achievement of the Week',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontSize: 11.r,
                      fontWeight: FontWeight.bold,
                      color: accent,
                    ),
                  ),
                ),
                if (earned)
                  _buildPill(
                    context,
                    icon: Symbols.verified_rounded,
                    label: 'Earned',
                    color: accent,
                  )
                else if (owned != null)
                  _buildPill(
                    context,
                    icon: Symbols.check_circle_rounded,
                    label: 'Owned',
                    color: accent,
                  ),
              ],
            ),
            SizedBox(height: 12.r),
            if (raProvider.gotwLoading && gotw == null)
              _buildLoadingState(context, minHeight: 138.r)
            else if (gotw == null)
              _buildSectionMessage(
                context,
                raProvider.gotwError ?? 'Could not load Achievement of the Week',
                isError: true,
                onRetry: raProvider.fetchGOTW,
                minHeight: 138.r,
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10.r),
                    child: SizedBox(
                      width: 72.r,
                      height: 72.r,
                      child: Image.network(
                        _raMediaUrl(gotw.achievement.badgeUrl),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: theme.colorScheme.surface,
                          child: Icon(
                            Symbols.emoji_events_rounded,
                            color: accent,
                            size: 30.r,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12.r),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          gotw.game.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.r,
                          ),
                        ),
                        SizedBox(height: 4.r),
                        Text(
                          gotw.console.title,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.7,
                            ),
                            fontSize: 9.r,
                          ),
                        ),
                        SizedBox(height: 8.r),
                        Text(
                          gotw.achievement.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w700,
                            fontSize: 11.r,
                          ),
                        ),
                        SizedBox(height: 4.r),
                        Text(
                          gotw.achievement.description,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 9.r,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.78,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            if (gotw != null) ...[
              SizedBox(height: 12.r),
              Wrap(
                spacing: 8.r,
                runSpacing: 8.r,
                children: [
                  _buildPill(
                    context,
                    icon: Symbols.stars_rounded,
                    label: '${gotw.achievement.points} pts',
                    color: accent,
                  ),
                  _buildPill(
                    context,
                    icon: Symbols.groups_rounded,
                    label: '${gotw.totalPlayers} players',
                    color: theme.colorScheme.tertiary,
                  ),
                  _buildPill(
                    context,
                    icon: Symbols.trophy_rounded,
                    label: '${gotw.unlocksCount} unlocks',
                    color: theme.colorScheme.tertiary,
                  ),
                ],
              ),
              if (earned) ...[
                SizedBox(height: 10.r),
                Text(
                  'You have already earned this achievement',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 8.r,
                    color: accent.withValues(alpha: 0.92),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ] else if (owned != null) ...[
                SizedBox(height: 10.r),
                Text(
                  'Tap to open local game details',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 8.r,
                    color: accent.withValues(alpha: 0.92),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecentUnlocksCard(
    BuildContext context,
    RetroAchievementsProvider raProvider,
  ) {
    final unlocks = raProvider.recentUnlocks.take(5).toList();
    return Container(
      padding: EdgeInsets.all(14.r),
      decoration: _cardDecoration(Theme.of(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            context,
            icon: Symbols.notifications_active_rounded,
            title: 'Recent Unlocks',
            trailing: '30d',
          ),
          SizedBox(height: 12.r),
          if (raProvider.recentUnlocksLoading && unlocks.isEmpty)
            _buildLoadingState(context, minHeight: 138.r)
          else if (raProvider.recentUnlocksError != null && unlocks.isEmpty)
            _buildSectionMessage(
              context,
              raProvider.recentUnlocksError!,
              isError: true,
              onRetry: raProvider.fetchRecentUnlocks,
              minHeight: 138.r,
            )
          else if (unlocks.isEmpty)
            _buildSectionMessage(
              context,
              'No recent unlocks in the last 30 days',
              minHeight: 138.r,
            )
          else
            Column(
              children: unlocks
                  .map((item) => _buildUnlockRow(context, item))
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildRecentMasteriesSection(
    BuildContext context,
    RetroAchievementsProvider raProvider,
  ) {
    final showCompletions = raProvider.user?.isSoftcore ?? false;
    final items = (showCompletions
            ? raProvider.recentCompletions
            : raProvider.recentMasteries)
        .take(5)
        .toList();
    final subtitle = raProvider.completionProgress?.total != null
        ? '${raProvider.completionProgress!.total} tracked games'
        : null;
    return _buildListSection<UserAward>(
      context,
      title: showCompletions ? 'Recent Completions' : 'Recent Masteries',
      icon: Symbols.workspace_premium_rounded,
      loading: !raProvider.userAwardsLoaded && raProvider.isConnected,
      error: raProvider.userAwardsLoaded ? null : raProvider.error,
      emptyMessage: showCompletions ? 'No completions yet' : 'No masteries yet',
      items: items,
      subtitle: subtitle,
      onRetry: raProvider.fetchUserAwards,
      itemBuilder: (context, item) => _buildAwardRow(
        context,
        item,
        accentLabel: showCompletions ? 'Completion' : 'Mastery',
        accentLabelColor: showCompletions
            ? const Color(0xFFC0C0C0)
            : const Color(0xFFFFD700),
      ),
    );
  }

  Widget _buildRecentlyPlayedSection(
    BuildContext context,
    RetroAchievementsProvider raProvider,
  ) {
    final items = raProvider.recentlyPlayedGames.take(5).toList();
    return _buildListSection<RetroAchievementRecentlyPlayedGameItem>(
      context,
      title: 'Recently Played',
      icon: Symbols.history_rounded,
      loading: raProvider.recentlyPlayedLoading && items.isEmpty,
      error: items.isEmpty ? raProvider.recentlyPlayedError : null,
      emptyMessage: 'No recently played games',
      items: items,
      onRetry: raProvider.fetchRecentlyPlayedGames,
      itemBuilder: (context, item) => _buildRecentlyPlayedRow(context, item),
    );
  }

  Widget _buildListSection<T>(
    BuildContext context, {
    required String title,
    required IconData icon,
    required bool loading,
    required String? error,
    required String emptyMessage,
    required List<T> items,
    required Widget Function(BuildContext context, T item) itemBuilder,
    String? subtitle,
    Future<bool> Function()? onRetry,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.all(14.r),
      decoration: _cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            context,
            icon: icon,
            title: title,
            trailing: subtitle,
          ),
          SizedBox(height: 10.r),
          if (loading)
            _buildLoadingState(context, minHeight: 120.r)
          else if (error != null)
            _buildSectionMessage(
              context,
              error,
              isError: true,
              onRetry: onRetry,
              minHeight: 120.r,
            )
          else if (items.isEmpty)
            _buildSectionMessage(
              context,
              emptyMessage,
              minHeight: 120.r,
            )
          else
            Column(
              children: items
                  .map((item) => itemBuilder(context, item))
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildUnlockRow(
    BuildContext context,
    RetroAchievementRecentUnlockItem item,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: 10.r),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _networkThumb(
            _raMediaUrl(item.badgeUrl.isNotEmpty ? item.badgeUrl : '/Badge/${item.badgeName}.png'),
            icon: Symbols.emoji_events_rounded,
          ),
          SizedBox(width: 10.r),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 10.r,
                  ),
                ),
                SizedBox(height: 3.r),
                Text(
                  '${item.gameTitle} • ${item.consoleName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 8.r,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 8.r),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${item.points} pts',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 9.r,
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 3.r),
              Text(
                _formatDate(item.date),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 8.r,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecentlyPlayedRow(
    BuildContext context,
    RetroAchievementRecentlyPlayedGameItem item,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: 10.r),
      child: Row(
        children: [
          _networkThumb(_raMediaUrl(item.imageIcon), icon: Symbols.videogame_asset_rounded),
          SizedBox(width: 10.r),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 10.r,
                  ),
                ),
                SizedBox(height: 3.r),
                Text(
                  '${item.consoleName} • ${item.numAchieved}/${item.numPossibleAchievements} achievements',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 8.r,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 8.r),
          Text(
            _formatDate(item.lastPlayed),
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 8.r,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAwardRow(
    BuildContext context,
    UserAward item, {
    String? accentLabel,
    Color? accentLabelColor,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: 10.r),
      child: Row(
        children: [
          _networkThumb(_raMediaUrl(item.imageIcon), icon: Symbols.military_tech_rounded),
          SizedBox(width: 10.r),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 10.r,
                  ),
                ),
                SizedBox(height: 3.r),
                Text(
                  '${item.consoleName} • ${item.awardType}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 8.r,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
          if (accentLabel != null) ...[
            SizedBox(width: 8.r),
            _buildPill(
              context,
              icon: Symbols.workspace_premium_rounded,
              label: accentLabel,
              color: accentLabelColor ?? theme.colorScheme.primary,
            ),
          ] else ...[
            SizedBox(width: 8.r),
            Text(
              _formatDate(item.awardedAt),
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 8.r,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? trailing,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18.r, color: theme.colorScheme.primary),
        SizedBox(width: 8.r),
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
              fontSize: 11.r,
            ),
          ),
        ),
        if (trailing != null && trailing.isNotEmpty)
          Text(
            trailing,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 8.r,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.58),
            ),
          ),
      ],
    );
  }

  Widget _buildPill(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.r, vertical: 4.r),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999.r),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10.r, color: color),
          SizedBox(width: 4.r),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 8.r,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context, {required double minHeight}) {
    final theme = Theme.of(context);
    return SizedBox(
      height: minHeight,
      child: Center(
        child: SizedBox(
          width: 22.r,
          height: 22.r,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            valueColor: AlwaysStoppedAnimation<Color>(
              theme.colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionMessage(
    BuildContext context,
    String message, {
    bool isError = false,
    Future<bool> Function()? onRetry,
    required double minHeight,
  }) {
    final theme = Theme.of(context);
    return SizedBox(
      height: minHeight,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 9.r,
                color: isError
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            if (onRetry != null) ...[
              SizedBox(height: 8.r),
              TextButton(
                onPressed: () => onRetry(),
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _networkThumb(String url, {required IconData icon}) {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        return ClipRRect(
          borderRadius: BorderRadius.circular(8.r),
          child: SizedBox(
            width: 40.r,
            height: 40.r,
            child: Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: theme.colorScheme.surface,
                child: Icon(icon, color: theme.colorScheme.primary, size: 18.r),
              ),
            ),
          ),
        );
      },
    );
  }

  BoxDecoration _cardDecoration(
    ThemeData theme, {
    Color? background,
    Color? borderColor,
  }) {
    return BoxDecoration(
      color: background ?? theme.cardColor.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(12.r),
      border: Border.all(
        color: borderColor ?? theme.colorScheme.primary.withValues(alpha: 0.15),
        width: 1.r,
      ),
    );
  }

  String _raMediaUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return 'https://media.retroachievements.org$path';
  }

  String _formatDate(String raw) {
    if (raw.isEmpty) return '';
    final parsed = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
    if (parsed == null) return raw;
    final local = parsed.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }

  Future<void> _openOwnedWeekGame(
    BuildContext context,
    OwnedWeekGameResolution owned,
  ) async {
    final configProvider = context.read<SqliteConfigProvider>();
    final fileProvider = context.read<FileProvider>();
    final system = _resolveSystem(configProvider.detectedSystems, owned);
    if (system == null) {
      AppNotification.showNotification(
        context,
        'Could not resolve the local system for this game',
        type: NotificationType.error,
      );
      return;
    }

    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SystemGamesList(
          system: system,
          fileProvider: fileProvider,
          initialRomPath: owned.game.romPath,
        ),
      ),
    );
  }

  SystemModel? _resolveSystem(
    List<SystemModel> systems,
    OwnedWeekGameResolution owned,
  ) {
    final folder = owned.game.systemFolderName;
    if (folder == null || folder.isEmpty) return null;
    for (final system in systems) {
      if (system.folderName == folder || system.primaryFolderName == folder) {
        return system;
      }
    }
    return null;
  }
}
