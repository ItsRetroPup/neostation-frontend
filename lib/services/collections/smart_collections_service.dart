import 'dart:convert';
import 'package:flutter/foundation.dart';
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
  final Map<String, Set<String>> collectionPaths;
  final Set<String> manualPaths;
  final Map<String, String> gameContent;
  final Object? libraryRevision;
  const CollectionsSnapshot(
    this.collections,
    this.memberPaths,
    this.nextBoundary, [
    this.collectionPaths = const {},
    this.manualPaths = const {},
    this.gameContent = const {},
    this.libraryRevision,
  ]);
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
      return a.displayTitle.toLowerCase().compareTo(
        b.displayTitle.toLowerCase(),
      );
    });
    return games;
  }

  static Future<CollectionsSnapshot> snapshot({
    Future<List<DatabaseGameModel>> Function()? readLibrary,
    CollectionsSnapshot? previous,
    bool libraryUnchanged = false,
    Object? libraryRevision,
  }) async {
    final collections = (await CollectionRepository.getCollections())
        .map(CollectionModel.fromJson)
        .toList();
    final manualByCollection =
        await CollectionRepository.getMemberPathsByCollection();
    final members = manualByCollection.values.expand((paths) => paths).toSet();
    if (previous != null &&
        libraryUnchanged &&
        (previous.nextBoundary == null ||
            previous.nextBoundary!.isAfter(DateTime.now())) &&
        setEquals(members, previous.manualPaths) &&
        previous.collections
            .where((c) => !c.isSmart)
            .every(
              (c) => setEquals(
                manualByCollection[c.id] ?? const {},
                previous.collectionPaths[c.id] ?? const {},
              ),
            ) &&
        listEquals(
          [
            for (final c in previous.collections)
              c.isSmart ? c.copyWith(gameCount: 0) : c,
          ],
          [
            for (final c in collections)
              c.isSmart ? c.copyWith(gameCount: 0) : c,
          ],
        )) {
      return previous;
    }
    final manualPaths = Set<String>.of(members);
    final smart = collections
        .where((c) => c.isSmart && c.rules != null)
        .toList();
    if (smart.isEmpty) {
      return CollectionsSnapshot(
        collections,
        members,
        null,
        manualByCollection,
        manualPaths,
        const {},
        libraryRevision,
      );
    }
    final games = await (readLibrary ?? library)();
    final evaluator = SmartCollectionEvaluator(DateTime.now());
    final pathsByCollection = {...manualByCollection};
    final computed = <String, int>{};
    for (final collection in smart) {
      final matches = games.where(
        (g) => evaluator.matches(g, collection.rules!),
      );
      final paths = matches.map((g) => g.romPath).toSet();
      pathsByCollection[collection.id] = paths;
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
      pathsByCollection,
      manualPaths,
      {for (final game in games) game.romPath: jsonEncode(game.toJson())},
      libraryRevision,
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

/// Provider-owned cache; every access checks the shared database for changes.
class SmartCollectionLibraryCache {
  Object? _revision;
  List<DatabaseGameModel>? _games;
  CollectionsSnapshot? _snapshot;
  Object? _snapshotRevision;

  Future<CollectionsSnapshot> snapshot() async {
    final revision = await GameRepository.smartLibraryRevision();
    final snapshot = await SmartCollectionsService.snapshot(
      readLibrary: library,
      previous: _snapshot,
      libraryUnchanged: revision == _snapshotRevision,
      libraryRevision: revision,
    );
    _snapshot = snapshot;
    _snapshotRevision = revision;
    return snapshot;
  }

  Future<List<DatabaseGameModel>> library() async {
    final revision = await GameRepository.smartLibraryRevision();
    if (_games != null && revision == _revision) return _games!;
    final games = await SmartCollectionsService.library();
    // Capture before the read: a concurrent write causes the next access to retry.
    _revision = revision;
    _games = games;
    return games;
  }
}
