part of '../ra_content.dart';

/// The see-all rows open a ROM-independent RetroAchievements game page. The
/// local library and RomM remain available through the weekly-game card; a
/// normal RA row is an information request and should never trigger a
/// download as a side effect.
extension _DrillDownHost on _RAContentState {
  Future<void> _activateUnlock(RetroAchievementRecentUnlockItem item) {
    return _openRaGameAchievements(
      gameId: item.gameId,
      gameTitle: item.gameTitle,
      achievementId: item.achievementId,
    );
  }

  Future<void> _activateGame(RaGamesListItem item) {
    return _openRaGameAchievements(gameId: item.gameId, gameTitle: item.title);
  }

  Future<void> _openRaGameAchievements({
    required int gameId,
    required String gameTitle,
    int? achievementId,
  }) async {
    if (_gameActivationInFlight || gameId <= 0) return;
    _gameActivationInFlight = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RaGameAchievementsPage(
            gameId: gameId,
            fallbackTitle: gameTitle,
            highlightAchievementId: achievementId,
          ),
        ),
      );
    } finally {
      _gameActivationInFlight = false;
    }
  }
}
