part of '../ra_content.dart';

/// Gamepad / keyboard input handling for the RetroAchievements tab root.
///
/// Registers the [GamepadNavigation] input mappings and the `ra_content`
/// gamepad layer, and implements its two focus zones: the login form's field
/// selection while signed out, and — while signed in — the sub-tab shell,
/// where Up from the top of the content parks the cursor on the strip
/// [RaTabStrip], Left/Right there switch sub-tabs, and Down (or A, or B in
/// the content) drops back into the active sub-tab at its parked cursor.
///
/// The strip is a zone of this one layer, never a layer of its own:
/// switching sub-tabs or zones never touches the
/// [GamepadNavigationManager] stack, so the double-dispatch class of bug
/// cannot come back through the tab. All state lives on the host [State];
/// `setState` calls route through the host [rebuild] bridge
/// (`State.setState` is `@protected` and can't be invoked from an
/// extension).
extension _GamepadNav on _RAContentState {
  void _initControllerNavigation() {
    _gamepadNav = GamepadNavigation(
      onNavigateUp: _handleNavigateUp,
      onNavigateDown: _handleNavigateDown,
      onNavigateLeft: _handleNavigateLeft,
      onNavigateRight: _handleNavigateRight,
      onSelectItem: _selectCurrent,
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
    final raProvider = context.read<RetroAchievementsProvider>();
    if (raProvider.isConnected) {
      if (_stripFocused) {
        // A on the strip enters the sub-tab under its cursor.
        _setStripFocused(false);
        return;
      }
      if (_logoutSelected) {
        _requestDisconnect();
        return;
      }
      if (_weekCardSelected) {
        _dashboardKey.currentState?.selectWeekCard();
      }
      return;
    }
    if (focusSelectedField()) return;
    if (selectedSlot == 2) {
      _openRaControlPanel();
      return;
    }
    _connectToRA();
  }

  /// B: in the content, it parks the cursor on the strip; on the strip (or
  /// signed out), it is the app-wide back — today's behaviour, which on a
  /// root tab means leaving a focused text field, and otherwise nothing.
  void _handleBack() {
    if (!context.read<RetroAchievementsProvider>().isConnected ||
        _stripFocused) {
      exitTextEntry();
      return;
    }
    _setStripFocused(true);
  }

  bool _setLogoutSelected(bool selected) {
    if (!mounted || _logoutSelected == selected) return false;
    rebuild(() => _logoutSelected = selected);
    return true;
  }

  bool _setWeekCardSelected(bool selected) {
    if (!mounted || _weekCardSelected == selected) return false;
    rebuild(() => _weekCardSelected = selected);
    return true;
  }

  bool _setStripFocused(bool focused) {
    if (!mounted || _stripFocused == focused) return false;
    rebuild(() => _stripFocused = focused);
    return true;
  }

  /// Steps the sub-tab cursor by [delta] with wrap-around. Only the sound
  /// contract cares about the return: with a single sub-tab there is nothing
  /// to switch, so the press is a silent no-op rather than a wrap onto
  /// itself.
  bool _switchSubTab(int delta) {
    final tabs = RaSubTab.values;
    if (tabs.length < 2) return false;
    final current = tabs.indexOf(_activeSubTab);
    final next = tabs[(current + delta + tabs.length) % tabs.length];
    rebuild(() => _activeSubTab = next);
    return true;
  }

  /// The strip's tap callback: the same switch the D-pad makes, minus the
  /// sound (the pill plays it, as the details-card tabs do).
  void _onSubTabTapped(RaSubTab tab) {
    if (tab == _activeSubTab) return;
    rebuild(() => _activeSubTab = tab);
  }

  /// Releases the header selection when the dashboard scrolls off the top by
  /// any means, so a touch or wheel scroll can't leave the logout button or the
  /// week card armed behind the content — both live in the header area, and a
  /// selection the user can no longer see still answers A.
  void _releaseSelectionOnScroll() {
    if (_scrollingToHeader) return;
    if (!_logoutSelected && !_weekCardSelected) return;
    if (!_dashboardScrollController.hasClients) return;
    final position = _dashboardScrollController.position;
    if (position.pixels > position.minScrollExtent + 1) {
      _setLogoutSelected(false);
      _setWeekCardSelected(false);
    }
  }

  /// Returns whether the selection/scroll actually moved, so the gamepad
  /// handler can suppress the nav sound at a boundary.
  ///
  /// From the top of the dashboard, Up parks the cursor on the sub-tab strip
  /// instead of scrolling nowhere — but only once the press has nothing
  /// finer to do inside the content: releasing the week card still counts as
  /// the move, so a selected card costs one Up to clear and a second to
  /// reach the strip.
  bool _handleNavigateUp() {
    final raProvider = context.read<RetroAchievementsProvider>();
    if (!raProvider.isConnected) {
      return moveSelection(-1);
    }
    if (_stripFocused) return false;
    final released = _setWeekCardSelected(false);
    final scrolled = _scrollDashboard(-160.r);
    if (scrolled || released) return true;
    if (_dashboardAtTop) return _setStripFocused(true);
    return false;
  }

  /// Down steps onto the dashboard's one actionable card before it starts
  /// scrolling, so the card is reachable without knowing to press Left.
  ///
  /// Only from the top, and only at rest: selecting a card that has already
  /// scrolled out of view would leave the highlight invisible, which is the
  /// same trap [_scrollHeaderIntoView] exists to keep the logout button out of.
  /// Once the card is selected — or the cursor is parked on logout — Down goes
  /// back to being a plain scroll.
  bool _handleNavigateDown() {
    final raProvider = context.read<RetroAchievementsProvider>();
    if (!raProvider.isConnected) return moveSelection(1);
    // Down is how the strip hands the cursor back: the sub-tab's own cursor
    // (scroll position, parked selection) is where it always was, because
    // switching zones tears nothing down.
    if (_stripFocused) return _setStripFocused(false);
    if (!_logoutSelected &&
        !_weekCardSelected &&
        _dashboardKey.currentState?.weekCardSelectable == true &&
        _dashboardAtTop) {
      return _setWeekCardSelected(true);
    }
    final released = _setWeekCardSelected(false);
    return _scrollDashboard(160.r) || released;
  }

  /// Whether the dashboard is scrolled to the top, within the same one-pixel
  /// tolerance [_releaseSelectionOnScroll] and [_scrollHeaderIntoView] use.
  bool get _dashboardAtTop {
    if (!_dashboardScrollController.hasClients) return true;
    final position = _dashboardScrollController.position;
    return position.pixels <= position.minScrollExtent + 1;
  }

  /// Right parks the cursor on the header's logout button.
  ///
  /// The header scrolls with the content, so anything below the top has to come
  /// back into view first — parking on a button that is off screen would leave
  /// the highlight invisible and A destructive-looking out of nowhere.
  bool _handleNavigateRight() {
    if (!context.read<RetroAchievementsProvider>().isConnected) return false;
    if (_stripFocused) return _switchSubTab(1);
    if (_logoutSelected) return false;
    _setWeekCardSelected(false);
    _scrollHeaderIntoView();
    return _setLogoutSelected(true);
  }

  /// Left is the mirror of Right along the same axis: it steps from the logout
  /// button straight onto the week card rather than dropping the selection in
  /// between. Releasing to nothing is only the fallback for when the card is
  /// not actionable, so the axis never costs a dead press.
  bool _handleNavigateLeft() {
    final raProvider = context.read<RetroAchievementsProvider>();
    if (!raProvider.isConnected) return false;
    if (_stripFocused) return _switchSubTab(-1);
    final released = _logoutSelected ? _setLogoutSelected(false) : false;
    if (_dashboardKey.currentState?.weekCardSelectable != true) {
      return released;
    }
    _scrollHeaderIntoView();
    return _setWeekCardSelected(true) || released;
  }

  void _scrollHeaderIntoView() {
    if (!_dashboardScrollController.hasClients) return;
    final position = _dashboardScrollController.position;
    if (position.pixels <= position.minScrollExtent + 1) return;
    _scrollingToHeader = true;
    _dashboardScrollController
        .animateTo(
          position.minScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() => _scrollingToHeader = false);
  }

  bool _scrollDashboard(double delta) {
    if (!_dashboardScrollController.hasClients) return false;
    final position = _dashboardScrollController.position;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < 1) return false;
    _dashboardScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
    return true;
  }
}
