import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/network/public_asset_uri.dart';
import '../../core/theme/iqro_theme.dart';
import 'course_feedback.dart' show courseVideoWatchedShare;
import 'course_models.dart';
import 'course_progress_store.dart';
import 'course_widgets.dart';
import 'lesson_video_fullscreen.dart';

/// Plays a lesson video from the network as it arrives; the whole file is
/// never downloaded first. Tests put a fake in.
final lessonVideoControllerProvider =
    Provider<VideoPlayerController Function(Uri uri)>(
      (ref) =>
          (uri) => VideoPlayerController.networkUrl(
            uri,
            videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
          ),
    );

/// Keeps the screen on while a lesson video plays.
final lessonVideoWakeProvider = Provider<Future<void> Function(bool on)>(
  (ref) =>
      (on) => WakelockPlus.toggle(enable: on),
);

const _approvedVideoHosts = <String>{'media.iqro.forum'};
const _savePeriod = Duration(seconds: 5);
const _skip = Duration(seconds: 10);
const _videoGreen = Color(0xFF073E34);
const _badge = Color(0xCC061D18);

/// The video of a lesson. Until it is tapped only the poster shows, so no
/// traffic is spent; then the player with its own controls. Where it stopped
/// is kept every 5 seconds and on pause; the end forgets the place.
class LessonVideo extends ConsumerStatefulWidget {
  const LessonVideo({
    required this.course,
    required this.lesson,
    required this.lessonTitle,
    required this.video,
    required this.language,
    this.onStarted,
    this.onWatched,
    this.onPosition,
    super.key,
  });

  /// Where the position is kept: a thematic course, or the tajweed course.
  final String course;

  /// The lesson's slug.
  final String lesson;
  final String lessonTitle;
  final CourseVideo video;

  /// The language of the document.
  final String language;

  /// The video first played while the lesson is shown.
  final VoidCallback? onStarted;

  /// The video reached [courseVideoWatchedShare] of its length, once.
  final VoidCallback? onWatched;

  /// Where the video is now.
  final ValueChanged<Duration>? onPosition;

  @override
  ConsumerState<LessonVideo> createState() => _LessonVideoState();
}

class _LessonVideoState extends ConsumerState<LessonVideo>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  var _failed = false;
  var _playing = false;
  var _fullscreen = false;
  var _started = false;
  var _watched = false;
  Timer? _saveTimer;

  /// Where a failed attempt stopped, for «Retry».
  Duration? _retryAt;

  // Kept for dispose, when ref can no longer be used.
  late final ProviderContainer _container;
  late final CourseProgressStore _store;
  late final Future<void> Function(bool on) _wake;

  @override
  void initState() {
    super.initState();
    _container = ProviderScope.containerOf(context, listen: false);
    _store = ref.read(courseProgressStoreProvider);
    _wake = ref.read(lessonVideoWakeProvider);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Another screen covered the lesson or another tab was opened; the
    // full screen of this video is not leaving it.
    if (!TickerMode.valuesOf(context).enabled && !_fullscreen) _pause();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final controller = _controller;
    if (controller != null) {
      _save(controller.value);
      _release(controller);
    }
    super.dispose();
  }

  void _pause() {
    final controller = _controller;
    if (controller != null && controller.value.isPlaying) {
      unawaited(controller.pause());
    }
  }

  Future<void> _start() async {
    if (_controller != null) return;
    final base = Uri.parse(ref.read(appConfigProvider).apiBaseUrl);
    final uri = base.resolve(widget.video.url);
    if (!isApprovedPublicAssetUri(
      uri,
      allowedHosts: _approvedVideoHosts,
      localApiBase: base,
    )) {
      setState(() => _failed = true);
      return;
    }
    final resume =
        _retryAt ??
        ref
            .read(coursePositionsProvider(widget.course))
            .valueOrNull
            ?.of(widget.lesson);
    final controller = ref.read(lessonVideoControllerProvider)(uri);
    controller.addListener(_onValue);
    setState(() {
      _controller = controller;
      _failed = false;
    });
    try {
      await controller.initialize();
      if (resume != null && resume < controller.value.duration) {
        await controller.seekTo(resume);
      }
      if (!mounted || _controller != controller) return;
      await controller.play();
    } on Object {
      if (mounted && _controller == controller) _fail();
    }
  }

  void _onValue() {
    final controller = _controller;
    if (controller == null) return;
    final value = controller.value;
    if (value.hasError) {
      _fail();
      return;
    }
    _report(value);
    if (value.isPlaying == _playing) return;
    _playing = value.isPlaying;
    _keepScreenOn(_playing);
    _saveTimer?.cancel();
    if (_playing) {
      unawaited(
        ref.read(audioControllerProvider.notifier).pauseForLessonVideo(),
      );
      _saveTimer = Timer.periodic(_savePeriod, (_) => _save(controller.value));
    } else {
      _save(value);
    }
  }

  void _report(VideoPlayerValue value) {
    if (value.isPlaying && !_started) {
      _started = true;
      widget.onStarted?.call();
    }
    if (!value.isInitialized || value.duration <= Duration.zero) return;
    widget.onPosition?.call(value.position);
    final watched =
        value.position.inMilliseconds >=
        value.duration.inMilliseconds * courseVideoWatchedShare;
    if (watched && !_watched) {
      _watched = true;
      widget.onWatched?.call();
    }
  }

  void _fail() {
    final controller = _controller;
    if (controller == null) return;
    final value = controller.value;
    if (value.isInitialized && value.position > Duration.zero) {
      _retryAt = value.position;
    }
    _release(controller);
    setState(() {
      _controller = null;
      _failed = true;
    });
  }

  void _release(VideoPlayerController controller) {
    controller.removeListener(_onValue);
    _saveTimer?.cancel();
    if (_playing) _keepScreenOn(false);
    _playing = false;
    // A failure is noticed while the controller notifies its listeners.
    unawaited(Future<void>.microtask(controller.dispose));
  }

  void _keepScreenOn(bool on) {
    // The screen going dark is an inconvenience, not a reason to stop.
    unawaited(_wake(on).catchError((Object _) {}));
  }

  /// Watched to the end: the next time starts from the beginning.
  void _save(VideoPlayerValue value) {
    if (!value.isInitialized) return;
    final ended = value.isCompleted || value.position >= value.duration;
    final course = widget.course;
    unawaited(
      _store
          .savePosition(
            course: course,
            lesson: widget.lesson,
            position: ended ? Duration.zero : value.position,
          )
          .then(
            (_) => _container.invalidate(coursePositionsProvider(course)),
            // The place is a convenience; the video plays without it.
            onError: (Object _) {},
          ),
    );
  }

  Future<void> _openFullscreen() async {
    final controller = _controller;
    if (controller == null) return;
    _fullscreen = true;
    await Navigator.of(
      context,
      rootNavigator: true,
    ).push(LessonVideoFullscreen.route(controller));
    _fullscreen = false;
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final spoken = widget.video.spokenLanguage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: controller != null
                ? LessonVideoView(
                    key: const ValueKey('lesson-video-player'),
                    controller: controller,
                    onFullscreen: _openFullscreen,
                  )
                : _failed
                ? _VideoFailed(onRetry: _start)
                : _VideoFacade(
                    course: widget.course,
                    lesson: widget.lesson,
                    lessonTitle: widget.lessonTitle,
                    video: widget.video,
                    onPlay: _start,
                  ),
          ),
        ),
        if (spoken.isNotEmpty && spoken != widget.language) ...<Widget>[
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _LanguageChip(language: spoken),
          ),
        ],
      ],
    );
  }
}

/// The poster with ▶, «9:48 · 108 MB» and «Continue from 4:12».
class _VideoFacade extends ConsumerWidget {
  const _VideoFacade({
    required this.course,
    required this.lesson,
    required this.lessonTitle,
    required this.video,
    required this.onPlay,
  });

  final String course;
  final String lesson;
  final String lessonTitle;
  final CourseVideo video;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final resume = ref
        .watch(coursePositionsProvider(course))
        .valueOrNull
        ?.of(lesson);
    final meta = courseVideoMeta(context, video);
    final resumeLabel = resume == null
        ? null
        : l10n.coursesVideoResumeFrom(courseVideoTime(resume));
    final watch = l10n.coursesVideoWatch(lessonTitle, meta);
    final poster = video.poster;
    return Semantics(
      button: true,
      label: resumeLabel == null ? watch : '$watch. $resumeLabel',
      excludeSemantics: true,
      onTap: onPlay,
      child: Stack(
        key: const ValueKey('lesson-video-facade'),
        fit: StackFit.expand,
        children: <Widget>[
          const ColoredBox(color: _videoGreen),
          CourseCoverImage(
            cover: CourseCover(
              url: poster.url,
              thumbUrl: poster.smallUrl,
              width: poster.width,
              height: poster.height,
            ),
            small: true,
          ),
          Center(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: Color(0xFF0B5D4A),
                shape: BoxShape.circle,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Color(0x52000000),
                    blurRadius: 18,
                    offset: Offset(0, 7),
                  ),
                ],
              ),
              child: const SizedBox.square(
                dimension: 64,
                child: Icon(
                  Icons.play_arrow_rounded,
                  size: 40,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          if (resumeLabel != null)
            PositionedDirectional(
              top: 12,
              start: 12,
              child: _Badge(
                key: const ValueKey('lesson-video-resume'),
                text: resumeLabel,
              ),
            ),
          PositionedDirectional(
            end: 12,
            bottom: 12,
            child: _Badge(key: const ValueKey('lesson-video-meta'), text: meta),
          ),
          Material(
            type: MaterialType.transparency,
            child: InkWell(onTap: onPlay),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: _badge,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

/// The notes stay below; only the video area says it failed.
class _VideoFailed extends StatelessWidget {
  const _VideoFailed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ColoredBox(
      key: const ValueKey('lesson-video-failed'),
      color: _videoGreen,
      child: Center(
        child: Semantics(
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.videocam_off_outlined,
                size: 36,
                color: Colors.white70,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.coursesVideoFailed,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const ValueKey('lesson-video-retry'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.retry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// «Video in Russian», named in the language of the interface.
class _LanguageChip extends StatelessWidget {
  const _LanguageChip({required this.language});

  final String language;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      key: const ValueKey('lesson-video-language'),
      decoration: BoxDecoration(
        color: context.iqroColors.panelSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.language,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                context.l10n.coursesVideoLanguage(language),
                style: theme.textTheme.labelMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A started video with its controls, left to right in every language. They
/// hide while it plays and come back on a tap.
class LessonVideoView extends StatefulWidget {
  const LessonVideoView({
    required this.controller,
    required this.onFullscreen,
    this.fullscreen = false,
    super.key,
  });

  final VideoPlayerController controller;

  /// Opens the full screen, or leaves it when [fullscreen].
  final VoidCallback onFullscreen;
  final bool fullscreen;

  @override
  State<LessonVideoView> createState() => _LessonVideoViewState();
}

class _LessonVideoViewState extends State<LessonVideoView> {
  var _controlsShown = true;
  Timer? _hide;

  /// Milliseconds while the slider is dragged.
  double? _drag;

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && widget.controller.value.isPlaying && _drag == null) {
        setState(() => _controlsShown = false);
      }
    });
  }

  /// Any use of the controls keeps them on screen a while longer.
  void _act(Future<void> Function() action) {
    unawaited(action());
    setState(() => _controlsShown = true);
    _scheduleHide();
  }

  Future<void> _seekBy(Duration offset) {
    final value = widget.controller.value;
    var target = value.position + offset;
    if (target < Duration.zero) target = Duration.zero;
    if (target > value.duration) target = value.duration;
    return widget.controller.seekTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = widget.controller;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final shown = _controlsShown || !value.isPlaying;
          final total = value.duration.inMilliseconds;
          final position = (_drag ?? value.position.inMilliseconds.toDouble())
              .clamp(0, total <= 0 ? 0 : total)
              .toDouble();
          final time =
              '${courseVideoTime(Duration(milliseconds: position.round()))}'
              ' / ${courseVideoTime(value.duration)}';
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              ColoredBox(
                color: Colors.black,
                child: Center(
                  child: value.isInitialized
                      ? AspectRatio(
                          aspectRatio: value.aspectRatio,
                          child: VideoPlayer(controller),
                        )
                      : null,
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onTap: () {
                  setState(() => _controlsShown = !shown);
                  if (!shown) _scheduleHide();
                },
              ),
              if (!value.isInitialized || (value.isBuffering && !shown))
                const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              if (value.isInitialized && shown)
                DecoratedBox(
                  key: const ValueKey('lesson-video-controls'),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        Color(0x47000000),
                        Color(0x1F000000),
                        Color(0x99000000),
                      ],
                      stops: <double>[0, .45, 1],
                    ),
                  ),
                  child: Column(
                    children: <Widget>[
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            _ControlButton(
                              key: const ValueKey('lesson-video-back'),
                              icon: Icons.replay_10_rounded,
                              label: l10n.coursesVideoBack10,
                              onPressed: () => _act(() => _seekBy(-_skip)),
                            ),
                            const SizedBox(width: 24),
                            _ControlButton(
                              key: const ValueKey('lesson-video-toggle'),
                              size: 56,
                              icon: value.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              label: value.isPlaying ? l10n.pause : l10n.play,
                              onPressed: () => _act(
                                value.isPlaying
                                    ? controller.pause
                                    : controller.play,
                              ),
                            ),
                            const SizedBox(width: 24),
                            _ControlButton(
                              key: const ValueKey('lesson-video-forward'),
                              icon: Icons.forward_10_rounded,
                              label: l10n.coursesVideoForward10,
                              onPressed: () => _act(() => _seekBy(_skip)),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 4, 2),
                        child: Row(
                          children: <Widget>[
                            ExcludeSemantics(
                              child: Text(
                                time,
                                key: const ValueKey('lesson-video-time'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  fontFeatures: <FontFeature>[
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                            Expanded(
                              child: MergeSemantics(
                                child: Semantics(
                                  label: l10n.coursesVideoPosition,
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      activeTrackColor: Colors.white,
                                      inactiveTrackColor: Colors.white38,
                                      thumbColor: Colors.white,
                                      overlayColor: Colors.white24,
                                    ),
                                    child: Slider(
                                      key: const ValueKey('lesson-video-seek'),
                                      max: total <= 0 ? 1 : total.toDouble(),
                                      value: position,
                                      semanticFormatterCallback: (_) => time,
                                      onChangeStart: (milliseconds) {
                                        _hide?.cancel();
                                        setState(() => _drag = milliseconds);
                                      },
                                      onChanged: (milliseconds) =>
                                          setState(() => _drag = milliseconds),
                                      onChangeEnd: (milliseconds) {
                                        setState(() => _drag = null);
                                        _act(
                                          () => controller.seekTo(
                                            Duration(
                                              milliseconds: milliseconds
                                                  .round(),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            _ControlButton(
                              key: const ValueKey('lesson-video-fullscreen'),
                              icon: widget.fullscreen
                                  ? Icons.fullscreen_exit_rounded
                                  : Icons.fullscreen_rounded,
                              label: widget.fullscreen
                                  ? l10n.coursesVideoExitFullscreen
                                  : l10n.coursesVideoFullscreen,
                              background: Colors.transparent,
                              onPressed: widget.onFullscreen,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.size = 48,
    this.background = const Color(0x59000000),
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final double size;
  final Color background;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    tooltip: label,
    iconSize: size * .55,
    style: IconButton.styleFrom(
      backgroundColor: background,
      foregroundColor: Colors.white,
      fixedSize: Size.square(size),
      minimumSize: Size.square(size),
    ),
    icon: Icon(icon),
  );
}
