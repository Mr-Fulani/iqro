import 'package:flutter/widgets.dart';

class IqroLazyIndexedStack extends StatefulWidget {
  const IqroLazyIndexedStack({
    required this.index,
    required this.builders,
    super.key,
  }) : assert(builders.length > 0),
       assert(index >= 0 && index < builders.length);

  final int index;
  final List<WidgetBuilder> builders;

  @override
  State<IqroLazyIndexedStack> createState() => _IqroLazyIndexedStackState();
}

class _IqroLazyIndexedStackState extends State<IqroLazyIndexedStack> {
  late List<Widget?> _children;

  @override
  void initState() {
    super.initState();
    _children = List<Widget?>.filled(widget.builders.length, null);
    _ensureBuilt(widget.index);
  }

  @override
  void didUpdateWidget(covariant IqroLazyIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.builders.length != widget.builders.length) {
      final previous = _children;
      _children = List<Widget?>.filled(widget.builders.length, null);
      final retained = previous.length < _children.length
          ? previous.length
          : _children.length;
      for (var index = 0; index < retained; index += 1) {
        _children[index] = previous[index];
      }
    }
    _ensureBuilt(widget.index);
  }

  void _ensureBuilt(int index) {
    _children[index] ??= Builder(builder: widget.builders[index]);
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.index,
      children: <Widget>[
        for (final child in _children) child ?? const SizedBox.shrink(),
      ],
    );
  }
}
