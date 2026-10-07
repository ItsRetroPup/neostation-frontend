import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/repositories/steamgriddb_repository.dart';
import 'package:neostation/services/game_service.dart'
    show GamepadNavigationManager;
import 'package:neostation/services/steamgriddb_service.dart';
import 'package:neostation/utils/gamepad_nav.dart';
import 'package:neostation/utils/login_form_selection.dart';
import 'package:neostation/widgets/custom_notification.dart';

/// Lets the user enter, replace or remove their SteamGridDB API key.
///
/// The key is checked against SteamGridDB before it is saved, so a typo is
/// caught here rather than the first time the user opens the artwork picker.
/// Owns its own gamepad layer while open; B leaves the text field first and
/// closes the dialog on the next press.
class SteamGridDbKeyDialog extends StatefulWidget {
  /// Whether a key is already stored, which adds the remove action.
  final bool hasKey;

  const SteamGridDbKeyDialog({super.key, required this.hasKey});

  /// Opens the dialog. Resolves to true when the stored key changed.
  static Future<bool> show(BuildContext context, {required bool hasKey}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => SteamGridDbKeyDialog(hasKey: hasKey),
    );
    return result ?? false;
  }

  @override
  State<SteamGridDbKeyDialog> createState() => _SteamGridDbKeyDialogState();
}

class _SteamGridDbKeyDialogState extends State<SteamGridDbKeyDialog>
    with LoginFormSelection<SteamGridDbKeyDialog> {
  static const String _layerId = 'steamgriddb_key_dialog';

  // Slot order: key field, save, then remove when a key exists.
  static const int _saveSlot = 1;
  static const int _removeSlot = 2;

  GamepadNavigation? _gamepadNav;
  final TextEditingController _keyController = TextEditingController();
  final FocusNode _keyFocus = FocusNode();
  bool _isBusy = false;

  @override
  List<FocusNode?> get selectionSlots => [
    _keyFocus,
    null,
    if (widget.hasKey) null,
  ];

  @override
  void initState() {
    super.initState();
    attachFocusSelectionListeners();
    _gamepadNav = GamepadNavigation(
      onNavigateUp: () => moveSelection(-1),
      onNavigateDown: () => moveSelection(1),
      onSelectItem: _activate,
      allowRepeat: false,
      isTextFieldFocused: isAnyFieldFocused,
      onBack: _handleBack,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _gamepadNav!.initialize();
      GamepadNavigationManager.pushLayer(
        _layerId,
        onActivate: () => _gamepadNav?.activate(),
        onDeactivate: () => _gamepadNav?.deactivate(),
      );
    });
  }

  @override
  void dispose() {
    GamepadNavigationManager.popLayer(_layerId);
    _gamepadNav?.dispose();
    detachFocusSelectionListeners();
    _keyController.dispose();
    _keyFocus.dispose();
    super.dispose();
  }

  void _handleBack() {
    if (isAnyFieldFocused()) {
      exitTextEntry();
    } else if (!_isBusy) {
      Navigator.of(context).pop(false);
    }
  }

  void _activate() {
    if (_isBusy) return;
    if (focusSelectedField()) return;
    if (selectedSlot == _saveSlot) {
      _save();
    } else if (selectedSlot == _removeSlot) {
      _remove();
    }
  }

  Future<void> _save() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      AppNotification.showNotification(
        context,
        AppLocale.pleaseCompleteAllFields.getString(context),
        type: NotificationType.error,
      );
      return;
    }

    setState(() => _isBusy = true);
    final service = SteamGridDbService(apiKey: key);
    try {
      await service.validateKey();
      await SteamGridDbRepository.saveApiKey(key);
      if (!mounted) return;
      AppNotification.showNotification(
        context,
        AppLocale.steamGridDbKeySaved.getString(context),
        type: NotificationType.success,
      );
      Navigator.of(context).pop(true);
    } on SteamGridDbException catch (e) {
      if (!mounted) return;
      AppNotification.showNotification(
        context,
        e.kind == SteamGridDbErrorKind.unauthorized
            ? AppLocale.steamGridDbKeyInvalid.getString(context)
            : AppLocale.steamGridDbUnreachable.getString(context),
        type: NotificationType.error,
      );
    } finally {
      service.close();
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _remove() async {
    setState(() => _isBusy = true);
    await SteamGridDbRepository.clearApiKey();
    if (!mounted) return;
    AppNotification.showNotification(
      context,
      AppLocale.steamGridDbKeyRemoved.getString(context),
      type: NotificationType.success,
    );
    Navigator.of(context).pop(true);
  }

  BoxDecoration? _glow(ThemeData theme, int slot) => isSelected(slot)
      ? BoxDecoration(
          borderRadius: BorderRadius.circular(8.r),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.primary.withValues(alpha: 0.4),
              blurRadius: 6.r,
              spreadRadius: 1.r,
            ),
          ],
        )
      : null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      backgroundColor: theme.scaffoldBackgroundColor,
      insetPadding: EdgeInsets.all(16.r),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
      child: SingleChildScrollView(
        padding: EdgeInsets.all(16.r),
        child: SizedBox(
          width: 300.r,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                AppLocale.steamGridDbApiKey.getString(context),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                  fontSize: 14.r,
                ),
              ),
              SizedBox(height: 6.r),
              Text(
                AppLocale.steamGridDbKeyHelp.getString(context),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  fontSize: 9.r,
                ),
              ),
              SizedBox(height: 12.r),
              Container(
                decoration: _glow(theme, 0),
                height: 32.r,
                child: TextField(
                  controller: _keyController,
                  focusNode: _keyFocus,
                  enabled: !_isBusy,
                  autocorrect: false,
                  enableSuggestions: false,
                  obscureText: true,
                  style: TextStyle(fontSize: 11.r),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                  decoration: InputDecoration(
                    hintText: AppLocale.steamGridDbKeyHint.getString(context),
                    hintStyle: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      fontSize: 10.r,
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.onSurface.withValues(
                      alpha: 0.05,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.r),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.r),
                      borderSide: BorderSide(
                        color: isSelected(0)
                            ? theme.colorScheme.primary
                            : theme.colorScheme.primary.withValues(alpha: 0.1),
                        width: isSelected(0) ? 2.r : 1.r,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 8.r),
              Container(
                decoration: _glow(theme, _saveSlot),
                height: 32.r,
                child: ElevatedButton(
                  onPressed: _isBusy ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                  ),
                  child: _isBusy
                      ? SizedBox(
                          width: 16.r,
                          height: 16.r,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.onPrimary,
                          ),
                        )
                      : Text(
                          AppLocale.save.getString(context),
                          style: TextStyle(
                            fontSize: 12.r,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              if (widget.hasKey) ...[
                SizedBox(height: 6.r),
                Container(
                  decoration: _glow(theme, _removeSlot),
                  height: 32.r,
                  child: OutlinedButton(
                    onPressed: _isBusy ? null : _remove,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      side: BorderSide(
                        color: theme.colorScheme.error.withValues(alpha: 0.6),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                    ),
                    child: Text(
                      AppLocale.steamGridDbRemoveKey.getString(context),
                      style: TextStyle(fontSize: 12.r),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
