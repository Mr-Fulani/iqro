import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../app/providers.dart';
import '../../core/auth/account_scope.dart';
import '../../core/widgets/home_widget_pinning.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/storage/preferences_store.dart';
import '../../core/theme/iqro_theme.dart';
import '../audio/mini_player.dart';
import 'plan_repository.dart';

class PlanScreen extends ConsumerStatefulWidget {
  const PlanScreen({super.key});

  @override
  ConsumerState<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends ConsumerState<PlanScreen> {
  var _rangeDays = 30;
  String? _selectedDate;
  String? _busySessionId;

  @override
  Widget build(BuildContext context) {
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
        actions: <Widget>[
          IconButton(
            tooltip: context.l10n.refresh,
            icon: const Icon(Icons.refresh_rounded),
            onPressed: canMutate ? controller.reload : null,
          ),
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
          final selectedDate = _selectedDate ?? value.localDate;
          final days = value.daysForRange(_rangeDays);
          final selectedDay = value.dayForDate(selectedDate);
          final stats = value.statsForRange(_rangeDays);
          final historyGroups = value.historyGroupsForRange(_rangeDays);
          final selectedHistoryGroup = historyGroups
              .where((group) => group.localDate == selectedDate)
              .firstOrNull;
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
                _PlanSummary(
                  stats: stats,
                  streak: value.streak,
                  rangeDays: _rangeDays,
                ),
                const SizedBox(height: 12),
                if (value.continueReading != null) ...<Widget>[
                  _ContinueReadingCard(
                    position: value.continueReading!,
                    onTap: () =>
                        _openContinueReading(context, value.continueReading!),
                  ),
                  const SizedBox(height: 22),
                ],
                IqroSectionHeader(title: context.l10n.planCalendarTitle),
                const SizedBox(height: 8),
                Text(context.l10n.planCalendarHint),
                const SizedBox(height: 12),
                _RangeSelector(
                  selected: _rangeDays,
                  onChanged: (range) {
                    setState(() {
                      _rangeDays = range;
                      if (_selectedDate != null &&
                          !value
                              .daysForRange(range)
                              .any(
                                (day) =>
                                    day.localDate != null &&
                                    _dateOnly(day.localDate!) == _selectedDate,
                              )) {
                        _selectedDate = null;
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),
                _CalendarCard(
                  days: days,
                  selectedDate: selectedDate,
                  onSelected: (date) => setState(() => _selectedDate = date),
                ),
                const SizedBox(height: 22),
                IqroSectionHeader(title: context.l10n.planSelectedDay),
                const SizedBox(height: 8),
                _SelectedDayCard(
                  day: selectedDay,
                  manualSessions:
                      selectedHistoryGroup?.manualSessions ??
                      const <ReadingSession>[],
                  onEdit: canMutate && !value.fromCache
                      ? (session) => _editManualReading(
                          context,
                          controller,
                          scope,
                          session,
                        )
                      : null,
                  onDelete: canMutate && !value.fromCache
                      ? (session) => _deleteManualReading(
                          context,
                          controller,
                          scope,
                          session,
                        )
                      : null,
                ),
                const SizedBox(height: 22),
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
                IqroSectionHeader(title: context.l10n.planRelatedTools),
                const SizedBox(height: 8),
                _RelatedToolsCard(
                  onReminders: () => context.push('/reminders'),
                  onMemorization: () => context.push('/memorization'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openContinueReading(
    BuildContext context,
    ReadingPositionSummary position,
  ) {
    final preferences = ref.read(appPreferencesProvider);
    if (preferences.readerMode == ReaderMode.mushaf) {
      final surah = position.surah;
      final ayah = position.ayah;
      if (surah != null && ayah != null) {
        context.push('/mushaf?page=${position.page}&surah=$surah&ayah=$ayah');
        return;
      }
      context.push('/mushaf?page=${position.page}');
      return;
    }
    final surah = position.surah;
    final ayah = position.ayah;
    if (surah != null && ayah != null) {
      context.push('/reader/$surah?ayah=$ayah');
    } else {
      context.push('/mushaf?page=${position.page}');
    }
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

  Future<void> _editManualReading(
    BuildContext context,
    PlanController controller,
    AccountScopeSnapshot scope,
    ReadingSession session,
  ) async {
    if (_busySessionId != null) return;
    final draft = await showModalBottomSheet<_ManualEntryDraft>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ManualEntryEditor(session: session),
    );
    if (draft == null ||
        !context.mounted ||
        !_stillCurrent(ref, controller, scope)) {
      return;
    }
    setState(() => _busySessionId = session.id);
    try {
      await controller.updateManualReading(
        session,
        metric: draft.metric,
        amount: draft.amount,
        localDate: draft.localDate,
      );
    } on Object {
      if (context.mounted) _showError(context);
    } finally {
      if (mounted) setState(() => _busySessionId = null);
    }
  }

  Future<void> _deleteManualReading(
    BuildContext context,
    PlanController controller,
    AccountScopeSnapshot scope,
    ReadingSession session,
  ) async {
    if (_busySessionId != null || !_stillCurrent(ref, controller, scope)) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.planDeleteEntryTitle),
        content: Text(context.l10n.planDeleteEntryConfirm),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    setState(() => _busySessionId = session.id);
    try {
      await controller.deleteManualReading(session);
    } on Object {
      if (context.mounted) _showError(context);
    } finally {
      if (mounted) setState(() => _busySessionId = null);
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

class _PlanSummary extends StatelessWidget {
  const _PlanSummary({
    required this.stats,
    required this.streak,
    required this.rangeDays,
  });

  final ReadingPlanStats stats;
  final int streak;
  final int rangeDays;

  @override
  Widget build(BuildContext context) => IqroCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          context.l10n.planSummaryTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(context.l10n.planSummaryRange(rangeDays)),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _SummaryMetric(
                value: '${stats.readingDays}',
                label: context.l10n.planReadingDays,
              ),
            ),
            Expanded(
              child: _SummaryMetric(
                value: '${stats.completedDays}',
                label: context.l10n.planCompletedDays,
              ),
            ),
            Expanded(
              child: _SummaryMetric(
                value: '${stats.partialDays}',
                label: context.l10n.planPartialDays,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            Icon(
              Icons.local_fire_department_outlined,
              size: 20,
              color: context.iqroColors.gold,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(context.l10n.planStreak(streak))),
          ],
        ),
      ],
    ),
  );
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(value, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 2),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _ContinueReadingCard extends StatelessWidget {
  const _ContinueReadingCard({required this.position, required this.onTap});

  final ReadingPositionSummary position;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IqroCard(
    onTap: onTap,
    child: Row(
      children: <Widget>[
        Icon(
          Icons.menu_book_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(context.l10n.continueReading),
              const SizedBox(height: 4),
              Text(
                position.surah == null
                    ? '${context.l10n.page} ${position.page}'
                    : '${context.l10n.surah} ${position.surah} · ${context.l10n.ayah} ${position.ayah ?? 1}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 2),
              Text('${context.l10n.page} ${position.page}'),
            ],
          ),
        ),
        const Icon(Icons.chevron_right),
      ],
    ),
  );
}

class _RangeSelector extends StatelessWidget {
  const _RangeSelector({required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: <Widget>[
        for (final days in const <int>[7, 30, 90]) ...<Widget>[
          ChoiceChip(
            label: Text(context.l10n.planDays(days)),
            selected: selected == days,
            onSelected: (_) => onChanged(days),
          ),
          const SizedBox(width: 8),
        ],
      ],
    ),
  );
}

class _CalendarCard extends StatelessWidget {
  const _CalendarCard({
    required this.days,
    required this.selectedDate,
    required this.onSelected,
  });

  final List<ReadingHistoryDay> days;
  final String selectedDate;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return Text(context.l10n.planCalendarEmpty);
    final firstDate = days.first.localDate;
    final offset = firstDate == null ? 0 : firstDate.weekday - 1;
    final weekdays = <String>[
      context.l10n.mondayShort,
      context.l10n.tuesdayShort,
      context.l10n.wednesdayShort,
      context.l10n.thursdayShort,
      context.l10n.fridayShort,
      context.l10n.saturdayShort,
      context.l10n.sundayShort,
    ];
    return IqroCard(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              for (final weekday in weekdays)
                Expanded(
                  child: Text(
                    weekday,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: offset + days.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent: 58,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemBuilder: (context, index) {
              if (index < offset) return const SizedBox.shrink();
              final day = days[index - offset];
              final date = day.localDate;
              if (date == null) return const SizedBox.shrink();
              final key = _dateOnly(date);
              return _CalendarDayCell(
                day: day,
                selected: key == selectedDate,
                onTap: () => onSelected(key),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({
    required this.day,
    required this.selected,
    required this.onTap,
  });

  final ReadingHistoryDay day;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = day.localDate!;
    final color = _stateColor(context, day.state);
    return Semantics(
      button: true,
      selected: selected,
      label: DateFormat.yMMMMd(
        Localizations.localeOf(context).languageCode,
      ).format(date),
      child: Material(
        color: selected
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  '${date.day}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 3),
                Icon(_stateIcon(day.state), size: 15, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedDayCard extends StatelessWidget {
  const _SelectedDayCard({
    required this.day,
    required this.manualSessions,
    required this.onEdit,
    required this.onDelete,
  });

  final ReadingHistoryDay? day;
  final List<ReadingSession> manualSessions;
  final ValueChanged<ReadingSession>? onEdit;
  final ValueChanged<ReadingSession>? onDelete;

  @override
  Widget build(BuildContext context) {
    final value = day;
    if (value == null || value.localDate == null) {
      return Text(context.l10n.planCalendarEmpty);
    }
    final locale = Localizations.localeOf(context).languageCode;
    return IqroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            DateFormat.yMMMMd(locale).format(value.localDate!),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Icon(
                _stateIcon(value.state),
                size: 20,
                color: _stateColor(context, value.state),
              ),
              const SizedBox(width: 8),
              Text(_stateLabel(context, value.state)),
            ],
          ),
          const SizedBox(height: 12),
          if (value.metric != null)
            Text(
              '${context.l10n.planCreditedAmount(_metricAmount(context, value.metric!, value.achieved))} · '
              '${context.l10n.planGoalAmount(_metricAmount(context, value.metric!, value.target))}',
            ),
          if (value.prayerCount > 0) ...<Widget>[
            const SizedBox(height: 8),
            Text(context.l10n.planPrayerCount(value.prayerCount)),
            for (final checkIn in value.prayerCheckIns)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${_prayerName(context, checkIn.prayer)} · ${context.l10n.planPages(checkIn.pages)}',
                ),
              ),
          ],
          if (value.automaticSessions > 0) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              '${context.l10n.planAutomaticSessions(value.automaticSessions)} · '
              '${context.l10n.planActiveTime(context.l10n.planMinutes((value.automaticSeconds / 60).floor()))}',
            ),
          ],
          if (manualSessions.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              leading: const Icon(Icons.edit_note_outlined),
              title: Text(context.l10n.history),
              subtitle: Text(context.l10n.planManualRecord),
              children: <Widget>[
                for (final session in manualSessions)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      session.manualMetric == null
                          ? context.l10n.manualEntry
                          : _metricAmount(
                              context,
                              session.manualMetric!,
                              session.manualAmount,
                            ),
                    ),
                    subtitle: Text(context.l10n.planManualRecord),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        IconButton(
                          tooltip: context.l10n.planEditEntry,
                          onPressed: onEdit == null
                              ? null
                              : () => onEdit!(session),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: context.l10n.planDeleteEntry,
                          onPressed: onDelete == null
                              ? null
                              : () => onDelete!(session),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RelatedToolsCard extends StatelessWidget {
  const _RelatedToolsCard({
    required this.onReminders,
    required this.onMemorization,
  });

  final VoidCallback onReminders;
  final VoidCallback onMemorization;

  @override
  Widget build(BuildContext context) => IqroCard(
    padding: EdgeInsets.zero,
    child: Column(
      children: <Widget>[
        ListTile(
          leading: const Icon(Icons.notifications_none_outlined),
          title: Text(context.l10n.reminders),
          subtitle: Text(context.l10n.remindersSubtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onReminders,
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.school_outlined),
          title: Text(context.l10n.memorization),
          subtitle: Text(context.l10n.memorizationPlanDescription),
          trailing: const Icon(Icons.chevron_right),
          onTap: onMemorization,
        ),
      ],
    ),
  );
}

class _ManualEntryDraft {
  const _ManualEntryDraft({
    required this.metric,
    required this.amount,
    required this.localDate,
  });

  final ReadingGoalMetric metric;
  final double amount;
  final String localDate;
}

class _ManualEntryEditor extends StatefulWidget {
  const _ManualEntryEditor({required this.session});

  final ReadingSession session;

  @override
  State<_ManualEntryEditor> createState() => _ManualEntryEditorState();
}

class _ManualEntryEditorState extends State<_ManualEntryEditor> {
  late ReadingGoalMetric _metric =
      widget.session.manualMetric ?? ReadingGoalMetric.pages;
  late final TextEditingController _amount = TextEditingController(
    text: _formatAmount(widget.session.manualAmount),
  );
  late String _localDate = widget.session.localDate;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
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
              context.l10n.planEditEntry,
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
            const SizedBox(height: 14),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: context.l10n.planReadingAmount,
                suffixText: _metricLabel(context, _metric),
                errorText: _error,
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(context.l10n.planReadingDate),
              subtitle: Text(_formatLocalDate(context, _localDate)),
              onTap: _pickDate,
            ),
            const SizedBox(height: 12),
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

  Future<void> _pickDate() async {
    final initial = DateTime.tryParse(_localDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() => _localDate = _dateOnly(picked));
  }

  void _save() {
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', '.'));
    if (amount == null ||
        amount <= 0 ||
        amount > maximumReadingTarget(_metric)) {
      setState(() => _error = '1–${maximumReadingTarget(_metric)}');
      return;
    }
    Navigator.pop(
      context,
      _ManualEntryDraft(metric: _metric, amount: amount, localDate: _localDate),
    );
  }
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

String _dateOnly(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String _formatLocalDate(BuildContext context, String value) {
  final date = DateTime.tryParse(value);
  if (date == null) return value;
  return DateFormat.yMMMMd(
    Localizations.localeOf(context).languageCode,
  ).format(date);
}

String _stateLabel(BuildContext context, String state) => switch (state) {
  'completed' => context.l10n.planStateCompleted,
  'partial' => context.l10n.planStatePartial,
  'missed' => context.l10n.planStateMissed,
  'pending' => context.l10n.planStatePending,
  _ => context.l10n.planStateNoGoal,
};

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
