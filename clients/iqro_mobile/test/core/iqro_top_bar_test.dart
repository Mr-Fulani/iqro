import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iqro_mobile/core/design_system/iqro_widgets.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';

void main() {
  final home = find.byKey(const ValueKey('iqro-top-bar-home'));

  Future<GoRouter> pump(WidgetTester tester, String location) async {
    final router = GoRouter(
      initialLocation: location,
      routes: <RouteBase>[
        GoRoute(
          path: '/app',
          builder: (context, state) => const Scaffold(body: Text('HOME')),
        ),
        GoRoute(
          path: '/dua',
          builder: (context, state) =>
              const Scaffold(appBar: IqroTopBar(title: 'Дуа')),
        ),
        // A screen under the app's tab bar, as Prayer times is.
        GoRoute(
          path: '/prayer',
          builder: (context, state) => const IqroTabsScope(
            child: Scaffold(appBar: IqroTopBar(title: 'Намаз')),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        locale: const Locale('ru'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('on iOS a screen opened in place of the others (by a '
      'notification or a link) leads home', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pump(tester, '/dua');
      expect(home, findsOneWidget);
      expect(find.byTooltip('Главная'), findsOneWidget);
      await tester.tap(home);
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('on iOS a screen opened over another keeps its Back, and one '
      'under the tab bar needs no way home', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final router = await pump(tester, '/app');
      unawaited(router.push('/dua'));
      await tester.pumpAndSettle();
      expect(find.byType(BackButton), findsOneWidget);
      expect(home, findsNothing);
      router.go('/prayer');
      await tester.pumpAndSettle();
      expect(home, findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android has a Back of its own: no button home', (tester) async {
    await pump(tester, '/dua');
    expect(home, findsNothing);
  });
}
