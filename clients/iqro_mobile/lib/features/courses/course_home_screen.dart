import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import 'course_models.dart';
import 'course_progress_store.dart';
import 'course_widgets.dart';

const _arabicFallback = <String>[IqroTheme.arabicFontFamily];

/// A course: its description, author and sources, progress with
/// «Continue», then the list of lessons.
class CourseHomeScreen extends ConsumerWidget {
  const CourseHomeScreen({required this.courseSlug, super.key});

  final String courseSlug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final course = ref.watch(courseDocumentProvider(courseSlug));
    final document = course.valueOrNull;
    return Scaffold(
      appBar: IqroTopBar(
        title: document?.course.title ?? context.l10n.coursesTitle,
      ),
      body: document != null
          ? _CourseContents(document: document)
          : course.hasError
          ? CourseProblem(
              error: course.error!,
              onRetry: () => ref.invalidate(courseCatalogProvider),
            )
          : const IqroLoading(),
    );
  }
}

class _CourseContents extends ConsumerWidget {
  const _CourseContents({required this.document});

  final CourseDocument document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final info = document.course;
    final progress =
        ref.watch(courseProgressProvider(info.slug)).valueOrNull ??
        const CourseProgress();
    return IqroPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (info.cover != null) ...<Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: CourseCoverImage(cover: info.cover),
            ),
            const SizedBox(height: 16),
          ],
          if (info.summary.isNotEmpty) ...<Widget>[
            Text(
              info.summary,
              style: theme.textTheme.bodyLarge?.copyWith(
                height: 1.5,
                fontFamilyFallback: _arabicFallback,
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (info.source.isNotEmpty) ...<Widget>[
            Text(
              context.l10n.coursesSource,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              info.source,
              key: const ValueKey('course-source'),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamilyFallback: _arabicFallback,
              ),
            ),
            const SizedBox(height: 16),
          ],
          _ProgressCard(
            document: document,
            progress: progress,
            positions:
                ref.watch(coursePositionsProvider(info.slug)).valueOrNull ??
                const CourseVideoPositions(),
          ),
          const SizedBox(height: 24),
          IqroSectionHeader(title: context.l10n.coursesLessons),
          const SizedBox(height: 10),
          for (final lesson in document.lessons) ...<Widget>[
            _LessonCard(
              lesson: lesson,
              done: progress.isDone(lesson.slug),
              onTap: () =>
                  context.push(courseLessonPath(info.slug, lesson.slug)),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.document,
    required this.progress,
    required this.positions,
  });

  final CourseDocument document;
  final CourseProgress progress;
  final CourseVideoPositions positions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = document.lessons.length;
    final done = progress.doneCount(document);
    final resume = progress.resumeLesson(document);
    final resumeAt = resume?.video == null ? null : positions.of(resume!.slug);
    return IqroCard(
      color: theme.colorScheme.primaryContainer,
      borderColor: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            context.l10n.coursesProgress(done, total),
            key: const ValueKey('course-progress'),
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
          if (resume != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.icon(
                key: const ValueKey('course-continue'),
                onPressed: () => context.push(
                  courseLessonPath(document.course.slug, resume.slug),
                ),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(
                  resumeAt != null
                      ? context.l10n.coursesVideoResumeFrom(
                          courseVideoTime(resumeAt),
                        )
                      : progress.isEmpty
                      ? context.l10n.coursesStart
                      : context.l10n.coursesContinue,
                ),
              ),
            )
          else
            Row(
              key: const ValueKey('course-completed'),
              children: <Widget>[
                Icon(Icons.check_circle, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  context.l10n.coursesCompleted,
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _LessonCard extends StatelessWidget {
  const _LessonCard({
    required this.lesson,
    required this.done,
    required this.onTap,
  });

  final CourseLesson lesson;
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final minutes = courseDurationLabel(context, lesson.minutes);
    return IqroCard(
      key: ValueKey('course-lesson-${lesson.slug}'),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: done ? scheme.primary : context.iqroColors.sand,
              borderRadius: BorderRadius.circular(14),
            ),
            child: done
                ? Icon(
                    Icons.check_rounded,
                    color: scheme.onPrimary,
                    semanticLabel: context.l10n.coursesLessonDone,
                  )
                : Text(
                    '${lesson.number}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.primary,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  lesson.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontFamilyFallback: _arabicFallback,
                  ),
                ),
                if (lesson.summary.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    lesson.summary,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamilyFallback: _arabicFallback,
                    ),
                  ),
                ],
                if (minutes.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    minutes,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}
