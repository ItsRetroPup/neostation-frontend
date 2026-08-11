import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:neostation/l10n/app_locale.dart';

import '../../widgets/core_footer.dart';

/// Control legend for the Discovery tab.
class DiscoveryFooter extends CoreFooter {
  const DiscoveryFooter({
    super.key,
    required this.onOpen,
    required this.onReroll,
    required this.onBack,
    this.selectionIcon,
    this.selectionText,
  });

  /// Icon of the section the cursor is in, shown beside [selectionText].
  final IconData? selectionIcon;

  /// What is currently selected, e.g. `Hidden Gem: ActRaiser`.
  ///
  /// The board's tiles carry a section label and a small title, so the footer
  /// is where the selected pick is named in full — the same job the concept's
  /// bottom-left chip does.
  final String? selectionText;

  /// Opens the focused pick in its system library, where its metadata, video
  /// and screenshots live. Discovery never launches a game itself.
  final VoidCallback onOpen;

  final VoidCallback onReroll;
  final VoidCallback onBack;

  /// Right-aligns the controls rather than centring them.
  ///
  /// The split layout is what puts the primary action against the right edge of
  /// the screen; the centred layout would leave it mid-row. It also drops the
  /// version label, which the centred layout positions on the right — directly
  /// on top of the controls.
  @override
  bool get centerControls => false;

  @override
  Widget? buildLeftContent(BuildContext context) {
    final text = selectionText;
    if (text == null || text.isEmpty) return null;

    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10.r, vertical: 5.r),
        decoration: BoxDecoration(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999.r),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selectionIcon != null) ...[
              Icon(selectionIcon, size: 13.r, color: theme.colorScheme.primary),
              SizedBox(width: 6.r),
            ],
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.r,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  List<Widget> buildControls(BuildContext context) {
    final theme = Theme.of(context);

    // Primary action furthest right, under the thumb, with Back beside it.
    // There is no D-pad "Navigate" hint: every screen in the app is navigated
    // that way, so it says nothing about this one.
    return [
      GamepadControl(
        iconPath: 'assets/images/gamepad/Xbox_Y_button.png',
        label: AppLocale.discoveryReroll.getString(context),
        onTap: onReroll,
        backgroundColor: theme.colorScheme.secondary.withValues(alpha: 0.8),
        textColor: Colors.white,
      ),
      SizedBox(width: 8.r),
      GamepadControl(
        iconPath: 'assets/images/gamepad/Xbox_B_button.png',
        label: AppLocale.back.getString(context),
        onTap: onBack,
        backgroundColor: theme.colorScheme.tertiary,
        textColor: theme.colorScheme.onTertiary,
      ),
      SizedBox(width: 8.r),
      GamepadControl(
        iconPath: 'assets/images/gamepad/Xbox_A_button.png',
        label: AppLocale.searchGoToGame.getString(context),
        onTap: onOpen,
        textColor: Colors.white,
        backgroundColor: const Color(0xFF2ECC71),
      ),
    ];
  }
}
