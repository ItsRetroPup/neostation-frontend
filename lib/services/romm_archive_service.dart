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

  /// A self-contained ROM needs no game folder, even inside archive wrappers.
  /// Descriptor files and games with companions retain their relative layout.
  static Future<bool> containsSingleGameFile(
    String archivePath,
    Set<String> extensions,
  ) => Isolate.run(() => _containsSingleGameFile(archivePath, extensions));

  static Future<bool> _containsSingleGameFile(
    String archivePath,
    Set<String> extensions,
  ) async {
    final archive = await openArchiveFile(archivePath);
    try {
      final files = archive.entries.where((entry) => entry.isFile).toList();
      if (files.length != 1) return false;
      final ext = p
          .extension(files.single.path)
          .toLowerCase()
          .replaceFirst('.', '');
      return extensions.contains(ext) &&
          !{'m3u', 'cue', 'scummvm'}.contains(ext);
    } finally {
      await archive.close();
    }
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
    try {
      final single = await containsSingleGameFile(archivePath, exts);
      return await prepareDownload(
        archivePath,
        reuseExistingDirectory || single
            ? systemDir
            : p.join(systemDir, folderName),
        exts,
        flattenSingleFile: single,
        forceExtract: forceExtract,
        playlistBaseName:
            playlistName != null && p.extension(playlistName) == '.m3u'
            ? p.basenameWithoutExtension(playlistName)
            : folderName,
      );
    } catch (e, st) {
      LoggerService.instance.e(
        'RomM archive inspection failed',
        error: e,
        stackTrace: st,
      );
      return null;
    }
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

  static Future<String?> prepareDownload(
    String archivePath,
    String destDir,
    Set<String> extensions, {
    bool scummVm = false,
    bool flattenSingleFile = false,
    bool forceExtract = false,
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
          flattenSingleFile,
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

  static Future<String?> _extract(
    String archivePath,
    String destDir,
    Set<String> exts,
    bool scummVm,
    bool flattenSingleFile,
    String? playlistBaseName,
  ) async {
    final archive = await openArchiveFile(
      archivePath,
      // Make the 7z decoder's built-in 1 GiB cap a typed size-limit error,
      // so the native fallback below can handle larger solid folders.
      options: p.extension(archivePath).toLowerCase() == '.7z'
          ? const ArchiveReadOptions(maxContainerDecodeSize: 1 << 30)
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
        final ext = p.extension(entry.path).toLowerCase().replaceFirst('.', '');
        return scummVm ? ext == 'scummvm' : exts.contains(ext);
      }).toList();
      if (playable.isEmpty ||
          (!scummVm &&
              playable.every(
                (entry) => p.extension(entry.path).toLowerCase() == '.m3u',
              ))) {
        return null;
      }
      playable.sort((a, b) {
        int priority(ArchiveEntry entry) =>
            switch (p.extension(entry.path).toLowerCase()) {
              '.m3u' => 0,
              '.cue' || '.ccd' || '.mds' || '.toc' => 1,
              _ => 2,
            };
        final order = priority(a).compareTo(priority(b));
        return order != 0 ? order : a.path.compareTo(b.path);
      });

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
            // The Dart decoder caps a solid 7z folder at 1 GiB. Use the
            // existing native SDK for large DVD ROMs instead of rejecting them.
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
      var indexedName = p.basename(playable.first.path);
      if (scummVm) {
        final descriptor = File(safeJoin(staging.path, playable.first.path)!);
        final id = (await descriptor.readAsString())
            .replaceFirst(RegExp(r'^\uFEFF'), '')
            .trim();
        if (!RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_-]*$').hasMatch(id)) {
          return null;
        }
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
        final relative = flattenSingleFile && files.length == 1
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
      if (!scummVm &&
          !flattenSingleFile &&
          exts.contains('m3u') &&
          p.extension(playable.first.path).toLowerCase() != '.m3u') {
        indexedName =
            '${playlistBaseName ?? p.basenameWithoutExtension(archivePath)}.m3u';
        playlistPath = p.join(destDir, indexedName);
        await _checkTarget(destDir, playlistPath, archivePath);
        if (outputs.values.any((target) => p.equals(target, playlistPath!))) {
          return null;
        }
        // Remove only each descriptor's own referenced data files. An ISO
        // belonging to another disc must stay in a mixed-format playlist.
        final companions = <String>{};
        for (final entry in playable) {
          final extension = p.extension(entry.path).toLowerCase();
          final stem = p.posix.withoutExtension(entry.path).toLowerCase();
          if (extension == '.ccd') {
            companions.addAll({'$stem.img', '$stem.sub'});
          } else if (extension == '.mds') {
            companions.add('$stem.mdf');
          } else if (extension == '.cue' || extension == '.toc') {
            final descriptor = await File(
              safeJoin(staging.path, entry.path)!,
            ).readAsString();
            final references = RegExp(
              r'^\s*(?:FILE|DATAFILE|AUDIOFILE)\s+(?:"([^"]+)"|([^\s]+))',
              caseSensitive: false,
              multiLine: true,
            ).allMatches(descriptor);
            for (final reference in references) {
              final name = (reference.group(1) ?? reference.group(2)!)
                  .replaceAll('\\', '/');
              companions.add(
                p.posix
                    .normalize(p.posix.join(p.posix.dirname(entry.path), name))
                    .toLowerCase(),
              );
            }
          }
        }
        final discs = playable.where(
          (entry) => !companions.contains(entry.path.toLowerCase()),
        );
        playlist =
            '${discs.map((entry) => p.relative(outputs[entry]!, from: destDir).replaceAll('\\', '/')).join('\n')}\n';
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
    var current = target;
    while (p.isWithin(root, current) || p.equals(root, current)) {
      if (await FileSystemEntity.type(current, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const FormatException('Archive target contains a symlink');
      }
      current = p.dirname(current);
    }
  }
}
