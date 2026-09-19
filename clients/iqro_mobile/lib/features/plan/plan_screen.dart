import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../app/providers.dart';
import '../../core/auth/account_scope.dart';
import '../../core/widgets/home_widget_pinning.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import '../audio/mini_player.dart';
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
        actions: [
          IconButton(
            tooltip: context.l10n.addPrayerWidget,
            icon: const Icon(Icons.widgets_outlined),
            onPressed: canMutate && plan.asData != null
                ? () => _addHomeWidget(context, ref, plan.asData!.value, scope)
                : null,
          ),
        ],
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
          return IqroPage(
            padding: iqroRootTabPadding(
              playerActive: playerActive,
              playerCollapsed: ref.watch(miniPlayerCollapsedProvider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (value.fromCache) ...<Widget>[
                  IqroStatusBanner(
                    icon: Icons.cloud_off_outlined,
                    title: context.l10n.planUnavailable,
                    actionLabel: context.l10n.retry,
                    onAction: canMutate ? controller.reload : null,
                  ),
                  const SizedBox(height: 12),
                ],
                _DailyProgressCard(
                  plan: value,
                  onEdit: !canMutate || value.fromCache
                      ? null
                      : () => _editGoal(context, ref, controller, scope, value),
                ),
                _ProgressExplanation(metric: value.metric),
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
                    label: Text(context.l10n.planManualEntry),
                  ),
                ),
                const SizedBox(height: 24),
                IqroSectionHeader(title: context.l10n.planPrayerTitle),
                const SizedBox(height: 8),
                Text(context.l10n.planPrayerSummary),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () => context.push('/after-prayer'),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(context.l10n.planEditPrayer),
                  ),
                ),
                const SizedBox(height: 4),
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
                            context.l10n.planPages(entry.value),
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

  Future<void> _addHomeWidget(
    BuildContext context,
    WidgetRef ref,
    DailyPlan plan,
    AccountScopeSnapshot scope,
  ) async {
    final service = ref.read(planWidgetServiceProvider);
    try {
      await service.update(
        plan: plan,
        locale: Localizations.localeOf(context).languageCode,
        accountScope: scope,
      );
      if (!context.mounted) return;
      final pinned = await service.requestPin();
      if (!context.mounted) return;
      if (pinned != HomeWidgetPinResult.unsupported) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              pinned == HomeWidgetPinResult.alreadyInstalled
                  ? context.l10n.homeWidgetAlreadyAdded
                  : context.l10n.prayerWidgetPinRequested,
            ),
          ),
        );
      } else {
        await showModalBottomSheet<void>(
          context: context,
          useSafeArea: true,
          builder: (context) => Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              Theme.of(context).platform == TargetPlatform.iOS
                  ? context.l10n.prayerWidgetManualIos
                  : context.l10n.prayerWidgetManualAndroid,
            ),
          ),
        );
      }
    } on AccountScopeChanged {
      // The next account publishes its own snapshot.
    } on Object {
      if (context.mounted) _showError(context);
    }
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
                context.l10n.planManualEntry,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(context.l10n.planManualHelp),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  for (final amount in _manualAmounts(metric))
                    ActionChip(
                      label: Text(_metricAmount(context, metric, amount)),
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

class _DailyProgressCard extends StatelessWidget {
  const _DailyProgressCard({required this.plan, required this.onEdit});
  final DailyPlan plan;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final reached = plan.target > 0 && plan.achieved >= plan.target;
    final remaining = (plan.target - plan.achieved).clamp(0, plan.target);
    return IqroCard(
      color: context.iqroColors.ink,
      borderColor: Colors.transparent,
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.planCreditedToday,
              style: textTheme.titleMedium?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              _metricAmount(context, plan.metric, plan.achieved),
              style: textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontFamily: textTheme.bodyLarge?.fontFamily,
              ),
            ),
            const SizedBox(height: 20),
            Divider(color: Colors.white.withValues(alpha: .24)),
            const SizedBox(height: 12),
            Text(context.l10n.planGoalLabel),
            const SizedBox(height: 4),
            Text(
              _metricAmount(context, plan.metric, plan.target),
              style: textTheme.titleLarge?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white.withValues(alpha: .5),
                padding: const EdgeInsets.symmetric(
                  horizontal: 0,
                  vertical: 12,
                ),
                minimumSize: const Size(48, 48),
              ),
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 20),
              label: Text(context.l10n.planEditGoal),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: plan.target <= 0
                  ? 0
                  : (plan.achieved / plan.target).clamp(0.0, 1.0),
              minHeight: 6,
              color: Colors.white,
              backgroundColor: Colors.white.withValues(alpha: .22),
              borderRadius: BorderRadius.circular(4),
              semanticsLabel: context.l10n.planGoalLabel,
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (reached) ...[
                  const Icon(
                    Icons.check_circle_outline,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    reached
                        ? context.l10n.planGoalReached
                        : context.l10n.planRemainingAmount(
                            _metricAmount(context, plan.metric, remaining),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressExplanation extends StatelessWidget {
  const _ProgressExplanation({required this.metric});
  final ReadingGoalMetric metric;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.only(bottom: 16),
    shape: const Border(),
    collapsedShape: const Border(),
    title: Text(
      context.l10n.planHowCounted,
      style: Theme.of(context).textTheme.titleSmall,
    ),
    children: [
      Text(switch (metric) {
        ReadingGoalMetric.pages => context.l10n.planPagesHelp,
        ReadingGoalMetric.minutes => context.l10n.planMinutesHelp,
        ReadingGoalMetric.ayahs => context.l10n.planAyahsHelp,
      }),
      const SizedBox(height: 12),
      Text(context.l10n.planDailyHelp),
      const SizedBox(height: 12),
      Text(context.l10n.planResetHelp),
    ],
  );
}

String _metricAmount(
  BuildContext context,
  ReadingGoalMetric metric,
  num amount,
) => switch (metric) {
  ReadingGoalMetric.pages => context.l10n.planPages(amount),
  ReadingGoalMetric.minutes => context.l10n.planMinutes(amount),
  ReadingGoalMetric.ayahs => context.l10n.planAyahs(amount),
};

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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                context.l10n.planEditGoal,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(context.l10n.planGoalHint),
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
              '${context.l10n.planStreak(plan.streak)}\n'
              '${context.l10n.planBestStreak(context.l10n.planStreak(plan.longestStreak))}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
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
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (metric != null) ...[
              Text(
                context.l10n.planCreditedAmount(
                  _metricAmount(context, metric, day.achieved),
                ),
              ),
              Text(
                context.l10n.planGoalAmount(
                  _metricAmount(context, metric, day.target),
                ),
              ),
            ],
            if (day.automaticSeconds > 0)
              Text(
                context.l10n.planActiveTime(
                  context.l10n.planMinutes((day.automaticSeconds / 60).floor()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class AfterPrayerScreen extends ConsumerStatefulWidget {
  const AfterPrayerScreen({super.key});

  @override
  ConsumerState<AfterPrayerScreen> createState() => _AfterPrayerScreenState();
}

class _AfterPrayerScreenState extends ConsumerState<AfterPrayerScreen> {
  String? _savingPrayer;

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(planProvider);
    final database = ref.watch(localDatabaseProvider);
    final accountKey = ref.watch(activeAccountScopeKeyProvider);
    final scope = database.accountScope.current;
    final controller = ref.read(planProvider.notifier);
    final canMutate =
        _savingPrayer == null &&
        scope != null &&
        accountKey == accountScopeKey(scope) &&
        controller.isBoundTo(scope);
    return Scaffold(
      appBar: IqroTopBar(title: context.l10n.planPrayerTitle),
      body: plan.when(
        loading: () => const IqroLoading(),
        error: (error, stack) => IqroAsyncError(
          title: context.l10n.networkError,
          onRetry: () {
            if (canMutate) controller.reload();
          },
        ),
        data: (value) => IqroPage(
          padding: iqroRootTabPadding(
            playerActive: ref.watch(
              audioControllerProvider.select((state) => state.active),
            ),
            playerCollapsed: ref.watch(miniPlayerCollapsedProvider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(context.l10n.planPrayerInstructions),
              const SizedBox(height: 16),
              if (value.fromCache) ...<Widget>[
                IqroStatusBanner(
                  icon: Icons.cloud_off_outlined,
                  title: context.l10n.planUnavailable,
                  actionLabel: context.l10n.retry,
                  onAction: canMutate ? controller.reload : null,
                ),
                const SizedBox(height: 12),
              ],
              for (final entry in value.prayerPages.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _PrayerCheckInRow(
                    prayer: _prayerName(context, entry.key),
                    pages: entry.value,
                    saving: _savingPrayer == entry.key,
                    onMinus: entry.value <= 0 || !canMutate || value.fromCache
                        ? null
                        : () => _setPrayerPages(
                            context,
                            controller,
                            entry.key,
                            entry.value - 1,
                          ),
                    onPlus: entry.value >= 604 || !canMutate || value.fromCache
                        ? null
                        : () => _setPrayerPages(
                            context,
                            controller,
                            entry.key,
                            entry.value + 1,
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
    if (_savingPrayer != null) return;
    setState(() => _savingPrayer = prayer);
    try {
      await controller.setPrayerPages(prayer, pages);
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(context.l10n.networkError)));
    } finally {
      if (mounted) setState(() => _savingPrayer = null);
    }
  }
}

class _PrayerCheckInRow extends StatelessWidget {
  const _PrayerCheckInRow({
    required this.prayer,
    required this.pages,
    required this.saving,
    required this.onMinus,
    required this.onPlus,
  });
  final String prayer;
  final int pages;
  final bool saving;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) => IqroCard(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final stack =
            constraints.maxWidth < 280 ||
            MediaQuery.textScalerOf(context).scale(16) > 21;
        final title = Row(
          children: [
            Icon(
              Icons.mosque_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                prayer,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        );
        final controls = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: context.l10n.planRemovePage(prayer),
              onPressed: onMinus,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 40),
              child: saving
                  ? const Center(
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Text(
                      '$pages',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
            ),
            IconButton(
              tooltip: context.l10n.planAddPage(prayer),
              onPressed: onPlus,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        );
        return stack
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  title,
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: controls,
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 8),
                  controls,
                ],
              );
      },
    ),
  );
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
