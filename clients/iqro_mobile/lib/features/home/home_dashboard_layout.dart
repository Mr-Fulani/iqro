import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/design_system/iqro_action_grid.dart';
import '../../core/design_system/iqro_widgets.dart';

/// Widest the Home dashboard grows on a tablet, padding included. A landscape
/// tablet (1280 dp) keeps its end edge free for the mini player's button.
const homeTabletContentWidth = 1100.0;

/// Content width where Home leaves the phone's single column (Material's
/// medium window class).
const homeMediumWidth = 600.0;

// The site's desktop home: sections 24 apart, cards in a row 16 apart.
const _sectionGap = 24.0;

/// Home's cards laid out for the width: one column on a phone; on a tablet
/// the order and grid of the site's desktop home (`HomePage.tsx`): reading
/// first like its hero, the daily goal, paired cards of equal height, and the
/// prayer times last, across the full width.
class HomeDashboardLayout extends StatelessWidget {
  const HomeDashboardLayout({
    required this.prayer,
    required this.reading,
    required this.plan,
    required this.features,
    required this.utilities,
    this.guest,
    super.key,
  });

  final Widget prayer;
  final Widget reading;
  final Widget plan;

  /// Shown in pairs on a tablet; the first pair stands above the utilities.
  final List<Widget> features;
  final List<Widget> utilities;
  final Widget? guest;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      // Large type needs the full width for every card, as on a phone.
      final largeType = MediaQuery.textScalerOf(context).scale(16) > 22;
      final List<Widget> children;
      if (width < homeMediumWidth || largeType) {
        children = <Widget>[
          prayer,
          const SizedBox(height: 12),
          reading,
          const SizedBox(height: 12),
          plan,
          const SizedBox(height: 16),
          IqroActionGrid(children: features),
          const SizedBox(height: 16),
          _utilityList(),
          if (guest case final guest?) ...<Widget>[
            const SizedBox(height: 14),
            guest,
          ],
        ];
      } else {
        final pairs = <Widget>[
          for (var start = 0; start < features.length; start += 2)
            _CardRow(children: features.skip(start).take(2).toList()),
        ];
        children = <Widget>[
          reading,
          const SizedBox(height: _sectionGap),
          plan,
          if (pairs.isNotEmpty) ...[
            const SizedBox(height: _sectionGap),
            pairs.first,
          ],
          const SizedBox(height: _sectionGap),
          _CardRow(
            children: <Widget>[
              for (final utility in utilities)
                IqroCard(padding: _utilityPadding, child: utility),
            ],
          ),
          if (guest case final guest?) ...[
            const SizedBox(height: _sectionGap),
            guest,
          ],
          for (final pair in pairs.skip(1)) ...[
            const SizedBox(height: _sectionGap),
            pair,
          ],
          const SizedBox(height: _sectionGap),
          prayer,
        ];
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      );
    },
  );

  static const _utilityPadding = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 4,
  );

  Widget _utilityList() => IqroCard(
    padding: _utilityPadding,
    child: Column(
      children: <Widget>[
        for (var index = 0; index < utilities.length; index++) ...[
          if (index > 0) const Divider(height: 1),
          utilities[index],
        ],
      ],
    ),
  );
}

/// Equal-width cards stretched to the tallest one. Unlike [IntrinsicHeight]
/// it lays the cards out instead of asking for intrinsic sizes, which the
/// cards' own [LayoutBuilder]s cannot answer.
class _CardRow extends MultiChildRenderObjectWidget {
  const _CardRow({required super.children});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCardRow(Directionality.of(context));

  @override
  void updateRenderObject(BuildContext context, _RenderCardRow renderObject) {
    renderObject.textDirection = Directionality.of(context);
  }
}

class _CardRowParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderCardRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _CardRowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _CardRowParentData> {
  _RenderCardRow(this._textDirection);

  static const _gap = 16.0;

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _CardRowParentData) {
      child.parentData = _CardRowParentData();
    }
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    if (childCount == 0) {
      size = constraints.constrain(Size(width, 0));
      return;
    }
    final cell = (width - _gap * (childCount - 1)) / childCount;
    var height = 0.0;
    var child = firstChild;
    while (child != null) {
      child.layout(BoxConstraints.tightFor(width: cell), parentUsesSize: true);
      height = math.max(height, child.size.height);
      child = childAfter(child);
    }
    var x = 0.0;
    child = firstChild;
    while (child != null) {
      // A minimum, not a tight height: under tight constraints a card would
      // relayout alone when its data arrives and overflow the old height.
      child.layout(
        BoxConstraints(minWidth: cell, maxWidth: cell, minHeight: height),
        parentUsesSize: true,
      );
      (child.parentData! as _CardRowParentData).offset = Offset(
        _textDirection == TextDirection.rtl ? width - x - cell : x,
        0,
      );
      x += cell + _gap;
      child = childAfter(child);
    }
    size = constraints.constrain(Size(width, height));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
