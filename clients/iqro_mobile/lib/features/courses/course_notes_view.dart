import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

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

/// The first letter decides, as the server decides a block's `dir`.
final _strongLetter = RegExp(
  r'[A-Za-zÀ-ɏͰ-ϿЀ-ӿ'
  r'؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻿]',
);
final _arabicLetter = RegExp(r'[؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻿]');

TextDirection _firstStrongDirection(String text) {
  final letter = _strongLetter.firstMatch(text)?.group(0);
  return letter != null && _arabicLetter.hasMatch(letter)
      ? TextDirection.rtl
      : TextDirection.ltr;
}

/// The blocks of a lesson's notes. The server has parsed the markup; this
/// only draws the blocks, each in its own direction.
class CourseNotesView extends StatelessWidget {
  const CourseNotesView({
    required this.blocks,
    this.plainArabic = false,
    super.key,
  });

  final List<NoteBlock> blocks;

  /// Arabic runs in the text font: a tajweed lesson in Arabic keeps its look.
  final bool plainArabic;

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
            child: _Block(block, plainArabic: plainArabic),
          ),
        ),
    ],
  );
}

class _Block extends StatelessWidget {
  const _Block(this.block, {required this.plainArabic});

  final NoteBlock block;
  final bool plainArabic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyLarge!.copyWith(height: 1.55);
    return switch (block) {
      NoteHeading(:final text) => Semantics(
        header: true,
        child: NoteText(
          [text],
          plainArabic: plainArabic,
          style: theme.textTheme.titleMedium!.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.3,
          ),
        ),
      ),
      NoteParagraph(:final lines) => NoteText(
        lines,
        style: body,
        plainArabic: plainArabic,
      ),
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
                  Expanded(
                    child: NoteText(
                      [item],
                      style: body,
                      plainArabic: plainArabic,
                    ),
                  ),
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
              NoteText(lines, style: body, plainArabic: plainArabic),
              if (source != null && source.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                // At the block's start edge, in its own direction: «— Коран»
                // under an Arabic verse keeps the dash before the name.
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    '— $source',
                    textDirection: _firstStrongDirection(source),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFamilyFallback: const [IqroTheme.arabicFontFamily],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      NoteCallout(:final lines) => _Callout(
        lines: lines,
        style: body,
        plainArabic: plainArabic,
      ),
    };
  }
}

/// «Important»: the amber of the prayer course's warnings.
class _Callout extends StatelessWidget {
  const _Callout({
    required this.lines,
    required this.style,
    required this.plainArabic,
  });

  final List<NoteLine> lines;
  final TextStyle style;
  final bool plainArabic;

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
            NoteText(lines, style: style, color: ink, plainArabic: plainArabic),
          ],
        ),
      ),
    );
  }
}

/// Lines of segments as one [Text.rich]: lines are joined by line breaks,
/// bold segments are bold, Arabic ones use the Arabic font and are isolated.
/// A link opens its screen or the browser; a note is a «!» or «?» icon after
/// its word that opens the note in a bottom sheet.
class NoteText extends StatefulWidget {
  const NoteText(
    this.lines, {
    required this.style,
    this.color,
    this.plainArabic = false,
    super.key,
  });

  final List<NoteLine> lines;
  final TextStyle style;

  /// Of all the text; by default Arabic takes the theme's Arabic ink.
  final Color? color;

  /// Arabic runs in the text font, without the Arabic font and its size.
  final bool plainArabic;

  @override
  State<NoteText> createState() => _NoteTextState();
}

class _NoteTextState extends State<NoteText> {
  /// One recognizer per link segment, kept while the text is shown.
  final _taps = <String, TapGestureRecognizer>{};

  @override
  void dispose() {
    for (final tap in _taps.values) {
      tap.dispose();
    }
    super.dispose();
  }

  TapGestureRecognizer _tap(String key, NoteLink link) =>
      (_taps[key] ??= TapGestureRecognizer())
        ..onTap = () => unawaited(openNoteLink(context, link));

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final arabic = style.copyWith(
      fontFamily: IqroTheme.arabicFontFamily,
      fontSize: (style.fontSize ?? 16) * _arabicScale,
      height: 1.5,
      color: widget.color ?? IqroTheme.arabicInk(context),
    );
    final linkColor = widget.color ?? Theme.of(context).colorScheme.primary;
    TextStyle? textStyle(NoteSegment segment) {
      final base = segment.arabic && !widget.plainArabic ? arabic : null;
      final bold = segment.bold
          ? (base ?? const TextStyle()).copyWith(fontWeight: FontWeight.w700)
          : base;
      if (segment.link == null) return bold;
      return (bold ?? const TextStyle()).copyWith(
        color: linkColor,
        decoration: TextDecoration.underline,
        decorationColor: linkColor,
      );
    }

    return Text.rich(
      TextSpan(
        style: style.copyWith(color: widget.color),
        children: <InlineSpan>[
          for (final (index, line) in widget.lines.indexed) ...<InlineSpan>[
            if (index > 0) const TextSpan(text: '\n'),
            for (final (position, segment) in line.indexed)
              if (segment.note case final note?)
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: NoteMarkButton(mark: note),
                )
              else ...<InlineSpan>[
                TextSpan(
                  text: segment.arabic && !widget.plainArabic
                      ? '$_isolateStart${segment.text}$_isolateEnd'
                      : segment.text,
                  locale: segment.arabic ? const Locale('ar') : null,
                  style: textStyle(segment),
                  recognizer: segment.link == null
                      ? null
                      : _tap('$index/$position', segment.link!),
                ),
                // A link to another site says so: «↗» and, read aloud, where it opens.
                if (segment.link case final link?
                    when link.external &&
                        line.elementAtOrNull(position + 1)?.link?.href !=
                            link.href)
                  TextSpan(
                    text: ' ↗',
                    semanticsLabel:
                        ' (${context.l10n.coursesLinkOpensBrowser})',
                    style: textStyle(
                      segment,
                    )?.copyWith(decoration: TextDecoration.none),
                    recognizer: _tap('$index/$position', link),
                  ),
              ],
          ],
        ],
      ),
      textAlign: TextAlign.start,
    );
  }
}

/// Opens a link of the notes: an internal one on its screen, another site in
/// the browser.
Future<void> openNoteLink(BuildContext context, NoteLink link) async {
  if (!link.external) {
    final route = link.route;
    if (route != null) unawaited(GoRouter.of(context).push(route));
    return;
  }
  try {
    await launchUrl(Uri.parse(link.href), mode: LaunchMode.externalApplication);
  } on Object {
    // No browser: the text stays as it is.
  }
}

/// The colours of a note's icon, as in the prayer course: the course's green
/// for help, amber for a warning.
({Color fill, Color ink, Color border}) noteMarkColors(
  BuildContext context,
  NoteMarkKind kind,
) {
  final scheme = Theme.of(context).colorScheme;
  final dark = Theme.of(context).brightness == Brightness.dark;
  if (kind == NoteMarkKind.warning) {
    return dark
        ? (
            fill: const Color(0xFF4A3410),
            ink: const Color(0xFFFCD34D),
            border: const Color(0xFFF59E0B),
          )
        : (
            fill: const Color(0xFFFEF3C7),
            ink: const Color(0xFF92400E),
            border: const Color(0xFFD97706),
          );
  }
  return (
    fill: scheme.primaryContainer,
    ink: scheme.onPrimaryContainer,
    border: scheme.primary.withValues(alpha: .55),
  );
}

String noteMarkLabel(BuildContext context, NoteMarkKind kind) =>
    kind == NoteMarkKind.warning
    ? context.l10n.coursesMarkWarning
    : context.l10n.coursesMarkHelp;

/// «!» or «?» after a word: a 22 dp circle in a 44 dp tap target.
class NoteMarkButton extends StatelessWidget {
  const NoteMarkButton({required this.mark, super.key});

  final NoteMark mark;

  @override
  Widget build(BuildContext context) {
    final colors = noteMarkColors(context, mark.kind);
    final label = noteMarkLabel(context, mark.kind);
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      // Its own node: the paragraph around it stays text, not a button.
      child: Semantics(
        container: true,
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkResponse(
          key: ValueKey('course-note-mark-${mark.kind.name}'),
          onTap: () => showNoteMark(context, mark),
          radius: 22,
          child: SizedBox.square(
            dimension: 44,
            child: Center(
              child: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.fill,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.border, width: 1.5),
                ),
                child: Text(
                  mark.kind == NoteMarkKind.warning ? '!' : '?',
                  style: TextStyle(
                    color: colors.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The note in a bottom sheet: a tap outside, a swipe down, «Close» or Esc
/// closes it.
Future<void> showNoteMark(BuildContext context, NoteMark mark) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => _NoteMarkSheet(mark: mark),
    );

class _NoteMarkSheet extends StatelessWidget {
  const _NoteMarkSheet({required this.mark});

  final NoteMark mark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = noteMarkColors(context, mark.kind);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 12, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.fill,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.border, width: 1.5),
                ),
                child: ExcludeSemantics(
                  child: Text(
                    mark.kind == NoteMarkKind.warning ? '!' : '?',
                    style: TextStyle(
                      color: colors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    noteMarkLabel(context, mark.kind),
                    key: const ValueKey('course-note-sheet-title'),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('course-note-sheet-close'),
                tooltip: context.l10n.coursesMarkClose,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(
            child: SingleChildScrollView(
              child: Directionality(
                textDirection: _firstStrongDirection(
                  mark.text.map((segment) => segment.text).join(),
                ),
                child: NoteText(
                  [mark.text],
                  key: const ValueKey('course-note-sheet-text'),
                  style: theme.textTheme.bodyLarge!.copyWith(height: 1.55),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
