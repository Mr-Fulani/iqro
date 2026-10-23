import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import '../tajweed/tajweed_sheet.dart' show TajweedRuleDot;
import 'tajweed_course_models.dart';
import 'tajweed_course_progress.dart';

// Lesson texts quote letters and Uthmani marks.
const _arabicFallback = <String>[IqroTheme.arabicFontFamily];

String tajweedLessonPath(String lesson) =>
    '/tajweed/lesson/${Uri.encodeComponent(lesson)}';

/// Course home: progress and «Continue», then the sections with lesson cards.
class TajweedCourseHomeScreen extends ConsumerStatefulWidget {
  const TajweedCourseHomeScreen({
    this.courseSlug = tajweedCourseSlug,
    super.key,
  });

  final String courseSlug;

  @override
  ConsumerState<TajweedCourseHomeScreen> createState() =>
      _TajweedCourseHomeScreenState();
}

class _TajweedCourseHomeScreenState
    extends ConsumerState<TajweedCourseHomeScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(ref.read(tajweedProgressSyncProvider).sync(widget.courseSlug));
  }

  @override
  Widget build(BuildContext context) {
    final course = ref.watch(tajweedCourseProvider(widget.courseSlug));
    final document = course.valueOrNull;
    return Scaffold(
      appBar: IqroTopBar(
        title: document?.course.title ?? context.l10n.tajweedCourseTitle,
      ),
      body: document != null
          ? _CourseContents(courseSlug: widget.courseSlug, document: document)
          : course.hasError
          ? IqroAsyncError(
              title: context.l10n.tajweedCourseUnavailable,
              onRetry: () =>
                  ref.invalidate(tajweedCourseProvider(widget.courseSlug)),
            )
          : const IqroLoading(),
    );
  }
}

class _CourseContents extends ConsumerWidget {
  const _CourseContents({required this.courseSlug, required this.document});

  final String courseSlug;
  final TajweedCourseDocument document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress =
        ref.watch(tajweedCourseProgressProvider(courseSlug)).valueOrNull ??
        const TajweedCourseProgress();
    void open(TajweedCourseLesson lesson) =>
        context.push(tajweedLessonPath(lesson.slug));
    return IqroPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _OverviewCard(document: document, progress: progress, onOpen: open),
          for (final section in document.sections)
            if (document.sectionLessons(section) case final lessons
                when lessons.isNotEmpty) ...<Widget>[
              const SizedBox(height: 24),
              IqroSectionHeader(title: section.title),
              const SizedBox(height: 10),
              for (final lesson in lessons) ...<Widget>[
                _LessonCard(
                  lesson: lesson,
                  target: document.target(lesson),
                  status: progress.statusOf(lesson.slug),
                  onTap: () => open(lesson),
                ),
                const SizedBox(height: 10),
              ],
            ],
        ],
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.document,
    required this.progress,
    required this.onOpen,
  });

  final TajweedCourseDocument document;
  final TajweedCourseProgress progress;
  final ValueChanged<TajweedCourseLesson> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = document.orderedLessons.length;
    final done = progress.completedCount(document);
    final resume = progress.resumeLesson(document);
    final started = progress.lessons.isNotEmpty;
    return IqroCard(
      color: theme.colorScheme.primaryContainer,
      borderColor: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (document.course.summary.isNotEmpty)
            Text(
              document.course.summary,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.45,
                fontFamilyFallback: _arabicFallback,
              ),
            ),
          if (document.pendingReview) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              context.l10n.tajweedReviewNote,
              key: const ValueKey('tajweed-course-review-note'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            context.l10n.tajweedCourseProgress(done, total),
            key: const ValueKey('tajweed-course-progress'),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: total == 0 ? 0 : done / total,
            minHeight: 6,
            borderRadius: BorderRadius.circular(6),
            backgroundColor: context.iqroColors.line,
          ),
          const SizedBox(height: 14),
          if (resume != null) ...<Widget>[
            Text(
              resume.title,
              style: theme.textTheme.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.icon(
                key: const ValueKey('tajweed-course-continue'),
                onPressed: () => onOpen(resume),
                icon: const Icon(Icons.play_arrow),
                label: Text(
                  started
                      ? context.l10n.tajweedCourseContinue
                      : context.l10n.tajweedCourseStart,
                ),
              ),
            ),
          ] else
            Text(
              context.l10n.tajweedCourseAllCompleted,
              key: const ValueKey('tajweed-course-all-completed'),
              style: theme.textTheme.bodyMedium,
            ),
        ],
      ),
    );
  }
}

class _LessonCard extends StatelessWidget {
  const _LessonCard({
    required this.lesson,
    required this.target,
    required this.status,
    required this.onTap,
  });

  final TajweedCourseLesson lesson;
  final TajweedCourseTarget target;
  final TajweedLessonStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusLabel = switch (status) {
      TajweedLessonStatus.completed =>
        context.l10n.tajweedCourseStatusCompleted,
      TajweedLessonStatus.inProgress =>
        context.l10n.tajweedCourseStatusInProgress,
      TajweedLessonStatus.notStarted => null,
    };
    final completed = status == TajweedLessonStatus.completed;
    return IqroCard(
      key: ValueKey('tajweed-lesson-${lesson.slug}'),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: completed ? scheme.primary : context.iqroColors.sand,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(switch (status) {
              TajweedLessonStatus.completed => Icons.check_rounded,
              TajweedLessonStatus.inProgress => Icons.play_arrow_rounded,
              TajweedLessonStatus.notStarted => Icons.menu_book_outlined,
            }, color: completed ? scheme.onPrimary : scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(lesson.title, style: theme.textTheme.titleSmall),
                if (lesson.summary.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    lesson.summary,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamilyFallback: _arabicFallback,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        TajweedRuleDot(target.color),
                        const SizedBox(width: 6),
                        Text(
                          target.name,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    if (lesson.minutes > 0)
                      Text(
                        context.l10n.salahMinutes(lesson.minutes),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    if (statusLabel != null)
                      DecoratedBox(
                        key: ValueKey('tajweed-lesson-status-${lesson.slug}'),
                        decoration: BoxDecoration(
                          color: completed
                              ? scheme.primaryContainer
                              : context.iqroColors.sand,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          child: Text(
                            statusLabel,
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}
