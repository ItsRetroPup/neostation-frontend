import '../data/datasources/sqlite_service.dart';

/// Repository for the NeoSync module's per-system custom save folders.
///
/// Standalone emulators with relocatable data directories (ARMSX2, ARMSX1,
/// etc.) cannot be resolved from the system definitions alone. This repository
/// reads and persists the folder the user selects for each system in its own
/// dedicated table, keeping the NeoSync module's configuration separate from
/// the global [SqliteService] user config.
class NeoSyncSaveFolderRepository {
  static const _table = 'user_custom_save_folders';

  /// Returns the user-selected save folder for [systemFolderName], or null.
  static Future<String?> getFolder(String systemFolderName) async {
    final db = await SqliteService.getDatabase();
    final results = await db.query(
      _table,
      where: 'system_folder_name = ?',
      whereArgs: [systemFolderName],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return results.first['folder_path']?.toString();
  }

  /// Returns all configured save folders keyed by system folder name.
  static Future<Map<String, String>> getAllFolders() async {
    final db = await SqliteService.getDatabase();
    final results = await db.query(_table);
    return {
      for (final row in results)
        if (row['system_folder_name'] != null && row['folder_path'] != null)
          row['system_folder_name'].toString(): row['folder_path'].toString(),
    };
  }

  /// Persists the selected save folder for [systemFolderName], upserting.
  static Future<void> saveFolder(
    String systemFolderName,
    String folderPath,
  ) async {
    final db = await SqliteService.getDatabase();
    await db.insert(
      _table,
      {
        'system_folder_name': systemFolderName,
        'folder_path': folderPath,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Removes the configured save folder for [systemFolderName], if any.
  static Future<void> removeFolder(String systemFolderName) async {
    final db = await SqliteService.getDatabase();
    await db.delete(
      _table,
      where: 'system_folder_name = ?',
      whereArgs: [systemFolderName],
    );
  }
}
