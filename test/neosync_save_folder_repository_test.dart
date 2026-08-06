import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/data/datasources/sqlite_service.dart';
import 'package:neostation/repositories/neosync_save_folder_repository.dart';

import 'database_test_helper.dart';

void main() {
  group('NeoSync custom save folders', () {
    final dbHelper = DatabaseTestHelper();

    setUp(() async => dbHelper.setUp());
    tearDown(() async => dbHelper.tearDown());

    test('returns null when no folder is configured for a system', () async {
      final folder = await NeoSyncSaveFolderRepository.getFolder('ps2');
      expect(folder, isNull);
    });

    test('persists and reads back a configured folder', () async {
      await NeoSyncSaveFolderRepository.saveFolder(
        'ps2',
        '/storage/emulated/0/ARMSX2',
      );

      final folder = await NeoSyncSaveFolderRepository.getFolder('ps2');
      expect(folder, '/storage/emulated/0/ARMSX2');
    });

    test('upserts on repeated saves for the same system', () async {
      await NeoSyncSaveFolderRepository.saveFolder('ps2', '/old/path');
      await NeoSyncSaveFolderRepository.saveFolder('ps2', '/new/path');

      final folder = await NeoSyncSaveFolderRepository.getFolder('ps2');
      expect(folder, '/new/path');
    });

    test('keeps separate folders for different systems', () async {
      await NeoSyncSaveFolderRepository.saveFolder('ps2', '/ps2/folder');
      await NeoSyncSaveFolderRepository.saveFolder('ps1', '/ps1/folder');

      final all = await NeoSyncSaveFolderRepository.getAllFolders();
      expect(all, {
        'ps2': '/ps2/folder',
        'ps1': '/ps1/folder',
      });
    });

    test('removes a configured folder', () async {
      await NeoSyncSaveFolderRepository.saveFolder('ps2', '/ps2/folder');
      await NeoSyncSaveFolderRepository.removeFolder('ps2');

      final folder = await NeoSyncSaveFolderRepository.getFolder('ps2');
      expect(folder, isNull);
    });
  });

  group('ROM folder persistence', () {
    final dbHelper = DatabaseTestHelper();

    setUp(() async => dbHelper.setUp());
    tearDown(() async => dbHelper.tearDown());

    test('deduplicates repeated paths instead of failing the UNIQUE constraint',
        () async {
      await SqliteService.saveUserRomFolders([
        'content://com.android.externalstorage.documents/tree/primary%3AROMs',
        'content://com.android.externalstorage.documents/tree/primary%3AROMs',
        '/storage/emulated/0/Games',
      ]);

      final folders = await SqliteService.getUserRomFolders();
      expect(folders, [
        'content://com.android.externalstorage.documents/tree/primary%3AROMs',
        '/storage/emulated/0/Games',
      ]);
    });

    test('replaces the existing folder list', () async {
      await SqliteService.saveUserRomFolders(['/old/folder']);
      await SqliteService.saveUserRomFolders(['/new/folder']);

      final folders = await SqliteService.getUserRomFolders();
      expect(folders, ['/new/folder']);
    });
  });
}
