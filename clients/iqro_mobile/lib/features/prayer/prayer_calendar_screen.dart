import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../app/providers.dart';
import '../../core/auth/account_scope.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import 'prayer_places.dart';
import 'prayer_repository.dart';

class PrayerCalendarScreen extends ConsumerStatefulWidget {
  const PrayerCalendarScreen({super.key});

  @override
  ConsumerState<PrayerCalendarScreen> createState() =>
      _PrayerCalendarScreenState();
}

class _PrayerCalendarScreenState extends ConsumerState<PrayerCalendarScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<PrayerSchedule> _schedules = const <PrayerSchedule>[];
  PrayerMethod? _method;
  PrayerLocation? _location;
  Object? _error;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final city = prayerCityById(_location?.cityId);
    final locationName = city?.nameFor(locale) ?? context.l10n.currentLocation;
    return Scaffold(
      appBar: IqroTopBar(
        title: context.l10n.prayerCalendar,
        subtitle: _location == null
            ? context.l10n.locationNotSelected
            : '$locationName · ${_method?.nameFor(locale) ?? ''}',
      ),
      body: IqroPage(
        scrollable: false,
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                IconButton(
                  tooltip: context.l10n.previousMonth,
                  onPressed: _loading ? null : () => _changeMonth(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    DateFormat.yMMMM(locale).format(_month),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.nextMonth,
                  onPressed: _loading ? null : () => _changeMonth(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Expanded(
                child: Center(
                  child: IqroStatusBanner(
                    icon: Icons.error_outline,
                    title: context.l10n.prayerCalendarUnavailable,
                    actionLabel: context.l10n.retry,
                    onAction: _load,
                  ),
                ),
              )
            else if (_schedules.isEmpty)
              Expanded(
                child: Center(
                  child: IqroStatusBanner(
                    icon: Icons.location_off_outlined,
                    title: context.l10n.prayerCalendarNeedsLocation,
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: _schedules.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _PrayerCalendarDay(
                    schedule: _schedules[index],
                    locale: locale,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeMonth(int delta) async {
    final next = DateTime(_month.year, _month.month + delta);
    if (next.year < 1900 || next.year > 2100) return;
    setState(() => _month = next);
    await _load();
  }

  Future<void> _load() async {
    final database = ref.read(localDatabaseProvider);
    final scope = database.accountScope.current;
    if (scope == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = ref.read(prayerRepositoryProvider);
      final values = await (
        repository.selectedMethod(accountScope: scope),
        repository.storedLocation(accountScope: scope),
      ).wait;
      database.ensureCurrent(scope);
      final schedules = await repository.calculateMonth(
        month: _month,
        method: values.$1,
        location: values.$2,
        accountScope: scope,
      );
      database.ensureCurrent(scope);
      if (!mounted) return;
      setState(() {
        _method = values.$1;
        _location = values.$2;
        _schedules = schedules;
        _loading = false;
      });
    } on AccountScopeChanged {
      // A newly mounted account owns its own calendar state.
    } on Object catch (error) {
      if (mounted && database.accountScope.isCurrent(scope)) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }
}

class _PrayerCalendarDay extends StatelessWidget {
  const _PrayerCalendarDay({required this.schedule, required this.locale});

  final PrayerSchedule schedule;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isToday =
        schedule.date.year == now.year &&
        schedule.date.month == now.month &&
        schedule.date.day == now.day;
    return IqroCard(
      color: isToday ? context.iqroColors.lavender : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  DateFormat.MMMEd(locale).format(schedule.date),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (isToday)
                Text(
                  context.l10n.today,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                for (final code in _calendarPrayerCodes)
                  SizedBox(
                    width: 76,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          _calendarPrayerName(context, code),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          schedule.times[code] == null
                              ? '—'
                              : DateFormat.Hm().format(schedule.times[code]!),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _calendarPrayerName(BuildContext context, String code) => switch (code) {
  'fajr' => context.l10n.fajr,
  'sunrise' => context.l10n.sunrise,
  'dhuhr' => context.l10n.dhuhr,
  'asr' => context.l10n.asr,
  'maghrib' => context.l10n.maghrib,
  _ => context.l10n.isha,
};

const _calendarPrayerCodes = <String>[
  'fajr',
  'sunrise',
  'dhuhr',
  'asr',
  'maghrib',
  'isha',
];
