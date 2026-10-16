import 'dart:io';
import 'dart:isolate';

import 'package:koni_archive/io.dart';
import 'package:flutter_7zip/flutter_7zip.dart' as f7z;
import 'package:path/path.dart' as p;

import '../utils/safe_path.dart';
import 'logger_service.dart';

/// Installs downloaded ZIP/7z/RAR game archives while retaining companion files.
class RommArchiveService {
  /// RomM can stream a folder as ZIP while its list entry has neither an
  /// archive extension nor the multi-file flag. Identify the actual payload
  /// using only its header, so extraction does not depend on that metadata.
  static Future<String> ensureArchiveExtension(
    String downloadPath, {
    Set<String> extensions = const {},
    bool isMultiFile = false,
  }) async {
    final current = p
        .extension(downloadPath)
        .toLowerCase()
        .replaceFirst('.', '');
    if (!isMultiFile &&
        extensions.any(
          (ext) =>
              ext.toLowerCase().replaceFirst(RegExp(r'^\.'), '') == current,
        )) {
      return downloadPath;
    }
    final input = await File(downloadPath).open();
    final List<int> header;
    try {
      header = await input.read(8);
    } finally {
      await input.close();
    }
    bool startsWith(List<int> signature) =>
        header.length >= signature.length &&
        List.generate(
          signature.length,
          (i) => header[i] == signature[i],
        ).every((matches) => matches);
    final String? extension;
    if (startsWith([0x50, 0x4b, 0x03, 0x04]) ||
        startsWith([0x50, 0x4b, 0x05, 0x06]) ||
        startsWith([0x50, 0x4b, 0x07, 0x08])) {
      extension = '.zip';
    } else if (startsWith([0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c])) {
      extension = '.7z';
    } else if (startsWith([0x52, 0x61, 0x72, 0x21, 0x1a, 0x07, 0x00]) ||
        startsWith([0x52, 0x61, 0x72, 0x21, 0x1a, 0x07, 0x01, 0x00])) {
      extension = '.rar';
    } else {
      extension = null;
    }
    if (extension == null ||
        p.extension(downloadPath).toLowerCase() == extension) {
      return downloadPath;
    }
    final target = '$downloadPath$extension';
    await File(downloadPath).rename(target);
    return target;
  }

  static String gameFolderName(String name) =>
      {'.zip', '.7z', '.rar'}.contains(p.extension(name).toLowerCase())
      ? p.basenameWithoutExtension(name)
      : name;

  static Future<String?> prepareGameDownload(
    String archivePath,
    String systemDir,
    String gameName,
    Set<String> extensions, {
    bool isMultiFile = false,
    bool scummVm = false,
    bool reuseExistingDirectory = false,
    String? playlistName,
  }) async {
    final ext = p.extension(archivePath).toLowerCase();
    if (scummVm) {
      return prepareScummVmDownload(
        archivePath,
        systemDir,
        reuseExistingDirectory: reuseExistingDirectory,
      );
    }
    final folderName = gameFolderName(gameName);
    if (!isSafeFileName(folderName)) return null;
    final exts = extensions
        .map((ext) => ext.toLowerCase().replaceFirst(RegExp(r'^\.'), ''))
        .toSet();
    final forceExtract = ext == '.zip' && isMultiFile && exts.contains('m3u');
    if (exts.contains(ext.replaceFirst('.', '')) && !forceExtract) {
      await File(
        archivePath,
      ).rename(p.join(systemDir, p.basename(archivePath)));
      return p.basename(archivePath);
    }
    return prepareDownload(
      archivePath,
      reuseExistingDirectory ? systemDir : p.join(systemDir, folderName),
      exts,
      // A self-contained ROM needs no game folder, even inside a wrapper.
      singleFileDir: systemDir,
      forceExtract: forceExtract,
      gameName: folderName,
      playlistBaseName:
          playlistName != null && p.extension(playlistName) == '.m3u'
          ? p.basenameWithoutExtension(playlistName)
          : folderName,
    );
  }

  static Future<String?> prepareScummVmDownload(
    String downloadPath,
    String destDir, {
    bool reuseExistingDirectory = false,
  }) async {
    final ext = p.extension(downloadPath).toLowerCase();
    if ({'.zip', '.7z', '.rar'}.contains(ext)) {
      // A known target folder must not become target/target on re-download.
      final result = await prepareDownload(
        downloadPath,
        reuseExistingDirectory ? p.dirname(destDir) : destDir,
        {'scummvm'},
        scummVm: true,
      );
      if (result != null) return result;
    } else if (ext == '.scummvm') {
      final id = (await File(
        downloadPath,
      ).readAsString()).replaceFirst(RegExp(r'^\uFEFF'), '').trim();
      if (RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_-]*$').hasMatch(id)) {
        final root = reuseExistingDirectory ? p.dirname(destDir) : destDir;
        final target = p.join(root, id, p.basename(downloadPath));
        await _checkTarget(root, target, downloadPath);
        await File(target).parent.create(recursive: true);
        await File(downloadPath).rename(target);
        return p.basename(target);
      }
    }
    // Descriptor-less ScummVM downloads historically remain usable as-is.
    final target = p.join(destDir, p.basename(downloadPath));
    if (!p.equals(target, downloadPath)) {
      await File(downloadPath).rename(target);
    }
    return p.basename(downloadPath);
  }

  /// Extracts [archivePath] into [destDir] and returns the name to index, or
  /// null when it holds nothing playable or fails verification. When the
  /// archive holds exactly one self-contained game file and [singleFileDir]
  /// is set, that file is installed there directly instead. [gameName] helps
  /// pick a bundle's base game over its updates and DLC.
  static Future<String?> prepareDownload(
    String archivePath,
    String destDir,
    Set<String> extensions, {
    bool scummVm = false,
    String? singleFileDir,
    bool forceExtract = false,
    String? gameName,
    String? playlistBaseName,
  }) async {
    final exts = extensions
        .map((ext) => ext.toLowerCase().replaceFirst(RegExp(r'^\.'), ''))
        .toSet();
    final format = p.extension(archivePath).toLowerCase().substring(1);
    if (!scummVm && !forceExtract && exts.contains(format)) {
      return p.basename(archivePath);
    }
    try {
      // Decoding large/solid archives must not block gamepad input or progress UI.
      return await Isolate.run(
        () => _extract(
          archivePath,
          destDir,
          exts,
          scummVm,
          singleFileDir,
          gameName,
          playlistBaseName,
        ),
      );
    } catch (e, st) {
      LoggerService.instance.e(
        'RomM archive extraction failed for $archivePath',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  /// Solid 7z folders up to this size decode in Dart, which buffers the
  /// folder in memory; larger ones go to the native SDK. Kept low because
  /// handhelds have little RAM to spare next to a running frontend.
  static const int _dartSevenZipLimit = 256 << 20;

  static Future<String?> _extract(
    String archivePath,
    String destDir,
    Set<String> exts,
    bool scummVm,
    String? singleFileDir,
    String? gameName,
    String? playlistBaseName,
  ) async {
    final archive = await openArchiveFile(
      archivePath,
      // Make the 7z decoder's solid-folder cap a typed size-limit error, so
      // the native fallback below can handle larger solid folders.
      options: p.extension(archivePath).toLowerCase() == '.7z'
          ? const ArchiveReadOptions(maxContainerDecodeSize: _dartSevenZipLimit)
          : const ArchiveReadOptions(),
    );
    Directory? staging;
    f7z.SZArchive? nativeSevenZ;
    Map<String, int>? nativeIndices;
    var closed = false;
    try {
      final entries = archive.entries;
      // Inspect the raw index: the VFS view hides duplicate paths.
      final seen = <String>{};
      for (final entry in entries) {
        if (entry.pathEscapedRoot ||
            (!entry.isFile && !entry.isDirectory) ||
            safeJoin(destDir, entry.path) == null ||
            !seen.add(entry.path.toLowerCase())) {
          throw const FormatException('Unsafe or duplicate archive entry');
        }
      }
      final files = entries.where((entry) => entry.isFile).toList();
      final playable = files.where((entry) {
        final ext = _ext(entry.path);
        return scummVm ? ext == 'scummvm' : exts.contains(ext);
      }).toList();
      if (playable.isEmpty ||
          (!scummVm && playable.every((entry) => _ext(entry.path) == 'm3u'))) {
        return null;
      }
      playable.sort((a, b) {
        final order = _priority(a.path).compareTo(_priority(b.path));
        return order != 0 ? order : a.path.compareTo(b.path);
      });
      final flattenSingleFile =
          !scummVm &&
          singleFileDir != null &&
          files.length == 1 &&
          playable.length == 1 &&
          !{'m3u', 'cue', 'scummvm'}.contains(_ext(files.single.path));
      if (flattenSingleFile) destDir = singleFileDir;

      // Verify/decompress the whole download before replacing library files.
      // Stage beside the archive (the download destination), not in the system
      // temp dir: on Android that is internal storage, which can't hold a
      // multi-GB extraction when the ROMs live on an SD card. A hidden folder
      // on the same volume also lets the final step rename instead of copy.
      staging = await Directory(
        p.dirname(archivePath),
      ).createTemp('.romm_archive_');
      for (final entry in files) {
        final output = File(safeJoin(staging.path, entry.path)!);
        await output.parent.create(recursive: true);
        if (nativeSevenZ == null) {
          try {
            final sink = output.openWrite();
            try {
              await sink.addStream(archive.openRead(entry));
              await sink.flush();
            } finally {
              await sink.close();
            }
            continue;
          } on SizeLimitExceededException {
            if (p.extension(archivePath).toLowerCase() != '.7z') rethrow;
            // The Dart decoder caps a solid 7z folder. Use the existing native
            // SDK for large DVD ROMs instead of rejecting them.
            nativeSevenZ = f7z.SZArchive.open(archivePath);
            nativeIndices = {};
            for (var i = 0; i < nativeSevenZ.numFiles; i++) {
              final file = nativeSevenZ.getFile(i);
              if (!file.isDirectory) {
                nativeIndices[normalizeEntryPath(file.name).path] = i;
              }
            }
          }
        }
        final index = nativeIndices![entry.path];
        if (index == null) {
          throw const FormatException('7z entry missing from native index');
        }
        nativeSevenZ.extractToFile(index, output.path);
      }

      var targetDir = destDir;
      var stripWrapper = files.every((entry) {
        final segments = entry.path.split('/');
        return segments.length > 1 && segments.first == p.basename(destDir);
      });
      // A bundle's launch file is its base game, not an update or DLC that
      // happens to sort first.
      final launch = [...playable]
        ..sort((a, b) => _compareLaunch(a.path, b.path, gameName));
      var indexedName = p.basename(launch.first.path);
      if (scummVm) {
        final descriptor = File(safeJoin(staging.path, playable.first.path)!);
        final id = (await descriptor.readAsString())
            .replaceFirst(RegExp(r'^﻿'), '')
            .trim();
        if (!RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_-]*$').hasMatch(id)) {
          return null;
        }
        indexedName = p.basename(playable.first.path);
        targetDir = p.join(destDir, id);
        final firstSegments = files
            .map((entry) => entry.path.split('/').first)
            .toSet();
        stripWrapper =
            firstSegments.length == 1 &&
            files.every((entry) => entry.path.contains('/'));
      }
      final outputs = <ArchiveEntry, String>{};
      for (final entry in files) {
        final relative = flattenSingleFile
            ? p.posix.basename(entry.path)
            : stripWrapper
            ? entry.path.split('/').skip(1).join('/')
            : entry.path;
        final target = safeJoin(targetDir, relative)!;
        await _checkTarget(destDir, target, archivePath);
        outputs[entry] = target;
      }

      String? playlistPath;
      String? playlist;
      if (!scummVm && !flattenSingleFile && exts.contains('m3u')) {
        final companions = await _companions(playable, staging.path);
        final discs =
            playable
                .where(
                  (entry) =>
                      _ext(entry.path) != 'm3u' &&
                      !companions.contains(entry.path.toLowerCase()),
                )
                .toList()
              ..sort((a, b) => a.path.compareTo(b.path));
        String listing(String from) =>
            '${discs.map((entry) => p.relative(outputs[entry]!, from: from).replaceAll('\\', '/')).join('\n')}\n';
        if (_ext(launch.first.path) == 'm3u') {
          // Keep a bundled playlist only while every line still names an
          // installed file; wrapper stripping and absolute paths break it.
          final bundled = launch.first;
          playlistPath = outputs[bundled]!;
          final contents = await File(
            safeJoin(staging.path, bundled.path)!,
          ).readAsString();
          playlist =
              _resolvePlaylist(
                contents,
                p.dirname(playlistPath),
                outputs.values.toList(),
              ) ??
              (discs.isEmpty ? null : listing(p.dirname(playlistPath)));
          if (playlist == null) return null;
          if (playlist == contents) playlistPath = null;
        } else {
          indexedName =
              '${playlistBaseName ?? p.basenameWithoutExtension(archivePath)}.m3u';
          playlistPath = p.join(destDir, indexedName);
          await _checkTarget(destDir, playlistPath, archivePath);
          if (outputs.values.any((target) => p.equals(target, playlistPath!))) {
            return null;
          }
          playlist = listing(destDir);
        }
      }
      // Close once before committing, so reader failures cannot leave a
      // successfully installed game reported as failed.
      closed = true;
      await archive.close();
      final stagedOutputs = <String, String>{
        for (final entry in files)
          outputs[entry]!: safeJoin(staging.path, entry.path)!,
      };
      if (playlistPath != null) {
        final generated = await Directory(
          staging.path,
        ).createTemp('.playlist_');
        final stagedPlaylist = p.join(generated.path, 'playlist');
        await File(stagedPlaylist).writeAsString(playlist!, flush: true);
        stagedOutputs[playlistPath] = stagedPlaylist;
      }
      await _install(stagedOutputs, staging.path, destDir, archivePath);
      return indexedName;
    } finally {
      nativeSevenZ?.dispose();
      if (!closed) await archive.close();
      await staging?.delete(recursive: true);
    }
  }

  static String _ext(String path) =>
      p.extension(path).toLowerCase().replaceFirst('.', '');

  /// Playlists first, then disc descriptors, then everything else.
  static int _priority(String path) => switch (_ext(path)) {
    'm3u' => 0,
    'cue' || 'ccd' || 'gdi' || 'mds' || 'toc' => 1,
    _ => 2,
  };

  static final _addOnFolder = RegExp(
    r'^(dlcs?|updates?|patch(es)?|add-?ons?)$',
    caseSensitive: false,
  );
  static final _addOnTag = RegExp(
    r'[\[(](dlc|upd|update|patch)[\])]|\[v(?!0\])\d+\]',
    caseSensitive: false,
  );

  /// Orders a bundle's playable entries so the base game comes first:
  /// playlists/descriptors, then entries outside DLC/update folders and
  /// without update tags, then names matching [gameName], then shallower
  /// paths.
  static int _compareLaunch(String a, String b, String? gameName) {
    int addOn(String path) {
      final segments = path.split('/');
      return segments.take(segments.length - 1).any(_addOnFolder.hasMatch) ||
              _addOnTag.hasMatch(segments.last)
          ? 1
          : 0;
    }

    int named(String path) {
      if (gameName == null || gameName.isEmpty) return 0;
      final stem = p.posix.basenameWithoutExtension(path).toLowerCase();
      return stem.startsWith(gameName.toLowerCase()) ? 0 : 1;
    }

    for (final order in [
      _priority(a).compareTo(_priority(b)),
      addOn(a).compareTo(addOn(b)),
      named(a).compareTo(named(b)),
      a.split('/').length.compareTo(b.split('/').length),
    ]) {
      if (order != 0) return order;
    }
    return a.compareTo(b);
  }

  /// Lower-cased archive paths of the data files each disc descriptor
  /// references, so they are not listed as discs of their own. An ISO
  /// belonging to another disc stays in a mixed-format playlist.
  static Future<Set<String>> _companions(
    List<ArchiveEntry> playable,
    String staging,
  ) async {
    final companions = <String>{};
    void add(ArchiveEntry descriptor, String name) => companions.add(
      p.posix
          .normalize(
            p.posix.join(
              p.posix.dirname(descriptor.path),
              name.replaceAll('\\', '/'),
            ),
          )
          .toLowerCase(),
    );
    for (final entry in playable) {
      final stem = p.posix.withoutExtension(entry.path).toLowerCase();
      final RegExp references;
      switch (_ext(entry.path)) {
        case 'ccd':
          companions.addAll({'$stem.img', '$stem.sub'});
          continue;
        case 'mds':
          companions.add('$stem.mdf');
          continue;
        case 'cue' || 'toc':
          references = RegExp(
            r'^\s*(?:FILE|DATAFILE|AUDIOFILE)\s+(?:"([^"]+)"|([^\s]+))',
            caseSensitive: false,
            multiLine: true,
          );
        case 'gdi':
          // `track lba type sector-size file offset`; the first line is the
          // track count and has no file field.
          references = RegExp(
            r'^[ \t]*\d+[ \t]+\d+[ \t]+\d+[ \t]+\d+[ \t]+(?:"([^"]+)"|(\S+))',
            multiLine: true,
          );
        default:
          continue;
      }
      final descriptor = await File(
        safeJoin(staging, entry.path)!,
      ).readAsString();
      for (final reference in references.allMatches(descriptor)) {
        add(entry, reference.group(1) ?? reference.group(2)!);
      }
    }
    return companions;
  }

  /// [contents] with every entry pointing at one of [installed], relative to
  /// [playlistDir]; null when an entry matches no installed file. Entries
  /// that only match by basename (wrapper-prefixed or absolute) are
  /// rewritten.
  static String? _resolvePlaylist(
    String contents,
    String playlistDir,
    List<String> installed,
  ) {
    final lines = <String>[];
    var entries = 0;
    for (final raw
        in contents.replaceFirst(RegExp(r'^﻿'), '').split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) {
        lines.add(raw);
        continue;
      }
      entries++;
      final reference = line.replaceAll('\\', '/');
      final absolute =
          reference.startsWith('/') ||
          RegExp(r'^[A-Za-z]:/').hasMatch(reference);
      if (!absolute &&
          installed.any(
            (path) => p.equals(path, p.join(playlistDir, reference)),
          )) {
        lines.add(raw);
        continue;
      }
      final name = p.posix.basename(reference).toLowerCase();
      final matches = installed
          .where((path) => p.basename(path).toLowerCase() == name)
          .toList();
      if (matches.length != 1) return null;
      lines.add(
        p.relative(matches.single, from: playlistDir).replaceAll('\\', '/'),
      );
    }
    if (entries == 0) return null;
    final resolved = lines.join('\n');
    return contents.endsWith('\n') || resolved.endsWith('\n')
        ? resolved
        : '$resolved\n';
  }

  /// Roll back replacements if any install operation fails. The archive is
  /// consumed only after every output has been installed successfully.
  static Future<void> _install(
    Map<String, String> outputs,
    String staging,
    String root,
    String archivePath,
  ) async {
    final backups = <String, String>{};
    final installed = <String>[];
    final createdDirs = <String>[];
    final backupDir = await Directory(staging).createTemp('.backups_');
    try {
      for (final output in outputs.entries) {
        await _checkTarget(root, output.key, archivePath);
        final target = File(output.key);
        var parent = target.parent;
        final missing = <String>[];
        while (!await parent.exists()) {
          missing.add(parent.path);
          parent = parent.parent;
        }
        for (final path in missing.reversed) {
          await Directory(path).create();
          createdDirs.add(path);
        }
        if (await target.exists()) {
          final backup = p.join(backupDir.path, '${backups.length}');
          await target.rename(backup);
          backups[output.key] = backup;
        }
        await File(output.value).rename(output.key);
        installed.add(output.key);
      }
      await File(archivePath).delete();
    } catch (_) {
      for (final path in installed.reversed) {
        await File(path).delete();
      }
      for (final backup in backups.entries) {
        await File(backup.value).rename(backup.key);
      }
      for (final path in createdDirs.reversed) {
        await Directory(path).delete();
      }
      rethrow;
    }
  }

  static Future<void> _checkTarget(
    String root,
    String target,
    String archivePath,
  ) async {
    if (p.equals(target, archivePath)) {
      throw const FormatException('Archive would overwrite itself');
    }
    if (await FileSystemEntity.type(target, followLinks: false) ==
        FileSystemEntityType.directory) {
      throw const FormatException('Archive target is a directory');
    }
    // Only links below [root] can come from archive entries. The root and its
    // parents are the user's own layout: EmuDeck links `roms/gc` to
    // `roms/gamecube`, and libraries are often linked to another drive.
    var current = target;
    while (p.isWithin(root, current)) {
      if (await FileSystemEntity.type(current, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const FormatException('Archive target contains a symlink');
      }
      current = p.dirname(current);
    }
  }
}
