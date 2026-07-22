import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/data/datasources/sqlite_service.dart';
import 'package:neostation/models/config_model.dart';

import 'database_test_helper.dart';

void main() {
  group('ARMSX2 NeoSync configuration', () {
    test('defaults to an empty data folder', () {
      expect(const ConfigModel().armsx2DataFolderPath, isEmpty);
    });

    test('preserves the configured folder through copy and JSON', () {
      const configured = ConfigModel(
        armsx2DataFolderPath: '/storage/emulated/0/ARMSX2',
      );

      expect(
        configured.copyWith().armsx2DataFolderPath,
        '/storage/emulated/0/ARMSX2',
      );
      expect(
        ConfigModel.fromJson(configured.toJson()).armsx2DataFolderPath,
        '/storage/emulated/0/ARMSX2',
      );
      expect(
        ConfigModel.fromJson({
          'armsx2_data_folder_path': '/storage/ABCD-1234/ARMSX2',
        }).armsx2DataFolderPath,
        '/storage/ABCD-1234/ARMSX2',
      );
    });

    group('SQLite persistence', () {
      final dbHelper = DatabaseTestHelper();

      setUp(() async => dbHelper.setUp());
      tearDown(() async => dbHelper.tearDown());

      test('persists the selected ARMSX2 data folder', () async {
        await SqliteService.saveUserConfig(
          armsx2DataFolderPath: '/storage/emulated/0/ARMSX2',
        );

        final config = await SqliteService.getUserConfig();
        expect(
          config?['armsx2_data_folder_path'],
          '/storage/emulated/0/ARMSX2',
        );
      });
    });
  });
}
