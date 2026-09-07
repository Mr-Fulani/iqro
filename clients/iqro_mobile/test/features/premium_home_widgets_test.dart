import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/design_system/iqro_animated_logo.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/audio/premium_reciter_portrait.dart';
import 'package:iqro_mobile/features/calendar/hijri_calendar_screen.dart';
import 'package:iqro_mobile/features/calendar/hijri_calendar_service.dart';
import 'package:iqro_mobile/features/home/home_hijri_card.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';

void main() {
  for (final locale in ['ru', 'en', 'ar', 'tr']) {
    for (final dark in [false, true]) {
      testWidgets(
        '$locale dark=$dark home calendar supports large text and tap',
        (tester) async {
          tester.view.physicalSize = const Size(360, 950);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var opened = false;
          final civil = const HijriCalendarService().civilDate(1448, 9, 23);
          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? IqroTheme.dark() : IqroTheme.light(),
              locale: Locale(locale),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(1.8)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: HomeHijriCard(
                      clock: civil,
                      adjustment: 0,
                      onTap: () => opened = true,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final context = tester.element(find.byType(HomeHijriCard));
          expect(
            find.text(
              hijriDateLabel(context, const HijriDate(1448, 9, 23, 30)),
            ),
            findsOneWidget,
          );
          expect(
            find.text(AppLocalizations.of(context).hijriCivilHint),
            findsOneWidget,
          );
          await tester.tap(find.byType(HomeHijriCard));
          expect(opened, isTrue);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('logo finishes once and remains idle on rebuild', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: IqroAnimatedLogo()));
    await tester.pump(const Duration(seconds: 2));
    expect(tester.hasRunningAnimations, isFalse);
    final scale = tester.widget<ScaleTransition>(
      find.descendant(
        of: find.byType(IqroAnimatedLogo),
        matching: find.byType(ScaleTransition),
      ),
    );
    expect(scale.scale.value, 1);
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets('logo respects reduced motion immediately', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const IqroAnimatedLogo(),
      ),
    );
    final scale = tester.widget<ScaleTransition>(
      find.descendant(
        of: find.byType(IqroAnimatedLogo),
        matching: find.byType(ScaleTransition),
      ),
    );
    expect(scale.scale.value, 1);
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pumpAndSettle();
  });
  testWidgets('portrait keeps admin URL and bounds decoded memory', (
    tester,
  ) async {
    const url =
        'https://staging.iqro.forum/media/reciters/admin-custom.webp?v=7';
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: PremiumReciterPortrait(url: url, size: 88, initials: 'AB'),
        ),
      ),
    );
    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.imageUrl, url);
    expect(image.memCacheWidth, greaterThan(0));
    expect(image.memCacheWidth, lessThanOrEqualTo(300));
    expect(find.byType(ColorFiltered), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('portrait has a stable offline fallback', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: PremiumReciterPortrait(url: null, size: 48, initials: 'AB'),
        ),
      ),
    );
    expect(find.text('AB'), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
  });
}
