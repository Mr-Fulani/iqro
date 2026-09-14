import 'package:flutter/material.dart';

/// Content-sized rows keep translated labels and large type fully visible.
class IqroActionGrid extends StatelessWidget {
  const IqroActionGrid({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final largeType = MediaQuery.textScalerOf(context).scale(16) > 22;
      final columns = constraints.maxWidth < 300 || largeType
          ? 1
          : constraints.maxWidth >= 720
          ? 3
          : 2;
      return Column(
        children: [
          for (var start = 0; start < children.length; start += columns) ...[
            if (start > 0) const SizedBox(height: 12),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var column = 0; column < columns; column++) ...[
                    if (column > 0) const SizedBox(width: 12),
                    Expanded(
                      child: start + column < children.length
                          ? children[start + column]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      );
    },
  );
}
