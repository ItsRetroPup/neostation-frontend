import 'package:flutter_test/flutter_test.dart';
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
}
