import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_widget/home_widget.dart';
import 'package:iqro_mobile/core/widgets/home_widget_pinning.dart';

void main() {
  for (final receiver in [
    'ReadingPlanHomeWidgetReceiver',
    'PrayerTimesHomeWidgetReceiver',
  ]) {
    test(
      '$receiver prevents duplicates and permits readding after removal',
      () async {
        var installed = true;
        var requests = 0;
        final pinning = HomeWidgetPinning(
          isAndroid: () => true,
          installedWidgets: () async => installed
              ? [
                  HomeWidgetInfo(
                    androidClassName: 'forum.iqro.app.$receiver',
                    androidWidgetId: 7,
                  ),
                ]
              : [],
          supportsPinning: () async => true,
          pin: (_) async {
            requests++;
          },
        );
        expect(
          await pinning.request(receiver),
          HomeWidgetPinResult.alreadyInstalled,
        );
        expect(
          await pinning.request(receiver),
          HomeWidgetPinResult.alreadyInstalled,
        );
        expect(requests, 0);
        installed = false;
        expect(await pinning.request(receiver), HomeWidgetPinResult.requested);
        expect(requests, 1);
      },
    );
  }
  test('another widget type does not prevent adding Plan', () async {
    var requests = 0;
    final pinning = HomeWidgetPinning(
      isAndroid: () => true,
      installedWidgets: () async => [
        HomeWidgetInfo(
          androidClassName: 'forum.iqro.app.PrayerTimesHomeWidgetReceiver',
        ),
      ],
      supportsPinning: () async => true,
      pin: (_) async {
        requests++;
      },
    );
    expect(
      await pinning.request('ReadingPlanHomeWidgetReceiver'),
      HomeWidgetPinResult.requested,
    );
    expect(requests, 1);
  });
  test('concurrent taps issue one launcher request', () async {
    final installed = Completer<List<HomeWidgetInfo>>();
    var requests = 0;
    final pinning = HomeWidgetPinning(
      isAndroid: () => true,
      installedWidgets: () => installed.future,
      supportsPinning: () async => true,
      pin: (_) async {
        requests++;
      },
    );
    final first = pinning.request('ReadingPlanHomeWidgetReceiver');
    final second = pinning.request('ReadingPlanHomeWidgetReceiver');
    installed.complete([]);
    expect(await first, HomeWidgetPinResult.requested);
    expect(await second, HomeWidgetPinResult.requested);
    expect(requests, 1);
  });
  test('unsupported launcher does not request a widget', () async {
    final pinning = HomeWidgetPinning(
      isAndroid: () => true,
      installedWidgets: () async => [],
      supportsPinning: () async => false,
      pin: (_) async => fail('Unexpected pin request'),
    );
    expect(
      await pinning.request('ReadingPlanHomeWidgetReceiver'),
      HomeWidgetPinResult.unsupported,
    );
  });
  test('failed launcher request can be retried', () async {
    var requests = 0;
    final pinning = HomeWidgetPinning(
      isAndroid: () => true,
      installedWidgets: () async => [],
      supportsPinning: () async => true,
      pin: (_) async {
        if (++requests == 1) throw StateError('launcher unavailable');
      },
    );
    await expectLater(
      pinning.request('ReadingPlanHomeWidgetReceiver'),
      throwsStateError,
    );
    expect(
      await pinning.request('ReadingPlanHomeWidgetReceiver'),
      HomeWidgetPinResult.requested,
    );
  });
}
