import 'package:flutter/material.dart';

import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import 'course_models.dart';

/// First strong isolate and pop directional isolate around Arabic runs: a
/// run inside Russian text keeps its own order and does not reorder the
/// punctuation next to it.
const _isolateStart = '\u2068';
const _isolateEnd = '\u2069';

/// Arabic script is drawn larger than the text around it, as on the site.
const _arabicScale = 1.3;

/// The blocks of a lesson's notes. The server has parsed the markup; this
/// only draws the blocks, each in its own direction.
class CourseNotesView extends StatelessWidget {
  const CourseNotesView({required this.blocks, super.key});

  final List<NoteBlock> blocks;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      for (final (index, block) in blocks.indexed)
        Padding(
          padding: EdgeInsets.only(
            top: index == 0 ? 0 : (block is NoteHeading ? 20 : 12),
          ),
          child: Directionality(
            textDirection: block.direction,
            child: _Block(block),
          ),
        ),
    ],
  );
}

class _Block extends StatelessWidget {
  const _Block(this.block);

  final NoteBlock block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyLarge!.copyWith(height: 1.55);
    return switch (block) {
      NoteHeading(:final text) => Semantics(
        header: true,
        child: NoteText(
          [text],
          style: theme.textTheme.titleMedium!.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.3,
          ),
        ),
      ),
      NoteParagraph(:final lines) => NoteText(lines, style: body),
      NoteList(:final ordered, :final items) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final (index, item) in items.indexed)
            Padding(
              padding: EdgeInsets.only(top: index == 0 ? 0 : 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 24,
                    child: ordered
                        ? Text('${index + 1}.', style: body)
                        : Padding(
                            padding: const EdgeInsetsDirectional.only(top: 10),
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                  ),
                  Expanded(child: NoteText([item], style: body)),
                ],
              ),
            ),
        ],
      ),
      NoteQuote(:final lines, :final source) => DecoratedBox(
        decoration: BoxDecoration(
          color: context.iqroColors.panelSoft,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              NoteText(lines, style: body),
              if (source != null && source.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  '— $source',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFamilyFallback: const [IqroTheme.arabicFontFamily],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      NoteCallout(:final lines) => _Callout(lines: lines, style: body),
    };
  }
}

/// «Important»: the amber of the prayer course's warnings.
class _Callout extends StatelessWidget {
  const _Callout({required this.lines, required this.style});

  final List<NoteLine> lines;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fill = dark ? const Color(0xFF4A3410) : const Color(0xFFFEF3C7);
    final ink = dark ? const Color(0xFFFCD34D) : const Color(0xFF92400E);
    final border = dark ? const Color(0xFFF59E0B) : const Color(0xFFD97706);
    return Semantics(
      container: true,
      label: context.l10n.coursesImportant,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(16),
          border: BorderDirectional(start: BorderSide(color: border, width: 4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ExcludeSemantics(
              child: Row(
                children: <Widget>[
                  Icon(Icons.error_outline, size: 18, color: ink),
                  const SizedBox(width: 8),
                  Text(
                    context.l10n.coursesImportant,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            NoteText(lines, style: style, color: ink),
          ],
        ),
      ),
    );
  }
}

/// Lines of segments as one [Text.rich]: lines are joined by line breaks,
/// bold segments are bold, Arabic ones use the Arabic font and are isolated.
class NoteText extends StatelessWidget {
  const NoteText(this.lines, {required this.style, this.color, super.key});

  final List<NoteLine> lines;
  final TextStyle style;

  /// Of all the text; by default Arabic takes the theme's Arabic ink.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final arabic = style.copyWith(
      fontFamily: IqroTheme.arabicFontFamily,
      fontSize: (style.fontSize ?? 16) * _arabicScale,
      height: 1.5,
      color: color ?? IqroTheme.arabicInk(context),
    );
    return Text.rich(
      TextSpan(
        style: style.copyWith(color: color),
        children: <InlineSpan>[
          for (final (index, line) in lines.indexed) ...<InlineSpan>[
            if (index > 0) const TextSpan(text: '\n'),
            for (final segment in line)
              segment.arabic
                  ? TextSpan(
                      text: '$_isolateStart${segment.text}$_isolateEnd',
                      locale: const Locale('ar'),
                      style: segment.bold
                          ? arabic.copyWith(fontWeight: FontWeight.w700)
                          : arabic,
                    )
                  : TextSpan(
                      text: segment.text,
                      style: segment.bold
                          ? const TextStyle(fontWeight: FontWeight.w700)
                          : null,
                    ),
          ],
        ],
      ),
      textAlign: TextAlign.start,
    );
  }
}
