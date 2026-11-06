import 'package:flutter/material.dart';

/// Widest the Home dashboard grows on a tablet, padding included. A landscape
/// tablet (1280 dp) keeps its end edge free for the mini player's button.
const homeTabletContentWidth = 1100.0;

/// Content width where Home leaves the phone's spacing (Material's medium
/// window class).
const homeMediumWidth = 600.0;

/// Home's order on every width, as on the site: the sky of prayers, the
/// reading to continue with the day's plan, then the sections. Tiles spread
/// into one row across a wide tablet.
class HomeDashboardLayout extends StatelessWidget {
  const HomeDashboardLayout({
    required this.prayer,
    required this.reading,
    required this.sections,
    this.guest,
    super.key,
  });

  final Widget prayer;
  final Widget reading;
  final Widget sections;
  final Widget? guest;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final gap = constraints.maxWidth < homeMediumWidth ? 12.0 : 24.0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          prayer,
          SizedBox(height: gap),
          reading,
          SizedBox(height: gap + 6),
          sections,
          if (guest case final guest?) ...<Widget>[
            SizedBox(height: gap + 2),
            guest,
          ],
        ],
      );
    },
  );
}
