import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

/// The page and the current step of a step-by-step lesson: the Salah lessons
/// and the tajweed breakdown turn their steps with it.
class IqroStepController {
  IqroStepController({int initialIndex = 0})
    : pages = PageController(initialPage: initialIndex),
      index = ValueNotifier<int>(initialIndex);

  final PageController pages;

  // The header and the buttons follow the page; the pager itself is not
  // rebuilt when it changes.
  final ValueNotifier<int> index;

  /// Turns to [target] when it is a step of [count].
  void goTo(BuildContext context, int target, int count) {
    if (target < 0 || target >= count || !pages.hasClients) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      pages.jumpToPage(target);
    } else {
      unawaited(
        pages.animateToPage(
          target,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  void dispose() {
    pages.dispose();
    index.dispose();
  }
}

/// The steps in a pager. Screen readers get «Next» and «Previous» actions,
/// and a hardware keyboard turns the steps with the arrow keys, forward in
/// the reading direction.
class IqroStepPager extends StatelessWidget {
  const IqroStepPager({
    required this.controller,
    required this.itemCount,
    required this.itemBuilder,
    required this.onPageChanged,
    required this.onNext,
    required this.onPrevious,
    required this.nextLabel,
    required this.previousLabel,
    required this.keyPrefix,
    super.key,
  });

  final IqroStepController controller;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  /// Called after [controller]'s index has moved to the new page.
  final ValueChanged<int> onPageChanged;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final String nextLabel;
  final String previousLabel;

  /// Keys `<prefix>-steps` (the pager) and `<prefix>-step-actions`.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.arrowRight): rtl
            ? onPrevious
            : onNext,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): rtl
            ? onNext
            : onPrevious,
      },
      child: Focus(
        autofocus: true,
        child: Semantics(
          key: ValueKey('$keyPrefix-step-actions'),
          container: true,
          customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
            CustomSemanticsAction(label: nextLabel): onNext,
            CustomSemanticsAction(label: previousLabel): onPrevious,
          },
          // PageView follows the reading direction: in RTL the next step
          // comes from the left.
          child: PageView.builder(
            key: ValueKey('$keyPrefix-steps'),
            controller: controller.pages,
            itemCount: itemCount,
            onPageChanged: (index) {
              controller.index.value = index;
              onPageChanged(index);
            },
            itemBuilder: itemBuilder,
          ),
        ),
      ),
    );
  }
}

/// «Back» and «Next»; the last step's button finishes the lesson.
class IqroStepButtons extends StatelessWidget {
  const IqroStepButtons({
    required this.isFirst,
    required this.isLast,
    required this.onBack,
    required this.onNext,
    required this.backLabel,
    required this.nextLabel,
    required this.finishLabel,
    required this.keyPrefix,
    this.finishIcon = Icons.check,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 12),
    super.key,
  });

  final bool isFirst;
  final bool isLast;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final String backLabel;
  final String nextLabel;
  final String finishLabel;
  final IconData finishIcon;
  final EdgeInsetsGeometry padding;

  /// Keys `<prefix>-back` and `<prefix>-next`.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    Widget label(String text) =>
        Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);
    return Padding(
      padding: padding,
      child: Row(
        children: <Widget>[
          Expanded(
            child: OutlinedButton.icon(
              key: ValueKey('$keyPrefix-back'),
              onPressed: isFirst ? null : onBack,
              icon: const Icon(Icons.arrow_back),
              label: label(backLabel),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              key: ValueKey('$keyPrefix-next'),
              onPressed: onNext,
              icon: Icon(isLast ? finishIcon : Icons.arrow_forward),
              label: label(isLast ? finishLabel : nextLabel),
            ),
          ),
        ],
      ),
    );
  }
}
