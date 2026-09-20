import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/widgets/dpad_glyph.dart';
import 'package:neostation/widgets/neo_glass.dart';

import '../../themes/corner_radii.dart';

/// The RetroAchievements tab's sub-tabs.
///
/// The strip renders the tabs in enum order, and the shell's IndexedStack
/// hosts them in the same order. The set grows by *adding* values — a sub-tab
/// that cannot be shown yet is absent from the strip, never a disabled pill.
enum RaSubTab { dashboard, unlocks, games }

/// The sub-tab strip across the top of the signed-in RetroAchievements tab:
/// which mini-app is open, and that left/right on the D-pad walks between
/// them.
///
/// The visual pattern is [GameDetailsTabsHeader] — the pill is the indicator,
/// the D-pad glyphs either side of it are the hint — with one difference in
/// kind: this strip is a *zone* of the tab's single `ra_content` gamepad
/// layer, not a layer of its own. Switching sub-tabs never pushes or pops a
/// layer, so one press can never end up dispatched twice.
///
/// [focused] is that zone state: true while the D-pad cursor is parked on
/// the strip (reached by pressing Up from the top of the content, or B in the
/// content). The border is the strip's answer to the week card's selection
/// treatment — the one signal that Left/Right will now switch sub-tabs
/// instead of acting inside the content.
class RaTabStrip extends StatelessWidget {
  final RaSubTab currentTab;
  final bool focused;
  final ValueChanged<RaSubTab> onTabChanged;

  const RaTabStrip({
    super.key,
    required this.currentTab,
    required this.focused,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tabs = const [RaSubTab.dashboard, RaSubTab.unlocks, RaSubTab.games];
    final numTabs = tabs.length;
    final tabWidth = 36.r;
    final visualIndex = tabs.indexOf(currentTab).clamp(0, numTabs - 1);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const DpadGlyph(isLeft: true),
        SizedBox(width: 6.r),
        AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeInOut,
          // Width constant so the border animates colour only: a border that
          // also grew would push the glyphs apart when the strip arms.
          decoration: BoxDecoration(
            border: Border.all(
              color: focused
                  ? theme.colorScheme.primary.withValues(alpha: 0.9)
                  : Colors.transparent,
              width: 2.r,
            ),
            borderRadius:
                theme.extension<CornerRadii>()?.radiusExternal ??
                BorderRadius.circular(12.r),
          ),
          child: NeoGlass(
            cornerRadius:
                theme.extension<CornerRadii>()?.radiusExternalRadius ?? 12.r,
            child: SizedBox(
              height: 32.r,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 4.r),
                child: SizedBox(
                  width: numTabs * tabWidth,
                  height: 32.r,
                  child: Stack(
                    children: [
                      // Transition cursor: fluidly follows the active sub-tab.
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeInOut,
                        left: visualIndex * tabWidth,
                        top: 4.r,
                        bottom: 4.r,
                        width: tabWidth,
                        child: Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius:
                                theme
                                    .extension<CornerRadii>()
                                    ?.radiusInternal ??
                                BorderRadius.circular(10.r),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          for (final tab in tabs)
                            _TabItem(
                              tab: tab,
                              width: tabWidth,
                              isSelected: currentTab == tab,
                              onTap: onTabChanged,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: 6.r),
        const DpadGlyph(isLeft: false),
      ],
    );
  }
}

/// One sub-tab pill. Tap switches tabs directly; the D-pad does the same via
/// the shell's strip zone, so both paths land in [onTap]'s callback.
class _TabItem extends StatelessWidget {
  final RaSubTab tab;
  final double width;
  final bool isSelected;
  final ValueChanged<RaSubTab> onTap;

  const _TabItem({
    required this.tab,
    required this.width,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: isSelected,
      label: _labelFor(tab, context),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            SfxService().playNavSound();
            onTap(tab);
          },
          canRequestFocus: false,
          focusColor: Colors.transparent,
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashColor: theme.colorScheme.onSurface.withValues(alpha: 0.1),
          child: SizedBox(
            width: width,
            height: 32.r,
            child: Icon(
              _iconFor(tab),
              size: 18.r,
              color: isSelected
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(RaSubTab tab) {
    return switch (tab) {
      RaSubTab.dashboard => Symbols.dashboard_rounded,
      RaSubTab.unlocks => Symbols.lock_open_rounded,
      RaSubTab.games => Symbols.sports_esports_rounded,
    };
  }

  static String _labelFor(RaSubTab tab, BuildContext context) {
    return switch (tab) {
      RaSubTab.dashboard => AppLocale.raSubtabDashboard.getString(context),
      RaSubTab.unlocks => AppLocale.raSubtabUnlocks.getString(context),
      RaSubTab.games => AppLocale.raSubtabGames.getString(context),
    };
  }
}
