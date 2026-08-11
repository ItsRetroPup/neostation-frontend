import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import 'package:neostation/data/datasources/sqlite_service.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/discovery_models.dart';
import 'package:neostation/providers/discovery_provider.dart';
import 'package:neostation/providers/file_provider.dart';
import 'package:neostation/screens/app_screen.dart';
import 'package:neostation/screens/game_screen/my_games_list.dart';
import 'package:neostation/services/game_service.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/utils/gamepad_nav.dart';

import 'discovery_footer.dart';
import 'discovery_mosaic.dart';
import 'discovery_storefront.dart';

/// The Discovery tab: a weekly, locally curated storefront over the user's own
/// library.
///
/// Owns the cursor (which cell of the mosaic) and the gamepad layer. The board
/// itself belongs to [DiscoveryProvider]; this widget only decides what is
/// focused and what each button does to it.
class DiscoveryContent extends StatefulWidget {
  const DiscoveryContent({super.key});

  @override
  State<DiscoveryContent> createState() => _DiscoveryContentState();
}

class _DiscoveryContentState extends State<DiscoveryContent> {
  late final GamepadNavigation _gamepadNav;

  int _selectedRow = 0;
  int _selectedColumn = 0;

  /// The mosaic the last build produced. Kept so the navigation handlers can
  /// work out their bounds without rebuilding the whole board on every press.
  DiscoveryMosaic _mosaic = const DiscoveryMosaic.empty();

  @override
  void initState() {
    super.initState();

    _gamepadNav = GamepadNavigation(
      onNavigateUp: _navigateUp,
      onNavigateDown: _navigateDown,
      onNavigateLeft: _navigateLeft,
      onNavigateRight: _navigateRight,
      onSelectItem: _openSelected,
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
  }

  @override
  void dispose() {
    GamepadNavigationManager.popLayer('discovery_content');
    _gamepadNav.dispose();
    super.dispose();
  }

  // ── Cursor ────────────────────────────────────────────────────────────────

  DiscoveryTile? get _selectedTile =>
      _mosaic.tileAt(_selectedRow, _selectedColumn);

  DiscoveryBoardEntry? get _selectedEntry => _selectedTile?.entry;

  /// Moves the cursor one cell in a direction, if there is one to move to.
  ///
  /// Which cell that is belongs to the mosaic: the hero spans both grid rows
  /// and notices hold no game, and both of those are layout facts rather than
  /// input ones.
  void _move({int dRow = 0, int dCol = 0}) {
    final next = _mosaic.step(
      _selectedRow,
      _selectedColumn,
      dRow: dRow,
      dCol: dCol,
    );
    if (next == null || !mounted) return;
    setState(() {
      _selectedRow = next.$1;
      _selectedColumn = next.$2;
    });
    SfxService().playNavSound();
  }

  void _navigateUp() => _move(dRow: -1);

  void _navigateDown() => _move(dRow: 1);

  void _navigateLeft() => _move(dCol: -1);

  void _navigateRight() => _move(dCol: 1);

  /// B returns to the headline tile, and does nothing once already there.
  ///
  /// Top-level tabs have no exit prompt (#308), so there is deliberately no
  /// "leave the app" path from here.
  void _handleBack() {
    final first = _mosaic.firstFocusable;
    if (first == null) return;
    if (_selectedRow == first.$1 && _selectedColumn == first.$2) return;
    setState(() {
      _selectedRow = first.$1;
      _selectedColumn = first.$2;
    });
  }

  void _onTileTapped(DiscoveryTile tile) {
    final cell = _mosaic.locate(tile);
    if (cell == null || !tile.isFocusable) return;
    setState(() {
      _selectedRow = cell.$1;
      _selectedColumn = cell.$2;
    });
    _openSelected();
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  /// A: open the focused pick in its system's library, selected.
  ///
  /// Discovery deliberately does not launch anything itself. A pick is a
  /// suggestion, and the useful next step is to look at it — description,
  /// video, screenshots, achievements — which is exactly what the games list
  /// already shows for a selected game, Play button included. Rebuilding that
  /// card here would duplicate the whole of `my_games_list`'s state machine
  /// (video controller, artwork versioning, scrape progress) for no gain.
  Future<void> _openSelected() async {
    final entry = _selectedEntry;
    if (entry == null) return;

    final folder = entry.game.systemFolderName;
    if (folder == null || folder.isEmpty) return;

    final fileProvider = context.read<FileProvider>();
    final system = await SqliteService.getSystemByFolderName(folder);
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SystemGamesList(
          system: system,
          fileProvider: fileProvider,
          initialRomPath: entry.game.romPath,
        ),
      ),
    );

    // The user may well have played the game from in there, and play time feeds
    // both the "never played" badges and the hero's eligibility.
    if (mounted) await context.read<DiscoveryProvider>().load(force: true);
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

        _mosaic = buildDiscoveryMosaic(board);
        if (!_mosaic.hasFocusableTile) {
          return _buildMessage(
            context,
            icon: Symbols.storefront_rounded,
            message: AppLocale.discoveryNoPickAvailable.getString(context),
          );
        }
        _clampCursor();

        // The footer takes real space in a Column rather than floating over the
        // board in a Stack: an overlaid legend leaves the bottom strip half
        // hidden behind it, and the tiles there are the ones the cursor reaches
        // last.
        final selected = _selectedTile;
        return Column(
          children: [
            Expanded(
              child: DiscoveryStorefront(
                board: board,
                mosaic: _mosaic,
                fileProvider: context.watch<FileProvider>(),
                selectedTile: selected,
                onTileTapped: _onTileTapped,
              ),
            ),
            DiscoveryFooter(
              onOpen: _openSelected,
              onReroll: _rerollSelected,
              onBack: _handleBack,
              selectionIcon: selected?.icon,
              selectionText: _selectionText(context, selected),
            ),
          ],
        );
      },
    );
  }

  /// Names the selected pick for the footer, e.g. `Hidden Gem: ActRaiser`.
  String? _selectionText(BuildContext context, DiscoveryTile? tile) {
    final game = tile?.entry?.game;
    if (tile == null || game == null) return null;
    final label = tile.labelKey.getString(context);
    return '$label: ${game.realName ?? game.filename}';
  }

  /// Keeps the cursor inside the board after it changes shape.
  ///
  /// A re-roll or a rescan can drop a whole section, which would otherwise
  /// leave the cursor pointing past the end and every button silently dead.
  void _clampCursor() {
    final tile = _mosaic.tileAt(_selectedRow, _selectedColumn);
    if (tile != null && tile.isFocusable) return;
    final first = _mosaic.firstFocusable;
    if (first == null) return;
    _selectedRow = first.$1;
    _selectedColumn = first.$2;
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
