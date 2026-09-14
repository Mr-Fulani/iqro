import 'dart:async';
import 'package:home_widget/home_widget.dart';

/// Only known home-widget destinations may navigate the app.
String? homeWidgetRoute(Uri uri) {
  if (uri.scheme != 'iqro' ||
      uri.host != 'open' ||
      !uri.queryParameters.containsKey('homeWidget')) {
    return null;
  }
  return switch (uri.path) {
    '/prayer' => '/prayer',
    '/plan' => '/app?tab=2',
    '/after-prayer' => '/after-prayer',
    _ => null,
  };
}

/// Subscribe before resolving the cold-start URI, so warm taps are not lost.
Stream<String> homeWidgetRoutes({
  Stream<Uri?>? widgetClicks,
  Future<Uri?> Function()? initialUri,
}) async* {
  final clicks = StreamController<Uri?>();
  final subscription = (widgetClicks ?? HomeWidget.widgetClicked).listen(
    clicks.add,
    onError: clicks.addError,
    onDone: clicks.close,
  );
  try {
    final initial =
        await (initialUri ?? HomeWidget.initiallyLaunchedFromHomeWidget)();
    final route = initial == null ? null : homeWidgetRoute(initial);
    if (route != null) yield route;
    await for (final uri in clicks.stream) {
      final next = uri == null ? null : homeWidgetRoute(uri);
      if (next != null) yield next;
    }
  } finally {
    await subscription.cancel();
    // A cold-start-only subscriber may cancel before listening to this buffer.
    unawaited(clicks.close());
  }
}
