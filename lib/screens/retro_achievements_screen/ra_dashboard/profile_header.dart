part of '../ra_dashboard.dart';

/// The profile header: avatar, stat pills, and the logout button.
///
/// All state lives on the host [State]; this extension only moves the
/// methods out of the monolith — behaviour is unchanged.
extension _ProfileHeader on RADashboardHubState {
  Widget _buildHeader(
    BuildContext context,
    RetroAchievementsProvider raProvider,
  ) {
    final theme = Theme.of(context);
    final user = raProvider.user!;
    final showCompletions = user.isCasual;
    final trackedGames = raProvider.completionProgress?.total ?? 0;
    // Bright gold/silver read fine on dark surfaces but wash out on light
    // palettes, so pick a darker goldenrod/grey when the theme is light.
    final isLightTheme = theme.brightness == Brightness.light;
    final highlightColor = showCompletions
        ? (isLightTheme ? const Color(0xFF757575) : const Color(0xFFC0C0C0))
        : (isLightTheme ? const Color(0xFFB8860B) : const Color(0xFFFFD700));
    final highlightCount = showCompletions
        ? (raProvider.userAwards?.completionAwardsCount ?? 0)
        : (raProvider.userAwards?.masteryAwardsCount ?? 0);
    final highlightLabel = showCompletions
        ? AppLocale.raCompletionsLabel.getString(context)
        : AppLocale.raMasteriesLabel.getString(context);
    final beatenGames = showCompletions
        ? (raProvider.userAwards?.beatenCasualAwardsCount ?? 0)
        : (raProvider.userAwards?.beatenHardcoreAwardsCount ?? 0);

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
                      label:
                          '${user.totalPoints} ${AppLocale.raPointsAbbrev.getString(context)}',
                      color: theme.colorScheme.primary,
                    ),
                    _buildPill(
                      context,
                      icon: Symbols.sports_esports_rounded,
                      label: AppLocale.raGamesPlayed
                          .getString(context)
                          .replaceFirst('{count}', '$trackedGames'),
                      color: theme.colorScheme.primary,
                    ),
                    _buildPill(
                      context,
                      icon: Symbols.flag_rounded,
                      label: AppLocale.raGamesBeaten
                          .getString(context)
                          .replaceFirst('{count}', '$beatenGames'),
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
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(
                color: widget.logoutSelected
                    ? theme.colorScheme.primary
                    : Colors.transparent,
                width: 2.r,
              ),
            ),
            child: IconButton(
              onPressed: widget.onDisconnectRequested,
              icon: Icon(
                Symbols.logout_rounded,
                color: theme.colorScheme.error,
                size: 20.r,
              ),
              tooltip: AppLocale.logout.getString(context),
            ),
          ),
        ],
      ),
    );
  }
}
