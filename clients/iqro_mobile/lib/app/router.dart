import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/design_system/iqro_widgets.dart';
import '../features/account/account_screen.dart';
import '../features/audio/player_screen.dart';
import '../features/dua/dua_repository.dart';
import '../features/dua/dua_screen.dart';
import '../features/favorites/favorites_screen.dart';
import '../features/memorization/memorization_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/plan/plan_screen.dart';
import '../features/prayer/prayer_screen.dart';
import '../features/quran/mushaf_screen.dart';
import '../features/quran/reader_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/share/share_screen.dart';
import 'app_shell.dart';

GoRouter createRouter({required bool onboardingComplete}) {
  return GoRouter(
    initialLocation: onboardingComplete ? '/app' : '/onboarding',
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
        path: '/memorization',
        builder: (context, state) => const MemorizationScreen(),
      ),
      GoRoute(path: '/dua', builder: (context, state) => const DuaScreen()),
      GoRoute(
        path: '/dua/:id',
        builder: (context, state) {
          final entry = state.extra;
          if (entry is DuaEntry) return DuaEntryScreen(entry: entry);
          return const DuaScreen();
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
