import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'lesson_video_player.dart';

/// The lesson video across the whole screen, turned sideways and without
/// the system bars. The lesson keeps the controller: playback, the place
/// and the screen staying on carry on as they were. Leaving gives the
/// orientation and the bars back.
class LessonVideoFullscreen extends StatefulWidget {
  const LessonVideoFullscreen({required this.controller, super.key});

  final VideoPlayerController controller;

  static Route<void> route(VideoPlayerController controller) =>
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) =>
            LessonVideoFullscreen(controller: controller),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      );

  @override
  State<LessonVideoFullscreen> createState() => _LessonVideoFullscreenState();
}

class _LessonVideoFullscreenState extends State<LessonVideoFullscreen> {
  @override
  void initState() {
    super.initState();
    unawaited(
      SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]),
    );
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
  }

  @override
  void dispose() {
    // No preference is the app's own: any orientation.
    unawaited(
      SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]),
    );
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    // The controls stay clear of a camera cutout.
    body: SafeArea(
      child: LessonVideoView(
        key: const ValueKey('lesson-video-fullscreen-view'),
        controller: widget.controller,
        fullscreen: true,
        onFullscreen: () => Navigator.of(context).maybePop(),
      ),
    ),
  );
}
