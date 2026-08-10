import '../../models/database_game_model.dart';
import '../../models/discovery_models.dart';
import '../../repositories/discovery_repository.dart';
import '../../utils/genre_buckets.dart';
import '../../utils/week_key.dart';
import 'discovery_pick_engine.dart';

/// Assembles the weekly Discovery board: reads the library, keeps the picks
/// already made for this week, fills the gaps and persists the result.
///
/// Holds no state of its own. The board is cheap to recompute and expensive to
/// keep in sync, and the secondary Flutter engine shares no memory with this
/// one — everything that must survive lives in `user_discovery_picks`.
class DiscoveryService {
  const DiscoveryService({
    this.engine = const DiscoveryPickEngine(),
    DateTime Function()? clock,
  }) : _clock = clock;

  final DiscoveryPickEngine engine;

  /// Injectable clock, so week rollover is testable without touching the
  /// device clock.
  final DateTime Function()? _clock;

  /// Weeks of history a pick is avoided for after being shown.
  static const int _historyWeeks = 4;

  /// Weeks of picks kept before pruning.
  static const int _retentionWeeks = 8;

  DateTime get _now => (_clock ?? DateTime.now)();

  /// The ISO week the board is currently built for.
  String get currentWeekKey => isoWeekKey(_now);

  /// Builds this week's board, filling and persisting any missing slot.
  ///
  /// Picks already stored for the week are kept untouched, which is what makes
  /// the board identical across launches; only slots that are missing — or
  /// whose ROM has since been removed by a rescan — are chosen anew.
  Future<DiscoveryBoard> loadBoard() async {
    final weekKey = currentWeekKey;
    final rows = await DiscoveryRepository.getCandidates();
    if (rows.isEmpty) return DiscoveryBoard.empty(weekKey);

    final byPath = _indexByRomPath(rows);
    final candidates = rows.map(_toCandidate).toList();

    final pinned = await _resolvedPicks(weekKey, byPath);
    final history = await DiscoveryRepository.getPickPathsSince(
      weekKeyMinus(weekKey, _historyWeeks),
    );

    final plan = engine.buildPlan(
      candidates: candidates,
      weekKey: weekKey,
      recentPickPaths: history,
      pinned: pinned,
    );

    if (plan.newPicks.isNotEmpty) {
      await DiscoveryRepository.upsertPicks(plan.newPicks);
      await DiscoveryRepository.pruneBefore(
        weekKeyMinus(weekKey, _retentionWeeks),
      );
    }

    return _composeBoard(weekKey, plan, byPath);
  }

  /// Replaces the pick in [slotId] with a different game and persists it.
  ///
  /// The new pick is seeded on the incremented re-roll count, so it is both
  /// different from the current one and stable for the rest of the week —
  /// re-rolling then restarting the app shows the game the user rolled, not
  /// another one.
  ///
  /// Returns the rebuilt board. A slot with nothing left to offer keeps its
  /// current pick rather than emptying the section.
  Future<DiscoveryBoard> reroll(String slotId) async {
    final weekKey = currentWeekKey;
    final rows = await DiscoveryRepository.getCandidates();
    if (rows.isEmpty) return DiscoveryBoard.empty(weekKey);

    final byPath = _indexByRomPath(rows);
    final candidates = rows.map(_toCandidate).toList();
    final pinned = await _resolvedPicks(weekKey, byPath);

    final history = await DiscoveryRepository.getPickPathsSince(
      weekKeyMinus(weekKey, _historyWeeks),
    );

    final current = pinned[slotId];
    if (current != null) {
      // Every game already on the board is off limits, including the one being
      // replaced: a re-roll that returns the same pick reads as a broken button.
      final excluded = <String>{
        for (final pick in pinned.values) pick.romPath.toLowerCase(),
      };

      final replacement = engine.rerollSlot(
        slot: current.slot,
        candidates: candidates,
        weekKey: weekKey,
        rerollCount: current.rerollCount + 1,
        excludedPaths: excluded,
        recentPickPaths: history,
      );

      if (replacement != null) {
        await DiscoveryRepository.upsertPick(replacement);
        pinned[slotId] = replacement;
      }
    }

    final plan = engine.buildPlan(
      candidates: candidates,
      weekKey: weekKey,
      recentPickPaths: history,
      pinned: pinned,
    );
    if (plan.newPicks.isNotEmpty) {
      await DiscoveryRepository.upsertPicks(plan.newPicks);
    }

    return _composeBoard(weekKey, plan, byPath);
  }

  /// Reads the stored picks for [weekKey] and drops the ones whose ROM is gone.
  ///
  /// A pick is a bare `rom_path` with no foreign key, so a rescan that removes
  /// a game leaves a row pointing at nothing. Deleting it here lets the engine
  /// refill the slot on this same pass instead of leaving a hole.
  Future<Map<String, DiscoveryPick>> _resolvedPicks(
    String weekKey,
    Map<String, Map<String, Object?>> byPath,
  ) async {
    final stored = await DiscoveryRepository.getPicks(weekKey);
    final resolved = <String, DiscoveryPick>{};
    for (final entry in stored.entries) {
      if (byPath.containsKey(entry.value.romPath.toLowerCase())) {
        resolved[entry.key] = entry.value;
      } else {
        await DiscoveryRepository.deletePick(weekKey, entry.key);
      }
    }
    return resolved;
  }

  DiscoveryBoard _composeBoard(
    String weekKey,
    DiscoveryPlan plan,
    Map<String, Map<String, Object?>> byPath,
  ) {
    final entries = <DiscoveryBoardEntry>[];
    for (final pick in plan.picks) {
      final row = byPath[pick.romPath.toLowerCase()];
      if (row == null) continue;
      entries.add(
        DiscoveryBoardEntry(
          pick: pick,
          game: DatabaseGameModel.fromJson(row),
          achievementCount: (row['ra_num_achievements'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    return DiscoveryBoard(
      weekKey: weekKey,
      entries: entries,
      scrapeCoverageLow: plan.scrapeCoverageLow,
    );
  }

  /// Indexes candidate rows by lower-cased ROM path.
  ///
  /// Lower-cased because `rom_path` is `COLLATE NOCASE` in the database, so two
  /// spellings of the same path are the same row there and must be here too.
  /// The path itself is never parsed — on Android it is a SAF `content://` URI
  /// whose separators are URL-encoded.
  Map<String, Map<String, Object?>> _indexByRomPath(
    List<Map<String, Object?>> rows,
  ) {
    final byPath = <String, Map<String, Object?>>{};
    for (final row in rows) {
      final path = row['rom_path'] as String?;
      if (path != null && path.isNotEmpty) byPath[path.toLowerCase()] = row;
    }
    return byPath;
  }

  DiscoveryCandidate _toCandidate(Map<String, Object?> row) {
    final lastPlayedRaw = row['last_played'];
    return DiscoveryCandidate(
      romPath: (row['rom_path'] ?? '').toString(),
      systemFolderName: (row['system_folder_name'] ?? '').toString(),
      genre: genreBucketOf(row['genre'] as String?),
      rating: (row['rating'] as num?)?.toDouble(),
      lastPlayed: lastPlayedRaw == null
          ? null
          : DateTime.tryParse(lastPlayedRaw.toString()),
      playTimeSeconds: (row['play_time'] as num?)?.toInt() ?? 0,
      isFullyScraped: _isTrue(row['is_fully_scraped']),
      isFavorite: _isTrue(row['is_favorite']),
      achievementCount: (row['ra_num_achievements'] as num?)?.toInt() ?? 0,
      // Earned counts are not part of the local catalog: `app_ra_game_list` is
      // the set list, not the user's progress. Left unknown so the achievement
      // slot's "never started" rule degrades to "has a set" rather than
      // guessing.
      achievementsEarned: null,
    );
  }

  bool _isTrue(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().toLowerCase();
    return text == '1' || text == 'true';
  }
}
