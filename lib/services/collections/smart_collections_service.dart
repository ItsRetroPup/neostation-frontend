import '../../models/collection_model.dart';
import '../../models/database_game_model.dart';
import '../../models/smart_collection_rules.dart';
import '../../repositories/collection_repository.dart';
import '../../repositories/game_repository.dart';
import 'smart_collection_evaluator.dart';

class CollectionsSnapshot {
  final List<CollectionModel> collections;
  final Set<String> memberPaths;
  final DateTime? nextBoundary;
  const CollectionsSnapshot(
    this.collections,
    this.memberPaths,
    this.nextBoundary,
  );
}

/// Stateless reads: separate Flutter engines always derive from persisted data.
class SmartCollectionsService {
  static Future<List<DatabaseGameModel>> library() async =>
      (await GameRepository.getAllGames())
          .where(SmartCollectionEvaluator.isEligible)
          .toList();

  static Future<List<DatabaseGameModel>> preview(
    SmartCollectionRules rules,
  ) async {
    final games = await library();
    final evaluator = SmartCollectionEvaluator(DateTime.now());
    return games.where((g) => evaluator.matches(g, rules)).toList();
  }

  static Future<List<DatabaseGameModel>> gamesFor(String id) async {
    final row = await CollectionRepository.getCollectionById(id);
    if (row == null) return [];
    final collection = CollectionModel.fromJson(row);
    if (!collection.isSmart) {
      return CollectionRepository.getGamesInCollection(id);
    }
    if (collection.rules == null) return [];
    final games = await preview(collection.rules!);
    games.sort((a, b) {
      if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
      return (a.realName ?? a.filename).toLowerCase().compareTo(
        (b.realName ?? b.filename).toLowerCase(),
      );
    });
    return games;
  }

  static Future<CollectionsSnapshot> snapshot() async {
    final collections = (await CollectionRepository.getCollections())
        .map(CollectionModel.fromJson)
        .toList();
    final members = await CollectionRepository.getCollectionMemberRomPaths();
    final smart = collections
        .where((c) => c.isSmart && c.rules != null)
        .toList();
    if (smart.isEmpty) return CollectionsSnapshot(collections, members, null);
    final games = await library();
    final evaluator = SmartCollectionEvaluator(DateTime.now());
    final computed = <String, int>{};
    for (final collection in smart) {
      final matches = games.where(
        (g) => evaluator.matches(g, collection.rules!),
      );
      final paths = matches.map((g) => g.romPath).toSet();
      computed[collection.id] = paths.length;
      members.addAll(paths);
    }
    return CollectionsSnapshot(
      [
        for (final c in collections)
          c.isSmart ? c.copyWith(gameCount: computed[c.id] ?? 0) : c,
      ],
      members,
      evaluator.nextBoundary(games, smart.map((c) => c.rules!)),
    );
  }

  /// [systemId] and [filename] let a single-row lookup stand in for loading the
  /// whole library; without them the library is scanned.
  static Future<Set<String>> collectionIdsFor(
    String romPath, {
    String? systemId,
    String? filename,
  }) async {
    final ids = (await CollectionRepository.getCollectionIdsForRom(
      romPath,
    )).toSet();
    final collections = (await CollectionRepository.getCollections())
        .map(CollectionModel.fromJson)
        .where((c) => c.isSmart)
        .toList();
    ids.removeAll(collections.map((c) => c.id));
    if (collections.isEmpty) return ids;
    Iterable<DatabaseGameModel> candidates;
    final single = systemId == null || filename == null
        ? null
        : await GameRepository.getSingleGame(systemId, filename);
    if (single != null && single.romPath == romPath) {
      candidates = SmartCollectionEvaluator.isEligible(single)
          ? [single]
          : const [];
    } else {
      candidates = (await library()).where((g) => g.romPath == romPath);
    }
    final evaluator = SmartCollectionEvaluator(DateTime.now());
    for (final c in collections) {
      if (c.rules != null &&
          candidates.any((g) => evaluator.matches(g, c.rules!))) {
        ids.add(c.id);
      }
    }
    return ids;
  }
}
