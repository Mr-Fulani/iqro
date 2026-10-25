import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/iqro_theme.dart';
import 'course_feedback.dart';
import 'course_models.dart';

/// «Share» in the top bar of a course or a lesson: the system share sheet
/// with the title and the link to the page on the site.
class CourseShareButton extends ConsumerWidget {
  const CourseShareButton({required this.title, required this.url, super.key});

  final String title;
  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Builder(
      builder: (buttonContext) => IconButton(
        key: const ValueKey('course-share'),
        tooltip: context.l10n.coursesShare,
        icon: const Icon(Icons.share_outlined),
        onPressed: () {
          final box = buttonContext.findRenderObject();
          unawaited(
            ref.read(courseShareProvider)(
              ShareParams(
                text: '$title\n$url',
                subject: title,
                sharePositionOrigin: box is RenderBox
                    ? box.localToGlobal(Offset.zero) & box.size
                    : null,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// «Was this lesson helpful?» under the notes; one vote per lesson.
class LessonVoteCard extends ConsumerWidget {
  const LessonVoteCard({required this.course, required this.lesson, super.key});

  final String course;
  final String lesson;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final votes = ref.watch(courseVotesProvider(course)).valueOrNull;
    final voted = votes?[lesson];

    Future<void> vote(LessonVote choice) async {
      try {
        final counted = await ref
            .read(courseFeedbackStoreProvider)
            .vote(course: course, lesson: lesson, vote: choice);
        if (counted) {
          ref.read(courseEventQueueProvider).add(course, lesson, choice.event);
        }
      } on Object {
        // The vote is a courtesy; the lesson reads without it.
      }
      ref.invalidate(courseVotesProvider(course));
    }

    return IqroCard(
      key: const ValueKey('course-lesson-vote'),
      child: Semantics(
        liveRegion: true,
        child: voted != null
            ? Row(
                children: <Widget>[
                  Icon(
                    Icons.favorite_rounded,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.coursesVoteThanks,
                      key: const ValueKey('course-lesson-vote-thanks'),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    l10n.coursesVoteQuestion,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: <Widget>[
                      OutlinedButton.icon(
                        key: const ValueKey('course-lesson-helpful'),
                        onPressed: votes == null
                            ? null
                            : () => vote(LessonVote.helpful),
                        icon: const Icon(Icons.thumb_up_alt_outlined),
                        label: Text(l10n.coursesVoteHelpful),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('course-lesson-not-helpful'),
                        onPressed: votes == null
                            ? null
                            : () => vote(LessonVote.notHelpful),
                        icon: const Icon(Icons.thumb_down_alt_outlined),
                        label: Text(l10n.coursesVoteNotHelpful),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

/// «How helpful was the course?»: five stars and an optional comment. Only
/// the student's own rating is shown, never an average.
class CourseRatingCard extends ConsumerStatefulWidget {
  const CourseRatingCard({
    required this.course,
    required this.language,
    super.key,
  });

  final String course;

  /// The language of the document.
  final String language;

  @override
  ConsumerState<CourseRatingCard> createState() => _CourseRatingCardState();
}

class _CourseRatingCardState extends ConsumerState<CourseRatingCard> {
  final _comment = TextEditingController();
  var _editing = false;
  var _stars = 0;
  var _sending = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  void _edit(CourseRating? saved) {
    setState(() {
      _editing = true;
      _stars = saved?.stars ?? 0;
      _comment.text = saved?.comment ?? '';
      _error = null;
    });
  }

  Future<void> _send() async {
    final l10n = context.l10n;
    final comment = _comment.text.trim();
    setState(() {
      _sending = true;
      _error = null;
    });
    final queue = ref.read(courseEventQueueProvider);
    try {
      final answer = await ref
          .read(courseFeedbackGatewayProvider)
          .rate(widget.course, <String, Object?>{
            'stars': _stars,
            'comment': comment,
            'language': widget.language,
            'platform': queue.platform,
          });
      final updatedAt = answer is Map ? answer['updated_at'] : null;
      await ref
          .read(courseFeedbackStoreProvider)
          .saveRating(
            widget.course,
            stars: _stars,
            comment: comment,
            updatedAt: updatedAt is String ? updatedAt : null,
          );
      if (!mounted) return;
      ref.invalidate(courseRatingProvider(widget.course));
      setState(() {
        _sending = false;
        _editing = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = error is ApiException && error.statusCode == 429
            ? l10n.coursesSendTooOften
            : l10n.coursesSendFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final saved = ref.watch(courseRatingProvider(widget.course)).valueOrNull;
    final showForm = _editing || saved == null;
    return IqroCard(
      key: const ValueKey('course-rating'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(
              l10n.coursesRatingQuestion,
              style: theme.textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 8),
          if (!showForm)
            Semantics(
              liveRegion: true,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      l10n.coursesRatingThanks(saved.stars),
                      key: const ValueKey('course-rating-thanks'),
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('course-rating-change'),
                    onPressed: () => _edit(saved),
                    child: Text(l10n.coursesRatingChange),
                  ),
                ],
              ),
            )
          else ...<Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (var stars = 1; stars <= 5; stars++)
                  Semantics(
                    inMutuallyExclusiveGroup: true,
                    checked: _stars == stars,
                    label: l10n.coursesRatingStars(stars),
                    button: true,
                    excludeSemantics: true,
                    onTap: _sending
                        ? null
                        : () => setState(() => _stars = stars),
                    child: IconButton(
                      key: ValueKey('course-rating-star-$stars'),
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      onPressed: _sending
                          ? null
                          : () => setState(() => _stars = stars),
                      icon: Icon(
                        stars <= _stars
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 36,
                        color: stars <= _stars
                            ? context.iqroColors.gold
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('course-rating-comment'),
              controller: _comment,
              enabled: !_sending,
              minLines: 2,
              maxLines: 5,
              maxLength: maxCourseRatingComment,
              decoration: InputDecoration(
                labelText: l10n.coursesRatingComment,
                border: const OutlineInputBorder(),
              ),
            ),
            if (_error case final error?) ...<Widget>[
              Semantics(
                liveRegion: true,
                child: Text(
                  error,
                  key: const ValueKey('course-rating-error'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton(
                key: const ValueKey('course-rating-send'),
                onPressed: _stars == 0 || _sending ? null : _send,
                child: Text(l10n.coursesSend),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// «Report an error» next to the sources of a lesson.
class LessonReportButton extends StatelessWidget {
  const LessonReportButton({
    required this.document,
    required this.lesson,
    required this.playback,
    super.key,
  });

  final CourseDocument document;
  final CourseLesson lesson;

  /// Where the video is, when the student started it.
  final Duration? Function() playback;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        key: const ValueKey('course-lesson-report'),
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (_) => LessonReportSheet(
            document: document,
            lesson: lesson,
            playback: playback(),
          ),
        ),
        icon: const Icon(Icons.flag_outlined),
        label: Text(context.l10n.coursesReportError),
      ),
    );
  }
}

/// The report form; it files an ordinary feedback ticket pointing at the
/// lesson.
class LessonReportSheet extends ConsumerStatefulWidget {
  const LessonReportSheet({
    required this.document,
    required this.lesson,
    this.playback,
    super.key,
  });

  final CourseDocument document;
  final CourseLesson lesson;
  final Duration? playback;

  @override
  ConsumerState<LessonReportSheet> createState() => _LessonReportSheetState();
}

class _LessonReportSheetState extends ConsumerState<LessonReportSheet> {
  final _form = GlobalKey<FormState>();
  final _message = TextEditingController();
  final _email = TextEditingController();
  var _category = lessonReportCategories.first;
  var _sending = false;
  String? _error;
  String? _ticket;

  @override
  void dispose() {
    _message.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final l10n = context.l10n;
    setState(() {
      _sending = true;
      _error = null;
    });
    final document = widget.document;
    try {
      final ticket = await ref
          .read(feedbackRepositoryProvider)
          .create(
            category: _category,
            subject: lessonReportSubject(document, widget.lesson),
            message: _message.text,
            contactEmail: _email.text,
            route: lessonReportRoute(document.course.slug, widget.lesson.slug),
            locale: document.course.language,
            context: lessonReportContext(
              document,
              widget.lesson,
              playback: widget.playback,
            ),
          );
      if (!mounted) return;
      setState(() {
        _sending = false;
        _ticket = ticket.publicId;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = error is ApiException && error.statusCode == 429
            ? l10n.coursesSendTooOften
            : l10n.coursesSendFailed;
      });
    }
  }

  String _label(String category) => switch (category) {
    'religious_content' => context.l10n.coursesReportReligious,
    'accessibility_localization' => context.l10n.coursesReportTypo,
    'technical' => context.l10n.coursesReportTechnical,
    _ => context.l10n.coursesReportOther,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final ticket = _ticket;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ticket != null
            ? Column(
                key: const ValueKey('course-report-done'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      l10n.coursesReportThanks(ticket),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (ref.read(sessionProvider).valueOrNull?.isVerified ??
                      false)
                    FilledButton(
                      key: const ValueKey('course-report-open'),
                      onPressed: () {
                        Navigator.of(context).pop();
                        unawaited(
                          GoRouter.of(context).push('/feedback/$ticket'),
                        );
                      },
                      child: Text(l10n.coursesReportOpen),
                    )
                  else
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        MaterialLocalizations.of(context).closeButtonLabel,
                      ),
                    ),
                ],
              )
            : Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Semantics(
                      header: true,
                      child: Text(
                        l10n.coursesReportError,
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      lessonReportSubject(widget.document, widget.lesson),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      key: const ValueKey('course-report-type'),
                      initialValue: _category,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: l10n.coursesReportType,
                        border: const OutlineInputBorder(),
                      ),
                      items: <DropdownMenuItem<String>>[
                        for (final category in lessonReportCategories)
                          DropdownMenuItem(
                            value: category,
                            child: Text(
                              _label(category),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _sending
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _category = value);
                              }
                            },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const ValueKey('course-report-message'),
                      controller: _message,
                      enabled: !_sending,
                      minLines: 3,
                      maxLines: 8,
                      maxLength: maxLessonReportMessage,
                      decoration: InputDecoration(
                        labelText: l10n.coursesReportMessage,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) => (value ?? '').trim().isEmpty
                          ? l10n.coursesReportMessageRequired
                          : null,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: const ValueKey('course-report-email'),
                      controller: _email,
                      enabled: !_sending,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: InputDecoration(
                        labelText: l10n.coursesReportEmail,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    if (_error case final error?) ...<Widget>[
                      const SizedBox(height: 12),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          error,
                          key: const ValueKey('course-report-error'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const ValueKey('course-report-send'),
                      onPressed: _sending ? null : _send,
                      child: _sending
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(l10n.coursesSend),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
