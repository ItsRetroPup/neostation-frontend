import 'dart:io';

import 'logger_service.dart';

/// Desktop filesystem helpers for ROM roots that may require network access.
class NetworkFolderService {
  static final _log = LoggerService.instance;
  static const _probeTimeout = Duration(seconds: 15);

  static bool looksLikeNetworkPath(String folder) {
    return RegExp(
      r'^(?:\\\\\?\\UNC\\|\\\\|//)[^\\/]+[\\/]|^[A-Za-z]:[\\/]|^/Volumes/|^/(?:mnt|media|run/media)/',
    ).hasMatch(folder);
  }

  static Future<List<String>> findUnreachableFolders(
    List<String> folders,
  ) async {
    if (Platform.isAndroid) return [];
    final candidates = folders.where(looksLikeNetworkPath).toList();
    final results = await Future.wait(
      candidates.map((folder) async {
        try {
          await Directory(
            folder,
          ).list().take(1).toList().timeout(_probeTimeout);
          return null;
        } catch (error) {
          _log.w('Network ROM folder is unreachable: $folder ($error)');
          return folder;
        }
      }),
    );
    return results.whereType<String>().toList();
  }

  static Future<bool> openFolder(String folder) async {
    final command = Platform.isWindows
        ? ('explorer.exe', <String>[folder])
        : Platform.isMacOS
        ? ('open', <String>[folder])
        : ('xdg-open', <String>[folder]);
    try {
      await Process.start(
        command.$1,
        command.$2,
        mode: ProcessStartMode.detached,
      );
      return true;
    } catch (error) {
      _log.e('Error opening network folder $folder: $error');
      return false;
    }
  }
}
