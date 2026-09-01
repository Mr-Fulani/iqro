import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';

class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(planProvider);
    final playerActive = ref.watch(
      audioControllerProvider.select((value) => value.active),
    );
    return Scaffold(
      appBar: IqroTopBar(
        title: context.l10n.dailyPlan,
        subtitle: context.l10n.today,
      ),
      body: plan.when(
        loading: () => const IqroLoading(),
        error: (error, stack) => IqroAsyncError(
          title: context.l10n.networkError,
          onRetry: ref.read(planProvider.notifier).reload,
        ),
        data: (value) {
          final remaining = (value.target - value.achieved).clamp(
            0,
            value.target,
          );
          return IqroPage(
            padding: iqroRootTabPadding(playerActive: playerActive),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                IqroCard(
                  color: context.iqroColors.ink,
                  borderColor: Colors.transparent,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      IqroEyebrow(context.l10n.dailyGoal, light: true),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          Text(
                            '${value.achieved}',
                            style: Theme.of(context).textTheme.displaySmall
                                ?.copyWith(color: Colors.white),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              ' / ${value.target} ${context.l10n.pages}',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: .7),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      LinearProgressIndicator(
                        value: value.target == 0
                            ? 0
                            : (value.achieved / value.target).clamp(0.0, 1.0),
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${context.l10n.remaining}: $remaining',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .72),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _addPages(context, ref),
                        icon: const Icon(Icons.add),
                        label: Text(context.l10n.manualEntry),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                IqroSectionHeader(
                  title: context.l10n.afterPrayerPlan,
                  eyebrow: context.l10n.yourRhythm,
                ),
                const SizedBox(height: 12),
                IqroCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  onTap: () => context.push('/after-prayer'),
                  child: Column(
                    children: <Widget>[
                      for (final entry in value.prayerPages.entries)
                        ListTile(
                          minTileHeight: 54,
                          leading: Icon(
                            Icons.mosque_outlined,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          title: Text(_prayerName(context, entry.key)),
                          trailing: Text(
                            '${entry.value} ${context.l10n.pages}',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                IqroSectionHeader(title: context.l10n.history),
                const SizedBox(height: 12),
                IqroCard(
                  color: context.iqroColors.lavender,
                  borderColor: Colors.transparent,
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.local_fire_department_outlined,
                        color: context.iqroColors.gold,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${value.streak} ${context.l10n.today.toLowerCase()}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _addPages(BuildContext context, WidgetRef ref) async {
    final value = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                context.l10n.addPages,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  for (final pages in const <int>[1, 2, 3, 5, 10])
                    ActionChip(
                      label: Text('+$pages'),
                      onPressed: () => Navigator.pop(context, pages),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (value != null) await ref.read(planProvider.notifier).addPages(value);
  }
}

String _prayerName(BuildContext context, String code) => switch (code) {
  'fajr' => context.l10n.fajr,
  'dhuhr' => context.l10n.dhuhr,
  'asr' => context.l10n.asr,
  'maghrib' => context.l10n.maghrib,
  _ => context.l10n.isha,
};

class AfterPrayerScreen extends ConsumerWidget {
  const AfterPrayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(planProvider);
    return Scaffold(
      appBar: IqroTopBar(title: context.l10n.afterPrayerPlan),
      body: plan.when(
        loading: () => const IqroLoading(),
        error: (error, stack) => IqroAsyncError(
          title: context.l10n.networkError,
          onRetry: ref.read(planProvider.notifier).reload,
        ),
        data: (value) => IqroPage(
          child: Column(
            children: value.prayerPages.entries
                .map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: IqroCard(
                      child: Row(
                        children: <Widget>[
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: context.iqroColors.sand,
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Icon(
                              Icons.mosque_outlined,
                              color: context.iqroColors.gold,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              _prayerName(context, entry.key),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            onPressed: entry.value <= 0
                                ? null
                                : () => ref
                                      .read(planProvider.notifier)
                                      .setPrayerPages(
                                        entry.key,
                                        entry.value - 1,
                                      ),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          SizedBox(
                            width: 28,
                            child: Text(
                              '${entry.value}',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            onPressed: () => ref
                                .read(planProvider.notifier)
                                .setPrayerPages(entry.key, entry.value + 1),
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                    ),
                  );
                })
                .toList(growable: false),
          ),
        ),
      ),
    );
  }
}
