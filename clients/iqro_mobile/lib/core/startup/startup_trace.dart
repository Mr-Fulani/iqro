/// Cold-start timings for the log. Off unless the app is built with
/// `--dart-define=STARTUP_TRACE=true`; see the cold start section of README.md.
abstract final class StartupTrace {
  static const enabled = bool.fromEnvironment('STARTUP_TRACE');

  static final _clock = Stopwatch();

  /// Called first thing in `main`: later times count from here.
  static void begin() {
    if (enabled) _clock.start();
  }

  static void mark(String name) {
    if (!enabled) return;
    // ignore: avoid_print
    print('IQRO startup: $name at ${_clock.elapsedMilliseconds} ms');
  }

  static Future<T> step<T>(String name, Future<T> Function() run) async {
    if (!enabled) return run();
    final start = _clock.elapsedMilliseconds;
    try {
      return await run();
    } finally {
      final end = _clock.elapsedMilliseconds;
      // ignore: avoid_print
      print('IQRO startup: $name ${end - start} ms (at $end ms)');
    }
  }
}
