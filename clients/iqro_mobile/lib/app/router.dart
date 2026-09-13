import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/design_system/iqro_widgets.dart';
import '../features/account/account_screen.dart';
import '../features/calendar/hijri_calendar_screen.dart';
import '../features/audio/player_screen.dart';
import '../features/dua/dua_repository.dart';
import '../features/dua/dua_screen.dart';
import '../features/favorites/favorites_screen.dart';
import '../features/memorization/memorization_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/plan/plan_screen.dart';
import '../features/prayer/prayer_screen.dart';
import '../features/prayer/prayer_calendar_screen.dart';
import '../features/quran/mushaf_screen.dart';
import '../features/quran/reader_screen.dart';
import '../features/reminders/reminders_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/offline_storage_screen.dart';
import '../features/share/share_screen.dart';
import 'app_shell.dart';

const _supportedWebLinkLocales = <String>{'ru', 'en', 'ar', 'tr'};

String? normalizeLocalizedDuaDeepLink(Uri uri) {
  final segments = uri.pathSegments;
  if (segments.length < 2 ||
      !_supportedWebLinkLocales.contains(segments.first) ||
      segments[1] != 'dua') {
    return null;
  }
  return Uri(
    path: '/${segments.skip(1).join('/')}',
    query: uri.hasQuery ? uri.query : null,
    fragment: uri.hasFragment ? uri.fragment : null,
  ).toString();
}

GoRouter createRouter({required bool onboardingComplete}) {
  return GoRouter(
    initialLocation: onboardingComplete ? '/app' : '/onboarding',
    redirect: (context, state) => normalizeLocalizedDuaDeepLink(state.uri),
    routes: <RouteBase>[
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/app',
        builder: (context, state) => AppShell(
          initialIndex:
              int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '/reader/:surah',
        builder: (context, state) => ReaderScreen(
          surah: int.tryParse(state.pathParameters['surah'] ?? '') ?? 1,
          initialAyah:
              int.tryParse(state.uri.queryParameters['ayah'] ?? '') ?? 1,
        ),
      ),
      GoRoute(
        path: '/mushaf',
        builder: (context, state) => MushafScreen(
          initialPage:
              int.tryParse(state.uri.queryParameters['page'] ?? '') ?? 1,
          surah: int.tryParse(state.uri.queryParameters['surah'] ?? '') ?? 1,
          ayah: int.tryParse(state.uri.queryParameters['ayah'] ?? '') ?? 1,
        ),
      ),
      GoRoute(
        path: '/player',
        builder: (context, state) => const PlayerScreen(),
      ),
      GoRoute(
        path: '/after-prayer',
        builder: (context, state) => const AfterPrayerScreen(),
      ),
      GoRoute(
        path: '/prayer',
        builder: (context, state) => const PrayerScreen(),
      ),
      GoRoute(
        path: '/prayer/calendar',
        builder: (context, state) => const PrayerCalendarScreen(),
      ),
      GoRoute(
        path: '/calendar',
        builder: (context, state) => const HijriCalendarScreen(),
      ),
      GoRoute(
        path: '/reminders',
        builder: (context, state) => const RemindersScreen(),
      ),
      GoRoute(
        path: '/memorization',
        builder: (context, state) => const MemorizationScreen(),
      ),
      GoRoute(path: '/dua', builder: (context, state) => const DuaScreen()),
      GoRoute(
        path: '/dua/:collection/:sourceNumber',
        builder: (context, state) {
          final entry = state.extra;
          return DuaEntryRouteScreen(
            collection: state.pathParameters['collection'] ?? '',
            sourceNumber:
                int.tryParse(state.pathParameters['sourceNumber'] ?? '') ?? 0,
            initialEntry: entry is DuaEntry ? entry : null,
          );
        },
      ),
      GoRoute(
        path: '/dua/:collection/categories/:category',
        builder: (context, state) => DuaScreen(
          initialCollection: state.pathParameters['collection'],
          initialCategory: state.pathParameters['category'],
        ),
      ),
      GoRoute(
        path: '/dua/:id',
        builder: (context, state) {
          final entry = state.extra;
          final id = state.pathParameters['id'] ?? '';
          if (!isDuaEntryId(id)) return DuaScreen(initialCategory: id);
          return DuaEntryRouteScreen(
            entryId: id,
            initialEntry: entry is DuaEntry ? entry : null,
          );
        },
      ),
      GoRoute(
        path: '/favorites',
        builder: (context, state) => const FavoritesScreen(),
      ),
      GoRoute(
        path: '/account',
        builder: (context, state) => const AccountScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/settings/offline-storage',
        builder: (context, state) => const OfflineStorageScreen(),
      ),
      GoRoute(path: '/share', builder: (context, state) => const ShareScreen()),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.error_outline, size: 42),
              const SizedBox(height: 12),
              Text(context.l10n.networkError, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go('/app'),
                child: const Text('IQRO'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
