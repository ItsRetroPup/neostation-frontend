import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';
import 'package:neostation/models/config_model.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('primary display configuration', () {
    test('defaults to the device display and round-trips through JSON', () {
      const config = ConfigModel(primaryDisplay: 'secondary');

      expect(ConfigModel.empty.primaryDisplay, 'default');
      expect(ConfigModel.fromJson(config.toJson()).primaryDisplay, 'secondary');
      expect(
        ConfigModel.fromJson({'primary_display': 'secondary'}).primaryDisplay,
        'secondary',
      );
      expect(
        ConfigModel.fromJson({'primary_display': 'invalid'}).primaryDisplay,
        'default',
      );
    });

    test('migration v102 adds primary_display once', () async {
      final db = sqlite3.openInMemory();
      addTearDown(db.close);
      db.execute('CREATE TABLE user_config (id INTEGER PRIMARY KEY)');

      await SqliteMigrations.migrateToVersion(db, 102);
      await SqliteMigrations.migrateToVersion(db, 102);

      final columns = db.select('PRAGMA table_info(user_config)');
      expect(
        columns.where((column) => column['name'] == 'primary_display'),
        hasLength(1),
      );
    });
  });
}
