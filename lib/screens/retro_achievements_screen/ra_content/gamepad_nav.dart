part of '../ra_content.dart';

/// Controller handling for the signed-in dashboard and the login form.
/// Dedicated collections push their own routes and navigation layers.
extension _GamepadNav on _RAContentState {
  void _initControllerNavigation() {
    _gamepadNav = GamepadNavigation(
      onNavigateUp: _handleNavigateUp,
      onNavigateDown: _handleNavigateDown,
      onNavigateLeft: _handleNavigateLeft,
      onNavigateRight: _handleNavigateRight,
      onSelectItem: _selectCurrent,
      onFavorite: _refresh,
      onPreviousTab: AppNavigation.previousTab,
      onNextTab: AppNavigation.nextTab,
      onLeftBumper: AppNavigation.previousTab,
      onRightBumper: AppNavigation.nextTab,
      allowRepeat: false,
      isTextFieldFocused: isAnyFieldFocused,
      onBack: _handleBack,
    );
    _gamepadNav!.initialize();
    GamepadNavigationManager.pushLayer(
      'ra_content',
      onActivate: () => _gamepadNav?.activate(),
      onDeactivate: () => _gamepadNav?.deactivate(),
    );
  }

  void _selectCurrent() {
    final provider = context.read<RetroAchievementsProvider>();
    if (!provider.isConnected) {
      if (focusSelectedField()) return;
      if (selectedSlot == 2) {
        _openRaControlPanel();
        return;
      }
      _connectToRA();
      return;
    }

    switch (_dashboardActionIndex) {
      case 0:
        _dashboardKey.currentState?.selectWeekCard();
        return;
      case 1:
        _openEvents();
        return;
      case 2:
        _openUnlocks();
        return;
      case 3:
        _openGames();
        return;
      case 4:
        _openAwards();
        return;
      case 5:
        _requestDisconnect();
        return;
    }
  }

  void _refresh() {
    final provider = context.read<RetroAchievementsProvider>();
    if (!provider.isConnected || provider.isDashboardLoading) return;
    provider.invalidateCachedReads();
  }

  void _handleBack() {
    if (!context.read<RetroAchievementsProvider>().isConnected) {
      exitTextEntry();
      return;
    }
    exitTextEntry();
  }

  bool _setDashboardAction(int action) {
    if (!mounted) return false;
    final next = action.clamp(0, 5).toInt();
    if (_dashboardActionIndex == next) return false;
    rebuild(() {
      _dashboardActionIndex = next;
      _logoutSelected = next == 5;
      _weekCardSelected = next == 0;
      _eventsSelected = next == 1;
      _recentUnlocksSelected = next == 2;
      _gamesPreviewSelected = next == 3;
      _awardsSelected = next == 4;
    });
    return true;
  }

  bool _handleNavigateUp() {
    final provider = context.read<RetroAchievementsProvider>();
    if (!provider.isConnected) return moveSelection(-1);
    return _setDashboardAction(_dashboardActionIndex - 1);
  }

  bool _handleNavigateDown() {
    final provider = context.read<RetroAchievementsProvider>();
    if (!provider.isConnected) return moveSelection(1);
    return _setDashboardAction(_dashboardActionIndex + 1);
  }

  bool _handleNavigateLeft() {
    final provider = context.read<RetroAchievementsProvider>();
    if (!provider.isConnected || _dashboardActionIndex <= 0) return false;
    return _setDashboardAction(_dashboardActionIndex - 1);
  }

  bool _handleNavigateRight() {
    final provider = context.read<RetroAchievementsProvider>();
    if (!provider.isConnected || _dashboardActionIndex >= 5) return false;
    return _setDashboardAction(_dashboardActionIndex + 1);
  }

  void _releaseSelectionOnScroll() {
    if (!_dashboardScrollController.hasClients) return;
    final position = _dashboardScrollController.position;
    if (position.pixels <= position.minScrollExtent + 1) return;
    if (!_logoutSelected &&
        !_weekCardSelected &&
        !_eventsSelected &&
        !_recentUnlocksSelected &&
        !_gamesPreviewSelected &&
        !_awardsSelected) {
      return;
    }
    rebuild(() {
      _dashboardActionIndex = -1;
      _logoutSelected = false;
      _weekCardSelected = false;
      _eventsSelected = false;
      _recentUnlocksSelected = false;
      _gamesPreviewSelected = false;
      _awardsSelected = false;
    });
  }
}
