import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import 'course_models.dart';
import 'course_notes_view.dart';
import 'course_widgets.dart';

/// A lesson: its notes and sources; «←», «Studied» and «→» stay at the
/// bottom of the screen.
class CourseLessonScreen extends ConsumerWidget {
  const CourseLessonScreen({
    required this.courseSlug,
    required this.lessonSlug,
    super.key,
  });

  final String courseSlug;
  final String lessonSlug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final course = ref.watch(courseDocumentProvider(courseSlug));
    final document = course.valueOrNull;
    final lesson = document?.lesson(lessonSlug);
    if (document != null && lesson != null) {
      final number = document.indexOf(lesson.slug) + 1;
      return Scaffold(
        appBar: IqroTopBar(
          title: lesson.title,
          subtitle: context.l10n.coursesLessonOf(
            document.course.title,
            number,
            document.lessons.length,
          ),
        ),
        body: _LessonContents(document: document, lesson: lesson),
        bottomNavigationBar: _LessonBar(document: document, lesson: lesson),
      );
    }
    return Scaffold(
      appBar: IqroTopBar(
        title: document?.course.title ?? context.l10n.coursesTitle,
      ),
      body: document != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  context.l10n.coursesLessonNotFound,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            )
          : course.hasError
          ? CourseProblem(
              error: course.error!,
              onRetry: () => ref.invalidate(courseCatalogProvider),
            )
          : const IqroLoading(),
    );
  }
}

/// Opening a lesson marks it as started: «Continue» follows the course
/// opened last.
class _LessonContents extends ConsumerStatefulWidget {
  const _LessonContents({required this.document, required this.lesson});

  final CourseDocument document;
  final CourseLesson lesson;

  @override
  ConsumerState<_LessonContents> createState() => _LessonContentsState();
}

class _LessonContentsState extends ConsumerState<_LessonContents> {
  @override
  void initState() {
    super.initState();
    unawaited(_recordOpen());
  }

  Future<void> _recordOpen() async {
    final course = widget.document.course;
    try {
      await ref
          .read(courseProgressStoreProvider)
          .recordOpen(
            course: course.slug,
            lesson: widget.lesson.slug,
            contentVersion: course.version,
          );
    } on Object {
      // Progress is a convenience; the lesson reads without it.
      return;
    }
    if (mounted) ref.invalidate(courseProgressProvider(course.slug));
  }

  @override
  Widget build(BuildContext context) {
    final lesson = widget.lesson;
    final theme = Theme.of(context);
    return IqroPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (lesson.notes.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Semantics(
              header: true,
              child: Text(
                context.l10n.coursesNotes,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 12),
            IqroCard(
              key: const ValueKey('course-lesson-notes'),
              child: CourseNotesView(blocks: lesson.notes),
            ),
          ],
          if (lesson.sources.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            _Sources(sources: lesson.sources),
          ],
        ],
      ),
    );
  }
}

/// Folded by default, as on the site.
class _Sources extends StatefulWidget {
  const _Sources({required this.sources});

  final List<String> sources;

  @override
  State<_Sources> createState() => _SourcesState();
}

class _SourcesState extends State<_Sources> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IqroCard(
      key: const ValueKey('course-lesson-sources'),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            button: true,
            expanded: _open,
            child: InkWell(
              onTap: () => setState(() => _open = !_open),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.menu_book_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          context.l10n.coursesSources,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      Text(
                        '${widget.sources.length}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedRotation(
                        turns: _open ? .5 : 0,
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 200),
                        child: const Icon(Icons.expand_more),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final (index, source) in widget.sources.indexed)
                    Padding(
                      padding: EdgeInsets.only(top: index == 0 ? 0 : 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SizedBox(
                            width: 28,
                            child: Text(
                              '${index + 1}.',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              source,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontFamilyFallback: const [
                                  IqroTheme.arabicFontFamily,
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _LessonBar extends ConsumerWidget {
  const _LessonBar({required this.document, required this.lesson});

  final CourseDocument document;
  final CourseLesson lesson;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final slug = document.course.slug;
    final progress = ref.watch(courseProgressProvider(slug)).valueOrNull;
    final done = progress?.isDone(lesson.slug) ?? false;
    final previous = document.previous(lesson.slug);
    final next = document.next(lesson.slug);
    final allDone =
        progress != null &&
        progress.doneCount(document) == document.lessons.length;
    final store = ref.read(courseProgressStoreProvider);

    Future<void> mark(bool studied) async {
      if (studied) {
        await store.markDone(
          course: slug,
          lesson: lesson.slug,
          contentVersion: document.course.version,
        );
      } else {
        await store.unmark(
          course: slug,
          lesson: lesson.slug,
          contentVersion: document.course.version,
        );
      }
      ref.invalidate(courseProgressProvider(slug));
    }

    void open(CourseLesson? other) {
      if (other != null) {
        context.pushReplacement(courseLessonPath(slug, other.slug));
      } else if (context.canPop()) {
        context.pop();
      } else {
        context.go(coursePath(slug));
      }
    }

    final back = OutlinedButton.icon(
      key: const ValueKey('course-lesson-previous'),
      onPressed: () => open(previous),
      icon: const Icon(Icons.arrow_back),
      label: Text(l10n.coursesPrevious),
    );
    final forward = done
        ? FilledButton(
            key: const ValueKey('course-lesson-next'),
            onPressed: () => open(next),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Flexible(
                  child: Text(
                    next == null ? l10n.coursesAllLessons : l10n.coursesNext,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(next == null ? Icons.list_rounded : Icons.arrow_forward),
              ],
            ),
          )
        : FilledButton.icon(
            key: const ValueKey('course-lesson-done'),
            onPressed: progress == null ? null : () => mark(true),
            icon: const Icon(Icons.check_rounded),
            label: Text(l10n.coursesMarkDone),
          );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: context.iqroColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Semantics(
                liveRegion: true,
                child: done
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              Icons.check_circle,
                              size: 20,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                allDone
                                    ? l10n.coursesCompleted
                                    : l10n.coursesLessonDone,
                                key: const ValueKey('course-lesson-status'),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                            TextButton(
                              key: const ValueKey('course-lesson-unmark'),
                              onPressed: () => mark(false),
                              child: Text(l10n.coursesUnmark),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Semantics(
                      label: previous == null
                          ? l10n.coursesAllLessons
                          : l10n.coursesPreviousTopic(previous.title),
                      excludeSemantics: true,
                      button: true,
                      onTap: () => open(previous),
                      child: back,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: done && next != null
                        ? Semantics(
                            label: l10n.coursesNextTopic(next.title),
                            excludeSemantics: true,
                            button: true,
                            onTap: () => open(next),
                            child: forward,
                          )
                        : forward,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
