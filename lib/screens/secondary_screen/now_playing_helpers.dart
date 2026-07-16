import 'dart:io';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/providers/theme_provider.dart';
import '../../models/secondary_display_state.dart';

/// Pure presentation helpers for the secondary display's Now Playing / panel
/// chrome — theme + colour-scheme resolution and the leaf builders/formatters.
///
/// Extracted verbatim from `_SecondaryScreenState`; every function is a pure
/// mapping from its inputs to a value/widget with no widget-state reads, so the
/// rendered output is unchanged.

/// Resolves the full user-selected theme for the secondary display from the
/// theme name pushed by the main engine. The secondary display runs in the
/// same isolate as the main app, so [ThemeProvider.availableThemes] is the
/// source of truth. Falls back to the brightness-appropriate neostation
/// theme for 'system' mode or an unknown/absent name.
ThemeData resolveTheme(String? themeName) {
  final themes = ThemeProvider.availableThemes;
  final direct = themeName != null ? themes[themeName] : null;
  if (direct != null) return direct;
  final brightness =
      WidgetsBinding.instance.platformDispatcher.platformBrightness;
  return brightness == Brightness.dark ? themes['dark']! : themes['light']!;
}

/// WCAG contrast ratio between two opaque colors (1.0 = identical, 21.0 =
/// black-on-white).
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Builds the effective color scheme for the Now Playing panel. Text colors
/// are derived from the *actual* painted background luminance (not the
/// theme's own on-colors, which can mismatch the pushed background and
/// collapse contrast on light themes), while the theme's primary accent is
/// preserved as long as it stays legible on that background.
ColorScheme panelScheme(SecondaryDisplayStateData value) {
  final base = resolveTheme(value.themeName).colorScheme;
  final bg = value.backgroundColor != null
      ? Color(value.backgroundColor!)
      : base.surface;
  final fg = bg.computeLuminance() > 0.5
      ? const Color(0xFF14161A)
      : Colors.white;
  final accent = contrastRatio(base.primary, bg) >= 3.0 ? base.primary : fg;
  return base.copyWith(surface: bg, onSurface: fg, primary: accent);
}

/// Height reserved for the persistent dock when it overlays a secondary screen.
///
/// The dock uses the legacy ScreenUtil scale, so reserving a percentage of the
/// actual display height keeps the content above it on both 4:3 and wide
/// swapped displays.
double secondaryDockReservedHeight({
  required double screenHeight,
  required bool dockEnabled,
}) {
  if (!dockEnabled) return 0;
  return (screenHeight * 0.2).clamp(88.0, 150.0);
}

Widget buildNowPlayingBoxart(
  String? path, {
  required double width,
  required double height,
  required double borderRadius,
}) {
  Widget placeholder() => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
    ),
    child: Icon(
      Symbols.videogame_asset_rounded,
      color: Colors.white24,
      size: width * 0.35,
    ),
  );

  if (path == null) return placeholder();
  final file = File(path);
  if (!file.existsSync()) return placeholder();

  return ClipRRect(
    borderRadius: BorderRadius.circular(borderRadius),
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: height, maxWidth: width),
      child: Image.file(
        file,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => placeholder(),
      ),
    ),
  );
}

Widget buildNowPlayingStat({
  required ColorScheme scheme,
  required IconData icon,
  required String label,
  required String text,
  required double scale,
}) {
  final muted = scheme.onSurface.withValues(alpha: 0.55);
  return Row(
    children: [
      Icon(icon, color: muted, size: 20 * scale),
      SizedBox(width: 10 * scale),
      Text(
        '$label  ',
        style: TextStyle(
          color: muted,
          fontSize: 14 * scale,
          letterSpacing: scale,
        ),
      ),
      Flexible(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: scheme.onSurface,
            fontSize: 16 * scale,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}

String formatPlayTime(int? seconds) {
  if (seconds == null || seconds <= 0) return '—';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m';
  return '<1m';
}

String formatLastPlayed(int? millis) {
  if (millis == null) return 'Never';
  final then = DateTime.fromMillisecondsSinceEpoch(millis);
  final diff = DateTime.now().difference(then);
  if (diff.inDays >= 1) {
    final d = diff.inDays;
    return d == 1 ? 'Yesterday' : '$d days ago';
  }
  if (diff.inHours >= 1) return '${diff.inHours}h ago';
  if (diff.inMinutes >= 1) return '${diff.inMinutes}m ago';
  return 'Just now';
}
