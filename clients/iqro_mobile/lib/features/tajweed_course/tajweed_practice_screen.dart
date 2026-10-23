import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../core/audio/audio_controller.dart';
import '../../core/design_system/iqro_step_flow.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import '../tajweed/tajweed_sheet.dart' show TajweedRuleDot, tajweedBodyStyle;
import 'tajweed_course_models.dart';
import 'tajweed_course_progress.dart';
import 'tajweed_course_sound.dart';
import 'tajweed_course_words.dart';
import 'tajweed_practice.dart';

// Rule names quote Arabic letters.
const _arabicFallback = <String>[IqroTheme.arabicFontFamily];

enum _Phase { start, loading, error, session, summary }

/// The first answer to a task: the word position or the option tapped.
typedef _Given = ({Object picked, TajweedPracticeAnswer answer});

/// Practice of the tajweed course (docs/tajweed/practice.md): tasks on the
/// rules of passed lessons from the whole Quran, one per step as in a
/// lesson, then the score, the day streak and what comes back for review.
class TajweedPracticeScreen extends ConsumerStatefulWidget {
  const TajweedPracticeScreen({this.courseSlug = tajweedCourseSlug, super.key});

  final String courseSlug;

  @override
  ConsumerState<TajweedPracticeScreen> createState() =>
      _TajweedPracticeScreenState();
}

class _TajweedPracticeScreenState extends ConsumerState<TajweedPracticeScreen>
    with WidgetsBindingObserver {
  late final TajweedCourseSound _sound;
  // Kept for dispose, when ref can no longer be read.
  late AudioController _audio;
  late final DateTime Function() _clock;
  var _pager = IqroStepController();
  var _pagerGeneration = 0;

  var _phase = _Phase.start;
  var _tasks = const <TajweedPracticeTask>[];
  final _given = <int, _Given>{};

  /// Each ayah's track and timings once looked up; null when it has none.
  final _ayahAudio = <String, TajweedAyahAudio?>{};
  ({int correct, int total})? _result;
  var _finishing = false;

  /// When the review list and the streak are counted.
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _audio = ref.read(audioControllerProvider.notifier);
    _clock = ref.read(tajweedPracticeClockProvider);
    _now = _clock();
    _sound = TajweedCourseSound(
      audio: _controller,
      repository: ref.read(audioRepositoryProvider),
      recitation: ref.read(tajweedCourseRecitationProvider),
    );
    unawaited(ref.read(tajweedPracticeSyncProvider).sync(widget.courseSlug));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Another screen over the practice leaves the task too.
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

  Future<void> _start(
    List<TajweedCourseLesson> passed,
    TajweedCourseDocument document,
    TajweedPracticeState state,
  ) async {
    _stopAudio();
    setState(() {
      _phase = _Phase.loading;
      _given.clear();
      _result = null;
    });
    try {
      final tasks = await ref
          .read(tajweedCourseRepositoryProvider)
          .practice(
            widget.courseSlug,
            lessons: [for (final lesson in passed) lesson.slug],
            seed: Random().nextInt(1 << 31),
            review: state.dueReviewKeys(_clock()),
          );
      final known = [
        for (final task in tasks)
          if (document.targets.containsKey(task.target)) task,
      ];
      if (known.isEmpty) throw StateError('No practice tasks');
      if (!mounted) return;
      final old = _pager;
      setState(() {
        _tasks = known;
        _phase = _Phase.session;
        _pager = IqroStepController();
        _pagerGeneration += 1;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      _lookUp(0);
    } on Object {
      if (mounted) setState(() => _phase = _Phase.error);
    }
  }

  /// Looks up the audio of the task at [index] and the next one: «listen»
  /// needs it to know whether it can be asked.
  void _lookUp(int index) {
    for (final task in _tasks.skip(index).take(2)) {
      final example = task.example;
      if (_ayahAudio.containsKey(example.verseKey)) continue;
      unawaited(
        _sound.ayah(example).then((audio) {
          if (mounted) setState(() => _ayahAudio[example.verseKey] = audio);
        }),
      );
    }
  }

  ({Duration start, Duration end})? _timing(
    TajweedPracticeTask task,
    TajweedOccurrence occurrence,
  ) {
    final audio = _ayahAudio[task.example.verseKey];
    return audio == null
        ? null
        : tajweedOccurrenceTiming(audio.playback.words, occurrence);
  }

  /// The type the task is asked as: «listen» without the reciter's timings
  /// is asked as «identify».
  TajweedPracticeTaskType _typeOf(int index) {
    final given = _given[index];
    if (given != null) return given.answer.type;
    final task = _tasks[index];
    if (task.type != TajweedPracticeTaskType.listen ||
        !_ayahAudio.containsKey(task.example.verseKey)) {
      return task.type;
    }
    return _timing(task, task.focusOccurrence) == null
        ? TajweedPracticeTaskType.identify
        : TajweedPracticeTaskType.listen;
  }

  /// Only the first answer counts.
  void _give(int index, Object picked, {required bool correct}) {
    if (_given.containsKey(index)) return;
    final task = _tasks[index];
    final type = _typeOf(index);
    setState(
      () => _given[index] = (
        picked: picked,
        answer: TajweedPracticeAnswer(
          key: tajweedPracticeKey(type, task.example.verseKey, task.target),
          target: task.target,
          type: type,
          correct: correct,
          at: tajweedProgressTime(_clock()),
        ),
      ),
    );
  }

  void _onPageChanged(int index) {
    _stopAudio();
    _sound.clearFailure();
    _lookUp(index);
  }

  void _goTo(int index) => _pager.goTo(context, index, _tasks.length);

  void _next() {
    final index = _pager.index.value;
    if (index >= _tasks.length - 1) {
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
    final answers = [
      for (var index = 0; index < _tasks.length; index++)
        if (_given[index] case final given?) given.answer,
    ];
    if (answers.isNotEmpty) {
      final sync = ref.read(tajweedPracticeSyncProvider);
      final finished = _clock();
      try {
        await ref
            .read(tajweedPracticeStoreProvider)
            .record(
              widget.courseSlug,
              TajweedPracticeSession(
                id: const Uuid().v4(),
                course: widget.courseSlug,
                localDate: tajweedLocalDate(finished),
                finishedAt: tajweedProgressTime(finished),
                answers: answers,
              ),
            );
      } on Object {
        // The session is lost; the practice still ends with its result.
      }
      unawaited(sync.sync(widget.courseSlug));
      if (!mounted) return;
      ref.invalidate(tajweedPracticeProvider(widget.courseSlug));
    }
    setState(() {
      _finishing = false;
      _now = _clock();
      _result = (
        correct: answers.where((answer) => answer.correct).length,
        total: answers.length,
      );
      _phase = _Phase.summary;
    });
  }

  void _toCourse() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/tajweed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final course = ref.watch(tajweedCourseProvider(widget.courseSlug));
    final progress = ref.watch(
      tajweedCourseProgressProvider(widget.courseSlug),
    );
    final practice = ref.watch(tajweedPracticeProvider(widget.courseSlug));
    final document = course.valueOrNull;
    final Widget body;
    if (document == null) {
      body = course.hasError
          ? IqroAsyncError(
              title: context.l10n.tajweedCourseUnavailable,
              onRetry: () =>
                  ref.invalidate(tajweedCourseProvider(widget.courseSlug)),
            )
          : const IqroLoading();
    } else if (_phase == _Phase.session) {
      body = _session(context, document);
    } else if (progress.isLoading && !progress.hasValue ||
        practice.isLoading && !practice.hasValue) {
      body = const IqroLoading();
    } else {
      final passed = progress.valueOrNull ?? const TajweedCourseProgress();
      body = _overview(
        context,
        document,
        [
          for (final lesson in document.orderedLessons)
            if (passed.statusOf(lesson.slug) == TajweedLessonStatus.completed)
              lesson,
        ],
        practice.valueOrNull?.state ?? const TajweedPracticeState(),
      );
    }
    return Scaffold(
      appBar: IqroTopBar(title: context.l10n.tajweedPracticeTitle),
      body: SafeArea(top: false, child: body),
    );
  }

  /// The start and the summary: the result, the stats, the passed rules.
  Widget _overview(
    BuildContext context,
    TajweedCourseDocument document,
    List<TajweedCourseLesson> passed,
    TajweedPracticeState state,
  ) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final result = _phase == _Phase.summary ? _result : null;
    final loading = _phase == _Phase.loading;
    return IqroPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (result != null)
            Semantics(
              liveRegion: true,
              header: true,
              child: Text(
                l10n.tajweedPracticeSummary(result.correct, result.total),
                key: const ValueKey('tajweed-practice-result'),
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
            )
          else
            Text(
              l10n.tajweedPracticeDescription,
              style: tajweedBodyStyle(context)?.copyWith(height: 1.45),
            ),
          const SizedBox(height: 16),
          _Stats(
            score: state.score,
            streak: state.shownStreak(tajweedLocalDate(_now)),
            due: state.dueReviewKeys(_now, limit: null).length,
          ),
          const SizedBox(height: 24),
          if (passed.isNotEmpty) ...<Widget>[
            Semantics(
              header: true,
              child: Text(
                l10n.tajweedPracticeLearned,
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final lesson in passed)
                  _RuleChip(
                    key: ValueKey('tajweed-practice-rule-${lesson.slug}'),
                    target: document.target(lesson),
                  ),
              ],
            ),
            if (_phase == _Phase.error || loading) ...<Widget>[
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Text(
                  loading
                      ? l10n.tajweedPracticeLoading
                      : l10n.tajweedPracticeError,
                  key: ValueKey(
                    loading
                        ? 'tajweed-practice-loading'
                        : 'tajweed-practice-error',
                  ),
                  style: loading
                      ? theme.textTheme.bodyMedium
                      : theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const ValueKey('tajweed-practice-start'),
              onPressed: loading ? null : () => _start(passed, document, state),
              icon: loading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      result == null
                          ? Icons.play_arrow_rounded
                          : Icons.replay_rounded,
                    ),
              label: Text(
                result == null
                    ? l10n.tajweedPracticeStart
                    : l10n.tajweedPracticeAgain,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              key: const ValueKey('tajweed-practice-to-course'),
              onPressed: _toCourse,
              child: Text(l10n.tajweedPracticeToCourse),
            ),
          ] else ...<Widget>[
            Text(
              l10n.tajweedPracticeNoLessons,
              key: const ValueKey('tajweed-practice-no-lessons'),
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('tajweed-practice-to-course'),
              onPressed: _toCourse,
              child: Text(l10n.tajweedPracticeToCourse),
            ),
          ],
        ],
      ),
    );
  }

  Widget _session(BuildContext context, TajweedCourseDocument document) {
    final l10n = context.l10n;
    return Column(
      children: <Widget>[
        ValueListenableBuilder<int>(
          valueListenable: _pager.index,
          builder: (context, index, _) => _TaskHeader(
            label: l10n.tajweedPracticeTaskOf(index + 1, _tasks.length),
            review: _tasks[index].review,
            value: (index + 1) / _tasks.length,
          ),
        ),
        Expanded(
          child: IqroStepPager(
            key: ValueKey('tajweed-practice-pager-$_pagerGeneration'),
            controller: _pager,
            keyPrefix: 'tajweed-practice',
            nextLabel: l10n.tajweedNextStep,
            previousLabel: l10n.tajweedPreviousStep,
            onNext: _next,
            onPrevious: _previous,
            itemCount: _tasks.length,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, index) => KeyedSubtree(
              key: ValueKey('tajweed-practice-task-$index'),
              child: _task(context, document, index),
            ),
          ),
        ),
        ValueListenableBuilder<int>(
          valueListenable: _pager.index,
          builder: (context, index, _) => IqroStepButtons(
            keyPrefix: 'tajweed-practice',
            isFirst: index == 0,
            isLast: index == _tasks.length - 1,
            onBack: _previous,
            onNext: _next,
            backLabel: l10n.tajweedPracticePrevious,
            nextLabel: l10n.tajweedPracticeNext,
            finishLabel: l10n.tajweedPracticeFinish,
          ),
        ),
      ],
    );
  }

  Widget _task(
    BuildContext context,
    TajweedCourseDocument document,
    int index,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final task = _tasks[index];
    final example = task.example;
    final target = document.targets[task.target]!;
    final type = _typeOf(index);
    final given = _given[index];
    final picked = given?.picked;
    final find = type == TajweedPracticeTaskType.find;
    // «Find» shows the place tapped, or the first one, once answered; the
    // other tasks show the place they ask about.
    final shown = !find
        ? task.focusOccurrence
        : given == null
        ? null
        : example.occurrences[max(
            0,
            picked is int ? example.occurrenceAt(picked) : -1,
          )];
    final timing = shown == null ? null : _timing(task, shown);
    final listening = type == TajweedPracticeTaskType.listen && given == null;
    final feedback = given == null
        ? ''
        : given.answer.correct
        ? l10n.tajweedPracticeCorrect
        : l10n.tajweedPracticeWrong(target.name);
    Widget clip(TajweedOccurrence occurrence) => TajweedCourseSoundControls(
      sound: _sound,
      example: example,
      occurrence: occurrence,
      part: 'occurrence${example.occurrences.indexOf(occurrence)}',
      wholeAyah: false,
    );
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(
              switch (type) {
                TajweedPracticeTaskType.find => l10n.tajweedPracticeFindPrompt(
                  target.name,
                ),
                TajweedPracticeTaskType.identify =>
                  l10n.tajweedPracticeIdentifyPrompt,
                TajweedPracticeTaskType.listen =>
                  l10n.tajweedPracticeListenPrompt,
              },
              key: const ValueKey('tajweed-practice-prompt'),
              style: theme.textTheme.titleLarge?.copyWith(
                fontFamilyFallback: _arabicFallback,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (listening) ...<Widget>[
            if (timing != null)
              clip(shown!)
            else
              Semantics(
                liveRegion: true,
                child: Text(
                  l10n.tajweedPracticeLoading,
                  key: const ValueKey('tajweed-practice-audio-loading'),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 12),
          ] else ...<Widget>[
            TajweedAyahWords(
              example: example,
              // Before the answer the place is in the accent colour: the
              // rule's own would tell it.
              target: given == null
                  ? TajweedCourseTarget(
                      name: target.name,
                      arabicName: target.arabicName,
                      color: scheme.primary,
                    )
                  : target,
              lit: shown,
              buttons: find,
              chosen: picked is int ? picked : null,
              wrong: <int>{if (picked is int && !given!.answer.correct) picked},
              onWord: find && given == null
                  ? (position) => _give(
                      index,
                      position,
                      correct: example.occurrenceAt(position) >= 0,
                    )
                  : null,
            ),
            const SizedBox(height: 12),
          ],
          if (!find)
            _Options(
              options: [
                for (final option in task.options)
                  if (document.targets[option] case final item?)
                    (id: option, target: item),
              ],
              answer: task.target,
              picked: picked is String ? picked : null,
              onPick: given == null
                  ? (option) =>
                        _give(index, option, correct: option == task.target)
                  : null,
            ),
          Semantics(
            container: true,
            liveRegion: true,
            child: Text(
              feedback,
              key: const ValueKey('tajweed-practice-feedback'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                color: given?.answer.correct ?? true
                    ? scheme.primary
                    : scheme.error,
                fontFamilyFallback: _arabicFallback,
              ),
            ),
          ),
          if (given != null && shown != null && timing != null) ...<Widget>[
            const SizedBox(height: 12),
            clip(shown),
          ],
        ],
      ),
    );
  }
}

/// «Task N of M», the review badge and a bar; screen readers hear it as the
/// task changes.
class _TaskHeader extends StatelessWidget {
  const _TaskHeader({
    required this.label,
    required this.review,
    required this.value,
  });

  final String label;
  final bool review;
  final double value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badge = context.l10n.tajweedPracticeReviewBadge;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Semantics(
        liveRegion: true,
        label: review ? '$label. $badge' : label,
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text(
                  label,
                  key: const ValueKey('tajweed-practice-counter'),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (review)
                  DecoratedBox(
                    key: const ValueKey('tajweed-practice-review-badge'),
                    decoration: BoxDecoration(
                      color: context.iqroColors.sand,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      child: Text(badge, style: theme.textTheme.labelSmall),
                    ),
                  ),
              ],
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

/// The names to choose from; after the answer the right one is marked, and
/// a wrong choice too.
class _Options extends StatelessWidget {
  const _Options({
    required this.options,
    required this.answer,
    required this.picked,
    required this.onPick,
  });

  final List<({String id, TajweedCourseTarget target})> options;
  final String answer;
  final String? picked;

  /// Null once the task is answered.
  final ValueChanged<String>? onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final answered = onPick == null;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: context.l10n.tajweedPracticeOptions,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final (:id, :target) in options)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _option(context, scheme, id, target, answered),
            ),
        ],
      ),
    );
  }

  Widget _option(
    BuildContext context,
    ColorScheme scheme,
    String id,
    TajweedCourseTarget target,
    bool answered,
  ) {
    final right = answered && id == answer;
    final wrong = answered && id == picked && id != answer;
    final (Color? background, Color? foreground, Color border) = right
        ? (scheme.primaryContainer, scheme.onPrimaryContainer, scheme.primary)
        : wrong
        // A tint: the theme's error container is the strong error colour.
        ? (scheme.error.withValues(alpha: .1), scheme.error, scheme.error)
        : (null, null, context.iqroColors.line);
    return MergeSemantics(
      child: Semantics(
        selected: id == picked,
        child: OutlinedButton(
          key: ValueKey('tajweed-practice-option-$id'),
          onPressed: answered ? null : () => onPick!(id),
          style: OutlinedButton.styleFrom(
            alignment: AlignmentDirectional.centerStart,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            side: BorderSide(color: border, width: right || wrong ? 2 : 1),
            backgroundColor: background,
            disabledBackgroundColor: background,
            foregroundColor: scheme.onSurface,
            disabledForegroundColor: foreground ?? scheme.onSurfaceVariant,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  target.name,
                  style: const TextStyle(fontFamilyFallback: _arabicFallback),
                ),
              ),
              if (right)
                Icon(Icons.check_circle_rounded, color: scheme.primary)
              else if (wrong)
                Icon(Icons.cancel_rounded, color: scheme.error),
            ],
          ),
        ),
      ),
    );
  }
}

/// Score, streak and the tasks due for review.
class _Stats extends StatelessWidget {
  const _Stats({required this.score, required this.streak, required this.due});

  final int score;
  final int streak;
  final int due;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    Widget stat(String label, String value, String key) => Expanded(
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(value, key: ValueKey(key), style: theme.textTheme.titleLarge),
          ],
        ),
      ),
    );
    return IqroCard(
      color: theme.colorScheme.primaryContainer,
      borderColor: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              stat(
                l10n.tajweedPracticeScore,
                '$score',
                'tajweed-practice-score',
              ),
              const SizedBox(width: 12),
              stat(
                l10n.tajweedPracticeStreak,
                l10n.tajweedPracticeStreakDays(streak),
                'tajweed-practice-streak',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Icon(
                Icons.replay_rounded,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.tajweedPracticeReviewCount(due),
                  key: const ValueKey('tajweed-practice-review-count'),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A passed rule: its colour and name.
class _RuleChip extends StatelessWidget {
  const _RuleChip({required this.target, super.key});

  final TajweedCourseTarget target;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border.all(color: context.iqroColors.line),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TajweedRuleDot(target.color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              target.name,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontFamilyFallback: _arabicFallback,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
