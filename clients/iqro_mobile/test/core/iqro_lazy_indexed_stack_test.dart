import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/design_system/iqro_lazy_indexed_stack.dart';

void main() {
  testWidgets('builds tabs on first visit and retains their state', (
    tester,
  ) async {
    var firstBuilds = 0;
    var secondBuilds = 0;

    Widget app(int index) => MaterialApp(
      home: IqroLazyIndexedStack(
        index: index,
        builders: <WidgetBuilder>[
          (_) {
            firstBuilds += 1;
            return const _StatefulTab(label: 'first');
          },
          (_) {
            secondBuilds += 1;
            return const _StatefulTab(label: 'second');
          },
        ],
      ),
    );

    await tester.pumpWidget(app(0));
    expect(firstBuilds, 1);
    expect(secondBuilds, 0);
    await tester.tap(find.text('first:0'));
    await tester.pump();

    await tester.pumpWidget(app(1));
    expect(firstBuilds, 1);
    expect(secondBuilds, 1);
    await tester.tap(find.text('second:0'));
    await tester.pump();

    await tester.pumpWidget(app(0));
    expect(find.text('first:1'), findsOneWidget);
    expect(firstBuilds, 1);
    expect(secondBuilds, 1);
  });
}

class _StatefulTab extends StatefulWidget {
  const _StatefulTab({required this.label});

  final String label;

  @override
  State<_StatefulTab> createState() => _StatefulTabState();
}

class _StatefulTabState extends State<_StatefulTab> {
  var _count = 0;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => setState(() => _count += 1),
      child: Text('${widget.label}:$_count'),
    );
  }
}
