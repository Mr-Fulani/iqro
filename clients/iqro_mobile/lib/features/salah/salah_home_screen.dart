import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import 'salah_models.dart';
import 'salah_progress.dart';
import 'salah_repository.dart';

String salahLessonPath(String lesson) =>
    '/salah/lesson/${Uri.encodeComponent(lesson)}';

/// Course home: sections with lesson cards, progress and «Continue».
class SalahHomeScreen extends ConsumerWidget {
  const SalahHomeScreen({this.courseSlug = salahDefaultCourseSlug, super.key});

  final String courseSlug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final course = ref.watch(salahCourseProvider(courseSlug));
    final document = course.valueOrNull;
    return Scaffold(
      appBar: IqroTopBar(
        title: context.l10n.salahTitle,
        subtitle: document?.course.sourceTitle.isNotEmpty == true
            ? document!.course.sourceTitle
            : null,
      ),
      body: document != null
          ? _CourseContents(courseSlug: courseSlug, document: document)
          : course.hasError
          ? IqroAsyncError(
              title: context.l10n.salahUnavailable,
              onRetry: () => ref.invalidate(salahCourseProvider(courseSlug)),
            )
          : const IqroLoading(),
    );
  }
}

class _CourseContents extends ConsumerWidget {
  const _CourseContents({required this.courseSlug, required this.document});

  final String courseSlug;
  final SalahCourseDocument document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress =
        ref.watch(salahProgressProvider(courseSlug)).valueOrNull ??
        const SalahCourseProgress();
    void open(SalahLesson lesson) => context.push(salahLessonPath(lesson.slug));
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

  final SalahCourseDocument document;
  final SalahCourseProgress progress;
  final ValueChanged<SalahLesson> onOpen;

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
          Text(
            context.l10n.salahLessonsProgress(done, total),
            key: const ValueKey('salah-progress'),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: total == 0 ? 0 : done / total,
            minHeight: 6,
            borderRadius: BorderRadius.circular(6),
            backgroundColor: context.iqroColors.line,
          ),
          if (resume != null) ...<Widget>[
            const SizedBox(height: 14),
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
                key: const ValueKey('salah-continue'),
                onPressed: () => onOpen(resume),
                icon: const Icon(Icons.play_arrow),
                label: Text(
                  started
                      ? context.l10n.salahContinue
                      : context.l10n.salahStart,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LessonCard extends StatelessWidget {
  const _LessonCard({
    required this.lesson,
    required this.status,
    required this.onTap,
  });

  final SalahLesson lesson;
  final SalahLessonStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusLabel = switch (status) {
      SalahLessonStatus.completed => context.l10n.salahStatusCompleted,
      SalahLessonStatus.inProgress => context.l10n.salahStatusInProgress,
      SalahLessonStatus.notStarted => null,
    };
    return IqroCard(
      key: ValueKey('salah-lesson-${lesson.slug}'),
      onTap: onTap,
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: status == SalahLessonStatus.completed
                  ? scheme.primary
                  : context.iqroColors.sand,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              switch (status) {
                SalahLessonStatus.completed => Icons.check_rounded,
                SalahLessonStatus.inProgress => Icons.play_arrow_rounded,
                SalahLessonStatus.notStarted =>
                  lesson.prayer != null
                      ? Icons.self_improvement
                      : Icons.menu_book_outlined,
              },
              color: status == SalahLessonStatus.completed
                  ? scheme.onPrimary
                  : scheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(lesson.title, style: theme.textTheme.titleSmall),
                if (lesson.summary.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(lesson.summary, style: theme.textTheme.bodySmall),
                ],
                const SizedBox(height: 4),
                Text(
                  <String>[
                    if (lesson.minutes > 0)
                      context.l10n.salahMinutes(lesson.minutes),
                    ?statusLabel,
                  ].join(' · '),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
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
