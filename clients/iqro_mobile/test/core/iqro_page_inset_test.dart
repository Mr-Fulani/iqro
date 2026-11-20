import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/design_system/iqro_widgets.dart';

// A phone with three-button navigation: the system bar takes 48 dp at the
// bottom. Settings and other pushed screens ended under it.
void main() {
  testWidgets('a pushed page ends above the system navigation bar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: IqroPage(
            scrollable: false,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(key: ValueKey('last'), height: 40),
            ),
          ),
        ),
      ),
    );
    final last = tester.getRect(find.byKey(const ValueKey('last')));
    // 24 of the page's own bottom padding plus the 48 of the bar.
    expect(last.bottom, 800 - 24 - 48);
  });

  testWidgets('a root tab keeps its room for the navigation bar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          extendBody: true,
          // Like NavigationBar, the bar pads itself above the system bar.
          bottomNavigationBar: const SafeArea(
            top: false,
            child: SizedBox(height: 72),
          ),
          body: Builder(
            builder: (context) => IqroPage(
              scrollable: false,
              padding: iqroRootTabPadding(context, playerActive: false),
              child: const Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(key: ValueKey('last'), height: 40),
              ),
            ),
          ),
        ),
      ),
    );
    final last = tester.getRect(find.byKey(const ValueKey('last')));
    // Above the 72 dp bar, which itself sits above the 48 dp system bar.
    expect(last.bottom, 800 - 48 - 72 - 4);
  });

  // iPad mini and iPad 11", an Android tablet, and phones for comparison.
  for (final (device, size, width) in <(String, Size, double)>[
    ('iPad mini upright', const Size(744, 1133), 640),
    ('iPad upright', const Size(834, 1194), 640),
    ('iPad on its side', const Size(1194, 834), 640),
    ('Android tablet upright', const Size(800, 1280), 640),
    ('small tablet upright', const Size(600, 960), 600),
    ('iPhone upright', const Size(393, 852), 393),
    ('iPhone on its side', const Size(852, 393), 640),
  ]) {
    testWidgets('$device: a page is $width dp wide, centred', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: IqroPage(
              padding: EdgeInsets.zero,
              child: SizedBox(
                key: ValueKey('content'),
                width: double.infinity,
                height: 40,
              ),
            ),
          ),
        ),
      );
      final content = tester.getRect(find.byKey(const ValueKey('content')));
      expect(content.width, width);
      expect(content.center.dx, size.width / 2);
    });
  }

  testWidgets('a tablet screen with its own width keeps it upright', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(834, 1194);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: IqroPage(
            padding: EdgeInsets.zero,
            tabletContentWidth: 1100,
            child: SizedBox(
              key: ValueKey('content'),
              width: double.infinity,
              height: 40,
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(const ValueKey('content'))).width, 834);
  });
}
