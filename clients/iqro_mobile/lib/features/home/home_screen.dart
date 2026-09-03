import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/storage/preferences_store.dart';
import '../../core/theme/iqro_theme.dart';
import '../audio/reciter_portraits.dart';
import '../dua/dua_repository.dart';
import '../memorization/memorization_repository.dart';
import '../prayer/prayer_repository.dart';
import '../quran/quran_models.dart';
import 'home_view_data.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(readingPositionProvider).valueOrNull;
    final catalog = ref.watch(quranCatalogProvider).valueOrNull;
    final readerMode = ref.watch(
      appPreferencesProvider.select((value) => value.readerMode),
    );
    final preferences = ref.watch(appPreferencesProvider);
    final planState = ref.watch(planProvider);
    final plan = planState.valueOrNull;
    final prayerState = ref.watch(prayerScheduleProvider);
    final memorizationState = ref.watch(memorizationProvider);
    final duaState = ref.watch(duaEntriesProvider);
    final session = ref.watch(sessionProvider).valueOrNull;
    final player = ref.watch(audioControllerProvider);
    final locale = Localizations.localeOf(context).languageCode;
    final currentSurahNumber = position?.surah ?? 1;
    final currentSurah = findSurah(catalog, currentSurahNumber);
    final currentSurahName =
        currentSurah?.nameFor(locale) ??
        '${context.l10n.surah} $currentSurahNumber';
    final memorization = memorizationState.valueOrNull;
    final memorizationPlan = memorization?.plan;
    final memorizationSurah = memorizationPlan == null
        ? null
        : findSurah(catalog, memorizationPlan.startAyah.surah);
    final dailyDua = duaForDate(duaState.valueOrNull, DateTime.now());
    final achieved = plan?.achieved ?? 0;
    final target =
        plan?.target ??
        (preferences.dailyUnit == DailyUnit.pages
            ? preferences.dailyTarget
            : 6);
    final remaining = (target - achieved).clamp(0, target);
    final goalAchieved = achieved.clamp(0, target);
    final planLoading = planState.isLoading && plan == null;
    final prayerPages =
        plan?.prayerPages.values.fold<int>(0, (sum, item) => sum + item) ?? 0;
    final reciter = player.reciter;
    final reciterPortrait = reciter == null
        ? null
        : resolveReciterPortraitUrl(
            reciter,
            apiBaseUrl: ref.watch(appConfigProvider).apiBaseUrl,
          );
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
        padding: iqroRootTabPadding(playerActive: player.active),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _ContinueCard(
              surahName: currentSurahName,
              ayah: position?.ayah ?? 1,
              page: position?.page ?? 1,
              onTap: () {
                if (readerMode == ReaderMode.mushaf) {
                  context.push(
                    '/mushaf?page=${position?.page ?? 1}&surah=${position?.surah ?? 1}&ayah=${position?.ayah ?? 1}',
                  );
                } else {
                  context.push(
                    '/reader/${position?.surah ?? 1}?ayah=${position?.ayah ?? 1}',
                  );
                }
              },
            ),
            const SizedBox(height: 12),
            _PrayerStrip(
              schedule: prayerState.valueOrNull,
              loading: prayerState.isLoading,
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
                        value: planLoading
                            ? null
                            : target == 0
                            ? 0
                            : goalAchieved / target,
                        strokeWidth: 7,
                        backgroundColor: context.iqroColors.line,
                        strokeCap: StrokeCap.round,
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            planLoading ? '—' : '$goalAchieved',
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
                        !planLoading && target > 0 && achieved >= target
                            ? context.l10n.completed
                            : context.l10n.calmPace,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        planLoading
                            ? context.l10n.loading
                            : target > 0 && achieved >= target
                            ? '$achieved ${context.l10n.pages}'
                            : '$remaining ${context.l10n.pages}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: planLoading
                            ? null
                            : target == 0
                            ? 0
                            : goalAchieved / target,
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
                    title: planLoading
                        ? context.l10n.loading
                        : '$prayerPages ${context.l10n.pages}',
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
                    title: _memorizationTitle(
                      context,
                      memorizationState,
                      memorization,
                      memorizationSurah,
                      locale,
                    ),
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
                      url: reciterPortrait,
                      initials: reciter?.initials ?? 'IQ',
                    ),
                    title: Text(
                      reciter == null
                          ? context.l10n.allReciters
                          : context.l10n.recentReciter,
                    ),
                    subtitle: Text(
                      reciter?.nameFor(locale) ?? context.l10n.audioTitle,
                    ),
                    trailing: player.active
                        ? IconButton(
                            tooltip: player.playing
                                ? context.l10n.pause
                                : context.l10n.play,
                            onPressed: player.buffering
                                ? null
                                : ref
                                      .read(audioControllerProvider.notifier)
                                      .toggle,
                            icon: player.buffering
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    player.playing
                                        ? Icons.pause_circle_filled
                                        : Icons.play_circle_fill,
                                  ),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: () => player.active
                        ? context.push('/player')
                        : context.push('/app?tab=3'),
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
                      _duaSubtitle(context, duaState, dailyDua),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => dailyDua == null
                        ? context.push('/dua')
                        : context.push(
                            duaEntryRoute(dailyDua),
                            extra: dailyDua,
                          ),
                  ),
                ],
              ),
            ),
            if (session?.isGuest == true) ...<Widget>[
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
          ],
        ),
      ),
    );
  }

  String _memorizationTitle(
    BuildContext context,
    AsyncValue<MemorizationDashboard> state,
    MemorizationDashboard? value,
    Surah? surah,
    String locale,
  ) {
    if (state.isLoading && value == null) return context.l10n.loading;
    final plan = value?.plan;
    if (plan == null) return context.l10n.memorizationCreatePlan;
    final name =
        surah?.nameFor(locale) ??
        '${context.l10n.surah} ${plan.startAyah.surah}';
    return '$name ${plan.startAyah.ayah}–${plan.endAyah.ayah} · '
        '${value!.today.completedRepetitions}/${plan.dailyRepetitions}';
  }

  String _duaSubtitle(
    BuildContext context,
    AsyncValue<List<DuaEntry>> state,
    DuaEntry? entry,
  ) {
    if (state.isLoading && entry == null) return context.l10n.loading;
    if (entry == null) return context.l10n.duaSubtitle;
    if (entry.meaning.trim().isNotEmpty) return entry.meaning.trim();
    if (entry.categoryTitle.trim().isNotEmpty) {
      return entry.categoryTitle.trim();
    }
    return entry.sourceLabel.trim().isEmpty
        ? context.l10n.duaSubtitle
        : entry.sourceLabel.trim();
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
    required this.surahName,
    required this.ayah,
    required this.page,
    required this.onTap,
  });
  final String surahName;
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
                surahName,
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
  const _PrayerStrip({
    required this.schedule,
    required this.loading,
    required this.onTap,
  });
  final PrayerSchedule? schedule;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final next = nextPrayerOccurrence(schedule, DateTime.now());
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
                  next == null && !loading
                      ? context.l10n.prayer
                      : context.l10n.nextPrayer,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  loading
                      ? context.l10n.loading
                      : next == null
                      ? context.l10n.prayerUnavailable
                      : _prayerName(context, next.code),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
          ),
          if (!loading && next != null)
            Text(
              DateFormat.Hm().format(next.time),
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
