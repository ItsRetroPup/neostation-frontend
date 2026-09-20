part of '../ra_content.dart';

/// The see-all Unlocks sub-tab's drill-down: what pressing A (or tapping) a
/// row does with the game behind it.
///
/// Resolution order is the player's interest: the local library first (they
/// already own the best version — same push the week card makes), RomM
/// second (one press downloads it, and once indexing lands the next press
/// opens it locally), and a notice when neither can serve the row.
///
/// All state lives on the host [State]; navigation reuses
/// [_DashboardHost._openOwnedWeekGame] rather than duplicating the push.
extension _UnlocksHost on _RAContentState {
  Future<void> _activateUnlock(RetroAchievementRecentUnlockItem item) async {
    if (_unlockActivationInFlight) return;
    _unlockActivationInFlight = true;
    try {
      final raProvider = context.read<RetroAchievementsProvider>();
      final owned = await raProvider.resolveLocalGameForRaId(item.gameId);
      if (!mounted) return;
      if (owned != null) {
        _openOwnedWeekGame(owned);
        return;
      }
      final rommProvider = context.read<RommProvider>();
      final remote = await rommProvider.findRomByRaGameId(
        item.gameId,
        item.gameTitle,
      );
      if (!mounted) return;
      if (remote != null) {
        await _downloadUnlockGame(remote, item.gameId);
        return;
      }
      AppNotification.showNotification(
        context,
        AppLocale.raUnlockGameNotOwned.getString(context),
        type: NotificationType.info,
      );
    } finally {
      _unlockActivationInFlight = false;
    }
  }

  /// The RomM branch of the drill-down. Deliberately leaner than the week
  /// card's flow: the row re-resolves from scratch on every press, so instead
  /// of the card's cached state there is only the download itself, then a
  /// wait for indexing so a completed transfer can go straight to the
  /// library entry the player just earned.
  Future<void> _downloadUnlockGame(RommRom rom, int raGameId) async {
    final rommProvider = context.read<RommProvider>();
    final activeDownload = rommProvider.downloadFor(rom.id);
    if (activeDownload?.status == RommDownloadStatus.downloading) {
      rommProvider.cancelDownload(rom.id);
      return;
    }
    final result = await rommProvider.downloadRom(
      rom,
      romFolders: context.read<SqliteConfigProvider>().config.romFolders,
      fileProvider: context.read<FileProvider>(),
    );
    if (!mounted) return;
    switch (result.status) {
      case RommDownloadStatus.completed:
        AppNotification.showNotification(
          context,
          AppLocale.rommDownloadComplete.getString(context),
          type: NotificationType.success,
        );
        break;
      case RommDownloadStatus.cancelled:
        AppNotification.showNotification(
          context,
          AppLocale.rommDownloadCancelled.getString(context),
          type: NotificationType.info,
        );
        return;
      case RommDownloadStatus.failed:
        AppNotification.showNotification(
          context,
          _unlockDownloadErrorMessage(result.error),
          type: NotificationType.error,
        );
        return;
      case RommDownloadStatus.downloading:
        return;
    }

    // The transfer is complete before the debounced scan has inserted the
    // user_roms row (the week card waits for the same reason). Once it has,
    // the press carries straight on into the library entry the player just
    // earned; if the wait times out, resolving simply finds nothing and the
    // press ends here — the completion notice already said what happened.
    await result.indexed.timeout(const Duration(seconds: 30), onTimeout: () {});
    if (!mounted) return;
    final raProvider = context.read<RetroAchievementsProvider>();
    final owned = await raProvider.resolveLocalGameForRaId(raGameId);
    if (!mounted || owned == null) return;
    _openOwnedWeekGame(owned);
  }

  String _unlockDownloadErrorMessage(RommDownloadError error) {
    switch (error) {
      case RommDownloadError.noSystemMatch:
        return AppLocale.rommNoSystemMatch.getString(context);
      case RommDownloadError.noWritableFolder:
        return AppLocale.rommNoWritableFolder.getString(context);
      case RommDownloadError.network:
      case RommDownloadError.none:
        return AppLocale.rommDownloadFailed.getString(context);
    }
  }
}
