import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/retro_achievements_game_info.dart';
import 'package:neostation/models/retro_achievements_leaderboard.dart';
import 'package:neostation/providers/retro_achievements_provider.dart';
import 'package:neostation/screens/game_screen/game_details_card/tabs/game_details_leaderboards_tab.dart';
import 'package:neostation/services/gamepad/gamepad_navigation_manager.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/utils/gamepad_nav.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

enum RaAchievementFilter { all, unlocked, locked, missable }

/// A ROM-independent RetroAchievements game view. It is intentionally keyed
/// by the RA game id so rows from the dashboard can open it even when the
/// player has not installed that game locally.
class RaGameAchievementsPage extends StatefulWidget {
  final int gameId;
  final String? fallbackTitle;
  final int? highlightAchievementId;

  const RaGameAchievementsPage({
    super.key,
    required this.gameId,
    this.fallbackTitle,
    this.highlightAchievementId,
  });

  @override
  State<RaGameAchievementsPage> createState() => _RaGameAchievementsPageState();
}

class _RaGameAchievementsPageState extends State<RaGameAchievementsPage> {
  final GlobalKey<GameDetailsLeaderboardsTabState> _leaderboardsKey =
      GlobalKey<GameDetailsLeaderboardsTabState>();
  final ScrollController _scrollController = ScrollController();
  GamepadNavigation? _gamepadNav;
  GameInfoAndUserProgress? _gameInfo;
  RaAchievementFilter _filter = RaAchievementFilter.all;
  int _selectedIndex = 0;
  bool _filterFocused = false;
  bool _headerFocused = false;
  int _headerActionIndex = 0;
  bool _leaderboardsView = false;
  bool _loading = true;
  String? _error;
  bool _requestInFlight = false;

  @override
  void initState() {
    super.initState();
    _gamepadNav = GamepadNavigation(
      onNavigateUp: _moveUp,
      onNavigateDown: _moveDown,
      onNavigateLeft: _moveLeft,
      onNavigateRight: _moveRight,
      onSelectItem: _activate,
      onBack: _handleBack,
      allowRepeat: false,
    )..initialize();
    GamepadNavigationManager.pushLayer(
      'ra_game_achievements',
      onActivate: () => _gamepadNav?.activate(),
      onDeactivate: () => _gamepadNav?.deactivate(),
    );
    unawaited(_load());
  }

  @override
  void dispose() {
    GamepadNavigationManager.popLayer('ra_game_achievements');
    _gamepadNav?.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    if (_requestInFlight) return;
    _requestInFlight = true;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final provider = context.read<RetroAchievementsProvider>();
    final info = await provider.getGameInfoAndUserProgress(
      widget.gameId,
      forceRefresh: forceRefresh,
    );
    if (!mounted) return;
    setState(() {
      _gameInfo = info;
      _loading = false;
      _error = info == null
          ? (provider.error ??
                AppLocale.raErrorGameInfoUnavailable.getString(context))
          : null;
      _selectedIndex = _initialIndex(info);
    });
    _requestInFlight = false;
  }

  int _initialIndex(GameInfoAndUserProgress? info) {
    if (info == null || widget.highlightAchievementId == null) return 0;
    final items = _filteredAchievements(info);
    final index = items.indexWhere(
      (a) => a.id == widget.highlightAchievementId,
    );
    return index < 0 ? 0 : index;
  }

  List<Achievement> _filteredAchievements(GameInfoAndUserProgress info) {
    final values = info.achievements.values.toList();
    values.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    return values.where(_matchesFilter).toList(growable: false);
  }

  bool _matchesFilter(Achievement achievement) {
    final unlocked = achievement.isUnlocked;
    switch (_filter) {
      case RaAchievementFilter.all:
        return true;
      case RaAchievementFilter.unlocked:
        return unlocked;
      case RaAchievementFilter.locked:
        return !unlocked;
      case RaAchievementFilter.missable:
        return achievement.isMissable;
    }
  }

  void _setFilter(RaAchievementFilter filter) {
    if (_filter == filter) return;
    final current = _selectedAchievement?.id;
    setState(() {
      _filter = filter;
      _selectedIndex = 0;
      final items = _gameInfo == null
          ? <Achievement>[]
          : _filteredAchievements(_gameInfo!);
      if (current != null) {
        final index = items.indexWhere((a) => a.id == current);
        if (index >= 0) _selectedIndex = index;
      }
    });
  }

  Achievement? get _selectedAchievement {
    final items = _gameInfo == null
        ? <Achievement>[]
        : _filteredAchievements(_gameInfo!);
    if (items.isEmpty) return null;
    return items[_selectedIndex.clamp(0, items.length - 1)];
  }

  void _moveUp() {
    if (_leaderboardsView) {
      _leaderboardsKey.currentState?.moveUp();
      return;
    }
    if (_headerFocused) return;
    if (_filterFocused) {
      setState(() {
        _filterFocused = false;
        _headerFocused = true;
      });
      return;
    }
    if (_selectedIndex == 0) {
      setState(() => _filterFocused = true);
      return;
    }
    setState(() => _selectedIndex--);
    _scrollToSelected();
  }

  void _moveDown() {
    if (_leaderboardsView) {
      _leaderboardsKey.currentState?.moveDown();
      return;
    }
    if (_headerFocused) {
      setState(() => _headerFocused = false);
      return;
    }
    if (_filterFocused) {
      setState(() => _filterFocused = false);
      return;
    }
    final items = _gameInfo == null
        ? <Achievement>[]
        : _filteredAchievements(_gameInfo!);
    if (_selectedIndex + 1 >= items.length) return;
    setState(() => _selectedIndex++);
    _scrollToSelected();
  }

  void _moveLeft() {
    if (_leaderboardsView) return;
    if (_headerFocused) {
      _moveHeaderAction(-1);
      return;
    }
    if (_filterFocused) {
      final values = RaAchievementFilter.values;
      final index =
          (values.indexOf(_filter) - 1 + values.length) % values.length;
      _setFilter(values[index]);
    }
  }

  void _moveRight() {
    if (_leaderboardsView) return;
    if (_headerFocused) {
      _moveHeaderAction(1);
      return;
    }
    if (_filterFocused) {
      final values = RaAchievementFilter.values;
      final index = (values.indexOf(_filter) + 1) % values.length;
      _setFilter(values[index]);
    }
  }

  List<String> get _headerActions => [
    'achievements',
    'leaderboards',
    if (_gameInfo?.guideUrl case final url? when _isHttpUrl(url)) 'guide',
    'refresh',
  ];

  void _moveHeaderAction(int delta) {
    final actions = _headerActions;
    setState(() {
      _headerActionIndex =
          (_headerActionIndex + delta + actions.length) % actions.length;
    });
  }

  void _activateHeaderAction() {
    final actions = _headerActions;
    final action = actions[_headerActionIndex.clamp(0, actions.length - 1)];
    switch (action) {
      case 'achievements':
        setState(() => _leaderboardsView = false);
      case 'leaderboards':
        setState(() => _leaderboardsView = true);
      case 'guide':
        final url = _gameInfo?.guideUrl;
        if (url != null && _isHttpUrl(url)) {
          unawaited(launchUrl(Uri.parse(url)));
        }
      case 'refresh':
        unawaited(_load(forceRefresh: true));
    }
  }

  void _activate() {
    if (_leaderboardsView) {
      final state = _leaderboardsKey.currentState;
      if (state != null && state.isPanelActive) {
        state.activateFocused();
      } else {
        state?.enterPanel();
      }
      return;
    }
    if (_headerFocused) {
      _activateHeaderAction();
      return;
    }
    if (_filterFocused) {
      setState(() => _filterFocused = false);
      return;
    }
    final achievement = _selectedAchievement;
    if (achievement != null) _showDetails(achievement);
  }

  void _handleBack() {
    if (_leaderboardsView) {
      final state = _leaderboardsKey.currentState;
      if (state?.exitPanel() == true) return;
      setState(() => _leaderboardsView = false);
      return;
    }
    if (_headerFocused) {
      setState(() => _headerFocused = false);
      return;
    }
    if (_filterFocused) {
      setState(() => _filterFocused = false);
      return;
    }
    Navigator.of(context).maybePop();
  }

  void _scrollToSelected() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      (_selectedIndex * 108.r).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
    );
  }

  Future<void> _showDetails(Achievement achievement) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(achievement.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(achievement.description),
            SizedBox(height: 10.r),
            Text(
              '${achievement.points} ${AppLocale.points.getString(context)} · ${_rarity(achievement) ?? '—'}',
            ),
            SizedBox(height: 4.r),
            Text(_unlockDates(context, achievement)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocale.close.getString(context)),
          ),
        ],
      ),
    );
  }

  String _imageUrl(String path) {
    if (path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return 'https://media.retroachievements.org$path';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = _gameInfo;
    final achievements = info == null
        ? <Achievement>[]
        : _filteredAchievements(info);
    if (_selectedIndex >= achievements.length && achievements.isNotEmpty) {
      _selectedIndex = achievements.length - 1;
    }
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(info?.title ?? widget.fallbackTitle ?? 'RetroAchievements'),
        leading: IconButton(
          tooltip: AppLocale.back.getString(context),
          onPressed: _handleBack,
          icon: const Icon(Symbols.arrow_back_rounded),
        ),
        actions: [
          if (info?.guideUrl case final url? when _isHttpUrl(url))
            IconButton(
              tooltip: AppLocale.raGuide.getString(context),
              onPressed: () => launchUrl(Uri.parse(url)),
              icon: const Icon(Symbols.menu_book_rounded),
            ),
          IconButton(
            tooltip: AppLocale.refresh.getString(context),
            onPressed: () => _load(forceRefresh: true),
            icon: const Icon(Symbols.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildGameHeader(context, info),
          _buildViewTabs(context),
          Expanded(
            child: _leaderboardsView
                ? _buildLeaderboards(context)
                : _buildAchievements(context, info, achievements),
          ),
        ],
      ),
    );
  }

  bool _isHttpUrl(String value) {
    final scheme = Uri.tryParse(value)?.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https';
  }

  Widget _buildGameHeader(BuildContext context, GameInfoAndUserProgress? info) {
    final theme = Theme.of(context);
    final total = info?.numAchievements ?? 0;
    final earned = info?.numAwardedToUser ?? 0;
    final earnedHardcore = info?.numAwardedToUserHardcore ?? 0;
    return Container(
      padding: EdgeInsets.all(12.r),
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          _boxArt(context, info?.imageBoxArt ?? ''),
          SizedBox(width: 12.r),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info?.title ?? widget.fallbackTitle ?? 'RetroAchievements',
                  style: theme.textTheme.titleMedium,
                ),
                if ((info?.consoleName ?? '').isNotEmpty)
                  Text(info!.consoleName, style: theme.textTheme.bodySmall),
                SizedBox(height: 6.r),
                Text(
                  '${AppLocale.achievements.getString(context)}: $earned/$total · ${AppLocale.raHardcore.getString(context)}: $earnedHardcore/$total',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _boxArt(BuildContext context, String path) {
    final url = _imageUrl(path);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8.r),
      child: SizedBox(
        width: 56.r,
        height: 70.r,
        child: url.isEmpty
            ? Icon(Symbols.videogame_asset_rounded, size: 28.r)
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, error, stack) =>
                    Icon(Symbols.videogame_asset_rounded, size: 28.r),
              ),
      ),
    );
  }

  Widget _buildViewTabs(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _viewTab(
            context,
            AppLocale.achievements.getString(context),
            !_leaderboardsView,
            () => setState(() => _leaderboardsView = false),
          ),
        ),
        Expanded(
          child: _viewTab(
            context,
            AppLocale.raSubtabLeaderboards.getString(context),
            _leaderboardsView,
            () => setState(() => _leaderboardsView = true),
          ),
        ),
      ],
    );
  }

  Widget _viewTab(
    BuildContext context,
    String label,
    bool selected,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () {
        SfxService().playNavSound();
        onTap();
      },
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 9.r),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? theme.colorScheme.primary : Colors.transparent,
              width: 2.r,
            ),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelLarge?.copyWith(
            color: selected ? theme.colorScheme.primary : null,
          ),
        ),
      ),
    );
  }

  Widget _buildAchievements(
    BuildContext context,
    GameInfoAndUserProgress? info,
    List<Achievement> achievements,
  ) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            TextButton(
              onPressed: _load,
              child: Text(AppLocale.retry.getString(context)),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        _buildFilters(context, info),
        Expanded(
          child: achievements.isEmpty
              ? Center(
                  child: Text(
                    AppLocale.raNoAchievementsForFilter.getString(context),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  itemCount: achievements.length,
                  itemBuilder: (context, index) => _achievementRow(
                    context,
                    achievements[index],
                    index == _selectedIndex,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildFilters(BuildContext context, GameInfoAndUserProgress? info) {
    final all = info?.achievements.values.toList() ?? <Achievement>[];
    final counts = <RaAchievementFilter, int>{
      RaAchievementFilter.all: all.length,
      RaAchievementFilter.unlocked: all.where((a) => a.isUnlocked).length,
      RaAchievementFilter.locked: all.where((a) => !a.isUnlocked).length,
      RaAchievementFilter.missable: all.where((a) => a.isMissable).length,
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: 12.r, vertical: 8.r),
      child: Row(
        children: [
          for (final filter in RaAchievementFilter.values)
            Padding(
              padding: EdgeInsets.only(right: 6.r),
              child: ChoiceChip(
                label: Text(
                  '${_filterLabel(context, filter)} ${counts[filter]}',
                ),
                selected: _filter == filter,
                onSelected: (_) => _setFilter(filter),
                side: BorderSide(
                  color: _filterFocused && _filter == filter
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _filterLabel(BuildContext context, RaAchievementFilter filter) =>
      switch (filter) {
        RaAchievementFilter.all => AppLocale.filterAll.getString(context),
        RaAchievementFilter.unlocked => AppLocale.unlocked.getString(context),
        RaAchievementFilter.locked => AppLocale.raFilterLocked.getString(
          context,
        ),
        RaAchievementFilter.missable => AppLocale.raFilterMissables.getString(
          context,
        ),
      };

  Widget _achievementRow(
    BuildContext context,
    Achievement achievement,
    bool selected,
  ) {
    final theme = Theme.of(context);
    final unlocked = achievement.isUnlocked;
    final rarity = _rarity(achievement);
    return InkWell(
      onTap: () {
        final index = _filteredAchievements(
          _gameInfo!,
        ).indexWhere((a) => a.id == achievement.id);
        setState(() => _selectedIndex = index < 0 ? 0 : index);
        _showDetails(achievement);
      },
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 12.r, vertical: 3.r),
        padding: EdgeInsets.all(8.r),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.14)
              : theme.cardColor.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: 0.6)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            _badge(context, achievement, unlocked),
            SizedBox(width: 10.r),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    achievement.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    achievement.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  SizedBox(height: 3.r),
                  Text(
                    _unlockDates(context, achievement),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall,
                  ),
                  SizedBox(height: 2.r),
                  Text(
                    '${achievement.points} ${AppLocale.points.getString(context)} · ${rarity ?? '—'}',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            Icon(
              unlocked ? Symbols.lock_open_rounded : Symbols.lock_rounded,
              size: 18.r,
              color: unlocked
                  ? theme.colorScheme.secondary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.45),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(BuildContext context, Achievement achievement, bool unlocked) {
    final name = achievement.badgeName.trim();
    final path = name.isEmpty
        ? ''
        : 'https://media.retroachievements.org/Badge/$name${unlocked ? '' : '_lock'}.png';
    return ClipRRect(
      borderRadius: BorderRadius.circular(6.r),
      child: SizedBox(
        width: 42.r,
        height: 42.r,
        child: path.isEmpty
            ? Icon(Symbols.emoji_events_rounded, size: 22.r)
            : Image.network(
                path,
                fit: BoxFit.cover,
                errorBuilder: (_, error, stack) =>
                    Icon(Symbols.emoji_events_rounded, size: 22.r),
              ),
      ),
    );
  }

  String _unlockDates(BuildContext context, Achievement achievement) {
    final dates = <String>[];
    final casual = achievement.dateEarned;
    final hardcore = achievement.dateEarnedHardcore;
    if (casual != null && casual.trim().isNotEmpty) {
      dates.add(
        '${AppLocale.raCasual.getString(context)}: ${_formatUnlockDate(casual)}',
      );
    }
    if (hardcore != null && hardcore.trim().isNotEmpty) {
      dates.add(
        '${AppLocale.raHardcore.getString(context)}: ${_formatUnlockDate(hardcore)}',
      );
    }
    return dates.isEmpty
        ? AppLocale.raFilterLocked.getString(context)
        : dates.join(' · ');
  }

  String _formatUnlockDate(String value) {
    final trimmed = value.trim();
    return trimmed.length > 10 ? trimmed.substring(0, 10) : trimmed;
  }

  String? _rarity(Achievement achievement) {
    final info = _gameInfo;
    if (info == null) return null;
    final casualRatio = info.numDistinctPlayersCasual > 0
        ? achievement.numAwarded / info.numDistinctPlayersCasual
        : null;
    final hardcoreRatio = info.numDistinctPlayersHardcore > 0
        ? achievement.numAwardedHardcore / info.numDistinctPlayersHardcore
        : null;
    String? format(double? ratio) => ratio == null
        ? null
        : '${(ratio * 100).toStringAsFixed(ratio < 0.01 ? 1 : 0)}%';
    final casual = format(casualRatio);
    final hardcore = format(hardcoreRatio);
    if (casual == null && hardcore == null) return null;
    if (hardcore == null || hardcore == casual) return casual;
    return 'C $casual · H $hardcore';
  }

  Widget _buildLeaderboards(BuildContext context) {
    final provider = context.read<RetroAchievementsProvider>();
    return Stack(
      fit: StackFit.expand,
      children: [
        GameDetailsLeaderboardsTab(
          key: _leaderboardsKey,
          gameId: widget.gameId,
          isConnected: provider.isConnected,
          loadGameLeaderboards: (id) async =>
              (await provider.getGameLeaderboards(id)) ??
              const RaGameLeaderboardsPage.empty(),
          loadLeaderboardEntries:
              (id, {required count, required offset}) async =>
                  (await provider.getLeaderboardEntries(
                    id,
                    count: count,
                    offset: offset,
                  )) ??
                  const RaLeaderboardEntriesPage.empty(),
          loadUserGameLeaderboards: (id) async =>
              (await provider.getUserGameLeaderboards(id)) ??
              const RaUserGameLeaderboardsPage.empty(),
          topOffset: 0,
          bottomOffset: 0,
        ),
      ],
    );
  }
}
