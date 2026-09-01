import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import '../quran/quran_models.dart';
import 'reminder_models.dart';

class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  static const _prayerEvents = <String>[
    'fajr',
    'dhuhr',
    'asr',
    'maghrib',
    'isha',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(reminderProvider);
    final reviewRules = state.rules
        .where((item) => item.type == ReminderType.quranReview)
        .toList(growable: false);
    return Scaffold(
      appBar: IqroTopBar(
        title: context.l10n.reminders,
        subtitle: context.l10n.remindersSubtitle,
      ),
      body: RefreshIndicator(
        onRefresh: ref.read(reminderProvider.notifier).reload,
        child: IqroPage(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (state.permission != ReminderPermission.granted)
                IqroStatusBanner(
                  icon: Icons.notifications_off_outlined,
                  title: context.l10n.notificationAccess,
                  message: context.l10n.notificationAccessBody,
                  color: context.iqroColors.sand,
                  actionLabel: context.l10n.allowNotifications,
                  onAction: state.saving
                      ? null
                      : ref.read(reminderProvider.notifier).requestPermission,
                )
              else if (!state.exactScheduling)
                IqroStatusBanner(
                  icon: Icons.schedule_outlined,
                  title: context.l10n.reminders,
                  message: context.l10n.approximateDelivery,
                  color: context.iqroColors.sand,
                ),
              if (state.offline) ...<Widget>[
                const SizedBox(height: 10),
                IqroStatusBanner(
                  icon: Icons.cloud_off_outlined,
                  title: context.l10n.offline,
                  message: context.l10n.offlineUsingCache,
                ),
              ],
              const SizedBox(height: 22),
              IqroSectionHeader(title: context.l10n.prayerReminders),
              const SizedBox(height: 10),
              FutureBuilder(
                future: ref.read(prayerRepositoryProvider).storedLocation(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done ||
                      snapshot.data != null) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: IqroStatusBanner(
                      icon: Icons.location_searching,
                      title: context.l10n.prayerUnavailable,
                      message: context.l10n.prayerReminderSetup,
                      actionLabel: context.l10n.prayer,
                      onAction: () => context.push('/prayer'),
                    ),
                  );
                },
              ),
              IqroCard(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Column(
                  children: <Widget>[
                    for (
                      var index = 0;
                      index < _prayerEvents.length;
                      index++
                    ) ...<Widget>[
                      _PrayerReminderTile(
                        event: _prayerEvents[index],
                        rule: _prayerRule(state.rules, _prayerEvents[index]),
                        enabled: !state.saving,
                      ),
                      if (index != _prayerEvents.length - 1)
                        const Divider(height: 1),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              IqroSectionHeader(title: context.l10n.quranReviewReminders),
              const SizedBox(height: 4),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: state.saving ? null : () => _openEditor(context),
                  icon: const Icon(Icons.add),
                  label: Text(context.l10n.addReminder),
                ),
              ),
              const SizedBox(height: 10),
              if (state.loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (reviewRules.isEmpty)
                IqroCard(
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.notifications_none_outlined, size: 32),
                      const SizedBox(width: 12),
                      Expanded(child: Text(context.l10n.noReminders)),
                    ],
                  ),
                )
              else
                for (final rule in reviewRules) ...<Widget>[
                  _ReviewReminderCard(rule: rule),
                  const SizedBox(height: 10),
                ],
              if (state.error != null) ...<Widget>[
                const SizedBox(height: 10),
                IqroStatusBanner(
                  icon: Icons.error_outline,
                  title: context.l10n.networkError,
                  message: state.error.toString(),
                  actionLabel: context.l10n.retry,
                  onAction: ref.read(reminderProvider.notifier).reload,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  ReminderRule? _prayerRule(List<ReminderRule> rules, String event) => rules
      .where(
        (item) =>
            item.type == ReminderType.prayer &&
            item.schedule.prayerEvent == event,
      )
      .firstOrNull;

  Future<void> _openEditor(BuildContext context, {ReminderRule? rule}) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _ReminderEditor(rule: rule),
      );
}

class _PrayerReminderTile extends ConsumerWidget {
  const _PrayerReminderTile({
    required this.event,
    required this.rule,
    required this.enabled,
  });

  final String event;
  final ReminderRule? rule;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = _prayerName(context, event);
    return SwitchListTile.adaptive(
      secondary: Icon(Icons.mosque_outlined, color: context.iqroColors.gold),
      title: Text(title),
      subtitle: rule == null
          ? null
          : Text(_daysSummary(context, rule!.weekdaysMask)),
      value: rule?.isEnabled == true,
      onChanged: enabled
          ? (value) async {
              try {
                await ref
                    .read(reminderProvider.notifier)
                    .togglePrayer(event, value);
              } on Object {
                if (context.mounted) _showError(context);
              }
            }
          : null,
    );
  }
}

class _ReviewReminderCard extends ConsumerWidget {
  const _ReviewReminderCard({required this.rule});

  final ReminderRule rule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final time = rule.schedule.timeParts;
    final target = rule.reviewTarget;
    final range = target == null
        ? ''
        : '${target.start.surah}:${target.start.ayah}–${target.end.surah}:${target.end.ayah}';
    return IqroCard(
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _ReminderEditor(rule: rule),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: context.iqroColors.lavender,
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(Icons.menu_book_outlined),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')} · $range',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '${_daysSummary(context, rule.weekdaysMask)} · ${_signalName(context, rule.signal)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: rule.isEnabled,
            onChanged: ref.watch(reminderProvider).saving
                ? null
                : (value) async {
                    try {
                      await ref
                          .read(reminderProvider.notifier)
                          .toggle(rule, value);
                    } on Object {
                      if (context.mounted) _showError(context);
                    }
                  },
          ),
        ],
      ),
    );
  }
}

class _ReminderEditor extends ConsumerStatefulWidget {
  const _ReminderEditor({this.rule});

  final ReminderRule? rule;

  @override
  ConsumerState<_ReminderEditor> createState() => _ReminderEditorState();
}

class _ReminderEditorState extends ConsumerState<_ReminderEditor> {
  late TimeOfDay _time;
  late int _weekdaysMask;
  late ReminderSignal _signal;
  late ReminderTimezoneMode _timezoneMode;
  late int _surah;
  late int _startAyah;
  late int _endAyah;
  late final TextEditingController _timezone;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    final parts = rule?.schedule.timeParts ?? (hour: 8, minute: 0);
    _time = TimeOfDay(hour: parts.hour, minute: parts.minute);
    _weekdaysMask = rule?.weekdaysMask ?? 127;
    _signal = rule?.signal ?? ReminderSignal.sound;
    _timezoneMode = rule?.timezoneMode ?? ReminderTimezoneMode.deviceLocal;
    _surah = rule?.reviewTarget?.start.surah ?? 1;
    _startAyah = rule?.reviewTarget?.start.ayah ?? 1;
    _endAyah = rule?.reviewTarget?.end.ayah ?? _startAyah;
    _timezone = TextEditingController(text: rule?.timezoneName ?? '');
    if (_timezone.text.isEmpty) _loadTimezone();
  }

  Future<void> _loadTimezone() async {
    try {
      final value = (await FlutterTimezone.getLocalTimezone()).identifier;
      if (mounted && _timezone.text.isEmpty) _timezone.text = value;
    } on Object {
      if (mounted && _timezone.text.isEmpty) _timezone.text = 'UTC';
    }
  }

  @override
  void dispose() {
    _timezone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(quranCatalogProvider);
    final ayahs = ref.watch(ayahsProvider(_surah));
    final surahs = catalog.valueOrNull?.surahs ?? const <Surah>[];
    final availableAyahs = ayahs.valueOrNull ?? const <QuranAyah>[];
    final locale = Localizations.localeOf(context).languageCode;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.reviewReminder),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
        actions: <Widget>[
          if (widget.rule != null)
            IconButton(
              tooltip: context.l10n.delete,
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        children: <Widget>[
          IqroCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule_outlined),
              title: Text(context.l10n.reminderTime),
              trailing: TextButton(
                onPressed: _pickTime,
                child: Text(
                  '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          IqroSectionHeader(title: context.l10n.surah),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: surahs.any((item) => item.number == _surah)
                ? _surah
                : null,
            isExpanded: true,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.menu_book_outlined),
              labelText: context.l10n.surah,
            ),
            items: surahs
                .map(
                  (item) => DropdownMenuItem<int>(
                    value: item.number,
                    child: Text('${item.number}. ${item.nameFor(locale)}'),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _surah = value;
                _startAyah = 1;
                _endAyah = 1;
              });
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: _AyahDropdown(
                  label: context.l10n.startAyah,
                  value: _startAyah,
                  ayahs: availableAyahs,
                  onChanged: (value) => setState(() {
                    _startAyah = value;
                    if (_endAyah < value) _endAyah = value;
                  }),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _AyahDropdown(
                  label: context.l10n.endAyah,
                  value: _endAyah,
                  ayahs: availableAyahs
                      .where((item) => item.number >= _startAyah)
                      .toList(growable: false),
                  onChanged: (value) => setState(() => _endAyah = value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          IqroSectionHeader(title: context.l10n.reminderDays),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: List<Widget>.generate(7, (index) {
              final bit = 1 << index;
              return FilterChip(
                label: Text(_dayNames(context)[index]),
                selected: _weekdaysMask & bit != 0,
                onSelected: (selected) => setState(() {
                  final next = selected
                      ? _weekdaysMask | bit
                      : _weekdaysMask & ~bit;
                  if (next != 0) _weekdaysMask = next;
                }),
              );
            }),
          ),
          const SizedBox(height: 20),
          IqroSectionHeader(title: context.l10n.signal),
          const SizedBox(height: 8),
          SegmentedButton<ReminderSignal>(
            segments: <ButtonSegment<ReminderSignal>>[
              ButtonSegment(
                value: ReminderSignal.sound,
                icon: const Icon(Icons.volume_up_outlined),
                label: Text(context.l10n.sound),
              ),
              ButtonSegment(
                value: ReminderSignal.vibration,
                icon: const Icon(Icons.vibration),
                label: Text(context.l10n.vibration),
              ),
              ButtonSegment(
                value: ReminderSignal.silent,
                icon: const Icon(Icons.volume_off_outlined),
                label: Text(context.l10n.silent),
              ),
            ],
            selected: <ReminderSignal>{_signal},
            showSelectedIcon: false,
            onSelectionChanged: (value) =>
                setState(() => _signal = value.first),
          ),
          const SizedBox(height: 20),
          IqroSectionHeader(title: context.l10n.timezone),
          const SizedBox(height: 8),
          SegmentedButton<ReminderTimezoneMode>(
            segments: <ButtonSegment<ReminderTimezoneMode>>[
              ButtonSegment(
                value: ReminderTimezoneMode.deviceLocal,
                label: Text(context.l10n.deviceTimezone),
              ),
              ButtonSegment(
                value: ReminderTimezoneMode.fixed,
                label: Text(context.l10n.fixedTimezone),
              ),
            ],
            selected: <ReminderTimezoneMode>{_timezoneMode},
            onSelectionChanged: (value) =>
                setState(() => _timezoneMode = value.first),
          ),
          if (_timezoneMode == ReminderTimezoneMode.fixed) ...<Widget>[
            const SizedBox(height: 10),
            TextField(
              controller: _timezone,
              decoration: InputDecoration(
                labelText: context.l10n.timezoneName,
                hintText: 'Europe/Istanbul',
              ),
              autocorrect: false,
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving || availableAyahs.isEmpty || surahs.isEmpty
                ? null
                : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(context.l10n.save),
          ),
        ],
      ),
    );
  }

  Future<void> _pickTime() async {
    final value = await showTimePicker(context: context, initialTime: _time);
    if (value != null) setState(() => _time = value);
  }

  Future<void> _save() async {
    final ayahs = ref.read(ayahsProvider(_surah)).valueOrNull;
    final start = ayahs?.where((item) => item.number == _startAyah).firstOrNull;
    final end = ayahs?.where((item) => item.number == _endAyah).firstOrNull;
    if (start == null || end == null) return;
    setState(() => _saving = true);
    final schedule = ReminderSchedule.localTime(
      '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}:00',
    );
    final target = ReminderReviewTarget(
      start: ReminderAyah(id: start.id, surah: _surah, ayah: start.number),
      end: ReminderAyah(id: end.id, surah: _surah, ayah: end.number),
    );
    try {
      final controller = ref.read(reminderProvider.notifier);
      final existing = widget.rule;
      if (existing == null) {
        await controller.create(
          type: ReminderType.quranReview,
          schedule: schedule,
          weekdaysMask: _weekdaysMask,
          signal: _signal,
          timezoneMode: _timezoneMode,
          timezoneName: _timezoneMode == ReminderTimezoneMode.fixed
              ? _timezone.text.trim()
              : null,
          reviewTarget: target,
        );
      } else {
        await controller.update(
          existing.copyWith(
            schedule: schedule,
            weekdaysMask: _weekdaysMask,
            signal: _signal,
            timezoneMode: _timezoneMode,
            timezoneName: _timezoneMode == ReminderTimezoneMode.fixed
                ? _timezone.text.trim()
                : null,
            reviewTarget: target,
          ),
        );
      }
      if (mounted) Navigator.pop(context);
    } on Object {
      if (mounted) {
        setState(() => _saving = false);
        _showError(context);
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.delete),
        content: Text(context.l10n.deleteReminderConfirm),
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
    if (confirmed != true || widget.rule == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(reminderProvider.notifier).delete(widget.rule!);
      if (mounted) Navigator.pop(context);
    } on Object {
      if (mounted) {
        setState(() => _saving = false);
        _showError(context);
      }
    }
  }
}

class _AyahDropdown extends StatelessWidget {
  const _AyahDropdown({
    required this.label,
    required this.value,
    required this.ayahs,
    required this.onChanged,
  });

  final String label;
  final int value;
  final List<QuranAyah> ayahs;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<int>(
    initialValue: ayahs.any((item) => item.number == value) ? value : null,
    decoration: InputDecoration(labelText: label),
    items: ayahs
        .map(
          (item) => DropdownMenuItem<int>(
            value: item.number,
            child: Text('${item.number}'),
          ),
        )
        .toList(growable: false),
    onChanged: (value) {
      if (value != null) onChanged(value);
    },
  );
}

String _prayerName(BuildContext context, String event) => switch (event) {
  'fajr' => context.l10n.fajr,
  'dhuhr' => context.l10n.dhuhr,
  'asr' => context.l10n.asr,
  'maghrib' => context.l10n.maghrib,
  _ => context.l10n.isha,
};

List<String> _dayNames(BuildContext context) => <String>[
  context.l10n.mondayShort,
  context.l10n.tuesdayShort,
  context.l10n.wednesdayShort,
  context.l10n.thursdayShort,
  context.l10n.fridayShort,
  context.l10n.saturdayShort,
  context.l10n.sundayShort,
];

String _daysSummary(BuildContext context, int mask) => mask == 127
    ? context.l10n.everyDay
    : List<int>.generate(7, (index) => index)
          .where((index) => mask & (1 << index) != 0)
          .map((index) => _dayNames(context)[index])
          .join(', ');

String _signalName(BuildContext context, ReminderSignal signal) =>
    switch (signal) {
      ReminderSignal.sound => context.l10n.sound,
      ReminderSignal.vibration => context.l10n.vibration,
      ReminderSignal.silent => context.l10n.silent,
    };

void _showError(BuildContext context) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(context.l10n.networkError)));
}
