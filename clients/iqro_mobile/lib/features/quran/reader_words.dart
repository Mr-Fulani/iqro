import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'word_range.dart';

/// The reader's ayahs on screen, so a drag that leaves one card finds the
/// word under the finger in another.
class ReaderWordRegistry {
  final _ayahs = <int, _ReaderAyahWordsState>{};

  /// The word at [global], else the nearest word of the nearest ayah.
  QuranWord? wordAt(Offset global) {
    QuranWord? best;
    var distance = double.infinity;
    for (final state in _ayahs.values) {
      final found = state._nearest(global);
      if (found == null) continue;
      if (found.distance < distance) {
        best = found.word;
        distance = found.distance;
      }
    }
    return best;
  }
}

/// The Arabic text of one ayah in the reader, word by word. A long press
/// selects its word, and moving the finger on selects the words up to
/// another one, also in a neighbouring ayah. Taps go to the card.
class ReaderAyahWords extends StatefulWidget {
  const ReaderAyahWords({
    required this.surah,
    required this.ayah,
    required this.words,
    required this.style,
    required this.registry,
    required this.onRange,
    this.marker = '',
    this.firstPosition = 1,
    this.range,
    this.playingWord,
    this.onDrag,
    super.key,
  });

  final int surah;
  final int ayah;

  /// The words in order; the first is at [firstPosition].
  final List<String> words;
  final int firstPosition;

  /// Text after the last word: the ayah's end marker.
  final String marker;
  final TextStyle? style;
  final ReaderWordRegistry registry;
  final QuranWordRange? range;
  final QuranWord? playingWord;
  final ValueChanged<QuranWordRange> onRange;

  /// Follows the finger while it pulls the selection, in global coordinates.
  final ValueChanged<Offset>? onDrag;

  @override
  State<ReaderAyahWords> createState() => _ReaderAyahWordsState();
}

class _ReaderAyahWordsState extends State<ReaderAyahWords> {
  TextPainter? _painter;

  /// The text offset where each word starts, and the end of the last.
  var _offsets = const <int>[];
  QuranWord? _anchor;

  @override
  void initState() {
    super.initState();
    widget.registry._ayahs[widget.ayah] = this;
  }

  @override
  void didUpdateWidget(covariant ReaderAyahWords oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ayah != widget.ayah ||
        oldWidget.registry != widget.registry) {
      if (identical(oldWidget.registry._ayahs[oldWidget.ayah], this)) {
        oldWidget.registry._ayahs.remove(oldWidget.ayah);
      }
      widget.registry._ayahs[widget.ayah] = this;
    }
  }

  @override
  void dispose() {
    if (identical(widget.registry._ayahs[widget.ayah], this)) {
      widget.registry._ayahs.remove(widget.ayah);
    }
    _painter?.dispose();
    super.dispose();
  }

  QuranWord _word(int index) =>
      QuranWord(widget.surah, widget.ayah, widget.firstPosition + index);

  ({QuranWord word, double distance})? _nearest(Offset global) {
    final painter = _painter;
    final box = context.findRenderObject() as RenderBox?;
    if (painter == null || box == null || !box.attached || _offsets.isEmpty) {
      return null;
    }
    final local = box.globalToLocal(global);
    final size = box.size;
    final dy = local.dy < 0 ? -local.dy : math.max(0.0, local.dy - size.height);
    final point = Offset(
      local.dx.clamp(0.0, size.width),
      local.dy.clamp(0.0, size.height - 1),
    );
    final offset = painter.getPositionForOffset(point).offset;
    var index = 0;
    while (index < widget.words.length - 1 && offset >= _offsets[index + 1]) {
      index++;
    }
    return (word: _word(index), distance: dy);
  }

  void _pull(Offset global, QuranWord anchor) {
    widget.onDrag?.call(global);
    final word = widget.registry.wordAt(global);
    final range = word == null ? null : QuranWordRange.between(anchor, word);
    if (range != null && range != widget.range) widget.onRange(range);
  }

  TextSpan _span() {
    final range = widget.range;
    final children = <InlineSpan>[];
    final offsets = <int>[];
    var length = 0;
    for (final (index, text) in widget.words.indexed) {
      final word = _word(index);
      final selected = range?.contains(word) ?? false;
      if (index > 0) {
        final joined = selected && range!.contains(_word(index - 1));
        children.add(
          TextSpan(
            text: ' ',
            style: joined
                ? const TextStyle(backgroundColor: wordRangeSelectionColor)
                : null,
          ),
        );
        length += 1;
      }
      offsets.add(length);
      children.add(
        TextSpan(
          text: text,
          style: selected
              ? TextStyle(
                  backgroundColor: word == widget.playingWord
                      ? wordRangePlayingColor
                      : wordRangeSelectionColor,
                )
              : null,
        ),
      );
      length += text.length;
    }
    offsets.add(length);
    if (widget.marker.isNotEmpty) children.add(TextSpan(text: widget.marker));
    _offsets = offsets;
    return TextSpan(style: widget.style, children: children);
  }

  Rect? _wordBox(int index) {
    final painter = _painter;
    if (painter == null) return null;
    final boxes = painter.getBoxesForSelection(
      TextSelection(
        baseOffset: _offsets[index],
        extentOffset: _offsets[index] + widget.words[index].length,
      ),
    );
    if (boxes.isEmpty) return null;
    return boxes
        .map((box) => box.toRect())
        .reduce((a, b) => a.expandToInclude(b));
  }

  List<Widget> _handles() {
    final range = widget.range;
    if (range == null) return const [];
    int? indexOf(QuranWord word) =>
        word.surah == widget.surah && word.ayah == widget.ayah
        ? word.position - widget.firstPosition
        : null;
    final start = indexOf(range.start);
    final end = indexOf(range.end);
    Widget? handle(int? index, {required bool start}) {
      if (index == null || index < 0 || index >= widget.words.length) {
        return null;
      }
      final box = _wordBox(index);
      if (box == null) return null;
      return Positioned(
        key: ValueKey(
          start ? 'word-range-start-handle' : 'word-range-end-handle',
        ),
        left: (start ? box.right : box.left) - WordRangeHandle.width / 2,
        top: box.top,
        child: WordRangeHandle(
          start: start,
          lineHeight: box.height,
          onDrag: (point) => _pull(point, start ? range.end : range.start),
        ),
      );
    }

    return <Widget>[?handle(start, start: true), ?handle(end, start: false)];
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _painter?.dispose();
      final painter = TextPainter(
        text: _span(),
        textAlign: TextAlign.center,
        textDirection: TextDirection.rtl,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(minWidth: constraints.maxWidth, maxWidth: constraints.maxWidth);
      _painter = painter;
      return Semantics(
        label: widget.words.join(' '),
        textDirection: TextDirection.rtl,
        child: GestureDetector(
          onLongPressStart: (details) {
            final found = _nearest(details.globalPosition);
            if (found == null) return;
            _anchor = found.word;
            unawaited(HapticFeedback.selectionClick());
            widget.onRange(QuranWordRange.single(found.word));
          },
          onLongPressMoveUpdate: (details) {
            final anchor = _anchor;
            if (anchor != null) _pull(details.globalPosition, anchor);
          },
          onLongPressEnd: (_) => _anchor = null,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              CustomPaint(
                size: Size(constraints.maxWidth, painter.height),
                painter: _WordsPainter(painter),
              ),
              ..._handles(),
            ],
          ),
        ),
      );
    },
  );
}

class _WordsPainter extends CustomPainter {
  const _WordsPainter(this.painter);

  final TextPainter painter;

  @override
  void paint(Canvas canvas, Size size) => painter.paint(canvas, Offset.zero);

  @override
  bool shouldRepaint(_WordsPainter oldDelegate) =>
      !identical(oldDelegate.painter, painter);
}
