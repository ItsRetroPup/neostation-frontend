import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/l10n/app_locale.dart';

import '../../../models/discovery_models.dart';
import '../../../models/game_model.dart';
import '../../../providers/file_provider.dart';
import '../../../themes/corner_radii.dart';
import '../../../widgets/marquee_text.dart';

/// One game on a Discovery shelf: its cover, its title and whether it has ever
/// been played.
class DiscoveryCard extends StatelessWidget {
  const DiscoveryCard({
    super.key,
    required this.entry,
    required this.isSelected,
    required this.fileProvider,
    this.onTap,
    this.width,
    this.caption,
  });

  final DiscoveryBoardEntry entry;
  final bool isSelected;
  final FileProvider fileProvider;
  final VoidCallback? onTap;

  /// Optional already-localized label drawn over the cover — the genre shelf
  /// uses it to say which bucket each pick came from, since one shelf holds a
  /// different genre per card.
  final String? caption;

  /// Card width. Shelves size their cards from the viewport, so this is passed
  /// in rather than decided here.
  final double? width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radii = theme.extension<CornerRadii>();
    final game = GameModel.fromDatabaseModel(entry.game);
    final folder = entry.game.systemFolderName ?? '';
    final cardWidth = width ?? 108.r;

    // Box art first; a screenshot stands in for the many games that have one
    // but no cover, and only then does the placeholder appear.
    final artPath = _firstExisting([
      if (folder.isNotEmpty) game.getImagePath(folder, 'box2d', fileProvider),
      if (folder.isNotEmpty)
        game.getImagePath(folder, 'screenshots', fileProvider),
    ]);

    final neverPlayed =
        entry.game.lastPlayed == null && (entry.game.playTime ?? 0) == 0;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: cardWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 3 / 4,
              child: Container(
                decoration: BoxDecoration(
                  color: theme.cardColor.withValues(alpha: 0.35),
                  borderRadius:
                      radii?.radiusInternal ?? BorderRadius.circular(8.r),
                  border: Border.all(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withValues(alpha: 0.12),
                    width: isSelected ? 2.r : 1.r,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (artPath != null)
                      Image.file(
                        File(artPath),
                        fit: BoxFit.cover,
                        // Decode at roughly the size actually drawn: a shelf of
                        // full-resolution covers is the fastest way to blow the
                        // image cache on a handheld.
                        cacheWidth: (cardWidth * 2).round(),
                        errorBuilder: (_, _, _) => _placeholder(theme),
                      )
                    else
                      _placeholder(theme),
                    if (neverPlayed)
                      Positioned(
                        top: 4.r,
                        right: 4.r,
                        child: _NeverPlayedBadge(),
                      ),
                    if (caption != null && caption!.isNotEmpty)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _CaptionBar(text: caption!),
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 4.r),
            MarqueeText(
              text: entry.game.realName ?? entry.game.filename,
              isActive: isSelected,
              style: TextStyle(
                fontSize: 8.r,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.78),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(ThemeData theme) => ColoredBox(
    color: theme.cardColor.withValues(alpha: 0.4),
    child: Center(
      child: Icon(
        Symbols.videogame_asset_rounded,
        size: 24.r,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
      ),
    ),
  );

  /// The first path that is actually on disk, or null.
  ///
  /// `getImagePath` returns a best-effort path even when nothing matched, so
  /// the existence check is what decides between box art, screenshot and
  /// placeholder.
  String? _firstExisting(List<String> paths) {
    for (final path in paths) {
      if (path.isNotEmpty && File(path).existsSync()) return path;
    }
    return null;
  }
}

/// The genre strip across the foot of a cover.
///
/// Sits on its own gradient rather than straight on the art: box art is
/// arbitrary, and light covers would otherwise swallow the label.
class _CaptionBar extends StatelessWidget {
  const _CaptionBar({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 5.r, vertical: 3.r),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.78),
            Colors.black.withValues(alpha: 0),
          ],
        ),
      ),
      child: Text(
        text.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 6.r,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5.r,
          color: Colors.white.withValues(alpha: 0.9),
        ),
      ),
    );
  }
}

/// The badge marking a game the user has never launched — the whole point of
/// most of the board, so it is called out on the card rather than only in the
/// hero.
class _NeverPlayedBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 4.r, vertical: 2.r),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999.r),
      ),
      child: Text(
        AppLocale.discoveryNeverPlayed.getString(context),
        style: TextStyle(
          fontSize: 6.r,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onPrimary,
        ),
      ),
    );
  }
}
