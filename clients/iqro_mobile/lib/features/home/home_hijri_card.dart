import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import '../calendar/hijri_calendar_screen.dart';
import '../calendar/hijri_calendar_service.dart';

class HomeHijriCard extends StatelessWidget {
  const HomeHijriCard({
    super.key,
    required this.clock,
    required this.adjustment,
    required this.onTap,
    this.maghribUtc,
  });
  final DateTime clock;
  final int adjustment;
  final DateTime? maghribUtc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = const HijriCalendarService().now(
      clock,
      adjustment: adjustment,
      maghribUtc: maghribUtc,
    );
    final days = date == null ? <IslamicDay>[] : islamicDays(date);
    final sunset = clock.isUtc ? maghribUtc?.toUtc() : maghribUtc?.toLocal();
    final hasSunset = sunset != null && DateUtils.isSameDay(sunset, clock);
    return IqroCard(
      color: context.iqroColors.sand,
      padding: const EdgeInsets.all(16),
      borderColor: context.iqroColors.gold.withValues(alpha: .22),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 3, end: 12),
            child: Icon(
              Icons.nights_stay_outlined,
              color: context.iqroColors.gold,
              size: 26,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  date == null
                      ? context.l10n.hijriUnavailable
                      : hijriDateLabel(context, date),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat.yMMMMEEEEd(
                    Localizations.localeOf(context).languageCode,
                  ).format(clock),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (days.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    days
                        .map((d) => context.l10n.hijriEventName(d.name))
                        .join(' · '),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  hasSunset
                      ? context.l10n.hijriSunsetDate
                      : context.l10n.hijriCivilHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsetsDirectional.only(start: 4, top: 3),
            child: Icon(Icons.chevron_right, size: 18),
          ),
        ],
      ),
    );
  }
}
