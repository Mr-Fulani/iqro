import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/audio/audio_controller.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/design_system/iqro_animated_logo.dart';
import '../../core/storage/preferences_store.dart';
import '../../core/theme/iqro_theme.dart';
import '../audio/mini_player.dart';
import '../calendar/hijri_calendar_service.dart';
import '../calendar/calendar_catalog.dart';
import '../dua/dua_repository.dart';
import '../memorization/memorization_repository.dart';
import '../prayer/prayer_repository.dart';
import '../quran/quran_models.dart';
import 'home_view_data.dart';
import 'home_dashboard_cards.dart';
import '../../core/design_system/iqro_action_grid.dart';
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
    final memorizationState = ref.watch(memorizationProvider);
    final duaState = ref.watch(duaEntriesProvider);
    final session = ref.watch(sessionProvider).valueOrNull;
    final player = ref.watch(
      audioControllerProvider.select(iqroAudioPresentation),
    );
    final locale = Localizations.localeOf(context).languageCode;
    final clock =
        ref.watch(calendarClockProvider).valueOrNull ?? DateTime.now();
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
    final dailyDua = duaForDate(duaState.valueOrNull, clock);
    final achieved = plan?.achieved ?? 0;
    final target = plan?.target ?? preferences.dailyTarget.toDouble();
    final planMetric =
        plan?.metric ?? readingMetricForDailyUnit(preferences.dailyUnit);
    final planLoading = planState.isLoading && plan == null;
    final prayerPages =
        plan?.prayerPages.values.fold<int>(0, (sum, item) => sum + item) ?? 0;
    final reciter = player.reciter;
    final hijri = const HijriCalendarService().now(
      clock,
      adjustment: preferences.hijriAdjustment,
      maghribUtc: DateUtils.isSameDay(prayerState.valueOrNull?.date, clock)
          ? prayerState.valueOrNull?.timesUtc['maghrib']
          : null,
    );
    final calendar = ref.watch(calendarCatalogProvider).valueOrNull;
    final calendarEvents = hijri == null
        ? ''
        : calendar
                  ?.forDate(hijri)
                  .map((event) => event.title(locale))
                  .join(' · ') ??
              '';
    return Scaffold(
      appBar: IqroTopBar(
        title: 'IQRO',
        subtitle: context.l10n.greeting,
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
        padding: iqroRootTabPadding(
          playerActive: player.track != null,
          playerCollapsed: ref.watch(miniPlayerCollapsedProvider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            HomePrayerCard(
              schedule: prayerState.valueOrNull,
              loading: prayerState.isLoading && prayerState.valueOrNull == null,
              clock: clock,
              onTap: () => context.push('/prayer'),
              onReminders: () => context.push('/reminders'),
            ),
            const SizedBox(height: 12),
            HomeContinueReadingCard(
              surahName: position == null
                  ? context.l10n.loading
                  : currentSurahName,
              ayah: position?.ayah,
              page: position?.page,
              error: positionState.hasError && position == null,
              onBookmarks: () => context.push('/favorites'),
              onTap: position == null
                  ? positionState.hasError && accountScopeKey != null
                        ? () => ref.invalidate(
                            readingPositionProvider(accountScopeKey),
                          )
                        : null
                  : () {
                      if (readerMode == ReaderMode.mushaf) {
                        context.push(
                          '/mushaf?page=${position.page}'
                          '&surah=${position.surah}&ayah=${position.ayah}',
                        );
                      } else {
                        context.push(
                          '/reader/${position.surah}?ayah=${position.ayah}',
                        );
                      }
                    },
            ),
            const SizedBox(height: 12),
            HomePlanCard(
              achieved: achieved,
              target: target,
              metric: planMetric,
              loading: planLoading,
              error: planState.hasError && plan == null,
              onTap: () => context.go('/app?tab=2'),
            ),
            const SizedBox(height: 16),
            IqroActionGrid(
              children: [
                HomeFeatureCard(
                  icon: Icons.schedule_outlined,
                  title: context.l10n.afterPrayer,
                  subtitle: planLoading
                      ? context.l10n.loading
                      : planState.hasError && plan == null
                      ? context.l10n.openPlan
                      : '$prayerPages ${context.l10n.pages}',
                  onTap: () => context.push('/after-prayer'),
                ),
                HomeFeatureCard(
                  icon: Icons.school_outlined,
                  title: context.l10n.memorization,
                  subtitle: _memorizationTitle(
                    context,
                    memorizationState,
                    memorization,
                    memorizationSurah,
                    locale,
                  ),
                  onTap: () => context.push('/memorization'),
                ),
                HomeFeatureCard(
                  icon: Icons.headphones_outlined,
                  title: context.l10n.navAudio,
                  subtitle:
                      reciter?.nameFor(locale) ?? context.l10n.allReciters,
                  onTap: () => player.track != null
                      ? context.push('/player')
                      : context.go('/app?tab=3'),
                  action: player.track == null
                      ? null
                      : IconButton.filledTonal(
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
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  player.playing
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                ),
                        ),
                ),
                HomeFeatureCard(
                  icon: Icons.nights_stay_outlined,
                  title: context.l10n.dua,
                  subtitle: _duaSubtitle(context, duaState, dailyDua),
                  onTap: () => dailyDua == null
                      ? context.push('/dua')
                      : context.push(duaEntryRoute(dailyDua), extra: dailyDua),
                ),
              ],
            ),
            const SizedBox(height: 16),
            IqroCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(
                children: [
                  HomeUtilityRow(
                    icon: Icons.bookmarks_outlined,
                    title: context.l10n.favorites,
                    subtitle: context.l10n.homeSavedHint,
                    onTap: () => context.push('/favorites'),
                  ),
                  const Divider(height: 1),
                  HomeUtilityRow(
                    icon: Icons.calendar_month_outlined,
                    title: context.l10n.hijriCalendar,
                    subtitle: [
                      if (hijri != null) hijriDateLabel(context, hijri),
                      if (calendarEvents.isNotEmpty) calendarEvents,
                    ].join(' · '),
                    onTap: () => context.push('/calendar'),
                  ),
                  const Divider(height: 1),
                  HomeUtilityRow(
                    icon: Icons.notifications_none_rounded,
                    title: context.l10n.reminders,
                    subtitle: context.l10n.remindersSubtitle,
                    onTap: () => context.push('/reminders'),
                  ),
                  const Divider(height: 1),
                  HomeUtilityRow(
                    icon: Icons.download_outlined,
                    title: context.l10n.homeDownloads,
                    subtitle: context.l10n.offlineStorageSettingsSubtitle,
                    onTap: () => context.push('/settings/offline-storage'),
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
