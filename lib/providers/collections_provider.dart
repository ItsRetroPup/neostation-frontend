import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import '../services/collections/smart_collection_evaluator.dart';
import '../models/smart_collection_rules.dart';
import '../models/database_game_model.dart';
import '../services/collections/smart_collections_service.dart';

import '../models/collection_model.dart';
import '../models/game_model.dart';
import '../services/collections/collections_service.dart';

/// Holds the user's collections for the widget tree.
///
/// Two consumers depend on being notified: the systems carousel/grid (the
/// Collections card's game count) and the collections browser screen.
///
/// Every mutation writes through [CollectionsService] and then re-reads the
/// list, so the game counts stay honest without a second query per collection —
/// the listing query already computes them in one `GROUP BY`.
///
/// Nothing here is static. `subDisplay()` runs a second Flutter engine that
/// shares the SQLite file and nothing in memory, so a process-wide cache would
/// go stale the moment either engine wrote (CLAUDE.md, dual-display devices).
class CollectionsProvider extends ChangeNotifier with WidgetsBindingObserver {
  /// [isBusy] reports a long-running writer (a scrape) whose notifications
  /// would otherwise each trigger a library re-evaluation; while it is true
  /// refreshes are throttled to [_busyRefreshInterval] instead of 300 ms.
  CollectionsProvider({
    List<ChangeNotifier> sources = const [],
    bool Function()? isBusy,
    Future<CollectionsSnapshot> Function()? readSnapshot,
  }) : _sources = sources,
       _isBusy = isBusy,
       _snapshotReader = readSnapshot {
    WidgetsBinding.instance.addObserver(this);
    for (final source in _sources) {
      source.addListener(_scheduleRefresh);
    }
  }

  static const _busyRefreshInterval = Duration(seconds: 10);

  final _libraryCache = SmartCollectionLibraryCache();
  final Future<CollectionsSnapshot> Function()? _snapshotReader;
  final Map<String, int> _collectionRevisions = {};
  Map<String, Set<String>> _collectionPaths = const {};
  Map<String, String> _gameContent = const {};
  int collectionRevision(String id) => _collectionRevisions[id] ?? 0;

  final List<ChangeNotifier> _sources;
  final bool Function()? _isBusy;
  bool _wasBusy = false;
  Timer? _debounce;
  Timer? _boundaryTimer;
  bool _disposed = false;
  bool _pending = false;
  Future<void>? _loadFuture;
  int _revision = 0;
  int get revision => _revision;

  void _scheduleRefresh() {
    final busy = _isBusy?.call() ?? false;
    // Leave a pending throttled refresh alone so a steady stream of
    // notifications cannot keep pushing it back; the busy->idle edge below
    // still refreshes promptly once the work finishes.
    if (busy && _wasBusy && (_debounce?.isActive ?? false)) return;
    _wasBusy = busy;
    _debounce?.cancel();
    _debounce = Timer(
      busy ? _busyRefreshInterval : const Duration(milliseconds: 300),
      () => load(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) load();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _boundaryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    for (final source in _sources) {
      source.removeListener(_scheduleRefresh);
    }
    super.dispose();
  }

  Future<bool> _readSnapshot() async {
    final snapshot = await (_snapshotReader ?? _libraryCache.snapshot)();
    if (_disposed) return false;
    var changed = false;
    for (final collection in snapshot.collections) {
      final old = byId(collection.id);
      final paths = snapshot.collectionPaths[collection.id] ?? const <String>{};
      final contentChanged =
          collection.isSmart &&
          paths.any((path) => snapshot.gameContent[path] != _gameContent[path]);
      if (old != collection ||
          contentChanged ||
          !setEquals(
            _collectionPaths[collection.id],
            snapshot.collectionPaths[collection.id],
          )) {
        changed = true;
        _collectionRevisions.update(
          collection.id,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
    }
    for (final old in _collections) {
      if (!snapshot.collections.any((c) => c.id == old.id)) {
        changed = true;
        _collectionRevisions.update(
          old.id,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
    }
    if (!listEquals(_collections, snapshot.collections) ||
        !setEquals(_memberRomPaths, snapshot.memberPaths) ||
        _collectionPaths.length != snapshot.collectionPaths.length ||
        _collectionPaths.entries.any(
          (entry) =>
              !setEquals(entry.value, snapshot.collectionPaths[entry.key]),
        )) {
      changed = true;
    }
    if (changed) _revision++;
    _collections = snapshot.collections;
    _memberRomPaths = snapshot.memberPaths;
    _collectionPaths = snapshot.collectionPaths;
    _gameContent = snapshot.gameContent;
    _boundaryTimer?.cancel();
    if (snapshot.nextBoundary != null) {
      final delay = snapshot.nextBoundary!.difference(DateTime.now());
      _boundaryTimer = Timer(
        delay.isNegative ? Duration.zero : delay,
        () => load(),
      );
    }
    return changed;
  }

  List<CollectionModel> _collections = const [];
  bool _isLoading = false;
  bool _hasLoaded = false;

  /// Every `rom_path` that was filed in at least one manual collection.
  ///
  /// Held here so the games views can badge a row without a query per card.
  /// Refreshed with the list itself, which is exactly when membership can have
  /// changed from this engine.
  Set<String> _memberRomPaths = const {};

  /// Bumped whenever a collection's artwork file is replaced in place.
  ///
  /// Replacing a file at the same path changes no `ValueKey`, so widgets need a
  /// value that does change to force a repaint — the same reason
  /// `SystemInfo.imageVersion` exists.
  int _imageVersion = 0;
  int _publishedImageVersion = 0;

  /// The collections, ordered by `sort_order` then name.
  List<CollectionModel> get collections => List.unmodifiable(_collections);

  /// True while a [load] is in flight.
  bool get isLoading => _isLoading;

  /// True once the first [load] has completed, successfully or not.
  bool get hasLoaded => _hasLoaded;

  /// Games filed manually, counting a game once per manual collection.
  /// Smart matches retain per-card counts but do not inflate the home total.
  int get totalGameCount => _collections
      .where((c) => !c.isSmart)
      .fold(0, (sum, c) => sum + c.gameCount);

  /// Seeds [collections] without a database, so a test can pin what the counts
  /// derived from them mean. Not a general setter: nothing in the app may
  /// bypass [CollectionsService] to change state.
  @visibleForTesting
  void debugSetCollections(List<CollectionModel> collections) {
    _collections = List.unmodifiable(collections);
  }

  /// Cache-busting counter for collection artwork.
  int get imageVersion => _imageVersion;

  /// Whether [romPath] is filed in any collection.
  ///
  /// Membership of a *particular* collection still needs [collectionIdsFor];
  /// this answers only the question a badge asks.
  bool isInAnyCollection(String? romPath) =>
      romPath != null &&
      romPath.isNotEmpty &&
      _memberRomPaths.contains(romPath);

  /// Returns the collection with [id], or null if it is not loaded.
  CollectionModel? byId(String id) {
    for (final collection in _collections) {
      if (collection.id == id) return collection;
    }
    return null;
  }

  /// Re-reads every collection (and its game count) from the database.
  ///
  /// Concurrent callers await the current read and a queued follow-up snapshot.
  Future<void> load() {
    if (_disposed) return Future.value();
    if (_loadFuture != null) {
      _pending = true;
      return _loadFuture!;
    }
    // Defer the first read so the future is installed before notifications.
    final completer = Completer<void>();
    _loadFuture = completer.future;
    scheduleMicrotask(() async {
      await _load();
      completer.complete();
    });
    return completer.future;
  }

  Future<void> _load() async {
    if (_disposed) return;
    final initialLoad = !_hasLoaded;
    var changed = false;
    _isLoading = true;
    if (initialLoad) notifyListeners();
    try {
      do {
        _pending = false;
        changed = await _readSnapshot() || changed;
      } while (_pending && !_disposed);
    } catch (error) {
      // Preserve the last successful snapshot on transient database failure.
      debugPrint('Collection refresh failed: $error');
    } finally {
      _loadFuture = null;
      _isLoading = false;
      _hasLoaded = true;
      if (!_disposed &&
          (initialLoad || changed || _publishedImageVersion != _imageVersion)) {
        _publishedImageVersion = _imageVersion;
        notifyListeners();
      }
    }
  }

  /// Creates a collection and returns it, refreshing the list.
  Future<CollectionModel> create(
    String name, {
    String? imageSourcePath,
    SmartCollectionRules? rules,
  }) async {
    final created = await CollectionsService.createCollection(
      name,
      imageSourcePath: imageSourcePath,
      rules: rules,
    );
    await _refresh();
    return byId(created.id) ?? created;
  }

  Future<void> updateRules(String id, SmartCollectionRules rules) async {
    await CollectionsService.updateRules(id, rules);
    await _refresh();
  }

  Future<List<DatabaseGameModel>> ruleLibrary() => _libraryCache.library();

  List<DatabaseGameModel> previewRules(
    List<DatabaseGameModel> library,
    SmartCollectionRules? rules,
  ) {
    if (rules == null) return [];
    final evaluator = SmartCollectionEvaluator(DateTime.now());
    return library.where((game) => evaluator.matches(game, rules)).toList();
  }

  DateTime? previewBoundary(
    List<DatabaseGameModel> library,
    SmartCollectionRules? rules,
  ) => rules == null
      ? null
      : SmartCollectionEvaluator(DateTime.now()).nextBoundary(library, [rules]);

  /// Renames a collection and refreshes the list.
  Future<void> rename(String id, String name) async {
    await CollectionsService.renameCollection(id, name);
    await _refresh();
  }

  /// Deletes a collection (and its artwork) and refreshes the list.
  Future<void> delete(String id) async {
    await CollectionsService.deleteCollection(id);
    await _refresh();
  }

  /// Replaces a collection's artwork with a copy of [pickedFilePath].
  ///
  /// Bumps [imageVersion] on success so widgets keyed on it repaint even though
  /// the file path is unchanged.
  Future<String?> setImage(String id, String pickedFilePath) async {
    final target = await CollectionsService.setCollectionImage(
      id,
      pickedFilePath,
    );
    if (target != null) _imageVersion++;
    await _refresh();
    return target;
  }

  /// Clears a collection's artwork and bumps [imageVersion].
  Future<void> clearImage(String id) async {
    await CollectionsService.clearCollectionImage(id);
    _imageVersion++;
    await _refresh();
  }

  /// Adds [game] to a collection, refreshing the counts.
  Future<void> addGame(String collectionId, GameModel game) async {
    await CollectionsService.addGame(collectionId, game);
    await _refresh();
  }

  /// Removes [game] from a collection, refreshing the counts.
  Future<void> removeGame(String collectionId, GameModel game) async {
    await CollectionsService.removeGame(collectionId, game);
    await _refresh();
  }

  /// Toggles [game]'s membership and returns whether it is now a member.
  Future<bool> toggleGame(String collectionId, GameModel game) async {
    final isMember = await CollectionsService.toggleGame(collectionId, game);
    await _refresh();
    return isMember;
  }

  /// Returns the ids of the collections [game] belongs to.
  ///
  /// Read straight from the database rather than from [collections]: membership
  /// is not held in memory, and the second engine may have changed it.
  Future<Set<String>> collectionIdsFor(GameModel game) =>
      CollectionsService.collectionIdsFor(game);

  /// Re-reads after a mutation, queuing a fresh snapshot if a read is in flight.
  Future<void> _refresh() async {
    await load();
  }
}
