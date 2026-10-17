import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/design_system/iqro_icon.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget icon) => tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: IconTheme(
        data: const IconThemeData(color: Color(0xFF0B5D4A), size: 24),
        child: Center(child: icon),
      ),
    ),
  );

  testWidgets('the du\'a icon is drawn in the icon theme, not a font glyph', (
    tester,
  ) async {
    await pump(tester, const IqroIcon(iqroDuaIcon, size: 42));

    expect(find.byType(RichText), findsNothing);
    final paint = find.descendant(
      of: find.byType(IqroIcon),
      matching: find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter != null,
      ),
    );
    expect(tester.getSize(paint), const Size.square(42));
    expect(
      (tester.widget<CustomPaint>(paint).painter! as dynamic).color,
      const Color(0xFF0B5D4A),
    );
  });

  testWidgets('the du\'a icon takes an explicit colour', (tester) async {
    await pump(tester, const IqroIcon(iqroDuaIcon, color: Color(0xFFD5A34C)));

    final painter = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byType(IqroIcon),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;
    expect((painter as dynamic).color, const Color(0xFFD5A34C));
  });

  testWidgets('other icons still come from the icon font', (tester) async {
    await pump(tester, const IqroIcon(Icons.repeat));

    expect(find.byType(RichText), findsOneWidget);
  });
}
