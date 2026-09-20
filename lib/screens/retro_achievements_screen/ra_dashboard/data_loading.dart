part of '../ra_dashboard.dart';

/// Dashboard data-loading orchestration for the RetroAchievements hub.
///
/// Sequences the five dashboard fetches (firing them all at once trips the
/// rate limiter) and reloads when the provider's cache generation is
/// bumped under us — after a game session, or a refresh. All state lives
/// on the host [State]; this extension only moves the methods out of the
/// monolith — behaviour is unchanged.
extension _DataLoading on RADashboardHubState {
  Future<void> _loadDashboard(RetroAchievementsProvider provider) async {
    // Stamped up front, not on completion: the five fetches below take a while
    // and the stamp is what stops a second entry starting a duplicate run
    // while this one is still going.
    provider.markDashboardAttempted();
    // Load sequentially rather than with Future.wait: firing every RA endpoint
    // at once trips the rate limiter (HTTP 429). AOTW goes first because it is
    // the dashboard's primary task; each section still resolves independently.
    await provider.fetchGOTW();
    await provider.fetchRecentUnlocks();
    await provider.fetchRecentlyPlayedGames();
    await provider.fetchUserAwards();
    await provider.fetchCompletionProgress();
  }

  /// Reloads when the cached reads have been invalidated under us — after a
  /// game session, or when the user pressed refresh. Deliberately keyed to the
  /// generation counter and not to `dashboardLoaded`: a section that failed
  /// leaves that flag false too, and retrying on it would loop.
  ///
  /// Only while the dashboard is the sub-tab on screen: a refresh pressed on
  /// another sub-tab is that sub-tab's business, and this one catches up on
  /// its next activation, when the invalidation's staleness reset sends the
  /// same reload through the entry path.
  void _onProviderChanged() {
    final provider = _provider;
    if (provider == null || !mounted) return;
    _resolveRommWeekGame(provider);
    if (provider.cacheGeneration == _seenCacheGeneration) return;
    _seenCacheGeneration = provider.cacheGeneration;
    if (!provider.isConnected || !widget.active) return;
    _dashboardLoadTimer?.cancel();
    // ignore: unawaited_futures
    _loadDashboard(provider);
  }
}
