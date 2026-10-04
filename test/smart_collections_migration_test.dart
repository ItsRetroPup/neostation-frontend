import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';

void main() {
  test(
    'v163 upgrades manual collections without changing data and is idempotent',
    () async {
      final db = sqlite3.openInMemory();
      addTearDown(db.close);
      db.execute(
        'CREATE TABLE user_collections (id TEXT PRIMARY KEY, name TEXT, image_path TEXT)',
      );
      db.execute(
        "INSERT INTO user_collections VALUES ('c', 'Classics', '/art/c.png')",
      );
      db.execute(
        'CREATE TABLE user_collection_items (collection_id TEXT, rom_path TEXT)',
      );
      db.execute(
        "INSERT INTO user_collection_items VALUES ('c', 'content://primary%3Aroms%2Fgame.zip')",
      );
      await SqliteMigrations.migrateToVersion(db, 163);
      await SqliteMigrations.migrateToVersion(db, 163);
      final row = db.select('SELECT * FROM user_collections').single;
      expect(row['collection_type'], 'manual');
      expect(row['rules_json'], isNull);
      expect(row['image_path'], '/art/c.png');
      expect(
        db.select('SELECT * FROM user_collection_items').single['rom_path'],
        'content://primary%3Aroms%2Fgame.zip',
      );
    },
  );

  test('fresh schema and partially migrated schema get both columns', () async {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    db.execute(SqliteMigrations.createUserCollectionsTableSql);
    await SqliteMigrations.migrateToVersion(db, 163);
    expect(
      db.select('PRAGMA table_info(user_collections)').map((r) => r['name']),
      containsAll(['collection_type', 'rules_json']),
    );
    db.execute('DROP TABLE user_collections');
    db.execute(
      "CREATE TABLE user_collections (id TEXT, collection_type TEXT DEFAULT 'manual')",
    );
    await SqliteMigrations.migrateToVersion(db, 163);
    expect(
      db.select('PRAGMA table_info(user_collections)').map((r) => r['name']),
      contains('rules_json'),
    );
  });
}
