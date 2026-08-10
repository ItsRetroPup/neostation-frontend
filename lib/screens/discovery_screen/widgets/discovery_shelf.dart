import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../models/discovery_models.dart';
import '../../../providers/file_provider.dart';
import 'discovery_card.dart';

/// A horizontal row of Discovery picks under a section heading.
///
/// A plain `ListView.builder` rather than `NativeCarousel`: that widget is a
/// full-page PageView, which is the wrong shape for a shelf several of which
/// share one scrolling page.
class DiscoveryShelf extends StatefulWidget {
  const DiscoveryShelf({
    super.key,
    required this.entries,
    required this.fileProvider,
    required this.isRowSelected,
    required this.selectedIndex,
    required this.cardWidth,
    this.onCardTapped,
    this.captionBuilder,
  });

  final List<DiscoveryBoardEntry> entries;
  final FileProvider fileProvider;

  /// Whether the cursor is on this shelf. Only then does a card draw as
  /// selected, so the board shows one focus ring rather than one per row.
  final bool isRowSelected;

  final int selectedIndex;
  final double cardWidth;
  final void Function(int index)? onCardTapped;

  /// Supplies each card's caption. The genre shelf uses it to name the bucket
  /// behind each pick; other shelves leave it null.
  final String Function(DiscoveryBoardEntry entry)? captionBuilder;

  @override
  State<DiscoveryShelf> createState() => _DiscoveryShelfState();
}

class _DiscoveryShelfState extends State<DiscoveryShelf> {
  final ScrollController _controller = ScrollController();

  @override
  void didUpdateWidget(DiscoveryShelf oldWidget) {
    super.didUpdateWidget(oldWidget);
    final movedWithinRow =
        widget.isRowSelected && widget.selectedIndex != oldWidget.selectedIndex;
    final arrivedOnRow = widget.isRowSelected && !oldWidget.isRowSelected;
    if (movedWithinRow || arrivedOnRow) _scrollSelectionIntoView();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Keeps the selected card on screen as the cursor walks the shelf.
  ///
  /// Runs after the frame because the extent is only known once the list has
  /// laid out — on the frame the cursor first arrives, it has not.
  void _scrollSelectionIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;

      final spacing = 8.r;
      final itemExtent = widget.cardWidth + spacing;
      final viewport = _controller.position.viewportDimension;
      // Park the card one slot in from the left edge, so there is always a hint
      // of the neighbour and the shelf reads as scrollable.
      final target = (widget.selectedIndex * itemExtent) - itemExtent / 2;
      final clamped = target.clamp(
        _controller.position.minScrollExtent,
        _controller.position.maxScrollExtent,
      );
      if (viewport <= 0) return;

      _controller.animateTo(
        clamped,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Height is the card's 3:4 cover plus the title line beneath it.
    final height = widget.cardWidth * 4 / 3 + 18.r;

    return SizedBox(
      height: height,
      child: ListView.separated(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: widget.entries.length,
        separatorBuilder: (_, _) => SizedBox(width: 8.r),
        itemBuilder: (context, index) => DiscoveryCard(
          entry: widget.entries[index],
          isSelected: widget.isRowSelected && index == widget.selectedIndex,
          fileProvider: widget.fileProvider,
          width: widget.cardWidth,
          caption: widget.captionBuilder?.call(widget.entries[index]),
          onTap: () => widget.onCardTapped?.call(index),
        ),
      ),
    );
  }
}
