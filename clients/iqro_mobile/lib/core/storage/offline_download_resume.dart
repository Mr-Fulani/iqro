import 'dart:async';

import 'package:flutter/widgets.dart';

/// Packages whose download runs in this app process now. A package that the
/// database still marks as downloading but that is not here was cut off when
/// the app was closed, so it can be tried again or deleted.
final Set<String> liveOfflineDownloads = <String>{};

/// iOS suspends the app soon after it leaves the screen or the screen locks,
/// and a file download in flight then fails. A file that fails while the app
/// is away, or after it has been away, is tried again once the app is back on
/// the screen; the download resumes from the bytes it has, so the package
/// goes on from that file instead of failing. A failure with the app on the
/// screen all along is not retried, so the next try always starts there.
Future<T> retryOfflineFileAfterBackground<T>(
  Future<T> Function() download,
) async {
  final presence = _AppPresence.instance;
  if (presence == null) return download();
  while (true) {
    final awayCount = presence.awayCount;
    final startedOnScreen = presence.onScreen;
    try {
      return await download();
    } on Object {
      if (startedOnScreen &&
          presence.awayCount == awayCount &&
          presence.onScreen) {
        rethrow;
      }
      await presence.back();
    }
  }
}

class _AppPresence with WidgetsBindingObserver {
  _AppPresence(WidgetsBinding binding) : _state = binding.lifecycleState {
    binding.addObserver(this);
  }

  /// Null without a Flutter binding (plain unit tests): nothing to wait for.
  static final _AppPresence? instance = () {
    try {
      return _AppPresence(WidgetsBinding.instance);
    } on Object {
      return null;
    }
  }();

  AppLifecycleState? _state;
  Completer<void>? _back;

  /// How many times the app has left the screen.
  var awayCount = 0;

  bool get onScreen =>
      _state == null ||
      _state == AppLifecycleState.resumed ||
      _state == AppLifecycleState.inactive;

  Future<void> back() {
    if (_state == AppLifecycleState.resumed || _state == null) {
      return Future<void>.value();
    }
    return (_back ??= Completer<void>()).future;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasOnScreen = onScreen;
    _state = state;
    if (wasOnScreen && !onScreen) awayCount += 1;
    if (state == AppLifecycleState.resumed) {
      _back?.complete();
      _back = null;
    }
  }
}
