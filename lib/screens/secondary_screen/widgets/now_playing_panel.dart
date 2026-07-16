import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../../models/secondary_display_state.dart';
import '../now_playing_helpers.dart';

/// The Now Playing page shown on the secondary display: boxart + game/system
/// title + play-time / session / last-played stats.
///
/// The app dock and all-apps launcher are no longer part of this panel — they
/// are drawn as a persistent overlay by [SecondaryScreen] so they stay visible
/// in every state (browsing and in-game), not just while a game is active.
///
/// Pure, input-driven subtree — the owning [SecondaryScreen] passes the current
/// state snapshot, the live session readout ([sessionRunning] / [sessionTime]),
/// and the action callbacks, so the panel re-reads no state of its own.
class NowPlayingPanel extends StatelessWidget {
  const NowPlayingPanel({
    super.key,
    required this.value,
    required this.sessionRunning,
    required this.sessionTime,
    required this.onRequestScreenshot,
  });

  final SecondaryDisplayStateData value;

  /// Whether a play session is currently being timed (drives the SESSION stat).
  final bool sessionRunning;

  /// Pre-formatted elapsed session time (`HH:MM:SS`); only shown when
  /// [sessionRunning].
  final String sessionTime;

  /// Asks the main engine to capture a screenshot of the main screen.
  final VoidCallback onRequestScreenshot;

  @override
  Widget build(BuildContext context) {
    final title = (value.gameTitle != null && value.gameTitle!.isNotEmpty)
        ? value.gameTitle!
        : value.systemName;
    final scheme = panelScheme(value);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = math.max(1.0, constraints.maxWidth - 40.0);
        final availableHeight = math.max(1.0, constraints.maxHeight - 24.0);
        final scale = math
            .min(availableWidth / 640.0, availableHeight / 400.0)
            .clamp(0.1, 1.25);

        return Container(
          width: double.infinity,
          height: double.infinity,
          color: scheme.surface,
          padding: const EdgeInsets.fromLTRB(20.0, 12.0, 20.0, 12.0),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 640.0 * scale,
              height: 400.0 * scale,
              child: _buildContent(title, scheme, scale),
            ),
          ),
        );
      },
    );
  }

  Widget _buildContent(String title, ColorScheme scheme, double scale) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        buildNowPlayingBoxart(
          value.gameBoxart,
          width: 184.0 * scale,
          height: 264.0 * scale,
          borderRadius: 12.0 * scale,
        ),
        SizedBox(width: 32.0 * scale),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'NOW PLAYING',
                style: TextStyle(
                  color: scheme.primary,
                  fontSize: 14.0 * scale,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 3.0 * scale,
                ),
              ),
              SizedBox(height: 12.0 * scale),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 30.0 * scale,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8.0 * scale),
              Text(
                value.systemName.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.7),
                  fontSize: 16.0 * scale,
                  letterSpacing: 1.5 * scale,
                ),
              ),
              SizedBox(height: 26.0 * scale),
              buildNowPlayingStat(
                scheme: scheme,
                icon: Symbols.schedule_rounded,
                label: 'PLAY TIME',
                text: formatPlayTime(value.playTimeSeconds),
                scale: scale,
              ),
              if (sessionRunning) ...[
                SizedBox(height: 12.0 * scale),
                buildNowPlayingStat(
                  scheme: scheme,
                  icon: Symbols.timer_rounded,
                  label: 'SESSION',
                  text: sessionTime,
                  scale: scale,
                ),
              ],
              SizedBox(height: 12.0 * scale),
              buildNowPlayingStat(
                scheme: scheme,
                icon: Symbols.history_rounded,
                label: 'LAST PLAYED',
                text: formatLastPlayed(value.lastPlayedMillis),
                scale: scale,
              ),
              if (value.screenshotAccessEnabled) ...[
                SizedBox(height: 28.0 * scale),
                _buildScreenshotButton(scheme, scale),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Tappable pill that asks the main engine to capture a system screenshot of
  /// the main screen.
  Widget _buildScreenshotButton(ColorScheme scheme, double scale) {
    return GestureDetector(
      onTap: onRequestScreenshot,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 20.0 * scale,
          vertical: 12.0 * scale,
        ),
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12.0 * scale),
          border: Border.all(color: scheme.onSurface.withValues(alpha: 0.18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Symbols.photo_camera_rounded,
              color: scheme.onSurface,
              size: 22.0 * scale,
            ),
            SizedBox(width: 12.0 * scale),
            Text(
              'SCREENSHOT',
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 14.0 * scale,
                fontWeight: FontWeight.w600,
                letterSpacing: 2.0 * scale,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
