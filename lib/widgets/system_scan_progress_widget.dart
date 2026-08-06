import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:provider/provider.dart';
import '../providers/sqlite_config_provider.dart';
import '../utils/gamepad_nav.dart';
import '../services/game_service.dart' show GamepadNavigationManager;

class SystemScanProgressWidget extends StatefulWidget {
  const SystemScanProgressWidget({super.key});

  @override
  State<SystemScanProgressWidget> createState() =>
      _SystemScanProgressWidgetState();
}

class _SystemScanProgressWidgetState extends State<SystemScanProgressWidget> {
  GamepadNavigation? _gamepadNavigation;
  int _selectedRecoveryAction = 0;

  void _syncGamepadNavigation(SqliteConfigProvider provider) {
    final hasRecovery = provider.unreachableNetworkRomFolders.isNotEmpty;
    if (!hasRecovery && _gamepadNavigation != null) {
      GamepadNavigationManager.popLayer('system_scan_recovery');
      _gamepadNavigation!.dispose();
      _gamepadNavigation = null;
    } else if (hasRecovery && _gamepadNavigation == null) {
      _gamepadNavigation = GamepadNavigation(
        onNavigateUp: () => _moveRecoveryAction(provider, -1),
        onNavigateDown: () => _moveRecoveryAction(provider, 1),
        onSelectItem: () => _activateRecoveryAction(provider),
        onBack: provider.clearUnreachableNetworkRomFolders,
      )..initialize();
      _gamepadNavigation!.activate();
      GamepadNavigationManager.pushLayer(
        'system_scan_recovery',
        onActivate: () => _gamepadNavigation?.activate(),
        onDeactivate: () => _gamepadNavigation?.deactivate(),
      );
    }
  }

  void _moveRecoveryAction(SqliteConfigProvider provider, int delta) {
    final actionCount = provider.unreachableNetworkRomFolders.length + 2;
    setState(() {
      _selectedRecoveryAction =
          (_selectedRecoveryAction + delta + actionCount) % actionCount;
    });
  }

  void _activateRecoveryAction(SqliteConfigProvider provider) {
    final folders = provider.unreachableNetworkRomFolders;
    if (_selectedRecoveryAction < folders.length) {
      provider.openNetworkFolder(folders[_selectedRecoveryAction]);
    } else if (_selectedRecoveryAction == folders.length) {
      provider.scanSystems();
    } else {
      provider.clearUnreachableNetworkRomFolders();
    }
  }

  @override
  void dispose() {
    GamepadNavigationManager.popLayer('system_scan_recovery');
    _gamepadNavigation?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SqliteConfigProvider>(
      builder: (context, configProvider, child) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _syncGamepadNavigation(configProvider),
        );
        if (!configProvider.isScanning &&
            configProvider.unreachableNetworkRomFolders.isEmpty) {
          return SizedBox.shrink();
        }

        return Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: configProvider.scanCompleted
                        ? Icon(
                            Symbols.check_circle_rounded,
                            color: Theme.of(context).colorScheme.primary,
                            size: 20,
                          )
                        : CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      configProvider.scanStatus.isNotEmpty
                          ? _localizedScanStatus(context, configProvider)
                          : AppLocale.scanningSystemsRoms.getString(context),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              if (configProvider.totalSystemsToScan > 0) ...[
                SizedBox(height: 12),
                LinearProgressIndicator(
                  value: configProvider.scanProgress,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
                SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      AppLocale.ofSystems
                          .getString(context)
                          .replaceFirst(
                            '{scanned}',
                            configProvider.scannedSystemsCount.toString(),
                          )
                          .replaceFirst(
                            '{total}',
                            configProvider.totalSystemsToScan.toString(),
                          ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      '${(configProvider.scanProgress * 100).toInt()}%',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ] else if (configProvider.detectedSystems.isNotEmpty) ...[
                SizedBox(height: 12),
                LinearProgressIndicator(
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  AppLocale.systemsDetected
                      .getString(context)
                      .replaceFirst(
                        '{count}',
                        configProvider.detectedRealSystems.length.toString(),
                      ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
              if (configProvider.unreachableNetworkRomFolders.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final folder
                    in configProvider.unreachableNetworkRomFolders) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          folder,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () =>
                            configProvider.openNetworkFolder(folder),
                        icon: const Icon(Symbols.folder_open_rounded, size: 18),
                        label: Text(
                          AppLocale.openNetworkFolder.getString(context),
                        ),
                        style: TextButton.styleFrom(
                          backgroundColor:
                              _selectedRecoveryAction ==
                                  configProvider.unreachableNetworkRomFolders
                                      .toList()
                                      .indexOf(folder)
                              ? Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.2)
                              : null,
                        ),
                      ),
                    ],
                  ),
                ],
                TextButton.icon(
                  onPressed: configProvider.isScanning
                      ? null
                      : configProvider.scanSystems,
                  icon: const Icon(Symbols.refresh_rounded, size: 18),
                  label: Text(AppLocale.retry.getString(context)),
                  style: TextButton.styleFrom(
                    backgroundColor:
                        _selectedRecoveryAction ==
                            configProvider.unreachableNetworkRomFolders.length
                        ? Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.2)
                        : null,
                  ),
                ),
                TextButton.icon(
                  onPressed: configProvider.clearUnreachableNetworkRomFolders,
                  icon: const Icon(Symbols.close_rounded, size: 18),
                  label: Text(AppLocale.close.getString(context)),
                  style: TextButton.styleFrom(
                    backgroundColor:
                        _selectedRecoveryAction ==
                            configProvider.unreachableNetworkRomFolders.length +
                                1
                        ? Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.2)
                        : null,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _localizedScanStatus(
    BuildContext context,
    SqliteConfigProvider configProvider,
  ) {
    final status = configProvider.scanStatus;
    var localized = status.getString(context);
    localized = localized.replaceFirst(
      '{folders}',
      configProvider.unreachableNetworkRomFolders.join(', '),
    );
    if (localized != status) return localized;
    return status;
  }
}

class ROMCountBadge extends StatelessWidget {
  final int romCount;
  final bool isLoading;

  const ROMCountBadge({
    super.key,
    required this.romCount,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: romCount > 0
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        AppLocale.romsLabel
            .getString(context)
            .replaceFirst('{count}', romCount.toString()),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: romCount > 0
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
