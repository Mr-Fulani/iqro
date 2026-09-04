import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../app/providers.dart';
import '../../core/auth/account_scope.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import 'plan_repository.dart';

class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(planProvider);
    final database = ref.watch(localDatabaseProvider);
    final accountKey = ref.watch(activeAccountScopeKeyProvider);
    final scope = database.accountScope.current;
    final controller = ref.read(planProvider.notifier);
    final canMutate =
        scope != null &&
        accountKey == accountScopeKey(scope) &&
        controller.isBoundTo(scope);
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
          onRetry: () {
            if (canMutate) controller.reload();
          },
        ),
        data: (value) {
          final remaining = (value.target - value.achieved).clamp(
            0.0,
            value.target,
          );
          return IqroPage(
            padding: iqroRootTabPadding(playerActive: playerActive),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (value.fromCache) ...<Widget>[
                  IqroStatusBanner(
                    icon: Icons.cloud_off_outlined,
                    title: context.l10n.offlineUsingCache,
                    actionLabel: context.l10n.retry,
                    onAction: canMutate ? controller.reload : null,
                  ),
                  const SizedBox(height: 12),
                ],
                IqroCard(
                  color: context.iqroColors.ink,
                  borderColor: Colors.transparent,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: IqroEyebrow(
                              context.l10n.dailyGoal,
                              light: true,
                            ),
                          ),
                          IconButton(
                            tooltip: context.l10n.dailyGoal,
                            color: Colors.white,
                            onPressed: !canMutate || value.fromCache
                                ? null
                                : () => _editGoal(
                                    context,
                                    ref,
                                    controller,
                                    scope,
                                    value,
                                  ),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          Text(
                            _formatAmount(value.achieved),
                            style: Theme.of(context).textTheme.displaySmall
                                ?.copyWith(color: Colors.white),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsetsDirectional.only(
                                start: 4,
                                bottom: 4,
                              ),
                              child: Text(
                                '/ ${_formatAmount(value.target)} '
                                '${_metricLabel(context, value.metric)}',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: .7),
                                ),
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
                        '${context.l10n.remaining}: '
                        '${_formatAmount(remaining)} '
                        '${_metricLabel(context, value.metric)}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .72),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: !canMutate || value.fromCache
                        ? null
                        : () => _addReading(
                            context,
                            ref,
                            controller,
                            scope,
                            value.metric,
                          ),
                    icon: const Icon(Icons.add),
                    label: Text(context.l10n.manualEntry),
                  ),
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
                _StreakCard(plan: value),
                if (value.history.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 10),
                  for (final day in value.history.take(7)) ...<Widget>[
                    _HistoryCard(day: day),
                    const SizedBox(height: 8),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _editGoal(
    BuildContext context,
    WidgetRef ref,
    PlanController controller,
    AccountScopeSnapshot scope,
    DailyPlan current,
  ) async {
    final draft = await showModalBottomSheet<_GoalDraft>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _GoalEditor(current: current),
    );
    if (draft == null || !context.mounted) return;
    if (!_stillCurrent(ref, controller, scope)) return;
    try {
      await controller.setGoal(
        draft.metric,
        draft.target,
        current.goalRevision,
      );
      if (!_stillCurrent(ref, controller, scope)) return;
      await ref
          .read(appPreferencesProvider.notifier)
          .setDailyReadingGoal(
            unit: dailyUnitForReadingMetric(draft.metric),
            target: draft.target,
          );
    } on Object {
      if (context.mounted) _showError(context);
    }
  }

  Future<void> _addReading(
    BuildContext context,
    WidgetRef ref,
    PlanController controller,
    AccountScopeSnapshot scope,
    ReadingGoalMetric metric,
  ) async {
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
                context.l10n.manualEntry,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(_metricLabel(context, metric)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  for (final amount in _manualAmounts(metric))
                    ActionChip(
                      label: Text('+$amount'),
                      onPressed: () => Navigator.pop(context, amount),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (value == null || !context.mounted) return;
    if (!_stillCurrent(ref, controller, scope)) return;
    try {
      await controller.addReading(value, metric);
    } on Object {
      if (context.mounted) _showError(context);
    }
  }

  bool _stillCurrent(
    WidgetRef ref,
    PlanController controller,
    AccountScopeSnapshot scope,
  ) {
    final database = ref.read(localDatabaseProvider);
    return database.accountScope.isCurrent(scope) &&
        controller.isBoundTo(scope) &&
        identical(ref.read(planProvider.notifier), controller);
  }

  void _showError(BuildContext context) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(context.l10n.networkError)));
}

class _GoalDraft {
  const _GoalDraft(this.metric, this.target);

  final ReadingGoalMetric metric;
  final int target;
}

class _GoalEditor extends StatefulWidget {
  const _GoalEditor({required this.current});

  final DailyPlan current;

  @override
  State<_GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends State<_GoalEditor> {
  late ReadingGoalMetric _metric = widget.current.metric;
  late final TextEditingController _target = TextEditingController(
    text: _formatAmount(widget.current.target),
  );
  String? _error;

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              context.l10n.dailyGoal,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final metric in ReadingGoalMetric.values)
                  ChoiceChip(
                    label: Text(_metricLabel(context, metric)),
                    selected: _metric == metric,
                    onSelected: (_) => setState(() {
                      _metric = metric;
                      _error = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _target,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: context.l10n.dailyGoal,
                suffixText: _metricLabel(context, _metric),
                errorText: _error,
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(context.l10n.cancel),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _save,
                    child: Text(context.l10n.save),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    final value = int.tryParse(_target.text.trim());
    if (value == null || value < 1 || value > maximumReadingTarget(_metric)) {
      setState(() => _error = '1–${maximumReadingTarget(_metric)}');
      return;
    }
    Navigator.pop(context, _GoalDraft(_metric, value));
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.plan});

  final DailyPlan plan;

  @override
  Widget build(BuildContext context) {
    return IqroCard(
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
              '${plan.streak} ${context.l10n.today.toLowerCase()}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Text(
            '★ ${plan.longestStreak}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.day});

  final ReadingHistoryDay day;

  @override
  Widget build(BuildContext context) {
    final metric = day.metric;
    final locale = Localizations.localeOf(context).languageCode;
    return IqroCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        minTileHeight: 58,
        leading: Icon(
          _stateIcon(day.state),
          color: _stateColor(context, day.state),
        ),
        title: Text(
          day.localDate == null
              ? '—'
              : DateFormat.MMMEd(locale).format(day.localDate!),
        ),
        subtitle: day.automaticSeconds <= 0
            ? null
            : Text(
                '${(day.automaticSeconds / 60).ceil()} ${context.l10n.minutes}',
              ),
        trailing: metric == null
            ? const Text('—')
            : Text(
                '${_formatAmount(day.achieved)} / '
                '${_formatAmount(day.target)} '
                '${_metricLabel(context, metric)}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
      ),
    );
  }
}

class AfterPrayerScreen extends ConsumerWidget {
  const AfterPrayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(planProvider);
    final database = ref.watch(localDatabaseProvider);
    final accountKey = ref.watch(activeAccountScopeKeyProvider);
    final scope = database.accountScope.current;
    final controller = ref.read(planProvider.notifier);
    final canMutate =
        scope != null &&
        accountKey == accountScopeKey(scope) &&
        controller.isBoundTo(scope);
    return Scaffold(
      appBar: IqroTopBar(title: context.l10n.afterPrayerPlan),
      body: plan.when(
        loading: () => const IqroLoading(),
        error: (error, stack) => IqroAsyncError(
          title: context.l10n.networkError,
          onRetry: () {
            if (canMutate) controller.reload();
          },
        ),
        data: (value) => IqroPage(
          child: Column(
            children: <Widget>[
              if (value.fromCache) ...<Widget>[
                IqroStatusBanner(
                  icon: Icons.cloud_off_outlined,
                  title: context.l10n.offlineUsingCache,
                ),
                const SizedBox(height: 12),
              ],
              for (final entry in value.prayerPages.entries)
                Padding(
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
                          onPressed:
                              entry.value <= 0 || !canMutate || value.fromCache
                              ? null
                              : () => _setPrayerPages(
                                  context,
                                  controller,
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
                          onPressed: !canMutate || value.fromCache
                              ? null
                              : () => _setPrayerPages(
                                  context,
                                  controller,
                                  entry.key,
                                  entry.value + 1,
                                ),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _setPrayerPages(
    BuildContext context,
    PlanController controller,
    String prayer,
    int pages,
  ) async {
    try {
      await controller.setPrayerPages(prayer, pages);
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(context.l10n.networkError)));
    }
  }
}

String _prayerName(BuildContext context, String code) => switch (code) {
  'fajr' => context.l10n.fajr,
  'dhuhr' => context.l10n.dhuhr,
  'asr' => context.l10n.asr,
  'maghrib' => context.l10n.maghrib,
  _ => context.l10n.isha,
};

String _metricLabel(BuildContext context, ReadingGoalMetric metric) =>
    switch (metric) {
      ReadingGoalMetric.minutes => context.l10n.minutes,
      ReadingGoalMetric.pages => context.l10n.pages,
      ReadingGoalMetric.ayahs => context.l10n.ayahs,
    };

List<int> _manualAmounts(ReadingGoalMetric metric) => switch (metric) {
  ReadingGoalMetric.minutes => const <int>[5, 10, 15, 30],
  ReadingGoalMetric.pages => const <int>[1, 2, 3, 5, 10],
  ReadingGoalMetric.ayahs => const <int>[1, 5, 10, 20],
};

String _formatAmount(num value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

IconData _stateIcon(String state) => switch (state) {
  'completed' => Icons.check_circle_outline,
  'partial' => Icons.timelapse_outlined,
  'missed' => Icons.cancel_outlined,
  _ => Icons.circle_outlined,
};

Color _stateColor(BuildContext context, String state) => switch (state) {
  'completed' => Colors.green.shade600,
  'partial' => context.iqroColors.gold,
  'missed' => Theme.of(context).colorScheme.error,
  _ => Theme.of(context).colorScheme.outline,
};
