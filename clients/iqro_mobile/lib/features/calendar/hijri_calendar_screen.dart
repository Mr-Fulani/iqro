import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import 'hijri_calendar_service.dart';
import 'calendar_catalog.dart';

String hijriNumber(BuildContext context, int value) => NumberFormat(
  '0',
  Localizations.localeOf(context).languageCode,
).format(value);

String hijriDateLabel(BuildContext context, HijriDate date) =>
    '${hijriNumber(context, date.day)} ${context.l10n.hijriMonthName('m${date.month}')} '
    '${hijriNumber(context, date.year)} ${context.l10n.hijriYearSuffix}';

class HijriCalendarScreen extends ConsumerStatefulWidget {
  const HijriCalendarScreen({super.key});
  @override
  ConsumerState<HijriCalendarScreen> createState() =>
      _HijriCalendarScreenState();
}

class _HijriCalendarScreenState extends ConsumerState<HijriCalendarScreen> {
  static const _service = HijriCalendarService();
  int? _year;
  int? _month;
  int? _day;

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(calendarClockProvider).valueOrNull ?? DateTime.now();
    final adjustment = ref.watch(
      appPreferencesProvider.select((p) => p.hijriAdjustment),
    );
    final today = _service.forCivilDate(now, adjustment: adjustment);
    if (today == null) {
      return Scaffold(
        appBar: IqroTopBar(title: context.l10n.hijriCalendar),
        body: Center(child: Text(context.l10n.hijriUnavailable)),
      );
    }
    final year = _year ?? today.year;
    final month = _month ?? today.month;
    final length = _service.monthLength(year, month);
    final day = math.min(_day ?? today.day, length);
    final selected = HijriDate(year, month, day, length);
    final catalog = ref.watch(calendarCatalogProvider).valueOrNull;
    final events = catalog?.forDate(selected) ?? <CalendarEvent>[];
    final civil = _service.civilDate(year, month, day, adjustment: adjustment);
    final locale = Localizations.localeOf(context).languageCode;
    return Scaffold(
      appBar: IqroTopBar(
        title: context.l10n.hijriCalendar,
        subtitle: context.l10n.hijriMethod,
        actions: [
          IconButton(
            tooltip: context.l10n.refresh,
            onPressed: () => ref.invalidate(calendarCatalogProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: IqroPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IqroCard(
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: context.l10n.previousMonth,
                        onPressed:
                            year == HijriCalendarService.minYear && month == 1
                            ? null
                            : () => _move(year, month, -1),
                        icon: const BackButtonIcon(),
                      ),
                      Expanded(
                        child: Text(
                          '${context.l10n.hijriMonthName('m$month')} ${hijriNumber(context, year)}',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: context.l10n.nextMonth,
                        onPressed:
                            year == HijriCalendarService.maxYear && month == 12
                            ? null
                            : () => _move(year, month, 1),
                        icon: const RotatedBox(
                          quarterTurns: 2,
                          child: BackButtonIcon(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  HijriMonthGrid(
                    catalog: catalog,
                    year: year,
                    month: month,
                    selectedDay: day,
                    today: today,
                    adjustment: adjustment,
                    onSelect: (value) => setState(() {
                      _year = year;
                      _month = month;
                      _day = value;
                    }),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _year = null;
                      _month = null;
                      _day = null;
                    }),
                    child: Text(context.l10n.today),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            IqroCard(
              color: context.iqroColors.sand,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hijriDateLabel(context, selected),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(DateFormat.yMMMMEEEEd(locale).format(civil)),
                  const SizedBox(height: 14),
                  if (events.isEmpty) Text(context.l10n.hijriNoEvents),
                  for (final event in events)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.auto_awesome_outlined),
                      title: Text(event.title(locale)),
                      trailing: const Icon(Icons.info_outline),
                      onTap: () => showCalendarSources(context, [event]),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            IqroCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.hijriAdjustment,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(context.l10n.hijriAdjustmentHint),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (var offset = -2; offset <= 2; offset++)
                        ChoiceChip(
                          label: Text(
                            offset > 0
                                ? '+${hijriNumber(context, offset)}'
                                : hijriNumber(context, offset),
                          ),
                          selected: offset == adjustment,
                          onSelected: (_) => ref
                              .read(appPreferencesProvider.notifier)
                              .setHijriAdjustment(offset),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              context.l10n.hijriDisclaimer,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () =>
                  showCalendarSources(context, catalog?.events ?? []),
              icon: const Icon(Icons.library_books_outlined),
              label: Text(context.l10n.hijriSources),
            ),
          ],
        ),
      ),
    );
  }

  void _move(int year, int month, int delta) {
    final absolute = year * 12 + month - 1 + delta;
    setState(() {
      _year = absolute ~/ 12;
      _month = absolute % 12 + 1;
      _day = 1;
    });
  }
}

class HijriMonthGrid extends StatelessWidget {
  const HijriMonthGrid({
    required this.year,
    required this.month,
    required this.selectedDay,
    required this.today,
    required this.adjustment,
    required this.onSelect,
    this.catalog,
    super.key,
  });
  final int year, month, selectedDay, adjustment;
  final HijriDate today;
  final ValueChanged<int> onSelect;
  final CalendarCatalog? catalog;

  @override
  Widget build(BuildContext context) {
    const service = HijriCalendarService();
    final length = service.monthLength(year, month);
    final first = service.civilDate(year, month, 1, adjustment: adjustment);
    final material = MaterialLocalizations.of(context);
    final firstWeekday = material.firstDayOfWeekIndex;
    final skip = (first.weekday % 7 - firstWeekday + 7) % 7;
    final cells = ((length + skip) / 7).ceil() * 7;
    final colors = Theme.of(context).colorScheme;
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 3.0);
    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Text(
                  material.narrowWeekdays[(firstWeekday + i) % 7],
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) => GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: cells,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio:
                  (constraints.maxWidth / 7) / (48 + 18 * textScale),
            ),
            itemBuilder: (context, index) {
              final day = index - skip + 1;
              if (day < 1 || day > length) return const SizedBox.shrink();
              final civil = service.civilDate(
                year,
                month,
                day,
                adjustment: adjustment,
              );
              final hDate = HijriDate(year, month, day, length);
              final events = catalog?.forDate(hDate) ?? <CalendarEvent>[];
              final selected = day == selectedDay;
              final isToday =
                  today.year == year &&
                  today.month == month &&
                  today.day == day;
              final foreground = selected ? colors.onPrimary : colors.onSurface;
              return Semantics(
                onTap: () => onSelect(day),
                selected: selected,
                button: true,
                label:
                    '${hijriDateLabel(context, hDate)}. ${DateFormat.yMd(Localizations.localeOf(context).languageCode).format(civil)}. '
                    '${isToday ? context.l10n.today : ''} ${events.map((e) => e.title(Localizations.localeOf(context).languageCode)).join(', ')}',
                child: ExcludeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Material(
                      color: selected ? colors.primary : colors.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: isToday ? colors.primary : Colors.transparent,
                        ),
                      ),
                      child: InkWell(
                        key: ValueKey('hijri-day-$day'),
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => onSelect(day),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              hijriNumber(context, day),
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: foreground,
                              ),
                            ),
                            Text(
                              hijriNumber(context, civil.day),
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 10,
                                color: foreground.withValues(alpha: .7),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: events.isEmpty
                                    ? Colors.transparent
                                    : selected
                                    ? colors.onPrimary
                                    : colors.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

Future<void> showCalendarSources(
  BuildContext context,
  List<CalendarEvent> events,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(context.l10n.hijriSources),
    content: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(context.l10n.hijriDisclaimer),
          const SizedBox(height: 12),
          Text(context.l10n.hijriEventHint),
          const SizedBox(height: 16),
          for (final item in events) ...[
            Text(
              item.title(Localizations.localeOf(context).languageCode),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(
              item.description(Localizations.localeOf(context).languageCode),
            ),
            const SizedBox(height: 8),
            Text(item.source['label']!),
            SelectableText(
              item.source['url']!,
              textDirection: TextDirection.ltr,
            ),
            TextButton.icon(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: item.source['url']!)),
              icon: const Icon(Icons.copy_outlined, size: 16),
              label: Text(context.l10n.copyLink),
            ),
          ],
          Text(context.l10n.hijriMethod),
          const SelectableText(
            'hijri 3.0.1 · BSD-2-Clause\nhttps://pub.dev/packages/hijri',
            textDirection: TextDirection.ltr,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.close),
      ),
    ],
  ),
);
