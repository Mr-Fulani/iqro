import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/audio/audio_controller.dart';
import '../../core/design_system/iqro_step_flow.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import '../tajweed/tajweed_sheet.dart'
    show TajweedRuleDot, tajweedArabicStyle, tajweedBodyStyle, tajweedLabel;
import 'tajweed_course_home_screen.dart' show tajweedLessonPath;
import 'tajweed_course_models.dart';
import 'tajweed_course_progress.dart';
import 'tajweed_course_sound.dart';
import 'tajweed_course_words.dart';

/// One lesson of the tajweed course. Opens on [stepSlug] once the lesson has
/// it, otherwise on the saved step of an unfinished lesson.
class TajweedLessonScreen extends ConsumerStatefulWidget {
  const TajweedLessonScreen({
    required this.lessonSlug,
    this.stepSlug,
    this.courseSlug = tajweedCourseSlug,
    super.key,
  });

  final String courseSlug;
  final String lessonSlug;
  final String? stepSlug;

  @override
  ConsumerState<TajweedLessonScreen> createState() =>
      _TajweedLessonScreenState();
}

class _TajweedLessonScreenState extends ConsumerState<TajweedLessonScreen> {
  late final Future<TajweedCourseProgress> _progress = _readProgress();

  Future<TajweedCourseProgress> _readProgress() async {
    final sync = ref.read(tajweedProgressSyncProvider);
    TajweedCourseProgress progress;
    try {
      progress = await ref
          .read(tajweedCourseProgressStoreProvider)
          .read(widget.courseSlug);
    } on Object {
      // Unreadable progress opens the lesson from its first step.
      progress = const TajweedCourseProgress();
    }
    // The lesson opens where it was left on this device; the account's copy
    // arrives for the next time.
    unawaited(sync.sync(widget.courseSlug));
    return progress;
  }

  @override
  Widget build(BuildContext context) {
    final course = ref.watch(tajweedCourseProvider(widget.courseSlug));
    final document = course.valueOrNull;
    if (document == null) {
      return Scaffold(
        appBar: IqroTopBar(title: context.l10n.tajweedCourseTitle),
        body: course.hasError
            ? IqroAsyncError(
                title: context.l10n.tajweedCourseUnavailable,
                onRetry: () =>
                    ref.invalidate(tajweedCourseProvider(widget.courseSlug)),
              )
            : const IqroLoading(),
      );
    }
    final lesson = document.lesson(widget.lessonSlug);
    if (lesson == null) {
      return Scaffold(
        appBar: IqroTopBar(title: context.l10n.tajweedCourseTitle),
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
    return FutureBuilder<TajweedCourseProgress>(
      future: _progress,
      builder: (context, snapshot) {
        final progress = snapshot.data;
        if (progress == null) {
          return Scaffold(
            appBar: IqroTopBar(title: lesson.title),
            body: const IqroLoading(),
          );
        }
        return TajweedLessonPlayer(
          key: ValueKey(
            '${document.course.version}:${lesson.slug}:${widget.stepSlug}',
          ),
          courseSlug: widget.courseSlug,
          document: document,
          lesson: lesson,
          resume: progress.resumeSteps(lesson.slug, widget.stepSlug),
        );
      },
    );
  }
}

/// The steps of a lesson: the rule, how to read it, examples from the
/// Quran and «find the rule». The examples arrive after the lesson opens.
class TajweedLessonPlayer extends ConsumerStatefulWidget {
  const TajweedLessonPlayer({
    required this.courseSlug,
    required this.document,
    required this.lesson,
    this.resume = const [],
    super.key,
  });

  final String courseSlug;
  final TajweedCourseDocument document;
  final TajweedCourseLesson lesson;

  /// Steps to open on, by preference, once the lesson has them.
  final List<String> resume;

  @override
  ConsumerState<TajweedLessonPlayer> createState() =>
      _TajweedLessonPlayerState();
}

enum _Feedback { wrong, correct, shown }

class _TajweedLessonPlayerState extends ConsumerState<TajweedLessonPlayer>
    with WidgetsBindingObserver {
  late IqroStepController _pager;
  // A new pager opens a step right after the steps changed, see _restartAt.
  var _pagerGeneration = 0;
  late final TajweedCourseSound _sound;
  // Kept for dispose, when ref can no longer be read.
  late AudioController _audio;

  var _loading = true;
  var _failed = false;
  var _shown = const <TajweedCourseExample>[];
  TajweedCourseExample? _find;

  /// `next_offset` of the last answer: «More examples» and «Another ayah»
  /// both continue from it, so no ayah comes twice.
  int? _cursor;
  var _moreLoading = false;
  var _moreFailed = false;
  var _anotherLoading = false;
  var _anotherFailed = false;

  // «Find the rule».
  int? _chosen;
  final _wrong = <int>{};
  var _misses = 0;
  int? _revealed;
  var _found = false;

  /// Steps to resume on that wait for the examples; a turn of the page by
  /// the learner cancels them.
  var _pending = const <String>[];
  late List<String> _steps;
  var _finishing = false;
  var _completed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _audio = ref.read(audioControllerProvider.notifier);
    _sound = TajweedCourseSound(
      audio: _controller,
      repository: ref.read(audioRepositoryProvider),
      recitation: ref.read(tajweedCourseRecitationProvider),
    );
    _steps = _stepSlugs();
    final first = widget.resume.isEmpty ? null : widget.resume.first;
    final initial = first == null ? -1 : _steps.indexOf(first);
    if (first != null && initial < 0) _pending = widget.resume;
    _pager = IqroStepController(initialIndex: initial < 0 ? 0 : initial);
    if (_pending.isEmpty) unawaited(_record(_pager.index.value));
    unawaited(_loadExamples());
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
    _sound.dispose();
    _pager.dispose();
    super.dispose();
  }

  AudioController _controller() {
    // In dispose the element is already unmounted and ref is gone.
    if (context.mounted) _audio = ref.read(audioControllerProvider.notifier);
    return _audio;
  }

  void _stopAudio() => unawaited(_sound.stopAll());

  List<String> _stepSlugs() => tajweedLessonStepSlugs(
    _loading || _failed ? 1 : _shown.length,
    find: _find != null,
  );

  Future<void> _loadExamples() async {
    if (!_loading) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    try {
      final page = await ref
          .read(tajweedCourseRepositoryProvider)
          .examples(
            widget.courseSlug,
            widget.lesson.slug,
            offset: 0,
            limit: tajweedFirstExamples,
          );
      if (!mounted) return;
      final split = splitFirstTajweedExamples(page.examples);
      setState(() {
        _loading = false;
        _failed = page.examples.isEmpty;
        _shown = split.shown;
        _find = split.find;
        _cursor = page.nextOffset;
        _steps = _stepSlugs();
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
        _steps = _stepSlugs();
      });
    }
    _resume();
  }

  /// Opens the saved or linked step now that the examples are here; a step
  /// the lesson does not have leaves it where it is.
  void _resume() {
    final pending = _pending;
    if (pending.isEmpty || !mounted) return;
    _pending = const [];
    final target = pending
        .map(_steps.indexOf)
        .where((index) => index >= 0)
        .firstOrNull;
    if (target != null && target != _pager.index.value) {
      _restartAt(target);
    } else {
      unawaited(_record(_pager.index.value));
    }
  }

  /// Opens [index] right after the steps changed. A PageView lays out its new
  /// page count only when its visible page changes, so turning the old pager
  /// could stop short of [index]; a new pager starts on it.
  void _restartAt(int index) {
    final old = _pager;
    setState(() {
      _pager = IqroStepController(initialIndex: index);
      _pagerGeneration += 1;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    _onPageChanged(index);
  }

  void _onPageChanged(int index) {
    _pending = const [];
    _stopAudio();
    _sound.clearFailure();
    unawaited(_record(index));
  }

  Future<void> _record(int index) async {
    if (index < 0 || index >= _steps.length) return;
    try {
      await ref
          .read(tajweedCourseProgressStoreProvider)
          .recordStep(
            course: widget.courseSlug,
            lesson: widget.lesson.slug,
            stepSlug: _steps[index],
            contentVersion: widget.document.course.version,
          );
      if (mounted) {
        ref.invalidate(tajweedCourseProgressProvider(widget.courseSlug));
      }
    } on Object {
      // Progress is a convenience: a failed write must not stop the lesson.
    }
  }

  Future<void> _moreExamples() async {
    final cursor = _cursor;
    if (cursor == null || _moreLoading) return;
    setState(() {
      _moreLoading = true;
      _moreFailed = false;
    });
    try {
      final page = await ref
          .read(tajweedCourseRepositoryProvider)
          .examples(
            widget.courseSlug,
            widget.lesson.slug,
            offset: cursor,
            limit: tajweedMoreExamples,
          );
      if (!mounted) return;
      // The first new example comes right after the ones already read.
      final first = 2 + _shown.length;
      setState(() {
        _moreLoading = false;
        _shown = [..._shown, ...page.examples];
        _cursor = page.nextOffset;
        _steps = _stepSlugs();
      });
      if (page.examples.isNotEmpty) _restartAt(first);
    } on Object {
      if (!mounted) return;
      setState(() {
        _moreLoading = false;
        _moreFailed = true;
      });
    }
  }

  Future<void> _anotherAyah() async {
    final cursor = _cursor;
    if (cursor == null || _anotherLoading) return;
    _stopAudio();
    setState(() {
      _anotherLoading = true;
      _anotherFailed = false;
    });
    try {
      final page = await ref
          .read(tajweedCourseRepositoryProvider)
          .examples(
            widget.courseSlug,
            widget.lesson.slug,
            offset: cursor,
            limit: 1,
          );
      if (!mounted) return;
      setState(() {
        _anotherLoading = false;
        _cursor = page.nextOffset;
        if (page.examples.isNotEmpty) {
          _find = page.examples.first;
          _chosen = null;
          _wrong.clear();
          _misses = 0;
          _revealed = null;
          _found = false;
        }
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _anotherLoading = false;
        _anotherFailed = true;
      });
    }
  }

  void _onWord(int position) {
    final occurrence = _find?.occurrenceAt(position) ?? -1;
    setState(() {
      _chosen = position;
      if (occurrence >= 0) {
        _revealed = occurrence;
        _found = true;
      } else {
        _wrong.add(position);
        _misses += 1;
      }
    });
  }

  void _showAnswer() => setState(() {
    _revealed = 0;
    _found = false;
  });

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
    _stopAudio();
    final sync = ref.read(tajweedProgressSyncProvider);
    try {
      await ref
          .read(tajweedCourseProgressStoreProvider)
          .complete(
            course: widget.courseSlug,
            lesson: widget.lesson.slug,
            stepSlug: _steps[_pager.index.value],
            contentVersion: widget.document.course.version,
          );
    } on Object {
      // The lesson still ends; the next visit records it again.
    }
    unawaited(sync.sync(widget.courseSlug));
    if (!mounted) return;
    ref.invalidate(tajweedCourseProgressProvider(widget.courseSlug));
    setState(() {
      _finishing = false;
      _completed = true;
    });
  }

  void _allLessons() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/tajweed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final lesson = widget.lesson;
    return Scaffold(
      appBar: IqroTopBar(title: lesson.title),
      body: SafeArea(
        top: false,
        child: _completed
            ? _CompletedView(
                next: widget.document.nextLesson(lesson.slug),
                onNext: (next) =>
                    context.pushReplacement(tajweedLessonPath(next.slug)),
                onAllLessons: _allLessons,
              )
            : Column(
                children: <Widget>[
                  ValueListenableBuilder<int>(
                    valueListenable: _pager.index,
                    builder: (context, index, _) => _StepHeader(
                      label: context.l10n.tajweedCourseStepOf(
                        index + 1,
                        _steps.length,
                      ),
                      value: (index + 1) / _steps.length,
                    ),
                  ),
                  Expanded(
                    child: IqroStepPager(
                      key: ValueKey('tajweed-course-pager-$_pagerGeneration'),
                      controller: _pager,
                      keyPrefix: 'tajweed-course',
                      nextLabel: context.l10n.tajweedNextStep,
                      previousLabel: context.l10n.tajweedPreviousStep,
                      onNext: _next,
                      onPrevious: _previous,
                      itemCount: _steps.length,
                      onPageChanged: _onPageChanged,
                      itemBuilder: (context, index) => KeyedSubtree(
                        key: ValueKey('tajweed-course-step-${_steps[index]}'),
                        child: _page(context, _steps[index]),
                      ),
                    ),
                  ),
                  ValueListenableBuilder<int>(
                    valueListenable: _pager.index,
                    builder: (context, index, _) => IqroStepButtons(
                      keyPrefix: 'tajweed-course',
                      isFirst: index == 0,
                      isLast: index == _steps.length - 1,
                      onBack: _previous,
                      onNext: _next,
                      backLabel: context.l10n.tajweedPrevious,
                      nextLabel: context.l10n.tajweedNext,
                      finishLabel: context.l10n.tajweedCourseFinish,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _page(BuildContext context, String slug) {
    final document = widget.document;
    final lesson = widget.lesson;
    final target = document.target(lesson);
    if (slug == 'intro') {
      return _IntroPage(
        lesson: lesson,
        target: target,
        pendingReview: document.pendingReview,
      );
    }
    if (slug == 'how') return _HowPage(lesson: lesson);
    if (slug == 'find') {
      final example = _find!;
      final revealed = _revealed;
      return _FindPage(
        example: example,
        target: target,
        sound: _sound,
        chosen: _chosen,
        wrong: _wrong,
        revealed: revealed,
        feedback: revealed != null
            ? (_found ? _Feedback.correct : _Feedback.shown)
            : _chosen != null
            ? _Feedback.wrong
            : null,
        canShowAnswer: revealed == null && _misses >= 2,
        onWord: _onWord,
        onShowAnswer: _showAnswer,
        onAnother: _cursor == null ? null : _anotherAyah,
        anotherLoading: _anotherLoading,
        anotherFailed: _anotherFailed,
      );
    }
    if (_loading) return const _ExamplesLoading();
    if (_failed) return _ExamplesError(onRetry: _loadExamples);
    final number = int.parse(slug.substring('example-'.length));
    final last = number == _shown.length;
    return _ExamplePage(
      example: _shown[number - 1],
      number: number,
      total: _shown.length,
      target: target,
      sound: _sound,
      onMore: last && _cursor != null ? _moreExamples : null,
      moreLoading: _moreLoading,
      moreFailed: last && _moreFailed,
    );
  }
}

/// «Step N of M» over a bar; screen readers hear it as the step changes.
class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Semantics(
        liveRegion: true,
        label: label,
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              key: const ValueKey('tajweed-course-step-label'),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: value,
              minHeight: 4,
              borderRadius: BorderRadius.circular(4),
              backgroundColor: context.iqroColors.line,
            ),
          ],
        ),
      ),
    );
  }
}

class _StepScroll extends StatelessWidget {
  const _StepScroll({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}

Widget _stepTitle(BuildContext context, String text, {Key? key}) => Semantics(
  header: true,
  child: Text(text, key: key, style: Theme.of(context).textTheme.titleLarge),
);

List<Widget> _paragraphs(BuildContext context, String text) {
  final style = tajweedBodyStyle(context)?.copyWith(fontSize: 16, height: 1.55);
  return <Widget>[
    for (final paragraph in text.split(RegExp(r'\n\s*\n')))
      if (paragraph.trim().isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(paragraph.trim(), style: style),
        ),
  ];
}

/// The target's colour dot and name; the Arabic name when it is another.
class _TargetHeading extends StatelessWidget {
  const _TargetHeading({required this.target});

  final TajweedCourseTarget target;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            TajweedRuleDot(target.color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                target.name,
                key: const ValueKey('tajweed-course-target'),
                style: theme.textTheme.titleMedium,
              ),
            ),
          ],
        ),
        if (target.arabicName != target.name)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 22),
            child: Text(
              target.arabicName,
              textDirection: TextDirection.rtl,
              style: tajweedArabicStyle(context, 20),
            ),
          ),
      ],
    );
  }
}

class _IntroPage extends StatelessWidget {
  const _IntroPage({
    required this.lesson,
    required this.target,
    required this.pendingReview,
  });

  final TajweedCourseLesson lesson;
  final TajweedCourseTarget target;
  final bool pendingReview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _StepScroll(
      children: <Widget>[
        _stepTitle(context, context.l10n.tajweedCourseRule),
        const SizedBox(height: 10),
        _TargetHeading(target: target),
        const SizedBox(height: 14),
        ..._paragraphs(context, lesson.explanation),
        if (lesson.letters.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          tajweedLabel(context, context.l10n.tajweedCourseLetters),
          Text(
            lesson.letters,
            key: const ValueKey('tajweed-course-letters'),
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            style: tajweedArabicStyle(context, 34),
          ),
        ],
        if (pendingReview) ...<Widget>[
          const SizedBox(height: 16),
          Text(
            context.l10n.tajweedReviewNote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _HowPage extends StatelessWidget {
  const _HowPage({required this.lesson});

  final TajweedCourseLesson lesson;

  @override
  Widget build(BuildContext context) => _StepScroll(
    children: <Widget>[
      _stepTitle(context, context.l10n.tajweedHowToRead),
      const SizedBox(height: 14),
      ..._paragraphs(context, lesson.how),
    ],
  );
}

class _ExamplesLoading extends StatelessWidget {
  const _ExamplesLoading();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CircularProgressIndicator(
            key: ValueKey('tajweed-course-examples-loading'),
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n.tajweedCourseExamplesLoading,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

class _ExamplesError extends StatelessWidget {
  const _ExamplesError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Semantics(
            liveRegion: true,
            child: Text(
              context.l10n.tajweedCourseExamplesError,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('tajweed-course-examples-retry'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(context.l10n.tajweedCourseRetry),
          ),
        ],
      ),
    ),
  );
}

Widget _reference(BuildContext context, TajweedCourseExample example) => Text(
  context.l10n.tajweedCourseAyahReference(example.surah, example.ayah),
  key: const ValueKey('tajweed-course-reference'),
  textAlign: TextAlign.center,
  style: Theme.of(context).textTheme.bodySmall,
);

class _ExamplePage extends StatelessWidget {
  const _ExamplePage({
    required this.example,
    required this.number,
    required this.total,
    required this.target,
    required this.sound,
    required this.onMore,
    required this.moreLoading,
    required this.moreFailed,
  });

  final TajweedCourseExample example;
  final int number;
  final int total;
  final TajweedCourseTarget target;
  final TajweedCourseSound sound;

  /// «More examples», on the last example while there are more.
  final VoidCallback? onMore;
  final bool moreLoading;
  final bool moreFailed;

  @override
  Widget build(BuildContext context) {
    final occurrence = example.occurrences.first;
    return _StepScroll(
      children: <Widget>[
        _stepTitle(
          context,
          context.l10n.tajweedCourseExampleOf(number, total),
          key: const ValueKey('tajweed-course-example-title'),
        ),
        const SizedBox(height: 12),
        TajweedAyahWords(example: example, target: target, lit: occurrence),
        const SizedBox(height: 6),
        _reference(context, example),
        const SizedBox(height: 12),
        Text.rich(
          tajweedOccurrenceSpan(example, occurrence, target),
          key: const ValueKey('tajweed-course-occurrence'),
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
          // Room for the marks under the letters.
          style: tajweedArabicStyle(context, 36).copyWith(height: 2.1),
        ),
        const SizedBox(height: 8),
        TajweedCourseSoundControls(
          sound: sound,
          example: example,
          occurrence: occurrence,
          part: 'occurrence0',
        ),
        if (onMore != null) ...<Widget>[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const ValueKey('tajweed-course-more'),
            onPressed: moreLoading ? null : onMore,
            icon: moreLoading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_rounded),
            label: Text(context.l10n.tajweedCourseMoreExamples),
          ),
          if (moreFailed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  context.l10n.tajweedCourseExamplesError,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _FindPage extends StatelessWidget {
  const _FindPage({
    required this.example,
    required this.target,
    required this.sound,
    required this.chosen,
    required this.wrong,
    required this.revealed,
    required this.feedback,
    required this.canShowAnswer,
    required this.onWord,
    required this.onShowAnswer,
    required this.onAnother,
    required this.anotherLoading,
    required this.anotherFailed,
  });

  final TajweedCourseExample example;
  final TajweedCourseTarget target;
  final TajweedCourseSound sound;
  final int? chosen;
  final Set<int> wrong;

  /// The occurrence shown in colour once found or given away.
  final int? revealed;
  final _Feedback? feedback;
  final bool canShowAnswer;
  final ValueChanged<int> onWord;
  final VoidCallback onShowAnswer;

  /// «Another ayah», while there are more examples.
  final VoidCallback? onAnother;
  final bool anotherLoading;
  final bool anotherFailed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final occurrence = revealed == null ? null : example.occurrences[revealed!];
    final message = switch (feedback) {
      _Feedback.correct => context.l10n.tajweedCourseFindCorrect(target.name),
      _Feedback.shown => context.l10n.tajweedCourseAnswerShown(target.name),
      _Feedback.wrong => context.l10n.tajweedCourseFindWrong,
      null => null,
    };
    return _StepScroll(
      children: <Widget>[
        _stepTitle(context, context.l10n.tajweedCourseFindTitle),
        const SizedBox(height: 6),
        Text(
          context.l10n.tajweedCourseFindPrompt(target.name),
          style: tajweedBodyStyle(context)?.copyWith(fontSize: 16),
        ),
        const SizedBox(height: 12),
        TajweedAyahWords(
          example: example,
          target: target,
          lit: occurrence,
          buttons: true,
          chosen: chosen,
          wrong: wrong,
          // Once the place is shown the exercise is over.
          onWord: occurrence == null ? onWord : null,
        ),
        const SizedBox(height: 6),
        _reference(context, example),
        if (message != null) ...<Widget>[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              message,
              key: const ValueKey('tajweed-course-feedback'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                color: feedback == _Feedback.wrong
                    ? scheme.error
                    : scheme.primary,
                fontFamilyFallback: const [IqroTheme.arabicFontFamily],
              ),
            ),
          ),
        ],
        if (canShowAnswer) ...<Widget>[
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              key: const ValueKey('tajweed-course-show-answer'),
              onPressed: onShowAnswer,
              child: Text(context.l10n.tajweedCourseShowAnswer),
            ),
          ),
        ],
        if (occurrence != null) ...<Widget>[
          const SizedBox(height: 12),
          TajweedCourseSoundControls(
            sound: sound,
            example: example,
            occurrence: occurrence,
            part: 'occurrence$revealed',
          ),
        ],
        if (onAnother != null) ...<Widget>[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const ValueKey('tajweed-course-another'),
            onPressed: anotherLoading ? null : onAnother,
            icon: anotherLoading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            label: Text(context.l10n.tajweedCourseAnotherAyah),
          ),
        ],
        if (anotherFailed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              liveRegion: true,
              child: Text(
                context.l10n.tajweedCourseExamplesError,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.error),
              ),
            ),
          ),
      ],
    );
  }
}

/// «Lesson completed», the next lesson and the way back to all of them.
class _CompletedView extends StatelessWidget {
  const _CompletedView({
    required this.next,
    required this.onNext,
    required this.onAllLessons,
  });

  final TajweedCourseLesson? next;
  final ValueChanged<TajweedCourseLesson> onNext;
  final VoidCallback onAllLessons;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final next = this.next;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Icon(
                Icons.check_circle_rounded,
                size: 56,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                header: true,
                child: Text(
                  context.l10n.tajweedCourseLessonCompleted,
                  key: const ValueKey('tajweed-course-completed'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: 24),
              if (next != null) ...<Widget>[
                FilledButton.icon(
                  key: const ValueKey('tajweed-course-next-lesson'),
                  onPressed: () => onNext(next),
                  icon: const Icon(Icons.arrow_forward),
                  label: Text(
                    context.l10n.tajweedCourseNextLesson(next.title),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              OutlinedButton(
                key: const ValueKey('tajweed-course-all-lessons'),
                onPressed: onAllLessons,
                child: Text(context.l10n.tajweedCourseAllLessons),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
