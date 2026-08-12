import 'package:flutter/material.dart';

/// The visual vocabulary used for controller hints in the UI.
enum ControllerGlyphProfile { xbox, playStation }

/// Shares the active controller's glyph profile with the widget tree.
class ControllerGlyphProfileNotifier {
  ControllerGlyphProfileNotifier._();

  static final ValueNotifier<ControllerGlyphProfile> profile = ValueNotifier(
    ControllerGlyphProfile.xbox,
  );

  static void updateForControllerName(String name) {
    final normalized = name.toLowerCase();
    ControllerGlyphProfile? next;
    if (normalized.contains('dualsense') ||
        normalized.contains('dualshock') ||
        normalized.contains('playstation')) {
      next = ControllerGlyphProfile.playStation;
    } else if (normalized.contains('xbox')) {
      next = ControllerGlyphProfile.xbox;
    }

    // The Darwin plugin can enumerate a placeholder "Unknown device" beside
    // the physical controller. It must not replace the actual controller's
    // visual profile.
    if (next != null && profile.value != next) profile.value = next;
  }

  /// Sets the initial profile from the currently connected controller names.
  ///
  /// Prefer PlayStation when one is connected, then fall back to Xbox.
  static void updateForConnectedControllerNames(Iterable<String> names) {
    String? xboxName;
    for (final name in names) {
      final normalized = name.toLowerCase();
      if (normalized.contains('dualsense') ||
          normalized.contains('dualshock') ||
          normalized.contains('playstation')) {
        updateForControllerName(name);
        return;
      }
      if (normalized.contains('xbox')) xboxName ??= name;
    }
    if (xboxName != null) updateForControllerName(xboxName);
  }
}

/// Resolves the established Xbox hint asset names to real PlayStation PNGs.
class ControllerGlyphAssets {
  ControllerGlyphAssets._();

  static const _playStation = <String, String>{
    'Xbox_A_button.png': 'Ps_cross_button.png',
    'Xbox_B_button.png': 'Ps_circle_button.png',
    'Xbox_X_button.png': 'Ps_square_button.png',
    'Xbox_Y_button.png': 'Ps_triangle_button.png',
    'Xbox_LB_bumper.png': 'Ps_L1_bumper.png',
    'Xbox_LB_bumper_filled.png': 'Ps_L1_bumper_filled.png',
    'Xbox_RB_bumper.png': 'Ps_R1_bumper.png',
    'Xbox_RB_bumper_filled.png': 'Ps_R1_bumper_filled.png',
    'Xbox_LT_trigger.png': 'Ps_L2_trigger.png',
    'Xbox_RT_trigger.png': 'Ps_R2_trigger.png',
    'Xbox_L-click.png': 'Ps_L3_click.png',
    'Xbox_R-click.png': 'Ps_R3_click.png',
    'Xbox_Menu_button.png': 'Ps_options_button.png',
    'Xbox_View_button.png': 'Ps_create_button.png',
    'Xbox_Share_button.png': 'Ps_create_button.png',
  };

  static String forProfile(String assetPath, ControllerGlyphProfile profile) {
    if (profile != ControllerGlyphProfile.playStation) return assetPath;
    const prefix = 'assets/images/gamepad/';
    final replacement =
        _playStation[assetPath.startsWith(prefix)
            ? assetPath.substring(prefix.length)
            : assetPath];
    return replacement == null ? assetPath : '$prefix$replacement';
  }
}

/// Displays a controller glyph with the asset set for the active profile.
class ControllerGlyphImage extends StatelessWidget {
  const ControllerGlyphImage({
    super.key,
    required this.assetPath,
    required this.width,
    required this.height,
    this.color,
    this.colorBlendMode,
  });

  final String assetPath;
  final double width;
  final double height;
  final Color? color;
  final BlendMode? colorBlendMode;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ControllerGlyphProfile>(
      valueListenable: ControllerGlyphProfileNotifier.profile,
      builder: (context, profile, child) => Image.asset(
        ControllerGlyphAssets.forProfile(assetPath, profile),
        width: width,
        height: height,
        color: color,
        colorBlendMode: colorBlendMode,
      ),
    );
  }
}
