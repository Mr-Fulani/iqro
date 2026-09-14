import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import '../plan/plan_repository.dart';
import '../prayer/prayer_repository.dart';
import 'home_view_data.dart';

class HomePrayerCard extends StatelessWidget {
  const HomePrayerCard({
    required this.schedule,
    required this.loading,
    required this.clock,
    required this.onTap,
    required this.onReminders,
    super.key,
  });
  final PrayerSchedule? schedule;
  final bool loading;
  final DateTime clock;
  final VoidCallback onTap;
  final VoidCallback onReminders;

  @override
  Widget build(BuildContext context) {
    final next = nextPrayerOccurrence(schedule, clock);
    final text = Theme.of(context).textTheme;
    final minutes = next == null
        ? 0
        : next.time.difference(clock).inMinutes.clamp(0, 2880);
    final countdown =
        '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';
    final name = switch (next?.code) {
      'fajr' => context.l10n.fajr,
      'dhuhr' => context.l10n.dhuhr,
      'asr' => context.l10n.asr,
      'maghrib' => context.l10n.maghrib,
      'isha' => context.l10n.isha,
      _ => context.l10n.prayer,
    };
    return IqroCard(
      key: const ValueKey('home-prayer'),
      color: context.iqroColors.ink,
      borderColor: context.iqroColors.inkSoft,
      onTap: onTap,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              constraints.maxWidth < 280 ||
              MediaQuery.textScalerOf(context).scale(16) > 20;
          final summary = Row(
            children: [
              Icon(
                Icons.mosque_outlined,
                color: context.iqroColors.gold,
                size: 36,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.nextPrayer,
                      style: text.bodySmall?.copyWith(color: Colors.white70),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      loading ? context.l10n.loading : name,
                      style: text.titleLarge?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      next == null
                          ? context.l10n.prayerUnavailable
                          : context.l10n.homePrayerIn(countdown),
                      style: text.bodySmall?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          );
          final time = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                next == null || loading
                    ? '—:—'
                    : DateFormat.Hm().format(next.time),
                textDirection: TextDirection.ltr,
                style: text.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: context.iqroColors.gold,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: onReminders,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF91D7C3),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(48, 48),
                  textStyle: text.labelMedium,
                ),
                icon: const Icon(Icons.notifications_none_rounded, size: 18),
                label: Text(context.l10n.reminders),
              ),
            ],
          );
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [summary, const SizedBox(height: 12), time],
            );
          }
          return IntrinsicHeight(
            child: Row(
              children: [
                Expanded(flex: 5, child: summary),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: VerticalDivider(
                    width: 1,
                    color: Colors.white.withValues(alpha: .16),
                  ),
                ),
                Expanded(flex: 4, child: time),
              ],
            ),
          );
        },
      ),
    );
  }
}

class HomeContinueReadingCard extends StatelessWidget {
  const HomeContinueReadingCard({
    required this.surahName,
    required this.ayah,
    required this.page,
    required this.onTap,
    this.onBookmarks,
    this.error = false,
    super.key,
  });
  final String surahName;
  final int? ayah;
  final int? page;
  final bool error;
  final VoidCallback? onTap;
  final VoidCallback? onBookmarks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      child: IqroCard(
        key: const ValueKey('home-reading'),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked =
                    constraints.maxWidth < 280 ||
                    MediaQuery.textScalerOf(context).scale(16) > 20;
                final summary = Row(
                  children: [
                    Icon(
                      Icons.menu_book_outlined,
                      color: theme.colorScheme.primary,
                      size: 36,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.continueReading,
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            error ? context.l10n.networkError : surahName,
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 5),
                          if (!error)
                            Text(
                              ayah == null || page == null
                                  ? context.l10n.loading
                                  : '${context.l10n.ayah} $ayah · ${context.l10n.page} $page',
                              style: theme.textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                  ],
                );
                final read = FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.brightness == Brightness.dark
                        ? const Color(0xFFFFFCF5)
                        : theme.colorScheme.primary,
                    foregroundColor: theme.brightness == Brightness.dark
                        ? context.iqroColors.ink
                        : theme.colorScheme.onPrimary,
                  ),
                  onPressed: onTap,
                  icon: Icon(
                    error ? Icons.refresh_rounded : Icons.menu_book_outlined,
                    size: 20,
                  ),
                  label: Text(error ? context.l10n.retry : context.l10n.read),
                );
                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [summary, const SizedBox(height: 12), read],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: summary),
                    const SizedBox(width: 12),
                    read,
                  ],
                );
              },
            ),
            if (onBookmarks != null) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              HomeUtilityRow(
                icon: Icons.bookmark_border_rounded,
                title: context.l10n.bookmarks,
                onTap: onBookmarks!,
                compact: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class HomePlanCard extends StatelessWidget {
  const HomePlanCard({
    required this.achieved,
    required this.target,
    required this.metric,
    required this.loading,
    required this.error,
    required this.onTap,
    super.key,
  });
  final num achieved;
  final num target;
  final ReadingGoalMetric metric;
  final bool loading;
  final bool error;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = switch (metric) {
      ReadingGoalMetric.minutes => context.l10n.minutes,
      ReadingGoalMetric.pages => context.l10n.pages,
      ReadingGoalMetric.ayahs => context.l10n.ayahs,
    };
    final complete = !loading && !error && target > 0 && achieved >= target;
    return IqroCard(
      key: const ValueKey('home-plan'),
      onTap: onTap,
      child: Row(
        children: [
          Icon(
            Icons.track_changes_rounded,
            size: 32,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.dailyGoal, style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Text(
                      loading
                          ? context.l10n.loading
                          : error
                          ? context.l10n.openPlan
                          : '${_amount(achieved)} / ${_amount(target)} $unit',
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (complete)
                      Text(
                        context.l10n.completed,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (!error)
                  LinearProgressIndicator(
                    value: loading
                        ? null
                        : target <= 0
                        ? 0
                        : (achieved / target).clamp(0, 1).toDouble(),
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(4),
                    backgroundColor: context.iqroColors.line,
                    semanticsLabel: context.l10n.dailyGoal,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            complete ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
            color: theme.colorScheme.primary,
            size: 20,
          ),
        ],
      ),
    );
  }
}

class HomeFeatureCard extends StatelessWidget {
  const HomeFeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.action,
    super.key,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IqroCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.primary, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          action ?? const Icon(Icons.chevron_right_rounded, size: 16),
        ],
      ),
    );
  }
}

class HomeUtilityRow extends StatelessWidget {
  const HomeUtilityRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.compact = false,
    super.key,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    minTileHeight: compact ? 48 : 72,
    horizontalTitleGap: 14,
    leading: Icon(
      icon,
      size: compact ? 24 : 28,
      color: Theme.of(context).colorScheme.primary,
    ),
    title: Text(
      title,
      style: compact
          ? Theme.of(context).textTheme.bodyMedium
          : Theme.of(context).textTheme.titleSmall,
    ),
    subtitle: subtitle == null || subtitle!.isEmpty
        ? null
        : Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis),
    trailing: const Icon(Icons.chevron_right_rounded, size: 20),
    onTap: onTap,
  );
}

String _amount(num value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
