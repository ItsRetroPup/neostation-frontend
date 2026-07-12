import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/services/rom_folder_organizer_service.dart';

void main() {
  group('RomFolderOrganizerService', () {
    test('moves Disc files and existing m3u into a game folder', () async {
      final root = await Directory.systemTemp.createTemp(
        'neostation_organize_',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      final psxDir = Directory('${root.path}/psx')..createSync(recursive: true);

      final disc1 = File('${psxDir.path}/Final Fantasy VIII (Disc 1).chd')
        ..writeAsStringSync('disc1');
      final disc2 = File('${psxDir.path}/Final Fantasy VIII (Disc 2).chd')
        ..writeAsStringSync('disc2');
      final playlist = File('${psxDir.path}/Final Fantasy VIII.m3u')
        ..writeAsStringSync('old-entry.chd\n');

      expect(await disc1.exists(), isTrue);
      expect(await disc2.exists(), isTrue);
      expect(await playlist.exists(), isTrue);

      final result = await RomFolderOrganizerService.organizeRomFolders([
        root.path,
      ]);

      expect(result.groupsOrganized, 1);
      expect(result.foldersCreated, 1);
      expect(result.playlistsCreated, 0);

      final targetDir = Directory('${psxDir.path}/Final Fantasy VIII');
      final movedDisc1 = File(
        '${targetDir.path}/Final Fantasy VIII (Disc 1).chd',
      );
      final movedDisc2 = File(
        '${targetDir.path}/Final Fantasy VIII (Disc 2).chd',
      );
      final movedPlaylist = File('${targetDir.path}/Final Fantasy VIII.m3u');

      expect(await targetDir.exists(), isTrue);
      expect(await movedDisc1.exists(), isTrue);
      expect(await movedDisc2.exists(), isTrue);
      expect(await movedPlaylist.exists(), isTrue);

      final lines = await movedPlaylist.readAsLines();
      expect(lines, [
        'Final Fantasy VIII (Disc 1).chd',
        'Final Fantasy VIII (Disc 2).chd',
      ]);
    });

    test(
      'creates m3u when missing and matches Disk/CD naming patterns',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'neostation_organize_',
        );
        addTearDown(() async {
          if (await root.exists()) {
            await root.delete(recursive: true);
          }
        });

        final saturnDir = Directory('${root.path}/saturn')
          ..createSync(recursive: true);
        File(
          '${saturnDir.path}/Panzer Dragoon Saga - Disk 1.cue',
        ).writeAsStringSync('disk1');
        File(
          '${saturnDir.path}/Panzer Dragoon Saga - CD 2.cue',
        ).writeAsStringSync('disk2');

        final result = await RomFolderOrganizerService.organizeRomFolders([
          root.path,
        ]);

        expect(result.groupsOrganized, 1);
        expect(result.playlistsCreated, 1);

        final targetDir = Directory('${saturnDir.path}/Panzer Dragoon Saga');
        final playlist = File('${targetDir.path}/Panzer Dragoon Saga.m3u');

        expect(await targetDir.exists(), isTrue);
        expect(await playlist.exists(), isTrue);

        final lines = await playlist.readAsLines();
        expect(lines, [
          'Panzer Dragoon Saga - Disk 1.cue',
          'Panzer Dragoon Saga - CD 2.cue',
        ]);
      },
    );

    test('organizes multi-disc files found in nested subfolders', () async {
      final root = await Directory.systemTemp.createTemp(
        'neostation_organize_',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });

      final nestedDir = Directory('${root.path}/psx/collections/rpg')
        ..createSync(recursive: true);
      File('${nestedDir.path}/Suikoden II Disc 1.chd').writeAsStringSync('1');
      File('${nestedDir.path}/Suikoden II Disc 2.chd').writeAsStringSync('2');

      final result = await RomFolderOrganizerService.organizeRomFolders([
        root.path,
      ]);

      expect(result.groupsOrganized, 1);
      expect(
        await File('${nestedDir.path}/Suikoden II/Suikoden II.m3u').exists(),
        isTrue,
      );
    });

    test('skips m3u folders and everything inside them', () async {
      final root = await Directory.systemTemp.createTemp(
        'neostation_organize_',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });

      final playlistDir = Directory('${root.path}/already-organized.m3u/discs')
        ..createSync(recursive: true);
      File('${playlistDir.path}/Game Disc 1.chd').writeAsStringSync('1');
      File('${playlistDir.path}/Game Disc 2.chd').writeAsStringSync('2');

      final result = await RomFolderOrganizerService.organizeRomFolders([
        root.path,
      ]);

      expect(result.groupsOrganized, 0);
      expect(result.foldersCreated, 0);
      expect(
        await File('${playlistDir.path}/Game Disc 1.chd').exists(),
        isTrue,
      );
      expect(
        await File('${playlistDir.path}/Game Disc 2.chd').exists(),
        isTrue,
      );
    });
  });
}
