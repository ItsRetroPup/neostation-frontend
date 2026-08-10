import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';

/// Tests for the two Discovery schema migrations, v175 (`user_discovery_picks`)
/// and v176 (`user_config.hide_tab_discovery`).
///
/// Both must be safe to re-run, because a device that already carries the
/// change — from another branch, or from a partially applied upgrade — runs
/// them again on the next launch.
///
/// The parity group guards the other half of the schema: `_onCreate` never runs
/// migrations, so a fresh install gets its tables from `_createUserTables`
/// alone. If that DDL and the migration drift apart, only brand new installs
/// break, and only at runtime.
void main() {
  late Database db;

  setUp(() {
    db = sqlite3.openInMemory();
  });

  tearDown(() {
    db.close();
  });

  Future<void> runV175() => SqliteMigrations.migrateToVersion(db, 175);
  Future<void> runV176() => SqliteMigrations.migrateToVersion(db, 176);

  void createUserConfig() {
    db.execute('''
      CREATE TABLE user_config (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        hide_tab_search INTEGER DEFAULT 0
      )
    ''');
  }

  List<String> columnsOf(String table) => db
      .select('PRAGMA table_info($table)')
      .map((row) => row['name'].toString())
      .toList();

  bool tableExists(String table) => db.select(
    "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
    [table],
  ).isNotEmpty;

  group('migration v175', () {
    test('creates the picks table with its full column set', () async {
      await runV175();

      expect(tableExists('user_discovery_picks'), isTrue);
      expect(columnsOf('user_discovery_picks'), [
        'week_key',
        'slot_id',
        'section',
        'genre_bucket',
        'slot_order',
        'rom_path',
        'reroll_count',
        'created_at',
      ]);
    });

    test('creates the week index', () async {
      await runV175();

      final indexes = db.select(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='user_discovery_picks'",
      );
      expect(
        indexes.map((row) => row['name']),
        contains('idx_user_discovery_picks_week'),
      );
    });

    test('week and slot together are the primary key', () async {
      await runV175();

      db.execute(
        "INSERT INTO user_discovery_picks (week_key, slot_id, section, rom_path) "
        "VALUES ('2026-W33', 'gotw', 'gameOfTheWeek', '/roms/a.sfc')",
      );
      // The same slot in another week is a different row...
      db.execute(
        "INSERT INTO user_discovery_picks (week_key, slot_id, section, rom_path) "
        "VALUES ('2026-W34', 'gotw', 'gameOfTheWeek', '/roms/b.sfc')",
      );
      // ...but the same slot in the same week replaces it, which is what makes
      // a re-roll a one-row write.
      db.execute(
        "INSERT OR REPLACE INTO user_discovery_picks (week_key, slot_id, section, rom_path) "
        "VALUES ('2026-W33', 'gotw', 'gameOfTheWeek', '/roms/c.sfc')",
      );

      final rows = db.select(
        'SELECT week_key, rom_path FROM user_discovery_picks ORDER BY week_key',
      );
      expect(rows.length, 2);
      expect(rows.first['rom_path'], '/roms/c.sfc');
    });

    test('rom_path compares case insensitively, like user_roms', () async {
      await runV175();

      db.execute(
        "INSERT INTO user_discovery_picks (week_key, slot_id, section, rom_path) "
        "VALUES ('2026-W33', 'gotw', 'gameOfTheWeek', '/roms/Game.sfc')",
      );

      final rows = db.select(
        "SELECT rom_path FROM user_discovery_picks WHERE rom_path = '/ROMS/GAME.SFC'",
      );
      expect(rows.length, 1);
    });

    test('re-running it changes nothing and keeps existing rows', () async {
      await runV175();
      db.execute(
        "INSERT INTO user_discovery_picks (week_key, slot_id, section, rom_path) "
        "VALUES ('2026-W33', 'gotw', 'gameOfTheWeek', '/roms/a.sfc')",
      );

      await runV175();

      expect(
        db.select('SELECT COUNT(*) AS n FROM user_discovery_picks').first['n'],
        1,
      );
    });

    test('an already present table is left alone', () async {
      // A device that got the table from somewhere else must not have it
      // rebuilt underneath its data.
      db.execute('''
        CREATE TABLE user_discovery_picks (
          week_key TEXT NOT NULL,
          slot_id TEXT NOT NULL,
          section TEXT NOT NULL,
          genre_bucket TEXT,
          slot_order INTEGER NOT NULL DEFAULT 0,
          rom_path TEXT NOT NULL COLLATE NOCASE,
          reroll_count INTEGER NOT NULL DEFAULT 0,
          created_at TEXT DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (week_key, slot_id)
        )
      ''');
      db.execute(
        "INSERT INTO user_discovery_picks (week_key, slot_id, section, rom_path) "
        "VALUES ('2026-W33', 'gotw', 'gameOfTheWeek', '/roms/kept.sfc')",
      );

      await runV175();

      final rows = db.select('SELECT rom_path FROM user_discovery_picks');
      expect(rows.single['rom_path'], '/roms/kept.sfc');
    });
  });

  group('migration v176', () {
    test('adds the hide_tab_discovery column, defaulting to visible', () async {
      createUserConfig();

      await runV176();

      expect(columnsOf('user_config'), contains('hide_tab_discovery'));
      db.execute('INSERT INTO user_config (id) VALUES (1)');
      expect(
        db
            .select('SELECT hide_tab_discovery FROM user_config')
            .first['hide_tab_discovery'],
        0,
      );
    });

    test('re-running it is a no-op and keeps the stored value', () async {
      createUserConfig();
      await runV176();
      db.execute(
        'INSERT INTO user_config (id, hide_tab_discovery) VALUES (1, 1)',
      );

      await runV176();

      expect(
        db
            .select('SELECT hide_tab_discovery FROM user_config')
            .first['hide_tab_discovery'],
        1,
      );
      expect(
        columnsOf('user_config').where((c) => c == 'hide_tab_discovery').length,
        1,
      );
    });

    test('a column that already exists is not added twice', () async {
      db.execute('''
        CREATE TABLE user_config (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          hide_tab_discovery INTEGER DEFAULT 0
        )
      ''');

      await runV176();

      expect(
        columnsOf('user_config').where((c) => c == 'hide_tab_discovery').length,
        1,
      );
    });
  });

  group('fresh install parity', () {
    // `_onCreate` never runs migrations, so these DDL strings are the only
    // thing a brand new database is built from. They are read from the source
    // rather than duplicated here: a copy would be one more thing to keep in
    // step, which is the very failure being guarded against.
    final source = File(
      'lib/data/datasources/sqlite_service.dart',
    ).readAsStringSync();

    String createTableDdl(String table) {
      final match = RegExp(
        'CREATE TABLE IF NOT EXISTS $table \\([\\s\\S]*?\\n\\s*\\);',
      ).firstMatch(source);
      expect(
        match,
        isNotNull,
        reason: 'no CREATE TABLE for $table in sqlite_service.dart',
      );
      return match!.group(0)!;
    }

    test('the fresh-install picks table matches the migrated one', () async {
      await runV175();
      final migrated = columnsOf('user_discovery_picks');

      final fresh = sqlite3.openInMemory();
      addTearDown(fresh.close);
      fresh.execute(createTableDdl('user_discovery_picks'));

      final freshColumns = fresh
          .select('PRAGMA table_info(user_discovery_picks)')
          .map((row) => row['name'].toString())
          .toList();

      expect(freshColumns, migrated);
    });

    test('the fresh-install picks table has the same key and collation', () async {
      final fresh = sqlite3.openInMemory();
      addTearDown(fresh.close);
      fresh.execute(createTableDdl('user_discovery_picks'));

      fresh.execute(
        "INSERT INTO user_discovery_picks (week_key, slot_id, section, rom_path) "
        "VALUES ('2026-W33', 'gotw', 'gameOfTheWeek', '/roms/Game.sfc')",
      );
      fresh.execute(
        "INSERT OR REPLACE INTO user_discovery_picks (week_key, slot_id, section, rom_path) "
        "VALUES ('2026-W33', 'gotw', 'gameOfTheWeek', '/roms/Other.sfc')",
      );

      expect(
        fresh
            .select('SELECT COUNT(*) AS n FROM user_discovery_picks')
            .first['n'],
        1,
      );
      expect(
        fresh
            .select(
              "SELECT rom_path FROM user_discovery_picks WHERE rom_path = '/ROMS/OTHER.SFC'",
            )
            .length,
        1,
      );
    });

    test('a fresh user_config already carries hide_tab_discovery', () async {
      final fresh = sqlite3.openInMemory();
      addTearDown(fresh.close);
      fresh.execute(createTableDdl('user_config'));

      final before = fresh
          .select('PRAGMA table_info(user_config)')
          .map((row) => row['name'].toString())
          .toList();
      expect(before, contains('hide_tab_discovery'));

      // Running the migration over the fresh schema must find nothing to do.
      await SqliteMigrations.migrateToVersion(fresh, 176);

      final after = fresh
          .select('PRAGMA table_info(user_config)')
          .map((row) => row['name'].toString())
          .toList();
      expect(after, before);
    });
  });
}
