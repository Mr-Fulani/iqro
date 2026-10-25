import 'package:flutter/material.dart';

import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';

/// «Author and sources» of a course and «Sources» of a lesson: the same
/// blocks in thematic courses, the prayer course and tajweed
/// (docs/salah/sources.md). Callers leave them out without text.
class CourseSourceBlock extends StatelessWidget {
  const CourseSourceBlock({required this.source, super.key});

  final String source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          context.l10n.coursesSource,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          source,
          key: const ValueKey('course-source'),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontFamilyFallback: const [IqroTheme.arabicFontFamily],
          ),
        ),
      ],
    );
  }
}

/// «Sources» at the end of a lesson, folded by default, as on the site.
class CourseLessonSources extends StatefulWidget {
  const CourseLessonSources({required this.sources, super.key});

  final List<String> sources;

  @override
  State<CourseLessonSources> createState() => _CourseLessonSourcesState();
}

class _CourseLessonSourcesState extends State<CourseLessonSources> {
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
