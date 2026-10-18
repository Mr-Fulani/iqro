import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'iqro_widgets.dart';

/// The count after one more tap on a counter of [total] repetitions. A light
/// tap per repetition, a strong one and a vibration at the end; a finished
/// count starts again on the next tap.
int advanceRepetitionCount(int completed, int total) {
  if (completed >= total) return 0;
  final next = completed + 1;
  if (next == total) {
    unawaited(HapticFeedback.heavyImpact());
    unawaited(HapticFeedback.vibrate());
  } else {
    unawaited(HapticFeedback.lightImpact());
  }
  return next;
}

/// Counts down the repetitions of a formula: tap after each one. Shared by
/// du'a and prayer lessons; the owner keeps the count and advances it with
/// [advanceRepetitionCount].
class IqroRepetitionCounter extends StatelessWidget {
  const IqroRepetitionCounter({
    required this.total,
    required this.completed,
    required this.onTap,
    super.key,
  });

  final int total;
  final int completed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final remaining = (total - completed).clamp(0, total);
    final done = remaining == 0;
    return Semantics(
      button: true,
      label: done
          ? context.l10n.done
          : context.l10n.duaCounterRemaining(remaining),
      excludeSemantics: true,
      child: Material(
        color: done ? scheme.primary : scheme.primaryContainer,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(
            dimension: 112,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                SizedBox.square(
                  dimension: 100,
                  child: CircularProgressIndicator(
                    value: total == 0 ? 0 : completed / total,
                    strokeWidth: 3,
                    color: done ? scheme.onPrimary : scheme.primary,
                    backgroundColor: Colors.transparent,
                  ),
                ),
                done
                    ? Icon(
                        Icons.check_rounded,
                        size: 44,
                        color: scheme.onPrimary,
                      )
                    // The count stays inside the circle at any text size.
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Text(
                            '$remaining',
                            style: Theme.of(context).textTheme.displaySmall
                                ?.copyWith(color: scheme.primary),
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
