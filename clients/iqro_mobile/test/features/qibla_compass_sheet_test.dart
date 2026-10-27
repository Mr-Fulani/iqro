import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/prayer/prayer_places.dart';
import 'package:iqro_mobile/features/prayer/qibla_compass.dart';
import 'package:iqro_mobile/features/prayer/qibla_compass_sheet.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';

const _latitude = 55.7558;
const _longitude = 37.6173;
final _bearing = qiblaBearing(latitude: _latitude, longitude: _longitude);

const _aligned = 'Вы смотрите на Киблу';
const _calibrate = 'Компас нужно откалибровать';
const _liveHint =
    'Компас устройства включён: держите телефон горизонтально — стрелка '
    'показывает Киблу относительно его верха.';

void main() {
  late List<MethodCall> haptics;

  setUp(() {
    haptics = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('without a compass the sheet keeps the bearing from north', (
    tester,
  ) async {
    final compass = _FakeCompass();
    await _pumpSheet(tester, compass);
    expect(find.textContaining('Сначала совместите верх'), findsOneWidget);

    compass.controller.addError(PlatformException(code: 'unavailable'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Компас на этом устройстве недоступен.'),
      findsOneWidget,
    );
    expect(find.textContaining('Сначала совместите верх'), findsOneWidget);
    expect(find.text(_liveHint), findsNothing);
    expect(
      find.text('${_bearing.round()}° от географического севера'),
      findsOneWidget,
    );
    expect(compass.cancels, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a compass that sends nothing is reported, not left still', (
    tester,
  ) async {
    final compass = _FakeCompass();
    await _pumpSheet(tester, compass);
    expect(find.byKey(const ValueKey('qibla-no-compass')), findsNothing);

    await tester.pump(qiblaCompassSilenceTimeout);
    expect(find.byKey(const ValueKey('qibla-no-compass')), findsOneWidget);
    expect(find.text('Компас на этом устройстве недоступен.'), findsOneWidget);
    expect(compass.cancels, 0);

    // A late first sample still brings the dial to life.
    compass.controller.add(<String, Object?>{
      'true': _bearing + 40,
      'magnetic': 0.0,
      'accuracy': 5.0,
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('qibla-no-compass')), findsNothing);
    expect(find.text(_liveHint), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('low accuracy asks for calibration and never claims alignment', (
    tester,
  ) async {
    final compass = _FakeCompass();
    await _pumpSheet(tester, compass);

    compass.controller.add(<String, Object?>{
      'true': _bearing,
      'magnetic': _bearing,
      'accuracy': -1.0,
    });
    await tester.pumpAndSettle();

    expect(find.text(_calibrate), findsOneWidget);
    expect(find.textContaining('восьмёркой'), findsOneWidget);
    expect(find.text(_aligned), findsNothing);
    expect(haptics, isEmpty);

    compass.controller.add(<String, Object?>{
      'true': _bearing,
      'magnetic': _bearing,
      'accuracy': 5.0,
    });
    await tester.pumpAndSettle();
    expect(find.text(_calibrate), findsNothing);
    expect(find.text(_aligned), findsOneWidget);
    expect(find.text(_liveHint), findsOneWidget);
  });

  testWidgets('facing the Qibla highlights once with hysteresis', (
    tester,
  ) async {
    final compass = _FakeCompass();
    await _pumpSheet(tester, compass);

    void face(double heading) => compass.controller.add(<String, Object?>{
      'true': normalizeDegrees(heading),
      'magnetic': 0.0,
      'accuracy': 5.0,
    });

    face(_bearing + 30);
    await tester.pumpAndSettle();
    expect(find.text(_aligned), findsNothing);
    expect(find.text(_liveHint), findsOneWidget);

    face(_bearing + 2);
    await tester.pumpAndSettle();
    expect(find.text(_aligned), findsOneWidget);
    expect(haptics, hasLength(1));

    // Inside the release band the state holds and does not vibrate again.
    face(_bearing - 4);
    await tester.pumpAndSettle();
    expect(find.text(_aligned), findsOneWidget);
    expect(haptics, hasLength(1));

    face(_bearing - 20);
    await tester.pumpAndSettle();
    expect(find.text(_aligned), findsNothing);

    face(_bearing);
    await tester.pumpAndSettle();
    expect(find.text(_aligned), findsOneWidget);
    expect(haptics, hasLength(2));
  });

  testWidgets('sensors stop in the background and when the sheet closes', (
    tester,
  ) async {
    final compass = _FakeCompass();
    await _pumpSheet(tester, compass);
    expect(compass.listens, 1);

    for (final state in const <AppLifecycleState>[
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    expect(compass.cancels, 1);
    expect(compass.controller.hasListener, isFalse);

    for (final state in const <AppLifecycleState>[
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    expect(compass.listens, 2);

    await tester.pumpWidget(const SizedBox());
    expect(compass.cancels, 2);
    expect(compass.controller.hasListener, isFalse);
  });

  testWidgets('Arabic sheet lays out right to left', (tester) async {
    final compass = _FakeCompass();
    await _pumpSheet(tester, compass, locale: const Locale('ar'));
    compass.controller.add(<String, Object?>{
      'true': _bearing,
      'magnetic': 0.0,
      'accuracy': 5.0,
    });
    await tester.pumpAndSettle();

    expect(find.text('أنت متجه إلى القبلة'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('أنت متجه إلى القبلة'))),
      TextDirection.rtl,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpSheet(
  WidgetTester tester,
  _FakeCompass compass, {
  Locale locale = const Locale('ru'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: IqroTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: QiblaCompassSheet(
          latitude: _latitude,
          longitude: _longitude,
          locationName: 'Москва',
          compass: compass,
        ),
      ),
    ),
  );
  await tester.pump();
}

class _FakeCompass extends QiblaCompass {
  _FakeCompass();

  var listens = 0;
  var cancels = 0;
  late final controller = StreamController<Object?>.broadcast(
    onListen: () => listens++,
    onCancel: () => cancels++,
  );

  @override
  Stream<Object?> events() => controller.stream;
}
