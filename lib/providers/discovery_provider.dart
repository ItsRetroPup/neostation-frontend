import 'package:flutter/foundation.dart';

import '../models/discovery_models.dart';
import '../services/discovery/discovery_service.dart';
import '../services/logger_service.dart';

/// Presentation state for the Discovery tab.
///
/// Owns nothing the database does not already hold: the board is rebuilt from
/// `user_discovery_picks` rather than cached across weeks, so a rollover, a
/// rescan or a re-roll from anywhere else all converge on the same answer.
class DiscoveryProvider extends ChangeNotifier {
  DiscoveryProvider({DiscoveryService service = const DiscoveryService()})
    : _service = service;

  final DiscoveryService _service;
  final _log = LoggerService.instance;

  DiscoveryBoard? _board;
  bool _loading = false;
  bool _failed = false;

  DiscoveryBoard? get board => _board;

  /// Whether a board is being computed. The first load runs a full library
  /// scan, so the tab shows a spinner rather than an empty storefront.
  bool get loading => _loading;

  /// Whether the last attempt threw. The tab offers a retry rather than
  /// pretending the library is empty.
  bool get failed => _failed;

  /// Whether a board has been produced at least once this session.
  bool get hasBoard => _board != null;

  /// Loads the board, reusing the one already in memory when it is still for
  /// the current week.
  ///
  /// [force] re-reads regardless, which is what a returning launch needs: play
  /// time changed while the game was running, and "never played" badges and the
  /// hero's eligibility both depend on it.
  Future<void> load({bool force = false}) async {
    if (_loading) return;
    if (!force &&
        _board != null &&
        _board!.weekKey == _service.currentWeekKey) {
      return;
    }

    _loading = true;
    _failed = false;
    notifyListeners();

    try {
      _board = await _service.loadBoard();
    } catch (e, stackTrace) {
      _failed = true;
      _log.e('DiscoveryProvider: failed to load the board: $e');
      _log.e('   StackTrace: $stackTrace');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Swaps the pick in [slotId] for a different game.
  ///
  /// The new pick is persisted, so it is what the tab shows for the rest of the
  /// week — including after a restart.
  Future<void> reroll(String slotId) async {
    if (_loading) return;

    _loading = true;
    notifyListeners();

    try {
      _board = await _service.reroll(slotId);
      _failed = false;
    } catch (e, stackTrace) {
      _log.e('DiscoveryProvider: failed to re-roll $slotId: $e');
      _log.e('   StackTrace: $stackTrace');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
