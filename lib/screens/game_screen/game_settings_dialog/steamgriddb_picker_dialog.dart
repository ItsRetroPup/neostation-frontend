import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/steamgriddb.dart';
import 'package:neostation/services/gamepad/gamepad_navigation_manager.dart';
import 'package:neostation/services/steamgriddb_service.dart';
import 'package:neostation/utils/gamepad_nav.dart';
import 'package:neostation/widgets/selection_grid/grid_navigation.dart';
import 'package:neostation/widgets/selection_grid/selection_grid.dart';
import 'package:neostation/widgets/selection_grid/selection_grid_geometry.dart';

enum _Stage { game, artwork }

enum _LoadStatus { loading, ready, error }

/// Lets the user pick one piece of SteamGridDB artwork for a game.
///
/// Two stages share one dialog and one gamepad layer:
///  1. **Game** — a search field (prefilled from the game's title) and the
///     SteamGridDB games that match. Steam games skip this stage when their
///     app ID resolves directly.
///  2. **Artwork** — a thumbnail grid of [type] images for the chosen game.
///     B goes back to the game list rather than closing.
///
/// Pops with the chosen [SteamGridDbImage], or null when the user backs out.
/// Downloading and saving the image is the caller's job.
class SteamGridDbPickerDialog extends StatefulWidget {
  final SteamGridDbService service;
  final SteamGridDbArtworkType type;
  final String gameTitle;

  /// The game's Steam app ID, when it is a Steam game.
  final String? steamAppId;

  const SteamGridDbPickerDialog({
    super.key,
    required this.service,
    required this.type,
    required this.gameTitle,
    this.steamAppId,
  });

  static Future<SteamGridDbImage?> show(
    BuildContext context, {
    required SteamGridDbService service,
    required SteamGridDbArtworkType type,
    required String gameTitle,
    String? steamAppId,
  }) {
    return showDialog<SteamGridDbImage>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SteamGridDbPickerDialog(
        service: service,
        type: type,
        gameTitle: gameTitle,
        steamAppId: steamAppId,
      ),
    );
  }

  @override
  State<SteamGridDbPickerDialog> createState() =>
      _SteamGridDbPickerDialogState();
}

class _SteamGridDbPickerDialogState extends State<SteamGridDbPickerDialog> {
  static const String _layerId = 'steamgriddb_picker_dialog';
  static final double _rowHeight = 36.r;

  late final GamepadNavigation _gamepadNav;
  final TextEditingController _queryController = TextEditingController();
  final FocusNode _queryFocus = FocusNode();
  final ScrollController _listController = ScrollController();

  _Stage _stage = _Stage.game;
  _LoadStatus _status = _LoadStatus.loading;
  bool _isFieldFocused = false;

  List<SteamGridDbGame> _games = const [];
  SteamGridDbGame? _game;
  List<SteamGridDbImage> _images = const [];

  /// Game stage: 0 is the search field, then one row per game (or the retry
  /// row on error). Artwork stage: index into [_images].
  int _selectedIndex = 0;

  /// Bumped on every request so a slow, superseded response is dropped.
  int _requestId = 0;

  /// Grid columns per artwork shape: tall grids pack more per row than wide
  /// heroes.
  int get _columns => switch (widget.type) {
    SteamGridDbArtworkType.grid => 5,
    SteamGridDbArtworkType.hero => 2,
    SteamGridDbArtworkType.logo => 3,
  };

  int get _gameItemCount =>
      1 + (_status == _LoadStatus.error ? 1 : _games.length);

  @override
  void initState() {
    super.initState();
    _queryController.text = steamGridDbSearchTerm(widget.gameTitle);
    _queryFocus.addListener(() {
      if (mounted) setState(() => _isFieldFocused = _queryFocus.hasFocus);
    });

    _gamepadNav = GamepadNavigation(
      onNavigateUp: () => _move(up: true),
      onNavigateDown: () => _move(up: false),
      onNavigateLeft: () => _moveHorizontal(left: true),
      onNavigateRight: () => _moveHorizontal(left: false),
      onSelectItem: _activate,
      onBack: _handleBack,
      isTextFieldFocused: () => _queryFocus.hasFocus,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _gamepadNav.initialize();
      GamepadNavigationManager.pushLayer(
        _layerId,
        onActivate: () => _gamepadNav.activate(),
        onDeactivate: () => _gamepadNav.deactivate(),
      );
    });

    _start();
  }

  @override
  void dispose() {
    GamepadNavigationManager.popLayer(_layerId);
    _gamepadNav.dispose();
    _queryController.dispose();
    _queryFocus.dispose();
    _listController.dispose();
    super.dispose();
  }

  // ── Loading ───────────────────────────────────────────────────────────────

  /// Steam games go straight to their artwork when the app ID resolves;
  /// everything else (and an unresolved app ID) starts with a title search.
  Future<void> _start() async {
    final appId = widget.steamAppId;
    if (appId != null && int.tryParse(appId) != null) {
      try {
        final game = await widget.service.gameForSteamAppId(appId);
        if (!mounted) return;
        if (game != null) {
          _openGame(game);
          return;
        }
      } on SteamGridDbException {
        // Fall through to the title search, which shows its own error.
      }
    }
    if (mounted) _search();
  }

  Future<void> _search() async {
    final id = ++_requestId;
    setState(() {
      _status = _LoadStatus.loading;
      _selectedIndex = 0;
    });
    try {
      final games = await widget.service.searchGames(_queryController.text);
      if (!mounted || id != _requestId) return;
      setState(() {
        _games = games;
        _status = _LoadStatus.ready;
        // Land on the best match so A picks it straight away.
        _selectedIndex = games.isEmpty ? 0 : 1;
      });
    } on SteamGridDbException {
      if (!mounted || id != _requestId) return;
      setState(() => _status = _LoadStatus.error);
    }
  }

  Future<void> _openGame(SteamGridDbGame game) async {
    final id = ++_requestId;
    setState(() {
      _game = game;
      _stage = _Stage.artwork;
      _status = _LoadStatus.loading;
      _images = const [];
      _selectedIndex = 0;
    });
    try {
      final images = await widget.service.getImages(game.id, widget.type);
      if (!mounted || id != _requestId) return;
      setState(() {
        _images = images;
        _status = _LoadStatus.ready;
      });
    } on SteamGridDbException {
      if (!mounted || id != _requestId) return;
      setState(() => _status = _LoadStatus.error);
    }
  }

  /// Back from the artwork grid to the game list. The list is searched lazily:
  /// a Steam game that skipped it has nothing listed yet.
  void _backToGames() {
    ++_requestId;
    setState(() {
      _stage = _Stage.game;
      _images = const [];
    });
    _search();
  }

  // ── Gamepad ───────────────────────────────────────────────────────────────

  bool _move({required bool up}) {
    if (_queryFocus.hasFocus) return false;
    final int next;
    if (_stage == _Stage.game) {
      next = (_selectedIndex + (up ? -1 : 1)).clamp(0, _gameItemCount - 1);
    } else {
      if (_images.isEmpty) return false;
      next = up
          ? gridMoveUp(
              index: _selectedIndex,
              columns: _columns,
              itemCount: _images.length,
            )
          : gridMoveDown(
              index: _selectedIndex,
              columns: _columns,
              itemCount: _images.length,
            );
    }
    if (next == _selectedIndex) return false;
    setState(() => _selectedIndex = next);
    if (_stage == _Stage.game) _scrollListToSelection();
    return true;
  }

  /// Returns whether the cursor moved; [GamepadNavigation] plays the nav
  /// sound from that, as it does for [_move].
  bool _moveHorizontal({required bool left}) {
    if (_queryFocus.hasFocus || _stage != _Stage.artwork) return false;
    if (_images.isEmpty) return false;
    final next = left
        ? gridMoveLeft(
            index: _selectedIndex,
            columns: _columns,
            itemCount: _images.length,
          )
        : gridMoveRight(
            index: _selectedIndex,
            columns: _columns,
            itemCount: _images.length,
          );
    if (next == _selectedIndex) return false;
    setState(() => _selectedIndex = next);
    return true;
  }

  void _activate() {
    if (_queryFocus.hasFocus) {
      // A/Enter while typing runs the search and returns to list navigation.
      _queryFocus.unfocus();
      _search();
      return;
    }

    if (_stage == _Stage.artwork) {
      if (_status == _LoadStatus.error && _game != null) {
        _openGame(_game!);
        return;
      }
      final image = _images.elementAtOrNull(_selectedIndex);
      if (image != null) {
        Navigator.of(context).pop(image);
      }
      return;
    }

    if (_selectedIndex == 0) {
      _queryFocus.requestFocus();
      return;
    }
    if (_status == _LoadStatus.error) {
      _search();
      return;
    }
    final game = _games.elementAtOrNull(_selectedIndex - 1);
    if (game != null) {
      _openGame(game);
    }
  }

  /// B leaves the text field first, then the artwork grid, then the dialog.
  void _handleBack() {
    if (_queryFocus.hasFocus) {
      _queryFocus.unfocus();
      return;
    }
    if (_stage == _Stage.artwork) {
      _backToGames();
      return;
    }
    Navigator.of(context).pop();
  }

  void _scrollListToSelection() {
    if (!_listController.hasClients) return;
    final target = ((_selectedIndex - 1) * _rowHeight).clamp(
      0.0,
      _listController.position.maxScrollExtent,
    );
    _listController.animateTo(
      target,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    return Dialog(
      backgroundColor: theme.cardColor,
      insetPadding: EdgeInsets.all(16.r),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.r),
        side: BorderSide(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Container(
        width: size.width * 0.75,
        height: size.height * 0.8,
        padding: EdgeInsets.all(12.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTitle(theme),
            SizedBox(height: 10.r),
            if (_stage == _Stage.game) ...[
              _buildSearchField(theme),
              SizedBox(height: 8.r),
              Expanded(child: _buildGameList(theme)),
            ] else
              Expanded(child: _buildArtwork(theme)),
          ],
        ),
      ),
    );
  }

  Widget _buildTitle(ThemeData theme) {
    final title = _stage == _Stage.game
        ? AppLocale.steamGridDbChooseGame.getString(context)
        : AppLocale.steamGridDbChooseArtwork
              .getString(context)
              .replaceFirst('{game}', _game?.name ?? '');
    return Row(
      children: [
        Icon(Symbols.image_search_rounded, color: theme.colorScheme.primary),
        SizedBox(width: 8.r),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: 13.r,
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          AppLocale.steamGridDbTitle.getString(context),
          style: TextStyle(
            fontSize: 10.r,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField(ThemeData theme) {
    final selected = _selectedIndex == 0;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(6.r),
        border: Border.all(
          color: selected || _isFieldFocused
              ? theme.colorScheme.primary
              : theme.colorScheme.outline.withValues(alpha: 0.4),
          width: selected || _isFieldFocused ? 2.r : 1.r,
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: 8.r),
      child: Row(
        children: [
          Icon(
            Symbols.search_rounded,
            size: 14.r,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          SizedBox(width: 6.r),
          Expanded(
            child: TextField(
              controller: _queryController,
              focusNode: _queryFocus,
              onTap: () => setState(() => _selectedIndex = 0),
              onSubmitted: (_) => _search(),
              textInputAction: TextInputAction.search,
              style: TextStyle(
                fontSize: 12.r,
                color: theme.colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 10.r),
                hintText: AppLocale.steamGridDbSearchHint.getString(context),
                hintStyle: TextStyle(
                  fontSize: 12.r,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
          if (_status == _LoadStatus.loading)
            SizedBox(
              width: 12.r,
              height: 12.r,
              child: CircularProgressIndicator(strokeWidth: 1.5.r),
            ),
        ],
      ),
    );
  }

  Widget _buildGameList(ThemeData theme) {
    if (_status == _LoadStatus.error) {
      return Align(
        alignment: Alignment.topCenter,
        child: _ListRow(
          height: _rowHeight,
          selected: _selectedIndex == 1,
          icon: Symbols.refresh_rounded,
          title: AppLocale.steamGridDbUnreachable.getString(context),
          trailing: AppLocale.retry.getString(context),
          onTap: _search,
        ),
      );
    }
    if (_status == _LoadStatus.ready && _games.isEmpty) {
      return _buildMessage(theme, AppLocale.steamGridDbNoGames);
    }
    return ListView.builder(
      controller: _listController,
      itemCount: _games.length,
      itemExtent: _rowHeight,
      itemBuilder: (context, i) {
        final game = _games[i];
        return _ListRow(
          height: _rowHeight,
          selected: _selectedIndex == i + 1,
          icon: Symbols.sports_esports_rounded,
          title: game.name,
          trailing: game.releaseYear?.toString(),
          onTap: () {
            setState(() => _selectedIndex = i + 1);
            _openGame(game);
          },
        );
      },
    );
  }

  Widget _buildArtwork(ThemeData theme) {
    if (_status == _LoadStatus.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_status == _LoadStatus.error) {
      return Align(
        alignment: Alignment.topCenter,
        child: _ListRow(
          height: _rowHeight,
          selected: true,
          icon: Symbols.refresh_rounded,
          title: AppLocale.steamGridDbUnreachable.getString(context),
          trailing: AppLocale.retry.getString(context),
          onTap: () => _openGame(_game!),
        ),
      );
    }
    if (_images.isEmpty) {
      return _buildMessage(theme, AppLocale.steamGridDbNoArtwork);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = 8.r;
        final geometry = computeSelectionGridGeometry(
          itemCount: _images.length,
          columns: _columns,
          availableWidth: constraints.maxWidth - 2 * spacing,
          spacingX: spacing,
          spacingY: spacing,
          // Uniform rows keep the grid tidy whatever each image's own size.
          itemHeightFor: (_, cardWidth) => cardWidth / _cellAspectRatio,
        );
        return SelectionGrid(
          geometry: geometry,
          padding: EdgeInsets.all(spacing),
          selectedIndex: _selectedIndex,
          revision: _images.length,
          itemBuilder: (context, index, cellSize) => _ArtworkTile(
            image: _images[index],
            onTap: () {
              setState(() => _selectedIndex = index);
              Navigator.of(context).pop(_images[index]);
            },
          ),
        );
      },
    );
  }

  /// Width over height of each grid cell for the artwork shape.
  double get _cellAspectRatio => switch (widget.type) {
    SteamGridDbArtworkType.grid => 2 / 3,
    SteamGridDbArtworkType.hero => 96 / 31,
    SteamGridDbArtworkType.logo => 2,
  };

  Widget _buildMessage(ThemeData theme, String key) {
    return Center(
      child: Text(
        key.getString(context),
        style: TextStyle(
          fontSize: 11.r,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

class _ListRow extends StatelessWidget {
  final double height;
  final bool selected;
  final IconData icon;
  final String title;
  final String? trailing;
  final VoidCallback onTap;

  const _ListRow({
    required this.height,
    required this.selected,
    required this.icon,
    required this.title,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        padding: EdgeInsets.symmetric(horizontal: 8.r),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6.r),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: 0.5)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 14.r,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            SizedBox(width: 8.r),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.r,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            if (trailing != null)
              Text(
                trailing!,
                style: TextStyle(
                  fontSize: 10.r,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ArtworkTile extends StatelessWidget {
  final SteamGridDbImage image;
  final VoidCallback onTap;

  const _ArtworkTile({required this.image, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.4);
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6.r),
        child: Container(
          color: theme.colorScheme.surfaceContainerHighest,
          child: Image.network(
            image.thumbUrl,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : Center(
                    child: SizedBox(
                      width: 14.r,
                      height: 14.r,
                      child: CircularProgressIndicator(strokeWidth: 1.5.r),
                    ),
                  ),
            errorBuilder: (_, _, _) =>
                Icon(Symbols.broken_image_rounded, size: 18.r, color: muted),
          ),
        ),
      ),
    );
  }
}
