import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import '../prayer/prayer_repository.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(readingPositionProvider).valueOrNull;
    final plan = ref.watch(planProvider).valueOrNull;
    final reciter = ref.watch(recitersProvider).valueOrNull?.firstOrNull;
    final prayer = ref.watch(prayerScheduleProvider).valueOrNull;
    final locale = Localizations.localeOf(context).languageCode;
    final achieved = plan?.achieved ?? 0;
    final target = plan?.target ?? 6;
    final remaining = (target - achieved).clamp(0, target);
    return Scaffold(
      appBar: IqroTopBar(
        title: context.l10n.greeting,
        subtitle: DateFormat.yMMMMEEEEd(locale).format(DateTime.now()),
        leading: const Padding(
          padding: EdgeInsetsDirectional.only(start: 12),
          child: _HomeLogo(),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: context.l10n.settings,
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: IqroPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _ContinueCard(
              ayah: position?.ayah ?? 1,
              page: position?.page ?? 1,
              onTap: () => context.push('/reader/${position?.surah ?? 1}'),
            ),
            const SizedBox(height: 12),
            _PrayerStrip(
              schedule: prayer,
              onTap: () => context.push('/prayer'),
            ),
            const SizedBox(height: 28),
            IqroSectionHeader(
              eyebrow: context.l10n.yourRhythm,
              title: context.l10n.today,
              action: TextButton(
                onPressed: () => context.push('/app?tab=2'),
                child: Text(context.l10n.openPlan),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                SizedBox(
                  width: 84,
                  height: 84,
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      CircularProgressIndicator(
                        value: target == 0 ? 0 : achieved / target,
                        strokeWidth: 7,
                        backgroundColor: context.iqroColors.line,
                        strokeCap: StrokeCap.round,
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            '$achieved',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            '/ $target',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        context.l10n.calmPace,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$remaining ${context.l10n.pages}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: target == 0 ? 0 : achieved / target,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              children: <Widget>[
                Expanded(
                  child: _FeaturePanel(
                    color: context.iqroColors.sand,
                    icon: Icons.schedule_outlined,
                    eyebrow: context.l10n.afterPrayer,
                    title:
                        '${plan?.prayerPages.values.fold<int>(0, (sum, item) => sum + item) ?? 0} / 10',
                    onTap: () => context.push('/after-prayer'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _FeaturePanel(
                    color: context.iqroColors.ink,
                    foreground: Colors.white,
                    icon: Icons.repeat,
                    eyebrow: context.l10n.memorization,
                    title: '${context.l10n.alFatiha} 1–3',
                    onTap: () => context.push('/memorization'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            IqroCard(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
              child: Column(
                children: <Widget>[
                  ListTile(
                    minTileHeight: 64,
                    contentPadding: EdgeInsets.zero,
                    leading: _ReciterAvatar(
                      url: reciter?.portraitUrl,
                      initials: reciter?.initials ?? 'IQ',
                    ),
                    title: Text(context.l10n.recentReciter),
                    subtitle: Text(
                      reciter?.nameFor(locale) ?? context.l10n.allReciters,
                    ),
                    trailing: const Icon(Icons.play_circle_fill),
                    onTap: () => context.push('/app?tab=3'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    minTileHeight: 64,
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: context.iqroColors.sand,
                      child: Icon(
                        Icons.auto_awesome_outlined,
                        color: context.iqroColors.gold,
                      ),
                    ),
                    title: Text(context.l10n.duaOfDay),
                    subtitle: Text(
                      context.l10n.duaSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/dua'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            IqroStatusBanner(
              icon: Icons.shield_outlined,
              title: context.l10n.readingAsGuest,
              message: context.l10n.guestSyncHint,
              actionLabel: context.l10n.signIn,
              onAction: () => context.push('/account'),
              color: context.iqroColors.lavender,
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeLogo extends StatelessWidget {
  const _HomeLogo();
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.iqroColors.ink,
        borderRadius: BorderRadius.circular(13),
      ),
      child: const Text(
        'اق',
        textDirection: TextDirection.rtl,
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.ayah,
    required this.page,
    required this.onTap,
  });
  final int ayah;
  final int page;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IqroCard(
      color: context.iqroColors.ink,
      borderColor: Colors.transparent,
      padding: const EdgeInsets.all(22),
      onTap: onTap,
      child: Stack(
        children: <Widget>[
          PositionedDirectional(
            end: -54,
            top: -72,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: .12)),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              IqroEyebrow(context.l10n.continueReading, light: true),
              const SizedBox(height: 10),
              Text(
                context.l10n.alFatiha,
                style: Theme.of(
                  context,
                ).textTheme.displaySmall?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 6),
              Text(
                '${context.l10n.ayah} $ayah · ${context.l10n.page} $page',
                style: TextStyle(color: Colors.white.withValues(alpha: .76)),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFFFCF5),
                  foregroundColor: context.iqroColors.ink,
                ),
                onPressed: onTap,
                icon: const Icon(Icons.menu_book_outlined),
                label: Text(context.l10n.read),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.sync,
                    size: 16,
                    color: Colors.white.withValues(alpha: .72),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      context.l10n.savedAutomatically,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: .72),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PrayerStrip extends StatelessWidget {
  const _PrayerStrip({required this.schedule, required this.onTap});
  final PrayerSchedule? schedule;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final next = _nextPrayer(context, schedule);
    return IqroCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: context.iqroColors.sand,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.mosque_outlined, color: context.iqroColors.gold),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  context.l10n.nextPrayer,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(next.$1, style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
          ),
          if (next.$2 != null)
            Text(
              DateFormat.Hm().format(next.$2!),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }

  (String, DateTime?) _nextPrayer(BuildContext context, PrayerSchedule? value) {
    if (value == null) return (context.l10n.maghrib, null);
    final now = DateTime.now();
    for (final entry in value.times.entries) {
      if (entry.value.isAfter(now) && entry.key != 'sunrise') {
        return (_prayerName(context, entry.key), entry.value);
      }
    }
    return (context.l10n.fajr, null);
  }

  String _prayerName(BuildContext context, String code) => switch (code) {
    'fajr' => context.l10n.fajr,
    'dhuhr' => context.l10n.dhuhr,
    'asr' => context.l10n.asr,
    'maghrib' => context.l10n.maghrib,
    _ => context.l10n.isha,
  };
}

class _FeaturePanel extends StatelessWidget {
  const _FeaturePanel({
    required this.color,
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.onTap,
    this.foreground,
  });
  final Color color;
  final Color? foreground;
  final IconData icon;
  final String eyebrow;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textColor = foreground ?? Theme.of(context).colorScheme.onSurface;
    return IqroCard(
      color: color,
      borderColor: Colors.transparent,
      onTap: onTap,
      child: SizedBox(
        height: 112,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: textColor),
            const Spacer(),
            Text(
              eyebrow,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: textColor.withValues(alpha: .72),
              ),
            ),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(color: textColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReciterAvatar extends StatelessWidget {
  const _ReciterAvatar({required this.url, required this.initials});
  final String? url;
  final String initials;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 22,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      backgroundImage: url == null ? null : CachedNetworkImageProvider(url!),
      child: url == null ? Text(initials) : null,
    );
  }
}
