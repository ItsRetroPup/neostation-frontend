import 'dart:io';

import 'package:path/path.dart' as path;

/// Discovers and launches emulators on Linux, including SteamOS installations.
///
/// Linux emulator packages do not all expose a normal executable file. Flatpak
/// applications are therefore stored as `flatpak:<application-id>` targets and
/// host binaries found from inside NeoStation's Flatpak are stored as
/// `host:<absolute-path>` targets.
class LinuxEmulatorService {
  LinuxEmulatorService._();

  static const String flatpakPrefix = 'flatpak:';
  static const String hostPrefix = 'host:';

  static Future<List<_FlatpakApplication>>? _flatpakApplications;
  static Future<List<String>>? _applicationFiles;

  static bool get isSandboxed =>
      (Platform.environment['FLATPAK_ID'] ?? '').isNotEmpty;

  static bool isLauncherTarget(String value) =>
      value.startsWith(flatpakPrefix) || value.startsWith(hostPrefix);

  static bool isFlatpakTarget(String value) => value.startsWith(flatpakPrefix);

  /// Converts a file selected inside a Flatpak into its corresponding host path.
  static String normalizeSelectedPath(String selectedPath) {
    var resolved = selectedPath;
    const hostPrefixPath = '/run/host/';
    if (resolved.startsWith(hostPrefixPath)) {
      resolved = '/${resolved.substring(hostPrefixPath.length)}';
    }
    return isSandboxed && !isLauncherTarget(resolved)
        ? '$hostPrefix$resolved'
        : resolved;
  }

  /// Returns the best installed target for an emulator database entry.
  static Future<String?> detect({
    required String name,
    String? uniqueId,
  }) async {
    if (!Platform.isLinux) return null;

    final aliases = _executableAliases(name, uniqueId);
    final appImage = await _findApplicationFile(aliases);
    if (appImage != null) {
      return isSandboxed ? '$hostPrefix$appImage' : appImage;
    }

    final native = await _findNativeExecutable(aliases);
    if (native != null) return native;

    final flatpak = await _findFlatpak(name, uniqueId, aliases);
    if (flatpak != null) return '$flatpakPrefix${flatpak.id}';

    return null;
  }

  static Future<bool> isAvailable(String target) async {
    if (!Platform.isLinux) return File(target).exists();
    if (target.isEmpty) return false;

    if (target.startsWith(flatpakPrefix)) {
      final id = target.substring(flatpakPrefix.length);
      return (await _installedFlatpaks()).any((app) => app.id == id);
    }

    if (target.startsWith(hostPrefix)) {
      final executable = target.substring(hostPrefix.length);
      if (!isSandboxed) {
        try {
          return (await Process.run('test', ['-x', executable])).exitCode == 0;
        } on ProcessException {
          return false;
        }
      }
      final result = await _runHost(['test', '-x', executable]);
      return result?.exitCode == 0;
    }

    try {
      return (await Process.run('test', ['-x', target])).exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  /// Starts [target], routing out of the NeoStation Flatpak when necessary.
  static Future<Process> start(
    String target,
    List<String> arguments, {
    Map<String, String>? environment,
  }) {
    if (!Platform.isLinux) {
      return Process.start(target, arguments, environment: environment);
    }

    if (target.startsWith(flatpakPrefix)) {
      final id = target.substring(flatpakPrefix.length);
      if (isSandboxed) {
        return Process.start('/usr/bin/flatpak-spawn', [
          '--host',
          'flatpak',
          'run',
          id,
          ...arguments,
        ]);
      }
      return Process.start('flatpak', ['run', id, ...arguments]);
    }

    if (target.startsWith(hostPrefix)) {
      final executable = target.substring(hostPrefix.length);
      if (isSandboxed) {
        return Process.start('/usr/bin/flatpak-spawn', [
          '--host',
          executable,
          ...arguments,
        ]);
      }
      return Process.start(executable, arguments, environment: environment);
    }

    if (isSandboxed) {
      return Process.start('/usr/bin/flatpak-spawn', [
        '--host',
        target,
        ...arguments,
      ]);
    }
    return Process.start(target, arguments, environment: environment);
  }

  static Future<String?> _findApplicationFile(Set<String> aliases) async {
    final files = await (_applicationFiles ??= _scanApplicationFiles());
    for (final filePath in files) {
      final fileName = _normalize(path.basenameWithoutExtension(filePath));
      if (aliases.any((alias) {
        final normalizedAlias = _normalize(alias);
        return fileName == normalizedAlias ||
            fileName.startsWith(normalizedAlias) ||
            fileName.contains(normalizedAlias);
      })) {
        return filePath;
      }
    }
    return null;
  }

  static Future<List<String>> _scanApplicationFiles() async {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return const [];

    final roots = <String>[
      path.join(home, 'Applications'),
      path.join(home, '.local', 'bin'),
      path.join(home, '.local', 'share', 'applications'),
    ];
    final found = <String>[];
    for (final root in roots) {
      final directory = Directory(root);
      if (!await directory.exists()) continue;
      try {
        await for (final entity in directory.list(
          recursive: root.endsWith('Applications'),
          followLinks: false,
        )) {
          if (entity is! File && entity is! Link) continue;
          final lower = entity.path.toLowerCase();
          if (lower.endsWith('.appimage') ||
              !path.basename(lower).contains('.')) {
            found.add(entity.path);
          }
        }
      } on FileSystemException {
        // A single unreadable directory should not abort the remaining roots.
      }
    }
    found.sort();
    return found;
  }

  static Future<String?> _findNativeExecutable(Set<String> aliases) async {
    if (isSandboxed) {
      for (final alias in aliases) {
        final result = await _runHost(['which', alias]);
        if (result?.exitCode == 0) {
          final executable = result!.stdout.toString().trim().split('\n').first;
          if (executable.startsWith('/')) return '$hostPrefix$executable';
        }
      }
      return null;
    }

    final searchPaths = <String>{
      ...?Platform.environment['PATH']?.split(':'),
      '/usr/bin',
      '/usr/local/bin',
      '/opt/bin',
    };
    for (final alias in aliases) {
      for (final directory in searchPaths) {
        if (directory.isEmpty) continue;
        final candidate = path.join(directory, alias);
        if (await File(candidate).exists()) return candidate;
      }
    }
    return null;
  }

  static Future<_FlatpakApplication?> _findFlatpak(
    String name,
    String? uniqueId,
    Set<String> aliases,
  ) async {
    final wanted = <String>{
      _normalize(name),
      if (uniqueId != null) _normalize(uniqueId),
      ...aliases.map(_normalize),
    }..removeWhere((value) => value.length < 3);

    final knownIds = _knownFlatpakIds(name, uniqueId);
    final applications = await _installedFlatpaks();
    for (final id in knownIds) {
      for (final app in applications) {
        if (app.id.toLowerCase() == id.toLowerCase()) return app;
      }
    }

    for (final app in applications) {
      final haystack = '${_normalize(app.id)}${_normalize(app.name)}';
      if (wanted.any(haystack.contains)) return app;
    }
    return null;
  }

  static Future<List<_FlatpakApplication>> _installedFlatpaks() =>
      _flatpakApplications ??= _loadInstalledFlatpaks();

  static Future<List<_FlatpakApplication>> _loadInstalledFlatpaks() async {
    ProcessResult? result;
    try {
      result = isSandboxed
          ? await _runHost([
              'flatpak',
              'list',
              '--app',
              '--columns=application,name',
            ])
          : await Process.run('flatpak', [
              'list',
              '--app',
              '--columns=application,name',
            ]);
    } on ProcessException {
      return const [];
    }
    if (result == null || result.exitCode != 0) return const [];

    final applications = <_FlatpakApplication>[];
    for (final line in result.stdout.toString().split('\n')) {
      final columns = line.trim().split('\t');
      if (columns.isEmpty || columns.first.isEmpty) continue;
      applications.add(
        _FlatpakApplication(
          id: columns.first,
          name: columns.length > 1 ? columns[1] : columns.first,
        ),
      );
    }
    return applications;
  }

  static Future<ProcessResult?> _runHost(List<String> arguments) async {
    try {
      return await Process.run('/usr/bin/flatpak-spawn', [
        '--host',
        ...arguments,
      ]);
    } on ProcessException {
      return null;
    }
  }

  static Set<String> _executableAliases(String name, String? uniqueId) {
    final normalized = _normalize(name);
    final aliases = <String>{normalized};

    const known = <String, List<String>>{
      'retroarch': ['retroarch'],
      'duckstation': ['duckstation', 'DuckStation'],
      'dolphin': ['dolphin-emu', 'dolphin'],
      'pcsx2': ['pcsx2-qt', 'pcsx2'],
      'rpcs3': ['rpcs3'],
      'ppsspp': ['ppsspp', 'PPSSPPSDL', 'PPSSPPQt'],
      'cemu': ['Cemu', 'cemu'],
      'xemu': ['xemu'],
      'mame': ['mame'],
      'scummvm': ['scummvm'],
      'dosbox': ['dosbox-x', 'dosbox'],
      'ryujinx': ['Ryujinx', 'ryujinx'],
      'yuzu': ['yuzu'],
      'eden': ['eden'],
      'citron': ['citron'],
      'citra': ['citra-qt', 'citra'],
      'azahar': ['azahar'],
      'vita3k': ['Vita3K', 'vita3k'],
      'melonds': ['melonDS', 'melonds'],
      'desmume': ['desmume'],
      'mgba': ['mgba-qt', 'mgba'],
      'snes9x': ['snes9x-gtk', 'snes9x'],
      'flycast': ['flycast'],
      'redream': ['redream'],
      'primehack': ['primehack'],
      'shadps4': ['shadPS4', 'shadps4'],
    };
    for (final entry in known.entries) {
      if (normalized.contains(entry.key) ||
          _normalize(uniqueId ?? '').contains(entry.key)) {
        aliases.addAll(entry.value);
      }
    }
    aliases.removeWhere((value) => value.length < 2);
    return aliases;
  }

  static List<String> _knownFlatpakIds(String name, String? uniqueId) {
    final value = '${_normalize(name)}${_normalize(uniqueId ?? '')}';
    const ids = <String, List<String>>{
      'retroarch': ['org.libretro.RetroArch'],
      'duckstation': ['org.duckstation.DuckStation'],
      'dolphin': ['org.DolphinEmu.dolphin-emu'],
      'pcsx2': ['net.pcsx2.PCSX2'],
      'rpcs3': ['net.rpcs3.RPCS3'],
      'ppsspp': ['org.ppsspp.PPSSPP'],
      'xemu': ['app.xemu.xemu'],
      'cemu': ['info.cemu.Cemu'],
      'mame': ['org.mamedev.MAME'],
      'scummvm': ['org.scummvm.ScummVM'],
      'dosbox': ['com.dosbox_x.DOSBox-X'],
      'ryujinx': ['org.ryujinx.Ryujinx', 'io.github.ryubing.Ryujinx'],
      'citra': ['org.citra_emu.citra'],
    };
    for (final entry in ids.entries) {
      if (value.contains(entry.key)) return entry.value;
    }
    return const [];
  }

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceFirst('standalone', '')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');
}

class _FlatpakApplication {
  final String id;
  final String name;

  const _FlatpakApplication({required this.id, required this.name});
}
