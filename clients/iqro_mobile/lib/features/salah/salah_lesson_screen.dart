import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/analytics/analytics.dart';
import '../../core/audio/audio_controller.dart';
import '../../core/design_system/iqro_repetition_counter.dart';
import '../../core/design_system/iqro_step_flow.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import '../courses/course_sources.dart';
import '../courses/lesson_media_view.dart';
import '../courses/lesson_video_player.dart';
import 'salah_3d.dart';
import 'salah_display.dart';
import 'salah_formula_card.dart';
import 'salah_models.dart';
import 'salah_progress.dart';
import 'salah_repository.dart';
import 'salah_step_notes.dart';

/// One lesson, step by step. Opens on [stepSlug] when it is given and still
/// exists, otherwise on the saved step.
class SalahLessonScreen extends ConsumerStatefulWidget {
  const SalahLessonScreen({
    required this.lessonSlug,
    this.stepSlug,
    this.courseSlug = salahDefaultCourseSlug,
    super.key,
  });

  final String courseSlug;
  final String lessonSlug;
  final String? stepSlug;

  @override
  ConsumerState<SalahLessonScreen> createState() => _SalahLessonScreenState();
}

class _SalahLessonScreenState extends ConsumerState<SalahLessonScreen> {
  late Future<SalahCourseProgress> _progress;

  @override
  void initState() {
    super.initState();
    _progress = _readProgress();
  }

  Future<SalahCourseProgress> _readProgress() async {
    try {
      return await ref.read(salahProgressStoreProvider).read(widget.courseSlug);
    } on Object {
      // Unreadable progress opens the lesson from its first step.
      return const SalahCourseProgress();
    }
  }

  @override
  Widget build(BuildContext context) {
    final course = ref.watch(salahCourseProvider(widget.courseSlug));
    final document = course.valueOrNull;
    if (document == null) {
      return Scaffold(
        appBar: IqroTopBar(title: context.l10n.salahTitle),
        body: course.hasError
            ? IqroAsyncError(
                title: context.l10n.salahUnavailable,
                onRetry: () =>
                    ref.invalidate(salahCourseProvider(widget.courseSlug)),
              )
            : const IqroLoading(),
      );
    }
    final lesson = document.lesson(widget.lessonSlug);
    if (lesson == null || lesson.steps.isEmpty) {
      return Scaffold(
        appBar: IqroTopBar(title: context.l10n.salahTitle),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              context.l10n.salahLessonNotFound,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return FutureBuilder<SalahCourseProgress>(
      future: _progress,
      builder: (context, snapshot) {
        final progress = snapshot.data;
        if (progress == null) {
          return Scaffold(
            appBar: IqroTopBar(title: lesson.title),
            body: const IqroLoading(),
          );
        }
        final requested = widget.stepSlug == null
            ? -1
            : lesson.indexOfStep(widget.stepSlug!);
        return SalahStepPlayer(
          // A new content version or a link to another step restarts the
          // player on the right step.
          key: ValueKey(
            '${document.course.version}:${lesson.slug}:${widget.stepSlug}',
          ),
          courseSlug: widget.courseSlug,
          document: document,
          lesson: lesson,
          initialIndex: requested >= 0
              ? requested
              : progress.resumeStepIndex(lesson),
        );
      },
    );
  }
}

/// The steps of a lesson in a pager, with «Back» and «Next» always visible.
class SalahStepPlayer extends ConsumerStatefulWidget {
  const SalahStepPlayer({
    required this.courseSlug,
    required this.document,
    required this.lesson,
    required this.initialIndex,
    super.key,
  });

  final String courseSlug;
  final SalahCourseDocument document;
  final SalahLesson lesson;
  final int initialIndex;

  @override
  ConsumerState<SalahStepPlayer> createState() => _SalahStepPlayerState();
}

class _SalahStepPlayerState extends ConsumerState<SalahStepPlayer>
    with WidgetsBindingObserver {
  late final IqroStepController _pager;
  var _finishing = false;
  final _three = Salah3DController();
  late final List<SalahMediaScene?> _scenes = salahStepScenes(
    widget.document,
    _steps,
  );

  // The lesson owns the recordings of its steps in the shared player: leaving
  // a step stops whichever of them sounds, and it starts over on return.
  final _audioOwner = Object();
  // Kept for dispose, when ref can no longer be read.
  late AudioController _audio;

  List<SalahStep> get _steps => widget.lesson.steps;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _audio = ref.read(audioControllerProvider.notifier);
    final initial = widget.initialIndex.clamp(0, _steps.length - 1);
    _pager = IqroStepController(initialIndex: initial);
    unawaited(_record(initial));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _precache(initial);
      _precache(initial + 1);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Another screen over the lesson leaves the step too.
    if (!TickerMode.valuesOf(context).enabled) _stopAudio();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _stopAudio();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopAudio();
    _pager.dispose();
    _three.dispose();
    super.dispose();
  }

  void _stopAudio() {
    // In dispose the element is already unmounted and ref is gone.
    if (context.mounted) _audio = ref.read(audioControllerProvider.notifier);
    unawaited(_audio.stopStandaloneOf(_audioOwner));
  }

  void _onPageChanged(int index) {
    _stopAudio();
    _three.stepChanged();
    unawaited(_record(index));
    _precache(index + 1);
  }

  /// Loads the next step's image ahead, so turning the page shows it at once.
  void _precache(int index) {
    if (index < 0 || index >= _steps.length) return;
    final media = widget.document.stepMedia(_steps[index]);
    if (media == null) return;
    unawaited(
      precacheImage(
        ref.read(salahCourseImageProvider(widget.courseSlug))(media),
        context,
        onError: (error, stack) {},
      ),
    );
  }

  Future<void> _record(int index) async {
    try {
      await ref
          .read(salahProgressStoreProvider)
          .recordStep(
            course: widget.courseSlug,
            lesson: widget.lesson.slug,
            stepSlug: _steps[index].slug,
            contentVersion: widget.document.course.version,
          );
      if (mounted) ref.invalidate(salahProgressProvider(widget.courseSlug));
    } on Object {
      // Progress is a convenience: a failed write must not stop the lesson.
    }
  }

  void _goTo(int index) => _pager.goTo(context, index, _steps.length);

  void _next() {
    final index = _pager.index.value;
    if (index >= _steps.length - 1) {
      unawaited(_finish());
    } else {
      _goTo(index + 1);
    }
  }

  void _previous() => _goTo(_pager.index.value - 1);

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    final message = context.l10n.salahLessonCompleted;
    try {
      await ref
          .read(salahProgressStoreProvider)
          .complete(
            course: widget.courseSlug,
            lesson: widget.lesson.slug,
            stepSlug: _steps.last.slug,
            contentVersion: widget.document.course.version,
          );
    } on Object {
      // The lesson still closes; the next visit records it again.
    }
    if (!mounted) return;
    // The site reports every prayer course as «salah».
    ref.read(analyticsProvider.notifier).track(AnalyticsEvent.lessonComplete, {
      'course': 'salah',
      'lesson': widget.lesson.slug,
    });
    ref.invalidate(salahProgressProvider(widget.courseSlug));
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/salah');
    }
    _finishing = false;
  }

  @override
  Widget build(BuildContext context) {
    final lesson = widget.lesson;
    return Scaffold(
      appBar: IqroTopBar(
        title: lesson.title,
        actions: const <Widget>[_DisplayMenu()],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: _ModeSwitch(),
            ),
            ValueListenableBuilder<int>(
              valueListenable: _pager.index,
              builder: (context, index, _) => _LessonHeader(
                lesson: lesson,
                step: _steps[index],
                index: index,
              ),
            ),
            Expanded(
              child: IqroStepPager(
                controller: _pager,
                keyPrefix: 'salah',
                nextLabel: context.l10n.salahNextStep,
                previousLabel: context.l10n.salahPreviousStep,
                onNext: _next,
                onPrevious: _previous,
                itemCount: _steps.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) => _StepPage(
                  key: ValueKey(_steps[index].slug),
                  courseSlug: widget.courseSlug,
                  document: widget.document,
                  lesson: lesson,
                  step: _steps[index],
                  showMedia: index == 0,
                  showSources: index == _steps.length - 1,
                  audioOwner: _audioOwner,
                  visual: _StepVisualState(
                    index: index,
                    current: _pager.index,
                    scene: _scenes[index],
                    three: _three,
                  ),
                ),
              ),
            ),
            ValueListenableBuilder<int>(
              valueListenable: _pager.index,
              builder: (context, index, _) => IqroStepButtons(
                keyPrefix: 'salah',
                isFirst: index == 0,
                isLast: index == _steps.length - 1,
                onBack: _previous,
                onNext: _next,
                backLabel: context.l10n.salahBack,
                nextLabel: context.l10n.salahNext,
                finishLabel: context.l10n.salahFinish,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeSwitch extends ConsumerWidget {
  const _ModeSwitch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(salahDisplayProvider.select((value) => value.mode));
    Widget label(String text) =>
        Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<SalahMode>(
        showSelectedIcon: false,
        segments: <ButtonSegment<SalahMode>>[
          ButtonSegment<SalahMode>(
            value: SalahMode.learn,
            label: label(context.l10n.salahModeLearn),
          ),
          ButtonSegment<SalahMode>(
            value: SalahMode.practice,
            label: label(context.l10n.salahModePractice),
          ),
        ],
        selected: <SalahMode>{mode},
        onSelectionChanged: (selection) {
          final notifier = ref.read(salahDisplayProvider.notifier);
          notifier.state = notifier.state.copyWith(mode: selection.single);
        },
      ),
    );
  }
}

enum _DisplayOption { arabic, transliteration, translation }

class _DisplayMenu extends ConsumerWidget {
  const _DisplayMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final display = ref.watch(salahDisplayProvider);
    return PopupMenuButton<_DisplayOption>(
      key: const ValueKey('salah-display-menu'),
      tooltip: context.l10n.salahDisplayOptions,
      icon: const Icon(Icons.tune),
      onSelected: (option) {
        final notifier = ref.read(salahDisplayProvider.notifier);
        final value = notifier.state;
        notifier.state = switch (option) {
          _DisplayOption.arabic => value.copyWith(
            showArabic: !value.showArabic,
          ),
          _DisplayOption.transliteration => value.copyWith(
            showTransliteration: !value.showTransliteration,
          ),
          _DisplayOption.translation => value.copyWith(
            showTranslation: !value.showTranslation,
          ),
        };
      },
      itemBuilder: (context) => <PopupMenuEntry<_DisplayOption>>[
        CheckedPopupMenuItem<_DisplayOption>(
          value: _DisplayOption.arabic,
          checked: display.showArabic,
          child: Text(context.l10n.salahShowArabic),
        ),
        CheckedPopupMenuItem<_DisplayOption>(
          value: _DisplayOption.transliteration,
          checked: display.showTransliteration,
          child: Text(context.l10n.salahShowTransliteration),
        ),
        CheckedPopupMenuItem<_DisplayOption>(
          value: _DisplayOption.translation,
          checked: display.showTranslation,
          child: Text(context.l10n.salahShowTranslation),
        ),
      ],
    );
  }
}

/// «Step N of M», and for a prayer the rak'ah dots.
class _LessonHeader extends StatelessWidget {
  const _LessonHeader({
    required this.lesson,
    required this.step,
    required this.index,
  });

  final SalahLesson lesson;
  final SalahStep step;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = lesson.steps.length;
    final rakats = lesson.prayer?.rakats ?? 0;
    final rakat = step.rakat;
    final stepLabel = Text(
      context.l10n.salahStepOf(index + 1, total),
      key: const ValueKey('salah-step-label'),
      style: theme.textTheme.labelLarge?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: rakats > 0 && rakat != null
          ? Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 6,
              children: <Widget>[
                Semantics(
                  label: context.l10n.salahRakatOf(rakat, rakats),
                  excludeSemantics: true,
                  child: Row(
                    key: const ValueKey('salah-rakat-dots'),
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (var number = 1; number <= rakats; number++)
                        _RakatDot(state: (number - rakat).sign),
                    ],
                  ),
                ),
                stepLabel,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                stepLabel,
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: (index + 1) / total,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(4),
                  backgroundColor: context.iqroColors.line,
                ),
              ],
            ),
    );
  }
}

class _RakatDot extends StatelessWidget {
  const _RakatDot({required this.state});

  /// Below zero for a finished rak'ah, zero for the current one.
  final int state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = state == 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsetsDirectional.only(end: 6),
      width: current ? 26 : 12,
      height: 12,
      decoration: BoxDecoration(
        color: state > 0
            ? Colors.transparent
            : scheme.primary.withValues(alpha: current ? 1 : .45),
        border: Border.all(color: scheme.primary, width: 1.5),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

class _StepPage extends ConsumerWidget {
  const _StepPage({
    required this.courseSlug,
    required this.document,
    required this.lesson,
    required this.step,
    required this.showMedia,
    required this.showSources,
    required this.audioOwner,
    required this.visual,
    super.key,
  });

  final String courseSlug;
  final SalahCourseDocument document;
  final SalahLesson lesson;
  final SalahStep step;

  /// The first step opens with the lesson's video, slides and banners, as
  /// on the site; the video stops when the learner turns the page.
  final bool showMedia;

  /// The last step ends with the lesson's «Sources», as on the site.
  final bool showSources;
  final Object audioOwner;
  final _StepVisualState visual;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final display = ref.watch(salahDisplayProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final media = document.stepMedia(step);
    final formulas = document.stepFormulas(step);
    final repeat = step.repeat ?? 1;
    final details = step.details;
    final ruling = _rulingLabel(context, step.ruling);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Practice is the prayer alone: no media, as no instruction. Each
          // block is followed by its gap.
          if (showMedia && display.learning && lesson.media.isNotEmpty)
            LessonMediaView(
              media: lesson.media,
              videoBuilder: (context, video) => LessonVideo(
                course: courseSlug,
                lesson: lesson.slug,
                lessonTitle: lesson.title,
                video: video,
                language: document.course.language,
              ),
            ),
          if (media != null) ...<Widget>[
            _StepVisual(courseSlug: courseSlug, media: media, state: visual),
            const SizedBox(height: 16),
          ],
          Text(
            step.title,
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.start,
          ),
          if (display.learning) ...<Widget>[
            // The ruling and the «?» and «!» notes, as by the title on the site.
            if (ruling != null || step.notes.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: <Widget>[
                  if (ruling != null)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: context.iqroColors.sand,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        child: Text(ruling, style: theme.textTheme.labelMedium),
                      ),
                    ),
                  if (step.notes.isNotEmpty) SalahStepNotes(notes: step.notes),
                ],
              ),
            ],
            if (step.instruction.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                step.instruction,
                key: ValueKey('salah-instruction-${step.slug}'),
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
              ),
            ],
            if (details != null) ...<Widget>[
              const SizedBox(height: 10),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: .6),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    details,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                ),
              ),
            ],
          ],
          if (step.audio case final audio?) ...<Widget>[
            const SizedBox(height: 16),
            SalahStepAudioBar(
              step: step,
              audio: audio,
              title: '${lesson.title} · ${step.title}',
              audioOwner: audioOwner,
            ),
          ],
          // A repeated action without a counted formula (washing the face
          // three times) gets its own counter.
          if (repeat > 1 &&
              formulas.every((formula) => formula.repetitions <= 1)) ...[
            const SizedBox(height: 16),
            Center(child: _StepRepeatCounter(total: repeat)),
          ],
          for (final formula in formulas) ...<Widget>[
            const SizedBox(height: 16),
            SalahFormulaCard(
              formula: formula,
              display: display,
              audioTitle: '${lesson.title} · ${step.title}',
              audioOwner: audioOwner,
            ),
          ],
          // Practice is the prayer alone: no sources, as no instruction.
          if (showSources &&
              display.learning &&
              lesson.sources.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            CourseLessonSources(sources: lesson.sources),
          ],
        ],
      ),
    );
  }

  static String? _rulingLabel(BuildContext context, String? ruling) =>
      switch (ruling) {
        'shart' => context.l10n.salahRulingShart,
        'rukn' => context.l10n.salahRulingRukn,
        'wajib' => context.l10n.salahRulingWajib,
        'sunnah' => context.l10n.salahRulingSunnah,
        _ => null,
      };
}

class _StepRepeatCounter extends StatefulWidget {
  const _StepRepeatCounter({required this.total});

  final int total;

  @override
  State<_StepRepeatCounter> createState() => _StepRepeatCounterState();
}

class _StepRepeatCounterState extends State<_StepRepeatCounter> {
  var _completed = 0;

  @override
  Widget build(BuildContext context) => IqroRepetitionCounter(
    key: const ValueKey('salah-step-counter'),
    total: widget.total,
    completed: _completed,
    onTap: () => setState(
      () => _completed = advanceRepetitionCount(_completed, widget.total),
    ),
  );
}

/// Where a step page stands in the lesson's 3D scene.
@immutable
class _StepVisualState {
  const _StepVisualState({
    required this.index,
    required this.current,
    required this.scene,
    required this.three,
  });

  final int index;
  final ValueListenable<int> current;

  /// The scene pose this page's picture is a still of, or null.
  final SalahMediaScene? scene;
  final Salah3DController three;
}

/// The step picture. A still of the 3D scene says it is schematic and, on
/// the current page, gives way to the running scene with its tools.
class _StepVisual extends StatelessWidget {
  const _StepVisual({
    required this.courseSlug,
    required this.media,
    required this.state,
  });

  final String courseSlug;
  final SalahMedia media;
  final _StepVisualState state;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final three = state.three;
    final scene = state.scene;
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[state.current, three]),
      builder: (context, _) {
        final runs =
            scene != null &&
            state.current.value == state.index &&
            !reduceMotion &&
            !three.failed;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _StepImage(
              courseSlug: courseSlug,
              media: media,
              view: runs ? _Salah3DHost(scene: scene, three: three) : null,
              stillOnTop: !(runs && three.ready),
            ),
            if (scene != null) _Salah3DBar(three: three, tools: runs),
          ],
        );
      },
    );
  }
}

/// Runs the scene only while it plays, the app is in the foreground and the
/// lesson is the visible route.
class _Salah3DHost extends ConsumerStatefulWidget {
  const _Salah3DHost({required this.scene, required this.three});

  final SalahMediaScene scene;
  final Salah3DController three;

  @override
  ConsumerState<_Salah3DHost> createState() => _Salah3DHostState();
}

class _Salah3DHostState extends ConsumerState<_Salah3DHost>
    with WidgetsBindingObserver {
  final _foreground = ValueNotifier<bool>(
    WidgetsBinding.instance.lifecycleState != AppLifecycleState.paused &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.hidden,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _foreground.dispose();
    super.dispose();
  }

  // Frames stop in the background, so this does not wait for a rebuild.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground.value = state == AppLifecycleState.resumed;
  }

  @override
  Widget build(BuildContext context) {
    final three = widget.three;
    final builder = ref.watch(salah3DViewBuilderProvider);
    return builder(
      context,
      Salah3DViewConfig(
        step: widget.scene.pose,
        view: widget.scene.view,
        running: three.playing && TickerMode.valuesOf(context).enabled,
        foreground: _foreground,
        speed: three.speed,
        replayCount: three.replayCount,
        onReady: three.markReady,
        onEnded: three.markEnded,
        onError: (code) {
          debugPrint('Salah 3D falls back to the still: $code');
          three.fail();
        },
      ),
    );
  }
}

/// «Schematic 3D illustration» and the tools of the scene.
class _Salah3DBar extends StatelessWidget {
  const _Salah3DBar({required this.three, required this.tools});

  final Salah3DController three;

  /// The scene runs on this page: its tools appear once it is drawn.
  final bool tools;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final speed =
        '${NumberFormat.decimalPattern(Localizations.localeOf(context).toLanguageTag()).format(three.speed)}×';
    // As tall as its tools, so they do not move the step when they appear.
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                l10n.salah3dSchematic,
                key: const ValueKey('salah-3d-caption'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (tools && three.ready) ...<Widget>[
              // Pause while the pose moves, play when paused, replay once it
              // has played.
              IconButton(
                key: const ValueKey('salah-3d-play'),
                tooltip: three.ended
                    ? l10n.salah3dReplay
                    : three.moving
                    ? l10n.salah3dPause
                    : l10n.salah3dPlay,
                onPressed: three.togglePlaying,
                icon: Icon(
                  three.ended
                      ? Icons.replay
                      : three.moving
                      ? Icons.pause
                      : Icons.play_arrow,
                ),
              ),
              Semantics(
                label: l10n.salah3dSpeed(speed),
                excludeSemantics: true,
                button: true,
                child: TextButton(
                  key: const ValueKey('salah-3d-speed'),
                  onPressed: three.cycleSpeed,
                  child: Text(speed),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The step illustration in its declared proportions, never wider than its
/// declared width and never taller than 40% of the screen. [view] (the
/// running 3D scene) lies under the picture, which fades out once the scene
/// has drawn ([stillOnTop] false).
class _StepImage extends ConsumerWidget {
  const _StepImage({
    required this.courseSlug,
    required this.media,
    this.view,
    this.stillOnTop = true,
  });

  final String courseSlug;
  final SalahMedia media;
  final Widget? view;
  final bool stillOnTop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = ref.watch(salahCourseImageProvider(courseSlug))(media);
    final maxHeight = MediaQuery.sizeOf(context).height * .4;
    final view = this.view;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: media.width > 0 ? media.width.toDouble() : double.infinity,
          maxHeight: maxHeight,
        ),
        child: AspectRatio(
          key: ValueKey('salah-image-${media.key}'),
          aspectRatio: media.aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (view != null)
                ClipRRect(
                  key: const ValueKey('salah-3d-view'),
                  borderRadius: BorderRadius.circular(22),
                  child: view,
                ),
              Semantics(
                image: true,
                label: media.alt,
                child: IgnorePointer(
                  ignoring: !stillOnTop,
                  child: AnimatedOpacity(
                    opacity: stillOnTop ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: ExcludeSemantics(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Image(
                          image: image,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          errorBuilder: (context, error, stack) => ColoredBox(
                            color: context.iqroColors.sand,
                            child: Center(
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                color: context.iqroColors.gold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
