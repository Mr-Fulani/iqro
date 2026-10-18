import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/favorites/favorites_screen.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';
import 'package:iqro_mobile/features/quran/surah_name_art.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';

void main() {
  Future<String> pumpTitle(
    WidgetTester tester,
    Future<QuranCatalog> Function() catalog,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          quranCatalogProvider.overrideWith((ref) => catalog()),
          surahHeaderFontProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          locale: const Locale('ru'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: IqroTheme.light(),
          home: const Scaffold(body: AyahFavoriteTitle(surah: 2, ayah: 255)),
        ),
      ),
    );
    await tester.pump();
    return tester
        .widgetList<RichText>(
          find.descendant(
            of: find.byType(AyahFavoriteTitle),
            matching: find.byType(RichText),
          ),
        )
        .map((text) => text.text.toPlainText())
        .join(' | ');
  }

  testWidgets('the name, the numbers and the Mushaf\'s Arabic name', (
    tester,
  ) async {
    final text = await pumpTitle(
      tester,
      () async => const QuranCatalog(
        fromCache: false,
        surahs: <Surah>[
          Surah(
            id: 'surah-2',
            number: 2,
            nameAr: 'البقرة',
            nameEn: 'Al-Baqarah',
            nameRu: 'Аль-Бакара',
            ayahCount: 286,
            revelationType: 'medinan',
          ),
        ],
      ),
    );

    expect(text, 'Аль-Бакара | Сура 2 · Аят 255 | البقرة');
  });

  testWidgets('without the catalog the numbers still show', (tester) async {
    final text = await pumpTitle(
      tester,
      () async => throw StateError('offline'),
    );

    expect(text, 'Сура 2 · Аят 255');
  });
}
