import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

/// Plays the bundled intro once; a decoder failure never blocks app startup.
class StartupVideo extends StatefulWidget {
  const StartupVideo({required this.onFinished, super.key});

  final VoidCallback onFinished;

  @override
  State<StartupVideo> createState() => _StartupVideoState();
}

class _StartupVideoState extends State<StartupVideo>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  Timer? _watchdog;
  var _started = false;
  var _finished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
    } else if (!_started) {
      _started = true;
      unawaited(_play());
    }
  }

  Future<void> _play() async {
    final controller = VideoPlayerController.asset(
      'assets/brand/startup.mp4',
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controller = controller;
    controller.addListener(_onVideoChanged);
    // Covers initialization, buffering and playback. The supplied clip is 5s.
    _watchdog = Timer(const Duration(seconds: 12), _finish);
    try {
      await controller.initialize().timeout(const Duration(seconds: 4));
      if (!mounted || _finished) return;
      await controller.setVolume(0);
      await controller.setLooping(false);
      if (!mounted || _finished) return;
      setState(() {});
      await controller.play();
    } on Object {
      _finish();
    }
  }

  void _onVideoChanged() {
    final value = _controller?.value;
    if (value != null && (value.hasError || value.isCompleted)) _finish();
  }

  void _finish() {
    if (!mounted || _finished) return;
    _finished = true;
    _watchdog?.cancel();
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    // Completion can be reported synchronously while Flutter builds a frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onFinished();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _finished) {
      return;
    }
    unawaited(_applyLifecycle(controller, state));
  }

  Future<void> _applyLifecycle(
    VideoPlayerController controller,
    AppLifecycleState state,
  ) async {
    try {
      if (state == AppLifecycleState.resumed) {
        await controller.play();
      } else {
        await controller.pause();
      }
    } on Object {
      _finish();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _watchdog?.cancel();
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    final controller = _controller;
    if (controller != null) {
      controller.removeListener(_onVideoChanged);
      unawaited(controller.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _finished) {
      return const SizedBox.shrink();
    }
    return GestureDetector(
      key: const ValueKey('startup-video-skip'),
      behavior: HitTestBehavior.opaque,
      onTap: _finish,
      child: ExcludeSemantics(
        child: ColoredBox(
          color: const Color(0xFFE6D8BF),
          child: SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
