import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/network/api_client.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/features/prayer/prayer_places.dart';
import 'package:iqro_mobile/features/prayer/prayer_repository.dart';
import 'package:iqro_mobile/features/prayer/prayer_screen.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';

void main() {
  final namangan = PrayerCity.found(
    geonameId: 1513157,
    name: 'Наманган',
    latitude: 40.9983,
    longitude: 71.67257,
    timezone: 'Asia/Tashkent',
  );

  test('a found city keeps its name with the saved place', () {
    final location = PrayerLocation.ofCity(namangan);
    expect(location.cityId, 'geonames:1513157');
    expect(location.cityName, 'Наманган');
    expect(location.placeName('en'), 'Наманган');

    final restored = PrayerLocation.fromJson(location.toJson());
    expect(restored.placeName('ru'), 'Наманган');
    expect(restored.timezone, 'Asia/Tashkent');
    expect(restored.latitude, 40.9983);
  });

  test('a curated city is named in the language of the screen', () {
    final location = PrayerLocation.ofCity(prayerCityById('kazan')!);
    expect(location.cityName, isNull);
    expect(location.toJson().containsKey('city_name'), isFalse);
    expect(location.placeName('ru'), 'Казань');
    expect(location.placeName('en'), 'Kazan');
    expect(
      const PrayerLocation(
        latitude: 1,
        longitude: 2,
        timezone: 'UTC',
      ).placeName('ru'),
      isNull,
    );
  });

  test('the repository asks the server and reads its places', () async {
    final api = _Api(<String, Object?>{
      'results': <Object?>[
        <String, Object?>{
          'id': 1513157,
          'name': 'Наманган',
          'country_code': 'UZ',
          'latitude': '40.99830',
          'longitude': '71.67257',
          'timezone': 'Asia/Tashkent',
        },
      ],
    });
    final repository = PrayerRepository(api: api, database: _Database());

    final cities = await repository.searchCities('Наманг', 'ru');

    expect(api.path, '/prayer/cities');
    expect(api.query, <String, Object?>{'q': 'Наманг', 'locale': 'ru'});
    expect(api.public, isTrue);
    expect(cities.single.id, 'geonames:1513157');
    expect(cities.single.nameFor('ru'), 'Наманган');
    expect(cities.single.latitude, closeTo(40.9983, 1e-9));
    expect(cities.single.timezone, 'Asia/Tashkent');

    await expectLater(
      PrayerRepository(
        api: _Api('unexpected'),
        database: _Database(),
      ).searchCities('Наманг', 'ru'),
      throwsFormatException,
    );
  });

  group('the city sheet', () {
    Future<void> open(
      WidgetTester tester,
      Future<List<PrayerCity>> Function(String query)? search,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: PrayerCitySheet(locale: 'ru', search: search),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> type(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
    }

    testWidgets('finds a city on the server after a pause in typing', (
      tester,
    ) async {
      final queries = <String>[];
      await open(tester, (query) async {
        queries.add(query);
        return <PrayerCity>[namangan];
      });
      // The curated cities are offered before anything is typed.
      expect(find.text('Казань'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Н');
      await tester.pump(const Duration(milliseconds: 350));
      expect(queries, isEmpty);

      await tester.enterText(find.byType(TextField), 'Нам');
      await tester.pump(const Duration(milliseconds: 100));
      await type(tester, 'Наманг');

      expect(queries, <String>['Наманг']);
      expect(find.text('Наманган'), findsOneWidget);
      expect(find.text('Asia/Tashkent'), findsOneWidget);
      expect(find.text('Казань'), findsNothing);
    });

    testWidgets('does not repeat a curated city the server also knows', (
      tester,
    ) async {
      await open(
        tester,
        (query) async => <PrayerCity>[
          PrayerCity.found(
            geonameId: 745044,
            name: 'Стамбул',
            latitude: 41.01384,
            longitude: 28.94966,
            timezone: 'Europe/Istanbul',
          ),
        ],
      );
      await type(tester, 'стам');
      expect(find.text('Стамбул'), findsOneWidget);
    });

    testWidgets('keeps the curated cities when the search cannot be reached', (
      tester,
    ) async {
      await open(tester, (query) async => throw Exception('offline'));
      await type(tester, 'каз');
      expect(find.text('Казань'), findsOneWidget);

      await type(tester, 'Наманг');
      expect(find.text('Подходящий город не найден'), findsOneWidget);
    });

    testWidgets('works without a search as before', (tester) async {
      await open(tester, null);
      await type(tester, 'моск');
      expect(find.text('Москва'), findsOneWidget);
    });
  });
}

class _Api implements ApiClient {
  _Api(this.payload);

  final Object? payload;
  String? path;
  Map<String, Object?>? query;
  bool? public;

  @override
  Future<Object?> get(
    String path, {
    Map<String, Object?>? query,
    bool public = false,
    String? etag,
    Object? accountScope,
  }) async {
    this.path = path;
    this.query = query;
    this.public = public;
    return payload;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Database implements LocalDatabase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
