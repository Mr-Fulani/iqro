import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/network/public_asset_uri.dart';
import 'course_models.dart';

const coursesPath = '/courses';

String coursePath(String course) => '/courses/${Uri.encodeComponent(course)}';

String courseLessonPath(String course, String lesson) =>
    '${coursePath(course)}/${Uri.encodeComponent(lesson)}';

const _approvedCoverHosts = <String>{'media.iqro.forum'};

/// «1 h 18 min», «30 min»; empty for nothing.
String courseDurationLabel(BuildContext context, int minutes) {
  final l10n = context.l10n;
  if (minutes <= 0) return '';
  if (minutes < 60) return l10n.salahMinutes(minutes);
  final rest = minutes % 60;
  return rest == 0
      ? l10n.coursesHours(minutes ~/ 60)
      : l10n.coursesHoursMinutes(minutes ~/ 60, rest);
}

/// «3 topics · 30 min».
String courseMetaLabel(BuildContext context, int lessons, int minutes) {
  final duration = courseDurationLabel(context, minutes);
  final count = context.l10n.coursesLessonCount(lessons);
  return duration.isEmpty ? count : '$count · $duration';
}

/// A 16:9 cover; the course's green with a book while it loads, when it
/// cannot, and for a course without one.
class CourseCoverImage extends ConsumerWidget {
  const CourseCoverImage({required this.cover, this.small = false, super.key});

  final CourseCover? cover;

  /// Cards take the small copy.
  final bool small;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const placeholder = _CoverPlaceholder();
    final cover = this.cover;
    Widget image = placeholder;
    if (cover != null) {
      final base = Uri.parse(ref.watch(appConfigProvider).apiBaseUrl);
      final uri = base.resolve(small ? cover.cardUrl : cover.url);
      if (isApprovedPublicAssetUri(
        uri,
        allowedHosts: _approvedCoverHosts,
        localApiBase: base,
      )) {
        image = Image(
          image: ref.watch(courseImageProvider)(uri.toString()),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, synchronous) =>
              frame == null && !synchronous ? placeholder : child,
          errorBuilder: (context, error, stackTrace) => placeholder,
        );
      }
    }
    return ExcludeSemantics(
      child: AspectRatio(aspectRatio: 16 / 9, child: image),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          Color(0xFF0B5D4A),
          Color(0xFF073E34),
          Color(0xFF061D18),
        ],
        stops: <double>[0, .62, 1],
      ),
    ),
    child: Center(
      child: Icon(Icons.menu_book_outlined, size: 48, color: Color(0x80D5A34C)),
    ),
  );
}

/// Why a course or a lesson cannot be shown, with what can be done.
class CourseProblem extends StatelessWidget {
  const CourseProblem({required this.error, required this.onRetry, super.key});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final (icon, title, message, retry) = switch (error) {
      CourseNeedsUpdate() => (
        Icons.system_update_outlined,
        l10n.coursesUpdateApp,
        l10n.coursesUpdateAppMessage,
        false,
      ),
      CourseUnavailable() => (
        Icons.visibility_off_outlined,
        l10n.coursesUnavailable,
        null,
        true,
      ),
      _ => (Icons.cloud_off_outlined, l10n.coursesLoadFailed, null, true),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 42, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            if (message != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(message, textAlign: TextAlign.center),
            ],
            if (retry) ...<Widget>[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.retry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
