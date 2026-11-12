import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A reader's list opened at one of its items: [initialIndex] is at the top
/// of the very first frame, with no travel to it from the start of the
/// surah, and nothing on the way is built. The items before it grow upwards
/// from it as the reader scrolls back, so the scroll offset is 0 at the
/// opened item and negative above it; text that reflows above the opened
/// item does not move it.
class ReaderAnchoredList extends StatefulWidget {
  const ReaderAnchoredList({
    required this.controller,
    required this.padding,
    required this.itemCount,
    required this.itemBuilder,
    this.initialIndex = 0,
    super.key,
  });

  final ScrollController controller;
  final EdgeInsetsGeometry padding;
  final int itemCount;
  final NullableIndexedWidgetBuilder itemBuilder;

  /// The item the list opens at; read once, when the list is first built.
  final int initialIndex;

  @override
  State<ReaderAnchoredList> createState() => _ReaderAnchoredListState();
}

class _ReaderAnchoredListState extends State<ReaderAnchoredList> {
  final _beforeKey = GlobalKey();
  final _centerKey = GlobalKey();
  late final _first = widget.initialIndex.clamp(0, widget.itemCount - 1);

  /// Where on the screen the opened item rests, as a share of its height:
  /// the top, unless the list ends less than a screen below the item.
  var _anchor = 0.0;

  @override
  void initState() {
    super.initState();
    if (_first > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fit(3));
    }
  }

  /// An item opened near the end of the list would leave the screen below
  /// the end empty: it rests lower then, the end of the list on the bottom
  /// of the screen, or the whole list from the top when it is that short.
  /// The items above are measured as they are built, so it looks again
  /// after a frame.
  void _fit(int passes) {
    if (!mounted || !widget.controller.hasClients) return;
    double? extent(GlobalKey key) {
      final sliver = key.currentContext?.findRenderObject();
      return sliver is RenderSliver ? sliver.geometry?.scrollExtent : null;
    }

    final before = extent(_beforeKey);
    final after = extent(_centerKey);
    final screen = widget.controller.position.viewportDimension;
    if (before == null || after == null || screen <= 0) return;
    final anchor = math.max(0.0, math.min(screen - after, before)) / screen;
    if ((anchor - _anchor).abs() * screen < .5) return;
    setState(() => _anchor = anchor);
    if (passes > 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fit(passes - 1));
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = widget.padding.resolve(Directionality.of(context));
    return CustomScrollView(
      controller: widget.controller,
      center: _centerKey,
      anchor: _anchor,
      slivers: <Widget>[
        SliverPadding(
          key: _beforeKey,
          padding: padding.copyWith(bottom: 0),
          sliver: SliverList.builder(
            itemCount: _first,
            itemBuilder: (context, index) =>
                widget.itemBuilder(context, _first - 1 - index),
          ),
        ),
        SliverPadding(
          key: _centerKey,
          padding: padding.copyWith(top: 0),
          sliver: SliverList.builder(
            itemCount: widget.itemCount - _first,
            itemBuilder: (context, index) =>
                widget.itemBuilder(context, _first + index),
          ),
        ),
      ],
    );
  }
}
