import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/widgets/home_widget_routes.dart';

void main() {
  test('widget taps open their corresponding sections', () {
    expect(
      homeWidgetRoute(Uri.parse('iqro://open/prayer?homeWidget')),
      '/prayer',
    );
    expect(
      homeWidgetRoute(Uri.parse('iqro://open/plan?homeWidget')),
      '/app?tab=2',
    );
    expect(
      homeWidgetRoute(Uri.parse('iqro://open/after-prayer?homeWidget')),
      '/after-prayer',
    );
  });
  test(
    'cold launch and taps during initialization are delivered in order',
    () async {
      final clicks = StreamController<Uri?>();
      final initial = Completer<Uri?>();
      final events = homeWidgetRoutes(
        widgetClicks: clicks.stream,
        initialUri: () => initial.future,
      );
      final received = <String>[];
      final subscription = events.listen(received.add);
      await Future<void>.delayed(Duration.zero);
      clicks.add(Uri.parse('iqro://open/after-prayer?homeWidget'));
      initial.complete(Uri.parse('iqro://open/plan?homeWidget'));
      await Future<void>.delayed(Duration.zero);
      expect(received, ['/app?tab=2', '/after-prayer']);
      await clicks.close();
      await subscription.cancel();
    },
  );
  test(
    'cold-launch-only listener can cancel without waiting for a warm tap',
    () async {
      final clicks = StreamController<Uri?>();
      final first = await homeWidgetRoutes(
        widgetClicks: clicks.stream,
        initialUri: () async => Uri.parse('iqro://open/prayer?homeWidget'),
      ).first;
      expect(first, '/prayer');
      expect(clicks.hasListener, false);
      await clicks.close();
    },
  );
  test('unknown destinations and ordinary links are not widget routes', () {
    for (final value in [
      'https://open/plan?homeWidget',
      'iqro://other/plan?homeWidget',
      'iqro://open/plan',
      'iqro://open/settings?homeWidget',
    ]) {
      expect(homeWidgetRoute(Uri.parse(value)), isNull);
    }
  });
}
