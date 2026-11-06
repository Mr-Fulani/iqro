import 'package:flutter/widgets.dart';

/// How long the app must stay in the background before Home plays its
/// opening animations again: opening the app counts, a glance at the
/// notification shade does not.
const homeReplayAfter = Duration(minutes: 1);

/// Plays [openController] once when the card's data is ready, and again when
/// the app returns after [homeReplayAfter]. Switching tabs keeps Home alive,
/// so it does not replay. With system animations off the final frame shows at
/// once.
mixin HomeOpenReplay<T extends StatefulWidget>
    on State<T>, WidgetsBindingObserver {
  AnimationController get openController;

  /// Whether the card has what it animates towards (a schedule, a plan).
  bool get openReady;

  bool _played = false;
  DateTime? _backgroundSince;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => playWhenReady());
  }

  /// Call from [didUpdateWidget]: the data often arrives after the first frame.
  void playWhenReady() {
    if (_played || !openReady || !mounted) return;
    _played = true;
    _play();
  }

  void _play() {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      openController.value = 1;
    } else {
      openController.forward(from: 0);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgroundSince ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final since = _backgroundSince;
      _backgroundSince = null;
      if (since != null &&
          DateTime.now().difference(since) >= homeReplayAfter &&
          _played &&
          mounted) {
        _play();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
