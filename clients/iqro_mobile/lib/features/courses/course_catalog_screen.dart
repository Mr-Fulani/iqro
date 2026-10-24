import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import '../dua/dua_thematic_icon.dart';
import 'course_models.dart';
import 'course_progress_store.dart';
import 'course_widgets.dart';

/// «Continue»: the first lesson not studied of the course studied last.
typedef CourseResume = ({CourseSummary course, CourseLesson lesson});

final courseResumeProvider = FutureProvider.autoDispose<CourseResume?>((
  ref,
) async {
  final catalog = await ref.watch(courseCatalogProvider.future);
  CourseSummary? latest;
  var latestAt = '';
  CourseProgress? latestProgress;
  for (final course in catalog.courses) {
    final progress = await ref.watch(
      courseProgressProvider(course.slug).future,
    );
    final at = progress.lastUpdatedAt;
    if (progress.isEmpty || (latest != null && at.compareTo(latestAt) <= 0)) {
      continue;
    }
    (latest, latestAt, latestProgress) = (course, at, progress);
  }
  if (latest == null) return null;
  final document = await ref.watch(courseDocumentProvider(latest.slug).future);
  final lesson = latestProgress!.resumeLesson(document);
  return lesson == null ? null : (course: latest, lesson: lesson);
});

/// «Courses»: the prayer and tajweed courses first, then the courses of the
/// API. Offline it lists the courses kept on the device.
class CourseCatalogScreen extends ConsumerWidget {
  const CourseCatalogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final catalog = ref.watch(courseCatalogProvider);
    final resume = ref.watch(courseResumeProvider).valueOrNull;
    final offline = catalog.valueOrNull?.offline ?? false;
    return Scaffold(
      appBar: IqroTopBar(
        title: l10n.coursesTitle,
        subtitle: l10n.coursesSubtitle,
      ),
      body: IqroPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (offline) ...<Widget>[
              Semantics(
                liveRegion: true,
                child: IqroStatusBanner(
                  key: const ValueKey('courses-offline'),
                  icon: Icons.wifi_off_rounded,
                  title: l10n.coursesOfflineBanner,
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (resume != null) ...<Widget>[
              _ResumeCard(resume: resume),
              const SizedBox(height: 12),
            ],
            _FixedCourseCard(
              key: const ValueKey('courses-salah'),
              art: 'remembrance',
              title: l10n.salahTitle,
              subtitle: l10n.salahHint,
              onTap: () => context.push('/salah'),
            ),
            const SizedBox(height: 12),
            _FixedCourseCard(
              key: const ValueKey('courses-tajweed'),
              art: 'quran',
              title: l10n.tajweedCourseTitle,
              subtitle: l10n.tajweedCourseHint,
              onTap: () => context.push('/tajweed'),
            ),
            const SizedBox(height: 12),
            ...switch (catalog) {
              AsyncData(:final value) when value.courses.isEmpty => <Widget>[
                _EmptyNote(
                  text: value.offline
                      ? l10n.coursesOfflineEmpty
                      : l10n.coursesEmpty,
                ),
              ],
              AsyncData(:final value) => <Widget>[
                for (final course in value.courses) ...<Widget>[
                  _CourseCard(course: course),
                  const SizedBox(height: 12),
                ],
              ],
              AsyncError() => <Widget>[
                IqroStatusBanner(
                  key: const ValueKey('courses-error'),
                  icon: Icons.cloud_off_outlined,
                  title: l10n.coursesLoadFailed,
                  actionLabel: l10n.retry,
                  onAction: () => ref.invalidate(courseCatalogProvider),
                ),
              ],
              _ => <Widget>[const IqroLoading()],
            },
          ],
        ),
      ),
    );
  }
}

class _ResumeCard extends ConsumerWidget {
  const _ResumeCard({required this.resume});

  final CourseResume resume;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final resumeAt = resume.lesson.video == null
        ? null
        : ref
              .watch(coursePositionsProvider(resume.course.slug))
              .valueOrNull
              ?.of(resume.lesson.slug);
    return IqroCard(
      key: const ValueKey('courses-resume'),
      color: theme.colorScheme.primaryContainer,
      borderColor: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          IqroEyebrow(context.l10n.coursesContinue),
          Text(
            '${resume.course.title} · ${resume.lesson.title}',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFamilyFallback: const [IqroTheme.arabicFontFamily],
            ),
          ),
          if (resumeAt != null) ...<Widget>[
            const SizedBox(height: 3),
            Text(
              context.l10n.coursesVideoFrom(courseVideoTime(resumeAt)),
              key: const ValueKey('courses-resume-video'),
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => context.push(
              courseLessonPath(resume.course.slug, resume.lesson.slug),
            ),
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(context.l10n.coursesContinue),
          ),
        ],
      ),
    );
  }
}

/// The prayer and tajweed courses open their own screens.
class _FixedCourseCard extends StatelessWidget {
  const _FixedCourseCard({
    required this.art,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final String art;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IqroCard(
      onTap: onTap,
      child: Row(
        children: <Widget>[
          Container(
            width: 64,
            height: 64,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: context.iqroColors.sand,
              borderRadius: BorderRadius.circular(18),
            ),
            child: FittedBox(child: DuaThematicIcon(topic: art)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(subtitle, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

class _CourseCard extends ConsumerWidget {
  const _CourseCard({required this.course});

  final CourseSummary course;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final progress = ref.watch(courseProgressProvider(course.slug)).valueOrNull;
    // The count needs the lessons of the current version; a course with
    // progress was opened, so its document is usually stored.
    final document = progress == null || progress.isEmpty
        ? null
        : ref.watch(courseDocumentProvider(course.slug)).valueOrNull;
    final done = document == null ? 0 : progress!.doneCount(document);
    final total = document?.lessons.length ?? course.lessonCount;
    return IqroCard(
      key: ValueKey('course-${course.slug}'),
      padding: EdgeInsets.zero,
      onTap: () => context.push(coursePath(course.slug)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          CourseCoverImage(cover: course.cover, small: true),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  course.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFamilyFallback: const [IqroTheme.arabicFontFamily],
                  ),
                ),
                if (course.summary.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    course.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamilyFallback: const [IqroTheme.arabicFontFamily],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        courseMetaLabel(
                          context,
                          course.lessonCount,
                          course.minutes,
                        ),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (document != null)
                      CourseStatusChip(
                        key: ValueKey('course-status-${course.slug}'),
                        completed: done >= total,
                        label: done >= total
                            ? context.l10n.coursesStatusCompleted
                            : context.l10n.coursesStatusStarted(done, total),
                      ),
                  ],
                ),
                if (document != null) ...<Widget>[
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: total == 0 ? 0 : done / total,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(6),
                    backgroundColor: context.iqroColors.line,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// «Started · 2/8», «Completed».
class CourseStatusChip extends StatelessWidget {
  const CourseStatusChip({
    required this.label,
    required this.completed,
    super.key,
  });

  final String label;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: completed ? scheme.primaryContainer : context.iqroColors.sand,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: completed ? scheme.onPrimaryContainer : null,
          ),
        ),
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => IqroCard(
    key: const ValueKey('courses-empty'),
    color: context.iqroColors.panelSoft,
    borderColor: Colors.transparent,
    child: Row(
      children: <Widget>[
        Icon(Icons.auto_stories_outlined, color: context.iqroColors.gold),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    ),
  );
}
