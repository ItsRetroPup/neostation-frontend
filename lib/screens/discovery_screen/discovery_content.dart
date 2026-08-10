import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import 'package:neostation/data/datasources/sqlite_service.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/discovery_models.dart';
import 'package:neostation/models/game_model.dart';
import 'package:neostation/models/secondary_display_state.dart';
import 'package:neostation/providers/discovery_provider.dart';
import 'package:neostation/providers/file_provider.dart';
import 'package:neostation/providers/retro_achievements_provider.dart';
import 'package:neostation/screens/app_screen.dart';
import 'package:neostation/screens/game_screen/my_games_list.dart';
import 'package:neostation/services/game_service.dart';
import 'package:neostation/services/secondary_achievements_controller.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/sync/sync_manager.dart';
import 'package:neostation/utils/game_launch_utils.dart';
import 'package:neostation/utils/gamepad_nav.dart';
import 'package:neostation/widgets/custom_notification.dart';

import 'discovery_footer.dart';
import 'discovery_storefront.dart';

/// The Discovery tab: a weekly, locally curated storefront over the user's own
/// library.
///
/// Owns the cursor (which row, which card) and the gamepad layer. The board
/// itself belongs to [DiscoveryProvider]; this widget only decides what is
/// focused and what each button does to it.
class DiscoveryContent extends StatefulWidget {
  const DiscoveryContent({super.key});

  @override
  State<DiscoveryContent> createState() => _DiscoveryContentState();
}

class _DiscoveryContentState extends State<DiscoveryContent> {
  late final GamepadNavigation _gamepadNav;
  final SecondaryAchievementsController _achievementsController =
      SecondaryAchievementsController();
  SecondaryDisplayState? _secondaryDisplayState;

  int _selectedRow = 0;
  int _selectedColumn = 0;

  /// The rows the last build produced. Kept so the navigation handlers can work
  /// out their bounds without rebuilding the whole board on every key press.
  List<DiscoveryRow> _rows = const [];

  @override
  void initState() {
    super.initState();

    _gamepadNav = GamepadNavigation(
      onNavigateUp: _navigateUp,
      onNavigateDown: _navigateDown,
      onNavigateLeft: _navigateLeft,
      onNavigateRight: _navigateRight,
      onSelectItem: _launchSelected,
      onXButton: _goToSelected,
      // Y is wired through the favourite callback: that is simply what the
      // translator routes the Y button to, and this tab has no favourites.
      onFavorite: _rerollSelected,
      onBack: _handleBack,
      // The tab owns the input layer while it is on screen, so bumper/tab
      // cycling has to keep working from in here.
      onPreviousTab: AppNavigation.previousTab,
      onNextTab: AppNavigation.nextTab,
      onLeftBumper: AppNavigation.previousTab,
      onRightBumper: AppNavigation.nextTab,
      allowRepeat: false,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gamepadNav.initialize();
      GamepadNavigationManager.pushLayer(
        'discovery_content',
        onActivate: () => _gamepadNav.activate(),
        onDeactivate: () => _gamepadNav.deactivate(),
      );

      // Let the 160ms tab indicator animation finish before touching the
      // database, so switching into the tab never janks.
      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted) context.read<DiscoveryProvider>().load();
      });
    });

    if (Platform.isAndroid) {
      _secondaryDisplayState = SecondaryDisplayState.instance;
    }
  }

  @override
  void dispose() {
    GamepadNavigationManager.popLayer('discovery_content');
    _achievementsController.dispose();
    _gamepadNav.dispose();
    super.dispose();
  }

  // ── Cursor ────────────────────────────────────────────────────────────────

  /// Indices of the rows the cursor may land on.
  ///
  /// Notice rows (the scrape-coverage message) hold no game, so they are
  /// skipped entirely rather than being a stop the user has to press through.
  List<int> get _focusableRows => [
    for (var i = 0; i < _rows.length; i++)
      if (_rows[i].isFocusable) i,
  ];

  DiscoveryBoardEntry? get _selectedEntry {
    if (_selectedRow < 0 || _selectedRow >= _rows.length) return null;
    final entries = _rows[_selectedRow].entries;
    if (_selectedColumn < 0 || _selectedColumn >= entries.length) return null;
    return entries[_selectedColumn];
  }

  void _moveToRow(int row) {
    if (!mounted) return;
    setState(() {
      _selectedRow = row;
      // Landing on a shorter shelf must not leave the cursor past its end.
      final length = _rows[row].entries.length;
      _selectedColumn = _selectedColumn.clamp(0, length > 0 ? length - 1 : 0);
    });
    SfxService().playNavSound();
  }

  void _navigateUp() {
    final rows = _focusableRows;
    final position = rows.indexOf(_selectedRow);
    if (position <= 0) return;
    _moveToRow(rows[position - 1]);
  }

  void _navigateDown() {
    final rows = _focusableRows;
    final position = rows.indexOf(_selectedRow);
    if (position < 0 || position >= rows.length - 1) return;
    _moveToRow(rows[position + 1]);
  }

  void _navigateLeft() {
    if (_selectedColumn <= 0) return;
    setState(() => _selectedColumn--);
    SfxService().playNavSound();
  }

  void _navigateRight() {
    final entry = _rows.elementAtOrNull(_selectedRow);
    if (entry == null) return;
    if (_selectedColumn >= entry.entries.length - 1) return;
    setState(() => _selectedColumn++);
    SfxService().playNavSound();
  }

  /// B returns to the top of the board, and does nothing once already there.
  ///
  /// Top-level tabs have no exit prompt (#308), so there is deliberately no
  /// "leave the app" path from here.
  void _handleBack() {
    final rows = _focusableRows;
    if (rows.isEmpty) return;
    if (_selectedRow == rows.first && _selectedColumn == 0) return;
    setState(() {
      _selectedRow = rows.first;
      _selectedColumn = 0;
    });
  }

  void _onEntryTapped(int row, int column) {
    setState(() {
      _selectedRow = row;
      _selectedColumn = column;
    });
    _launchSelected();
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  /// A: launch the focused pick.
  ///
  /// Mirrors `SearchScreen._launch` — the same secondary-display push, the same
  /// sync-provider guard and the same reactivation on close.
  Future<void> _launchSelected() async {
    final entry = _selectedEntry;
    if (entry == null) return;

    final dbGame = entry.game;
    final folder = dbGame.systemFolderName;
    if (folder == null || folder.isEmpty) return;

    final fileProvider = context.read<FileProvider>();
    final syncProvider = context.read<SyncManager>().active;
    if (syncProvider == null) return;

    final system = await SqliteService.getSystemByFolderName(folder);
    if (!mounted) return;

    final game = GameModel.fromDatabaseModel(dbGame);

    _gamepadNav.deactivate();

    // Drives the bottom screen's "Now Playing" page and the live RA panel for
    // this session. Not awaited so it never blocks the emulator handoff.
    // ignore: unawaited_futures
    _achievementsController.pushForLaunch(
      state: _secondaryDisplayState,
      provider: context.read<RetroAchievementsProvider>(),
      game: game,
      systemFolderName: system.primaryFolderName,
      boxartPath: SecondaryAchievementsController.resolveBoxart(
        game,
        system.primaryFolderName,
        fileProvider,
      ),
    );

    await launchGameWithDialog(
      context: context,
      game: game,
      system: system,
      fileProvider: fileProvider,
      syncProvider: syncProvider,
      onGameClosed: () {
        _achievementsController.stop(hidePanel: true);
        GamepadNavigationManager.reactivate();
        // Play time and last-played just changed, and both feed the picks'
        // "never played" badges and the hero's eligibility.
        if (mounted) context.read<DiscoveryProvider>().load(force: true);
      },
      onLaunchFailed: (ctx, result) async {
        _achievementsController.stop(hidePanel: true);
        if (mounted) {
          AppNotification.showNotification(
            context,
            AppLocale.errorLaunchingGame
                .getString(context)
                .replaceFirst('{error}', ''),
            type: NotificationType.error,
          );
        }
        GamepadNavigationManager.reactivate();
      },
    );
  }

  /// X: open the pick's system list with that game selected.
  Future<void> _goToSelected() async {
    final entry = _selectedEntry;
    if (entry == null) return;

    final folder = entry.game.systemFolderName;
    if (folder == null || folder.isEmpty) return;

    final fileProvider = context.read<FileProvider>();
    final system = await SqliteService.getSystemByFolderName(folder);
    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SystemGamesList(
          system: system,
          fileProvider: fileProvider,
          initialRomPath: entry.game.romPath,
        ),
      ),
    );
  }

  /// Y: swap the focused section's pick for a different game.
  Future<void> _rerollSelected() async {
    final entry = _selectedEntry;
    if (entry == null) return;
    await context.read<DiscoveryProvider>().reroll(entry.pick.slotId);
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Consumer<DiscoveryProvider>(
      builder: (context, provider, _) {
        final board = provider.board;

        if (provider.loading && board == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (provider.failed && board == null) {
          return _buildMessage(
            context,
            icon: Symbols.error_rounded,
            message: AppLocale.discoveryNoPickAvailable.getString(context),
            onRetry: () => provider.load(force: true),
          );
        }
        if (board == null || board.libraryIsEmpty) {
          return _buildMessage(
            context,
            icon: Symbols.storefront_rounded,
            message: AppLocale.discoveryEmptyLibrary.getString(context),
          );
        }

        _rows = buildDiscoveryRows(board);
        if (_rows.every((row) => !row.isFocusable)) {
          return _buildMessage(
            context,
            icon: Symbols.storefront_rounded,
            message: AppLocale.discoveryNoPickAvailable.getString(context),
          );
        }
        _clampCursor();

        return Stack(
          children: [
            DiscoveryStorefront(
              board: board,
              rows: _rows,
              fileProvider: context.watch<FileProvider>(),
              selectedRow: _selectedRow,
              selectedColumn: _selectedColumn,
              onEntryTapped: _onEntryTapped,
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DiscoveryFooter(
                onPlay: _launchSelected,
                onGoToGame: _goToSelected,
                onReroll: _rerollSelected,
                onBack: _handleBack,
              ),
            ),
          ],
        );
      },
    );
  }

  /// Keeps the cursor inside the board after it changes shape.
  ///
  /// A re-roll or a rescan can drop a whole section, which would otherwise
  /// leave the cursor pointing past the end and every button silently dead.
  void _clampCursor() {
    final rows = _focusableRows;
    if (rows.isEmpty) return;
    if (!rows.contains(_selectedRow)) {
      _selectedRow = rows.first;
      _selectedColumn = 0;
      return;
    }
    final length = _rows[_selectedRow].entries.length;
    if (_selectedColumn >= length) _selectedColumn = length - 1;
    if (_selectedColumn < 0) _selectedColumn = 0;
  }

  Widget _buildMessage(
    BuildContext context, {
    required IconData icon,
    required String message,
    VoidCallback? onRetry,
  }) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32.r),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 40.r,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
            ),
            SizedBox(height: 12.r),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10.r,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            if (onRetry != null) ...[
              SizedBox(height: 12.r),
              TextButton(
                onPressed: onRetry,
                child: Text(AppLocale.retry.getString(context)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
