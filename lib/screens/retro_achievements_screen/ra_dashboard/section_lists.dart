part of '../ra_dashboard.dart';

/// The dashboard's list sections — recent unlocks, recent
/// masteries/completions, recently played — and their row builders.
///
/// All state lives on the host [State]; this extension only moves the
/// methods out of the monolith — behaviour is unchanged.
extension _SectionLists on RADashboardHubState {
  Widget _buildRecentUnlocksCard(
    BuildContext context,
    RetroAchievementsProvider raProvider,
  ) {
    final unlocks = raProvider.recentUnlocks.take(5).toList();
    return Container(
      padding: EdgeInsets.all(14.r),
      decoration: _cardDecoration(
        Theme.of(context),
        borderColor: widget.recentUnlocksSelected
            ? Theme.of(context).colorScheme.primary
            : null,
        borderWidth: widget.recentUnlocksSelected ? 2.r : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            context,
            icon: Symbols.notifications_active_rounded,
            title: AppLocale.raRecentUnlocks.getString(context),
            trailing: AppLocale.raRecent30Days.getString(context),
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
              AppLocale.raNoRecentUnlocks.getString(context),
              minHeight: 138.r,
            )
          else
            Column(
              children: unlocks
                  .map(
                    (item) => _buildUnlockRow(
                      context,
                      item,
                      onTap: widget.onUnlockSelected == null
                          ? null
                          : () => widget.onUnlockSelected!(item),
                    ),
                  )
                  .toList(),
            ),
        ],
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
      title: AppLocale.raRecentlyPlayedTitle.getString(context),
      icon: Symbols.history_rounded,
      loading: raProvider.recentlyPlayedLoading && items.isEmpty,
      error: items.isEmpty ? raProvider.recentlyPlayedError : null,
      emptyMessage: AppLocale.raNoRecentlyPlayed.getString(context),
      items: items,
      selected: widget.gamesSelected,
      onRetry: raProvider.fetchRecentlyPlayedGames,
      itemBuilder: (context, item) => _buildRecentlyPlayedRow(
        context,
        item,
        onTap: widget.onGameSelected == null
            ? null
            : () => widget.onGameSelected!(item.gameId, item.title),
      ),
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
    bool selected = false,
    String? subtitle,
    Future<bool> Function()? onRetry,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.all(14.r),
      decoration: _cardDecoration(
        theme,
        borderColor: selected ? theme.colorScheme.primary : null,
        borderWidth: selected ? 2.r : null,
      ),
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
            _buildSectionMessage(context, emptyMessage, minHeight: 120.r)
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
    RetroAchievementRecentUnlockItem item, {
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: 10.r),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8.r),
        child: Padding(
          padding: EdgeInsets.all(4.r),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RaEarnedBadge(
                casual: true,
                hardcore: item.hardcoreMode,
                child: _networkThumb(
                  _raMediaUrl(
                    item.badgeUrl.isNotEmpty
                        ? item.badgeUrl
                        : '/Badge/${item.badgeName}.png',
                  ),
                  icon: Symbols.emoji_events_rounded,
                ),
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
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.65,
                        ),
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
                    '${item.points} ${AppLocale.raPointsAbbrev.getString(context)}',
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
        ),
      ),
    );
  }

  Widget _buildRecentlyPlayedRow(
    BuildContext context,
    RetroAchievementRecentlyPlayedGameItem item, {
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: 10.r),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8.r),
        child: Padding(
          padding: EdgeInsets.all(4.r),
          child: Row(
            children: [
              _networkThumb(
                _raMediaUrl(item.imageIcon),
                icon: Symbols.videogame_asset_rounded,
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
                      '${item.consoleName} • ${AppLocale.raAchievementProgress.getString(context).replaceFirst('{earned}', '${item.numAchieved}').replaceFirst('{total}', '${item.numPossibleAchievements}')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 8.r,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.65,
                        ),
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
        ),
      ),
    );
  }
}
