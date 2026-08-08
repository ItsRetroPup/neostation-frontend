import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/services/game_service.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/utils/gamepad_nav.dart';

/// A gamepad-navigable dropdown for the available UI sound themes.
class SoundThemePickerOverlay extends StatefulWidget {
  final Offset anchorOffset;
  final String currentTheme;

  const SoundThemePickerOverlay({
    super.key,
    required this.anchorOffset,
    required this.currentTheme,
  });

  @override
  State<SoundThemePickerOverlay> createState() =>
      _SoundThemePickerOverlayState();
}

class _SoundThemePickerOverlayState extends State<SoundThemePickerOverlay> {
  late final GamepadNavigation _gamepadNav;
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = SfxService.availableThemes.indexWhere(
      (theme) => theme.name == widget.currentTheme,
    );
    if (_selectedIndex < 0) {
      _selectedIndex = 0;
    }
    _gamepadNav = GamepadNavigation(
      onNavigateUp: () => _move(-1),
      onNavigateDown: () => _move(1),
      onSelectItem: _select,
      onBack: () => Navigator.pop(context),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gamepadNav.initialize();
      GamepadNavigationManager.pushLayer(
        'sound_theme_picker_overlay',
        onActivate: _gamepadNav.activate,
        onDeactivate: _gamepadNav.deactivate,
      );
    });
  }

  @override
  void dispose() {
    GamepadNavigationManager.popLayer('sound_theme_picker_overlay');
    _gamepadNav.dispose();
    super.dispose();
  }

  void _move(int amount) {
    setState(() {
      _selectedIndex =
          (_selectedIndex + amount) % SfxService.availableThemes.length;
      if (_selectedIndex < 0) {
        _selectedIndex += SfxService.availableThemes.length;
      }
    });
    SfxService().playNavSound();
  }

  void _select() {
    SfxService().playEnterSound();
    Navigator.pop(context, SfxService.availableThemes[_selectedIndex].name);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const itemHeight = 32.0;
    final width = 180.r;
    final height = (itemHeight * SfxService.availableThemes.length + 16).r;
    final screen = MediaQuery.of(context).size;
    final left = (widget.anchorOffset.dx - width).clamp(
      8.0,
      screen.width - width - 8,
    );
    final top = (widget.anchorOffset.dy - height / 2).clamp(
      8.0,
      screen.height - height - 8,
    );

    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: width,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 8.r),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: SfxService.availableThemes.asMap().entries.map((
                  entry,
                ) {
                  final index = entry.key;
                  final soundTheme = entry.value;
                  final selected = index == _selectedIndex;
                  final active = soundTheme.name == widget.currentTheme;
                  return SizedBox(
                    height: itemHeight.r,
                    child: InkWell(
                      onTap: () {
                        setState(() => _selectedIndex = index);
                        _select();
                      },
                      child: Container(
                        margin: EdgeInsets.symmetric(horizontal: 6.r),
                        padding: EdgeInsets.symmetric(horizontal: 10.r),
                        decoration: BoxDecoration(
                          color: selected
                              ? theme.colorScheme.primary.withValues(
                                  alpha: 0.15,
                                )
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                soundTheme.name,
                                style: TextStyle(fontSize: 10.r),
                              ),
                            ),
                            if (active)
                              Icon(
                                Symbols.check_rounded,
                                size: 14.r,
                                color: theme.colorScheme.secondary,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
