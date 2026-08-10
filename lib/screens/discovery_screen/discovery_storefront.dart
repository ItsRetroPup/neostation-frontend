import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/l10n/app_locale.dart';

import '../../models/discovery_models.dart';
import '../../providers/file_provider.dart';
import '../../utils/genre_buckets.dart';
import 'widgets/discovery_hero_card.dart';
import 'widgets/discovery_shelf.dart';

/// What a band of the board is.
enum DiscoveryRowKind {
  /// The Game of the Week banner.
  hero,

  /// A horizontal row of picks.
  shelf,

  /// A message where a section would have been — not focusable.
  notice,
}

/// One band of the board, as both the layout and the cursor see it.
///
/// Rows are derived from the board rather than stored, so a section with no
/// pick simply never becomes a row: there is no such thing as an empty shelf to
/// navigate into.
class DiscoveryRow {
  const DiscoveryRow({
    required this.kind,
    required this.titleKey,
    required this.icon,
    this.entries = const [],
    this.subtitleKey,
    this.noticeKey,
    this.showGenreCaptions = false,
    this.achievementCount = 0,
  });

  final DiscoveryRowKind kind;

  /// [AppLocale] key for the section heading.
  final String titleKey;

  final IconData icon;
  final List<DiscoveryBoardEntry> entries;
  final String? subtitleKey;

  /// [AppLocale] key of the message shown by a [DiscoveryRowKind.notice] row.
  final String? noticeKey;

  /// Whether each card names the genre it was picked for.
  final bool showGenreCaptions;

  /// Set size shown at the end of the achievement heading; 0 hides it. Kept as
  /// a number rather than a formatted string because the row is built without
  /// a [BuildContext] to localize with.
  final int achievementCount;

  /// Whether the cursor can land here. Notices carry no game, so they are
  /// skipped by Up/Down rather than being a dead stop.
  bool get isFocusable => entries.isNotEmpty;
}

/// Builds the board's rows in display order.
///
/// The order is the storefront's, not the engine's: the hero leads, then the
/// widest shelf, then the two single-pick features.
List<DiscoveryRow> buildDiscoveryRows(DiscoveryBoard board) {
  final rows = <DiscoveryRow>[];

  final hero = board.heroEntry;
  if (hero != null) {
    rows.add(
      DiscoveryRow(
        kind: DiscoveryRowKind.hero,
        titleKey: AppLocale.discoveryGameOfTheWeek,
        icon: Symbols.local_fire_department_rounded,
        entries: [hero],
      ),
    );
  }

  final genres = board.genreEntries;
  if (genres.isNotEmpty) {
    rows.add(
      DiscoveryRow(
        kind: DiscoveryRowKind.shelf,
        titleKey: AppLocale.discoveryGenrePicks,
        icon: Symbols.category_rounded,
        entries: genres,
        showGenreCaptions: true,
      ),
    );
  }

  if (board.scrapeCoverageLow) {
    // The gate tripped: say why the section is missing rather than leaving a
    // gap the user cannot explain.
    rows.add(
      const DiscoveryRow(
        kind: DiscoveryRowKind.notice,
        titleKey: AppLocale.discoveryHiddenGem,
        icon: Symbols.diamond_rounded,
        noticeKey: AppLocale.discoveryNeedsScraping,
      ),
    );
  } else {
    final gem = board.hiddenGemEntry;
    if (gem != null) {
      rows.add(
        DiscoveryRow(
          kind: DiscoveryRowKind.shelf,
          titleKey: AppLocale.discoveryHiddenGem,
          icon: Symbols.diamond_rounded,
          entries: [gem],
          subtitleKey: AppLocale.discoveryHiddenGemSubtitle,
        ),
      );
    }
  }

  final achievement = board.achievementEntry;
  if (achievement != null) {
    rows.add(
      DiscoveryRow(
        kind: DiscoveryRowKind.shelf,
        titleKey: AppLocale.discoveryAchievementSpotlight,
        icon: Symbols.trophy_rounded,
        entries: [achievement],
        achievementCount: achievement.achievementCount,
      ),
    );
  }

  return rows;
}

/// The [AppLocale] key naming [bucket] on a shelf.
///
/// Lives here rather than beside [GenreBucket] so the bucket table itself stays
/// free of any Flutter or localization dependency and remains directly
/// unit-testable.
String genreBucketLabelKey(GenreBucket bucket) => switch (bucket) {
  GenreBucket.platform => AppLocale.genrePlatform,
  GenreBucket.rpg => AppLocale.genreRpg,
  GenreBucket.shooter => AppLocale.genreShooter,
  GenreBucket.fighting => AppLocale.genreFighting,
  GenreBucket.racing => AppLocale.genreRacing,
  GenreBucket.puzzle => AppLocale.genrePuzzle,
  GenreBucket.sports => AppLocale.genreSports,
  GenreBucket.adventure => AppLocale.genreAdventure,
  GenreBucket.strategy => AppLocale.genreStrategy,
  GenreBucket.simulation => AppLocale.genreSimulation,
  GenreBucket.action => AppLocale.genreAction,
  GenreBucket.arcade => AppLocale.genreArcade,
  GenreBucket.other => AppLocale.genreOther,
};

/// The scrolling board: hero on top, shelves below.
class DiscoveryStorefront extends StatefulWidget {
  const DiscoveryStorefront({
    super.key,
    required this.board,
    required this.rows,
    required this.fileProvider,
    required this.selectedRow,
    required this.selectedColumn,
    required this.onEntryTapped,
  });

  final DiscoveryBoard board;
  final List<DiscoveryRow> rows;
  final FileProvider fileProvider;
  final int selectedRow;
  final int selectedColumn;

  /// Fired by touch/mouse. The tap both moves the cursor and acts, matching
  /// what pressing A on that card would do.
  final void Function(int row, int column) onEntryTapped;

  @override
  State<DiscoveryStorefront> createState() => _DiscoveryStorefrontState();
}

class _DiscoveryStorefrontState extends State<DiscoveryStorefront> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _rowKeys = {};

  @override
  void didUpdateWidget(DiscoveryStorefront oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedRow != oldWidget.selectedRow) _scrollRowIntoView();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollRowIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _rowKeys[widget.selectedRow]?.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        // Keep the row a little below the header rather than flush against it.
        alignment: 0.1,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // constraints.maxWidth is already in logical pixels — the same space
        // .r resolves to — so these breakpoints are raw values. A .r here would
        // double-scale and pick the narrow layout on wide screens.
        final width = constraints.maxWidth;
        final cardWidth = width >= 900
            ? 128.r
            : width >= 640
            ? 108.r
            : 92.r;

        return SingleChildScrollView(
          controller: _scrollController,
          padding: EdgeInsets.symmetric(horizontal: 12.r),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Clears the global header, as every other tab does.
              SizedBox(height: 64.r),
              for (var i = 0; i < widget.rows.length; i++) ...[
                _buildRow(context, i, widget.rows[i], cardWidth),
                SizedBox(height: 14.r),
              ],
              // Clears the footer legend, which floats over the content.
              SizedBox(height: 48.r),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRow(
    BuildContext context,
    int index,
    DiscoveryRow row,
    double cardWidth,
  ) {
    final key = _rowKeys.putIfAbsent(index, GlobalKey.new);
    final isSelected = widget.selectedRow == index;

    if (row.kind == DiscoveryRowKind.hero) {
      return KeyedSubtree(
        key: key,
        child: DiscoveryHeroCard(
          entry: row.entries.first,
          isSelected: isSelected,
          fileProvider: widget.fileProvider,
          weekLabel: _weekLabel(context),
          onTap: () => widget.onEntryTapped(index, 0),
        ),
      );
    }

    return KeyedSubtree(
      key: key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(context, row),
          SizedBox(height: 6.r),
          if (row.kind == DiscoveryRowKind.notice)
            _buildNotice(context, row)
          else
            DiscoveryShelf(
              entries: row.entries,
              fileProvider: widget.fileProvider,
              isRowSelected: isSelected,
              selectedIndex: widget.selectedColumn,
              cardWidth: cardWidth,
              onCardTapped: (column) => widget.onEntryTapped(index, column),
              captionBuilder: row.showGenreCaptions
                  ? (entry) => _genreCaption(context, entry)
                  : null,
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, DiscoveryRow row) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(row.icon, size: 16.r, color: theme.colorScheme.primary),
        SizedBox(width: 8.r),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                row.titleKey.getString(context),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                  fontSize: 11.r,
                ),
              ),
              if (row.subtitleKey != null)
                Text(
                  row.subtitleKey!.getString(context),
                  style: TextStyle(
                    fontSize: 8.r,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
            ],
          ),
        ),
        if (row.achievementCount > 0)
          Text(
            AppLocale.discoveryAchievementsCount
                .getString(context)
                .replaceFirst('{count}', '${row.achievementCount}'),
            style: TextStyle(
              fontSize: 8.r,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.58),
            ),
          ),
      ],
    );
  }

  Widget _buildNotice(BuildContext context, DiscoveryRow row) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12.r, vertical: 14.r),
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.15),
          width: 1.r,
        ),
      ),
      child: Text(
        row.noticeKey!.getString(context),
        style: TextStyle(
          fontSize: 9.r,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
    );
  }

  String _genreCaption(BuildContext context, DiscoveryBoardEntry entry) {
    final bucket = entry.pick.genre;
    if (bucket == null) return '';
    return genreBucketLabelKey(bucket).getString(context);
  }

  /// The week the board belongs to, rendered from its own key.
  ///
  /// Formatted from the key rather than from `DateTime.now()` so it always
  /// names the week the picks are actually for, even if the board was built
  /// before midnight on a Sunday.
  String _weekLabel(BuildContext context) => AppLocale.discoveryWeekOf
      .getString(context)
      .replaceFirst('{date}', widget.board.weekKey);
}
