import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat, toBeginningOfSentenceCase;

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/design_system/iqro_animated_logo.dart';
import '../../core/storage/preferences_store.dart';
import '../../core/theme/iqro_theme.dart';
import '../announcements/announcement_bubble.dart';
import '../audio/mini_player.dart';
import '../calendar/hijri_calendar_service.dart';
import '../plan/palm_growth.dart';
import '../prayer/prayer_repository.dart';
import '../quran/quran_models.dart';
import 'home_view_data.dart';
import 'home_dashboard_cards.dart';
import 'home_plan_walker.dart';
import 'home_section_tiles.dart';
import 'home_sky_card.dart';
import 'home_dashboard_layout.dart';
import '../calendar/hijri_calendar_screen.dart' show hijriDateLabel;
export 'home_dashboard_cards.dart' show HomeContinueReadingCard;

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountScopeKey = ref.watch(activeAccountScopeKeyProvider);
    final positionState = accountScopeKey == null
        ? const AsyncValue<ReadingPosition>.loading()
        : ref.watch(readingPositionProvider(accountScopeKey));
    final position = positionState.valueOrNull;
    final catalog = ref.watch(quranCatalogProvider).valueOrNull;
    final readerMode = ref.watch(
      appPreferencesProvider.select((value) => value.readerMode),
    );
    final preferences = ref.watch(appPreferencesProvider);
    final planState = ref.watch(planProvider);
    final plan = planState.valueOrNull;
    final prayerState = accountScopeKey == null
        ? const AsyncValue<PrayerSchedule?>.loading()
        : ref.watch(prayerScheduleProvider(accountScopeKey));
    final session = ref.watch(sessionProvider).valueOrNull;
    final audioController = ref.read(audioControllerProvider.notifier);
    // Select the presentation only: position ticks during playback must not
    // rebuild the whole dashboard.
    final player = ref.watch(
      audioControllerProvider.select(audioController.listeningPresentation),
    );
    final locale = Localizations.localeOf(context).languageCode;
    final clock =
        ref.watch(calendarClockProvider).valueOrNull ?? DateTime.now();
    final currentSurahNumber = position?.surah ?? 1;
    final currentSurah = findSurah(catalog, currentSurahNumber);
    final currentSurahName =
        currentSurah?.nameFor(locale) ??
        '${context.l10n.surah} $currentSurahNumber';
    final achieved = plan?.achieved ?? 0;
    final target = plan?.target ?? preferences.dailyTarget.toDouble();
    final planMetric =
        plan?.metric ?? readingMetricForDailyUnit(preferences.dailyUnit);
    final planLoading = planState.isLoading && plan == null;
    final hijri = const HijriCalendarService().now(
      clock,
      adjustment: preferences.hijriAdjustment,
      maghribUtc: DateUtils.isSameDay(prayerState.valueOrNull?.date, clock)
          ? prayerState.valueOrNull?.timesUtc['maghrib']
          : null,
    );
    final dateLine = [
      toBeginningOfSentenceCase(DateFormat.MMMMEEEEd(locale).format(clock)),
      if (hijri != null) hijriDateLabel(context, hijri),
    ].join(' · ');
    final prayerCard = HomePrayerSkyCard(
      schedule: prayerState.valueOrNull,
      loading: prayerState.isLoading && prayerState.valueOrNull == null,
      clock: clock,
      onTap: () => context.push('/prayer'),
      onQibla: () => context.push('/prayer?qibla=1'),
      onReminders: () => context.push('/reminders'),
    );
    final mushafRoute = position == null
        ? '/mushaf'
        : '/mushaf?page=${position.page}'
              '&surah=${position.surah}&ayah=${position.ayah}';
    final readingCard = HomeContinueReadingCard(
      surahName: position == null ? context.l10n.loading : currentSurahName,
      ayah: position?.ayah,
      page: position?.page,
      error: positionState.hasError && position == null,
      onTap: position == null
          ? positionState.hasError && accountScopeKey != null
                ? () => ref.invalidate(readingPositionProvider(accountScopeKey))
                : null
          : () {
              if (readerMode == ReaderMode.mushaf) {
                context.push(mushafRoute);
              } else {
                context.push('/reader/${position.surah}?ayah=${position.ayah}');
              }
            },
      footer: HomePlanWalker(
        achieved: achieved,
        target: target,
        metric: planMetric,
        loading: planLoading,
        error: planState.hasError && plan == null,
        palm: plan == null ? null : palmGrowthFor(plan),
        onTap: () => context.go('/app?tab=2'),
      ),
    );
    final colors = context.iqroColors;
    final mint = Theme.of(context).colorScheme.primaryContainer;
    final tiles = <HomeSectionTile>[
      HomeSectionTile(
        id: 'mushaf',
        art: 'quran',
        title: context.l10n.mushafMode,
        color: mint,
        onTap: () => context.push(mushafRoute),
      ),
      HomeSectionTile(
        id: 'dua',
        art: 'dua',
        title: context.l10n.dua,
        color: mint,
        onTap: () => context.push('/dua'),
      ),
      HomeSectionTile(
        id: 'courses',
        art: 'courses',
        title: context.l10n.coursesTitle,
        color: colors.sand,
        onTap: () => context.push('/courses'),
      ),
      HomeSectionTile(
        id: 'memorization',
        art: 'memorization',
        title: context.l10n.memorization,
        color: colors.lavender,
        onTap: () => context.push('/memorization'),
      ),
      HomeSectionTile(
        id: 'qibla',
        art: 'qibla',
        title: context.l10n.qibla,
        color: colors.sand,
        onTap: () => context.push('/prayer?qibla=1'),
      ),
      HomeSectionTile(
        id: 'favorites',
        art: 'favorites',
        title: context.l10n.favorites,
        color: colors.panelSoft,
        onTap: () => context.push('/favorites'),
      ),
      HomeSectionTile(
        id: 'calendar',
        art: 'hijri-calendar',
        title: context.l10n.hijriCalendar,
        color: colors.sand,
        onTap: () => context.push('/calendar'),
      ),
      HomeSectionTile(
        id: 'notes',
        art: 'notes',
        title: context.l10n.notes,
        color: colors.panelSoft,
        onTap: () => context.push('/notes'),
      ),
      HomeSectionTile(
        id: 'all',
        art: 'sections',
        title: context.l10n.homeAllSections,
        color: colors.panelSoft,
        onTap: () => context.go('/app?tab=4'),
      ),
    ];
    return AnnouncementBubbleLayer(
      child: Scaffold(
        appBar: IqroTopBar(
          title: 'IQRO',
          subtitle: dateLine,
          leading: const Padding(
            padding: EdgeInsetsDirectional.only(start: 10, end: 8),
            child: Center(child: IqroAnimatedLogo(size: 36)),
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
          tabletContentWidth: homeTabletContentWidth,
          padding: iqroRootTabPadding(
            context,
            playerActive: player.track != null,
            playerCollapsed: ref.watch(miniPlayerCollapsedProvider),
          ),
          child: HomeDashboardLayout(
            prayer: prayerCard,
            reading: readingCard,
            sections: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.l10n.homeSections,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                HomeSectionTiles(tiles: tiles),
              ],
            ),
            guest: session?.isGuest == true
                ? IqroStatusBanner(
                    icon: Icons.shield_outlined,
                    title: context.l10n.readingAsGuest,
                    message: context.l10n.guestSyncHint,
                    actionLabel: context.l10n.signIn,
                    onAction: () => context.push('/account'),
                    color: context.iqroColors.lavender,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
