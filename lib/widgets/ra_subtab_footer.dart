import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../l10n/app_locale.dart';
import 'core_footer.dart';
import 'footer_label_pill.dart';

/// The compact action legend shared by the four RetroAchievements sub-tabs.
///
/// The left pill names the row currently under the D-pad cursor. The controls
/// deliberately use the same split footer shape as the systems and RomM
/// views: Y refreshes the active RA data, B returns to the sub-tab strip, and
/// A opens the focused row.
class RaSubTabFooter extends CoreFooter {
  final String label;
  final VoidCallback? onRefresh;
  final VoidCallback? onBack;
  final VoidCallback? onSelect;

  const RaSubTabFooter({
    super.key,
    required this.label,
    this.onRefresh,
    this.onBack,
    this.onSelect,
  });

  @override
  bool get centerControls => false;

  @override
  bool get showVersion => false;

  @override
  Widget? buildLeftContent(BuildContext context) {
    return FooterLabelPill(
      label: '${AppLocale.hintNavigate.getString(context)}: $label',
    );
  }

  @override
  List<Widget> buildControls(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final secondaryBackground = scheme.surfaceContainerHighest.withValues(
      alpha: 0.3,
    );

    return [
      GamepadControl(
        label: AppLocale.hintRefresh.getString(context),
        iconPath: 'assets/images/gamepad/Xbox_Y_button.png',
        onTap: onRefresh,
        textColor: scheme.onTertiaryFixed,
        backgroundColor: scheme.tertiaryFixed,
      ),
      SizedBox(width: 8.r),
      GamepadControl(
        label: AppLocale.hintBack.getString(context),
        iconPath: 'assets/images/gamepad/Xbox_B_button.png',
        onTap: onBack,
        textColor: scheme.onSurface,
        backgroundColor: secondaryBackground,
      ),
      SizedBox(width: 8.r),
      GamepadControl(
        label: AppLocale.hintSelect.getString(context),
        iconPath: 'assets/images/gamepad/Xbox_A_button.png',
        onTap: onSelect,
        textColor: scheme.onTertiary,
        backgroundColor: scheme.tertiary,
      ),
    ];
  }
}
