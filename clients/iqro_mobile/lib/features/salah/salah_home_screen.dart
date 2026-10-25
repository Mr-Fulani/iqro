import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_icon.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import '../courses/course_sources.dart';
import '../settings/offline_storage_screen.dart' show formatOfflineBytes;
import 'salah_models.dart';
import 'salah_offline_repository.dart';
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
          // «Author and sources» above the progress, as in a thematic course.
          if (document.course.source.isNotEmpty) ...<Widget>[
            CourseSourceBlock(source: document.course.source),
            const SizedBox(height: 16),
          ],
          _OverviewCard(document: document, progress: progress, onOpen: open),
          _OfflineCard(courseSlug: courseSlug),
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

/// Saves the course pictures for use without a network; the audio stays
/// streamed. Hidden while neither a package nor its manifest is known.
class _OfflineCard extends ConsumerWidget {
  const _OfflineCard({required this.courseSlug});

  final String courseSlug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(salahOfflineProvider(courseSlug));
    if (state.status == SalahOfflineStatus.notDownloaded &&
        state.totalBytes <= 0) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final controller = ref.read(salahOfflineProvider(courseSlug).notifier);
    final size = formatOfflineBytes(state.totalBytes);
    final downloading = state.status == SalahOfflineStatus.downloading;
    final ready = state.status == SalahOfflineStatus.ready;
    final subtitle = switch (state.status) {
      SalahOfflineStatus.notDownloaded =>
        '${context.l10n.salahOfflineImages} · $size',
      SalahOfflineStatus.downloading =>
        '${context.l10n.downloadInProgress} · ${(state.progress * 100).round()}%',
      SalahOfflineStatus.ready => '${context.l10n.salahOfflineSaved} · $size',
      SalahOfflineStatus.outdated =>
        '${context.l10n.salahOfflineUpdateAvailable} · $size',
      SalahOfflineStatus.failed => context.l10n.downloadFailed,
    };
    final action = switch (state.status) {
      SalahOfflineStatus.notDownloaded => context.l10n.downloadForOffline,
      SalahOfflineStatus.outdated => context.l10n.salahOfflineUpdate,
      SalahOfflineStatus.failed => context.l10n.retry,
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: IqroCard(
        key: const ValueKey('salah-offline'),
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: ready ? scheme.primary : context.iqroColors.sand,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    ready
                        ? Icons.offline_pin_outlined
                        : Icons.download_for_offline_outlined,
                    color: ready ? scheme.onPrimary : scheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        context.l10n.salahOfflineTitle,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        key: const ValueKey('salah-offline-status'),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (action != null)
                  TextButton(
                    key: const ValueKey('salah-offline-download'),
                    onPressed: controller.download,
                    child: Text(action),
                  )
                else if (ready)
                  IconButton(
                    key: const ValueKey('salah-offline-delete'),
                    tooltip: context.l10n.deleteOfflinePackage,
                    onPressed: () => _confirmDelete(context, controller, size),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
              ],
            ),
            if (downloading) ...<Widget>[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: LinearProgressIndicator(
                  value: state.totalBytes > 0 ? state.progress : null,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(6),
                  backgroundColor: context.iqroColors.line,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    SalahOfflineController controller,
    String size,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.deleteOfflinePackage),
        content: Text(
          context.l10n.deleteOfflinePackageConfirmation(
            context.l10n.salahOfflineImages,
            size,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.l10n.offlinePackageDeleteFailed;
    try {
      await controller.delete();
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
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
            child:
                status == SalahLessonStatus.notStarted && lesson.prayer != null
                ? IqroIcon(iqroSalahIcon, color: scheme.primary)
                : Icon(
                    switch (status) {
                      SalahLessonStatus.completed => Icons.check_rounded,
                      SalahLessonStatus.inProgress => Icons.play_arrow_rounded,
                      SalahLessonStatus.notStarted => Icons.menu_book_outlined,
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
                    ?lesson.prayer?.kindTitle,
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
