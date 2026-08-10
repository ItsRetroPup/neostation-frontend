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
import '../../search_screen/search_filter.dart';

/// The Game of the Week banner: the board's headline.
///
/// Built entirely from the user's own scraped art — fanart behind, the game's
/// wheel logo in front — so it looks like a storefront without any of the
/// content coming from outside the device.
class DiscoveryHeroCard extends StatelessWidget {
  const DiscoveryHeroCard({
    super.key,
    required this.entry,
    required this.isSelected,
    required this.fileProvider,
    required this.weekLabel,
    this.onTap,
  });

  final DiscoveryBoardEntry entry;
  final bool isSelected;
  final FileProvider fileProvider;

  /// Human-readable week, already localized by the caller.
  final String weekLabel;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radii = theme.extension<CornerRadii>();
    final game = GameModel.fromDatabaseModel(entry.game);
    final folder = entry.game.systemFolderName ?? '';

    final backdrop = _firstExisting([
      if (folder.isNotEmpty) game.getImagePath(folder, 'fanarts', fileProvider),
      if (folder.isNotEmpty)
        game.getImagePath(folder, 'screenshots', fileProvider),
    ]);
    final wheel = folder.isEmpty
        ? null
        : _firstExisting([game.getImagePath(folder, 'wheels', fileProvider)]);

    final rating = entry.game.rating;
    final hasRating = rating != null && rating > 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 150.r,
        decoration: BoxDecoration(
          color: theme.cardColor.withValues(alpha: 0.3),
          borderRadius: radii?.radiusExternal ?? BorderRadius.circular(14.r),
          border: Border.all(
            color: isSelected
                ? scheme.primary
                : scheme.primary.withValues(alpha: 0.15),
            width: isSelected ? 2.r : 1.r,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (backdrop != null)
              Image.file(
                File(backdrop),
                fit: BoxFit.cover,
                cacheWidth: 1280,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            // The art is arbitrary, so the text needs its own contrast rather
            // than trusting whatever happens to be behind it.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.black.withValues(alpha: 0.82),
                    Colors.black.withValues(alpha: 0.35),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(14.r),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Symbols.local_fire_department_rounded,
                        size: 14.r,
                        color: scheme.primary,
                      ),
                      SizedBox(width: 6.r),
                      Text(
                        AppLocale.discoveryGameOfTheWeek.getString(context),
                        style: TextStyle(
                          fontSize: 10.r,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1.r,
                          color: scheme.primary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        weekLabel,
                        style: TextStyle(
                          fontSize: 8.r,
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (wheel != null)
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: 44.r,
                            maxWidth: 220.r,
                          ),
                          child: Image.file(
                            File(wheel),
                            fit: BoxFit.contain,
                            alignment: Alignment.centerLeft,
                            cacheWidth: 440,
                            errorBuilder: (_, _, _) =>
                                _titleText(context, scheme),
                          ),
                        )
                      else
                        _titleText(context, scheme),
                      SizedBox(height: 8.r),
                      Row(
                        children: [
                          if (hasRating)
                            _Pill(
                              icon: Symbols.star_rounded,
                              // Stored 0..20, shown out of 10 — the scale the
                              // rest of the app displays.
                              label: searchRatingScore(
                                rating,
                              ).toStringAsFixed(1),
                              color: scheme.primary,
                            ),
                          if (hasRating) SizedBox(width: 6.r),
                          _Pill(
                            icon: Symbols.sports_esports_rounded,
                            label:
                                entry.game.systemShortName ??
                                entry.game.systemRealName ??
                                '',
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _titleText(BuildContext context, ColorScheme scheme) => Text(
    entry.game.realName ?? entry.game.filename,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: 18.r,
      fontWeight: FontWeight.w800,
      color: Colors.white,
      shadows: const [Shadow(blurRadius: 8, color: Colors.black87)],
    ),
  );

  String? _firstExisting(List<String> paths) {
    for (final path in paths) {
      if (path.isNotEmpty && File(path).existsSync()) return path;
    }
    return null;
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.r, vertical: 4.r),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999.r),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10.r, color: color),
          SizedBox(width: 4.r),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 8.r,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
