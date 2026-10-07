import '../services/credential_store.dart';
import '../services/logger_service.dart';

/// Repository for the user's SteamGridDB API key.
///
/// SteamGridDB is an optional, manual artwork source: there is no account to
/// sign in to, only a personal API key the user pastes in. It lives in
/// [CredentialStore] alongside the RetroAchievements key, never in SQLite.
class SteamGridDbRepository {
  static const String _apiKeyStorageKey = 'steamgriddb_api_key';

  static final _log = LoggerService.instance;

  /// Persists the API key, reporting where it ended up so the caller can tell
  /// the user when it will not survive a restart.
  static Future<CredentialWriteOutcome> saveApiKey(String apiKey) {
    return CredentialStore.write(_apiKeyStorageKey, apiKey);
  }

  /// Returns the stored API key, or null when none is set.
  ///
  /// An unreadable store also yields null. That is safe here, unlike for an
  /// account token: nothing deletes the key on a null read, so the worst case
  /// is SteamGridDB looking unset until the store answers again, instead of a
  /// settings page or an artwork row failing outright.
  static Future<String?> getApiKey() async {
    try {
      final key = await CredentialStore.read(_apiKeyStorageKey);
      return (key != null && key.trim().isNotEmpty) ? key.trim() : null;
    } on CredentialStoreException catch (e) {
      _log.w('SteamGridDB: could not read the API key: $e');
      return null;
    }
  }

  /// Removes the stored API key.
  static Future<void> clearApiKey() {
    return CredentialStore.delete(_apiKeyStorageKey);
  }
}
