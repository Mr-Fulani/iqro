import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import 'memorization_repository.dart';

/// The current range, the queue and the memorized count, above the practice.
/// With no current range (just marked memorized) the queue's head is offered.
class MemorizationListCard extends ConsumerWidget {
  const MemorizationListCard({
    super.key,
    required this.dashboard,
    required this.busy,
    required this.onStart,
    required this.onMemorized,
    required this.onRemove,
  });

  final MemorizationDashboard dashboard;
  final bool busy;
  final ValueChanged<MemorizationItem> onStart;
  final ValueChanged<MemorizationItem> onMemorized;
  final ValueChanged<MemorizationItem> onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final surahs = ref.watch(quranCatalogProvider).valueOrNull?.surahs;
    String label(MemorizationItem item) {
      final surah = surahs?.where((entry) => entry.number == item.surah);
      final start = item.startAyah.ayah;
      final end = item.endAyah.ayah;
      return l10n.memorizationListItemRange(
        surah?.firstOrNull?.nameFor(locale) ?? '${l10n.surah} ${item.surah}',
        start == end ? '$start' : '$start–$end',
      );
    }

    final active = dashboard.activeItem;
    final queued = dashboard.queuedItems;
    final next = active == null ? queued.firstOrNull : null;
    return IqroCard(
      key: const ValueKey('memorization-list'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l10n.memorizationListCurrent,
                      style: theme.textTheme.labelMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      active == null
                          ? l10n.memorizationListNoCurrent
                          : label(active),
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                l10n.memorizationListMemorizedCount(
                  dashboard.memorizedAyahCount,
                ),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          if (active != null) ...<Widget>[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const ValueKey('memorization-list-memorized'),
              onPressed: busy ? null : () => onMemorized(active),
              icon: const Icon(Icons.check_rounded),
              label: Text(l10n.memorizationListMarkMemorized),
            ),
          ],
          if (next != null) ...<Widget>[
            const SizedBox(height: 10),
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        l10n.memorizationListNextPrompt(label(next)),
                        style: TextStyle(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    FilledButton(
                      key: const ValueKey('memorization-list-begin'),
                      onPressed: busy ? null : () => onStart(next),
                      child: Text(l10n.memorizationListBegin),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (queued.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              l10n.memorizationListQueue(queued.length),
              style: theme.textTheme.labelMedium,
            ),
            for (final item in queued)
              Row(
                children: <Widget>[
                  Expanded(child: Text(label(item))),
                  TextButton(
                    onPressed: busy ? null : () => onStart(item),
                    child: Text(l10n.memorizationListLearnNow),
                  ),
                  IconButton(
                    tooltip: l10n.memorizationListRemove(label(item)),
                    onPressed: busy ? null : () => onRemove(item),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}
