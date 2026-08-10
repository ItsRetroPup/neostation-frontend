import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:neostation/l10n/app_locale.dart';

import '../../widgets/core_footer.dart';

/// Control legend for the Discovery tab.
class DiscoveryFooter extends CoreFooter {
  const DiscoveryFooter({
    super.key,
    required this.onPlay,
    required this.onGoToGame,
    required this.onReroll,
    required this.onBack,
  });

  final VoidCallback onPlay;
  final VoidCallback onGoToGame;
  final VoidCallback onReroll;
  final VoidCallback onBack;

  /// Right-aligns the controls rather than centring them.
  ///
  /// The split layout is what puts Play against the right edge of the screen;
  /// the centred layout would leave it in the middle of a floating group. It
  /// also drops the version label, which the centred layout positions on the
  /// right — directly on top of a five-control row.
  @override
  bool get centerControls => false;

  @override
  List<Widget> buildControls(BuildContext context) {
    final theme = Theme.of(context);

    // Ordered so the primary action sits furthest right, under the thumb, with
    // Back next to it: Navigate, Go to game, Re-roll, Back, Play.
    return [
      GamepadControl(
        iconPath: 'assets/images/gamepad/Xbox_D-pad_ALL.png',
        label: AppLocale.hintNavigate.getString(context),
      ),
      SizedBox(width: 8.r),
      GamepadControl(
        iconPath: 'assets/images/gamepad/Xbox_X_button.png',
        label: AppLocale.searchGoToGame.getString(context),
        onTap: onGoToGame,
        backgroundColor: theme.colorScheme.primary,
        textColor: Colors.white,
      ),
      SizedBox(width: 8.r),
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
        label: AppLocale.play.getString(context),
        onTap: onPlay,
        textColor: Colors.white,
        backgroundColor: const Color(0xFF2ECC71),
      ),
    ];
  }
}
