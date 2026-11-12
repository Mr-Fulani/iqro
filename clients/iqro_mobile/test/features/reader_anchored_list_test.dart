import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/quran/reader_anchored_list.dart';

void main() {
  testWidgets('a list opened at an item far down shows it at the top of the '
      'first frame and builds nothing on the way', (tester) async {
    final built = await _pump(tester, count: 300, initialIndex: 200);
    expect(tester.getTopLeft(find.text('item 200')).dy, 0);
    expect(built.reduce((a, b) => a < b ? a : b), greaterThan(190));

    // The items above are there to scroll back to.
    await tester.drag(find.byType(ReaderAnchoredList), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(find.text('item 197'), findsOneWidget);
    await tester.fling(
      find.byType(ReaderAnchoredList),
      const Offset(0, 30000),
      20000,
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('item 0')).dy, 10);
  });

  testWidgets('an item opened less than a screen from the end leaves no '
      'empty screen under the end', (tester) async {
    await _pump(tester, count: 300, initialIndex: 298);
    await tester.pumpAndSettle();
    // 600 high: the last item ends 20 above the bottom, on the padding.
    expect(tester.getBottomLeft(find.text('item 299')).dy, closeTo(580, .01));
    expect(find.text('item 298'), findsOneWidget);
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    expect(position.pixels, position.maxScrollExtent);
  });

  testWidgets('a list shorter than the screen opens from its top whichever '
      'item it opens at', (tester) async {
    await _pump(tester, count: 4, initialIndex: 3);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('item 0')).dy, closeTo(10, .01));
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    expect(position.minScrollExtent, position.maxScrollExtent);
  });
}

/// A list 600 high of items 100 high; returns the indexes it builds.
Future<Set<int>> _pump(
  WidgetTester tester, {
  required int count,
  required int initialIndex,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(400, 600);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final controller = ScrollController();
  addTearDown(controller.dispose);
  final built = <int>{};
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: ReaderAnchoredList(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 20),
        itemCount: count,
        initialIndex: initialIndex,
        itemBuilder: (context, index) {
          built.add(index);
          return SizedBox(height: 100, child: Text('item $index'));
        },
      ),
    ),
  );
  return built;
}
