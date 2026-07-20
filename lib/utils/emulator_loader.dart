import 'dart:io';
import 'package:flutter/services.dart';
import 'package:neostation/models/core_emulator_model.dart';
import 'package:neostation/models/system_model.dart';
import 'package:neostation/repositories/emulator_repository.dart';
import 'package:neostation/services/logger_service.dart';

/// Hydrates the list of supported emulators for [system], verifying package
/// presence on Android hosts and RetroArch core availability on desktop.
///
/// Shared by the game details settings tab and the game settings dialog so
/// both enumerate identical emulator options.
Future<List<CoreEmulatorModel>> loadEmulatorsForSystem(
  SystemModel system,
) async {
  final log = LoggerService.instance;
  final systemId = system.id;
  if (systemId == null) return [];
  try {
    var emulators = await EmulatorRepository.getEmulatorsForSystemCurrentOs(
      systemId,
    );
    if (Platform.isAndroid) {
      // Verification Protocol: Check native package presence via platform channel.
      final updated = <CoreEmulatorModel>[];
      for (final e in emulators) {
        if (e.androidPackageName != null && e.androidPackageName!.isNotEmpty) {
          try {
            const ch = MethodChannel('com.neogamelab.neostation/game');
            final installed = await ch.invokeMethod<bool>(
              'isPackageInstalled',
              {'packageName': e.androidPackageName},
            );
            updated.add(e.copyWith(isInstalled: installed ?? false));
          } catch (_) {
            updated.add(e);
          }
        } else {
          updated.add(e);
        }
      }
      emulators = updated;
    } else {
      // Desktop: RetroArch cores are considered installed when the global
      // RetroArch executable has been detected/configured by the user.
      final retroArchPath =
          await EmulatorRepository.getRetroArchExecutablePath();
      if (retroArchPath != null && retroArchPath.isNotEmpty) {
        final updated = <CoreEmulatorModel>[];
        for (final e in emulators) {
          final uid = e.uniqueId;
          final isRaCore =
              uid.contains('.ra.') ||
              uid.contains('.ra32.') ||
              uid.contains('.ra64.');
          if (isRaCore && !e.isInstalled) {
            updated.add(e.copyWith(isInstalled: true));
          } else {
            updated.add(e);
          }
        }
        emulators = updated;
      }
    }
    return emulators;
  } catch (e) {
    log.e('Emulator enumeration failed: $e');
    return [];
  }
}
