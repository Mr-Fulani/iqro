import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import 'mushaf_paper.dart';
import 'quran_models.dart';

final _fontLoads = <String, Future<void>>{};

class FoundationPageResources {
  FoundationPageResources({
    this.fontFamily,
    this.decorationFontFamily,
    this.images = const {},
  });
  final String? fontFamily;
  final String? decorationFontFamily;
  final Map<int, ui.Image> images;
  void dispose() {
    for (final image in images.values) {
      image.dispose();
    }
  }
}

/// Load only the opened page's official font or word images. Downloaded files
/// have verified local checksums and are reusable on an offline reopening.
Future<FoundationPageResources> loadFoundationPageResources(
  FoundationMushafPage page,
  Future<File> Function(Uri uri, String version) asset,
) async {
  Future<String> loadFont(String url) async {
    final uri = Uri.parse(url);
    final family =
        'qf-${sha256.convert(Uint8List.fromList('$uri:${page.sourceChecksum}'.codeUnits)).toString().substring(0, 20)}';
    final request = _fontLoads.putIfAbsent(family, () async {
      final file = await asset(uri, page.sourceChecksum);
      final loader = FontLoader(family)
        ..addFont(file.readAsBytes().then(ByteData.sublistView));
      await loader.load();
    });
    try {
      await request;
    } on Object {
      _fontLoads.remove(family);
      rethrow;
    }
    return family;
  }

  final decorationFamily = page.hasQulLayout
      ? await loadFont(page.layout['native_decoration_font_url'] as String)
      : null;
  if (page.rendering['mode'] != 'word-images') {
    return FoundationPageResources(
      fontFamily: await loadFont(page.rendering['native_font_url'] as String),
      decorationFontFamily: decorationFamily,
    );
  }
  final images = <int, ui.Image>{};
  var next = 0;
  Future<void> worker() async {
    while (next < page.words.length) {
      final word = page.words[next++];
      final file = await asset(
        Uri.parse(word['image_url'] as String),
        page.sourceChecksum,
      );
      final codec = await ui.instantiateImageCodec(await file.readAsBytes());
      try {
        images[(word['id'] as num).toInt()] =
            (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    }
  }

  try {
    await Future.wait(List.generate(4, (_) => worker()));
    return FoundationPageResources(
      images: images,
      decorationFontFamily: decorationFamily,
    );
  } on Object {
    for (final image in images.values) {
      image.dispose();
    }
    rethrow;
  }
}

class FoundationMushafPageContent extends ConsumerStatefulWidget {
  const FoundationMushafPageContent({
    required this.page,
    required this.selected,
    required this.playing,
    required this.onSelect,
    required this.onOpen,
    required this.onBackgroundTap,
    this.surahs = const [],
    this.excerpt = false,
    super.key,
  });
  final FoundationMushafPage page;
  final QuranAyahReference? selected;
  final QuranAyahReference? playing;
  final ValueChanged<QuranAyahReference> onSelect;
  final ValueChanged<QuranAyahReference> onOpen;
  final VoidCallback onBackgroundTap;
  final List<Surah> surahs;
  final bool excerpt;
  @override
  ConsumerState<FoundationMushafPageContent> createState() =>
      _FoundationContentState();
}

class _FoundationContentState
    extends ConsumerState<FoundationMushafPageContent> {
  Future<FoundationPageResources>? _loading;
  FoundationPageResources? _resources;
  var _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant FoundationMushafPageContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page != widget.page) _load();
  }

  void _load() {
    final generation = ++_generation;
    _resources?.dispose();
    _resources = null;
    _loading =
        loadFoundationPageResources(
          widget.page,
          ref.read(selectedMushafRepositoryProvider).foundationAsset,
        ).then((resources) {
          if (!mounted || generation != _generation) {
            resources.dispose();
            throw StateError('Obsolete page');
          }
          _resources = resources;
          return resources;
        });
  }

  @override
  void dispose() {
    _generation++;
    _resources?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<FoundationPageResources>(
    future: _loading,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return IqroAsyncError(
          title: context.l10n.noQuranData,
          message: context.l10n.networkError,
          onRetry: () => setState(_load),
        );
      }
      if (snapshot.connectionState != ConnectionState.done ||
          !snapshot.hasData ||
          snapshot.data != _resources) {
        return const IqroLoading();
      }
      return FoundationPageCanvas(
        page: widget.page,
        resources: snapshot.data!,
        selected: widget.selected,
        playing: widget.playing,
        onSelect: widget.onSelect,
        onOpen: widget.onOpen,
        onBackgroundTap: widget.onBackgroundTap,
        surahs: widget.surahs,
        excerpt: widget.excerpt,
      );
    },
  );
}

/// Text is shaped by Flutter with the provider font. The painted word boxes
/// also define hit testing, so zoom, selection and audio use the same geometry.
class FoundationPageCanvas extends StatefulWidget {
  const FoundationPageCanvas({
    required this.page,
    required this.resources,
    required this.selected,
    required this.playing,
    required this.onSelect,
    required this.onOpen,
    required this.onBackgroundTap,
    this.surahs = const [],
    this.excerpt = false,
    super.key,
  });
  final FoundationMushafPage page;
  final FoundationPageResources resources;
  final QuranAyahReference? selected;
  final QuranAyahReference? playing;
  final ValueChanged<QuranAyahReference> onSelect;
  final ValueChanged<QuranAyahReference> onOpen;
  final VoidCallback onBackgroundTap;
  final List<Surah> surahs;
  final bool excerpt;
  @override
  State<FoundationPageCanvas> createState() => _FoundationCanvasState();
}

class _FoundationCanvasState extends State<FoundationPageCanvas> {
  FoundationPageLayout? _layout;
  @override
  void didUpdateWidget(covariant FoundationPageCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page != widget.page ||
        oldWidget.resources != widget.resources ||
        oldWidget.surahs != widget.surahs) {
      _layout?.dispose();
      _layout = null;
    }
  }

  @override
  void dispose() {
    _layout?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = Size(
        constraints.maxWidth,
        widget.excerpt
            ? constraints.maxWidth * 1380 / 900
            : constraints.maxHeight,
      );
      if (_layout?.size != size) {
        _layout?.dispose();
        _layout = FoundationPageLayout(
          widget.page,
          widget.resources,
          size,
          widget.surahs,
        );
      }
      final layout = _layout!;
      if (widget.excerpt) {
        final words = layout.words.where(
          (word) => word.reference == widget.selected,
        );
        if (words.isEmpty) return const SizedBox.shrink();
        final top = math.max(
          0.0,
          words.map((word) => word.rect.top).reduce(math.min) - 4,
        );
        final bottom = math.min(
          size.height,
          words.map((word) => word.rect.bottom).reduce(math.max) + 4,
        );
        return CustomPaint(
          size: Size(size.width, bottom - top),
          painter: FoundationPagePainter(
            layout,
            null,
            null,
            onlyAyah: widget.selected,
            top: top,
          ),
        );
      }
      QuranAyahReference? at(Offset point) => layout.words
          .where((w) => w.rect.contains(point))
          .firstOrNull
          ?.reference;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          final ayah = at(details.localPosition);
          if (ayah == null) {
            widget.onBackgroundTap();
          } else {
            widget.onSelect(ayah);
          }
        },
        onLongPressStart: (details) {
          final ayah = at(details.localPosition);
          if (ayah != null) widget.onOpen(ayah);
        },
        child: CustomPaint(
          size: size,
          painter: FoundationPagePainter(
            layout,
            widget.selected,
            widget.playing,
          ),
        ),
      );
    },
  );
}

class _WordPaint {
  _WordPaint(this.reference, this.painter, this.image);
  final QuranAyahReference reference;
  final TextPainter? painter;
  final ui.Image? image;
  late Rect rect;
  double get width => painter?.width ?? image!.width.toDouble();
  double get height => painter?.height ?? image!.height.toDouble();
  double get baseline =>
      painter?.computeDistanceToActualBaseline(TextBaseline.alphabetic) ??
      height / 2;
}

class FoundationPageLayout {
  FoundationPageLayout(
    FoundationMushafPage page,
    FoundationPageResources resources,
    this.size,
    List<Surah> surahs,
  ) {
    final lines = <int, List<_WordPaint>>{};
    for (final word in page.words) {
      final key = (word['verse_key'] as String).split(':');
      final reference = QuranAyahReference(
        id: '',
        surah: int.parse(key[0]),
        ayah: int.parse(key[1]),
      );
      final image = resources.images[(word['id'] as num).toInt()];
      TextPainter? text;
      if (image == null) {
        final runs = word['text_runs'] as List?;
        final overrideBidi = (word['css_class']?.toString() ?? '')
            .split(RegExp(r'\s+'))
            .contains('bidi-override');
        text = TextPainter(
          textDirection: TextDirection.rtl,
          textScaler: TextScaler.noScaling,
          text: TextSpan(
            style: TextStyle(
              fontFamily: resources.fontFamily,
              fontSize: 56,
              height: 1.6,
              color: mushafInkColor,
            ),
            text: runs == null
                ? (overrideBidi
                      ? '\u202e${word['text']}\u202c'
                      : word['text'] as String)
                : null,
            children: runs
                ?.whereType<Map>()
                .map(
                  (run) => TextSpan(
                    text: run['text'] as String,
                    style:
                        run['color'] is String &&
                            RegExp(
                              r'^#[0-9a-fA-F]{6}$',
                            ).hasMatch(run['color'] as String)
                        ? TextStyle(
                            color: Color(
                              0xff000000 |
                                  int.parse(
                                    (run['color'] as String).substring(1),
                                    radix: 16,
                                  ),
                            ),
                          )
                        : null,
                  ),
                )
                .toList(),
          ),
        )..layout();
      }
      final entry = _WordPaint(reference, text, image);
      lines
          .putIfAbsent((word['line_number'] as num).toInt(), () => [])
          .add(entry);
      words.add(entry);
    }
    final paddingX = size.width * .06;
    final paddingY = size.height * .035;
    final rowHeight = (size.height - 2 * paddingY) / page.linesPerPage;
    final availableWidth = size.width - 2 * paddingX;
    final roles = {
      for (final row in page.layoutLines)
        (row['line_number'] as num).toInt(): row,
    };
    var scale = 1.0;
    const gap = 3.5;
    for (final line in lines.values) {
      final width =
          line.fold(0.0, (sum, word) => sum + word.width) +
          gap * (line.length - 1);
      final ascent = line.map((word) => word.baseline).reduce(math.max);
      final descent = line
          .map((word) => word.height - word.baseline)
          .reduce(math.max);
      final height = page.hasQulLayout
          ? ascent + descent
          : line.map((word) => word.height).reduce(math.max);
      scale = math.min(
        scale,
        math.min(availableWidth / width, rowHeight / height),
      );
    }
    final firstLine = lines.keys.reduce(math.min);
    final offset = page.pageNumber > 2
        ? 0.0
        : page.hasQulLayout
        ? (page.linesPerPage - roles.keys.reduce(math.max)) / 2
        : -((firstLine - 1) ~/ 2).toDouble();
    for (final entry in lines.entries) {
      final line = entry.value;
      final inkWidth = line.fold(0.0, (sum, word) => sum + word.width);
      final centered =
          !page.hasQulLayout || roles[entry.key]?['is_centered'] != false;
      final lineGap = centered || line.length < 2
          ? gap
          : math.max(
              gap,
              (availableWidth / scale - inkWidth) / (line.length - 1),
            );
      final width = (inkWidth + lineGap * (line.length - 1)) * scale;
      var right = (size.width + width) / 2;
      final centerY = paddingY + (entry.key + offset - .5) * rowHeight;
      final ascent = line.map((word) => word.baseline).reduce(math.max);
      final descent = line
          .map((word) => word.height - word.baseline)
          .reduce(math.max);
      final baseline = centerY + (ascent - descent) * scale / 2;
      for (final word in line) {
        final width = word.width * scale;
        final height = word.height * scale;
        word.rect = Rect.fromLTWH(
          right - width,
          page.hasQulLayout
              ? baseline - word.baseline * scale
              : centerY - height / 2,
          width,
          height,
        );
        right -= width + lineGap * scale;
      }
    }
    if (page.hasQulLayout) {
      for (final row in page.layoutLines) {
        final kind = row['line_type'];
        if (kind == 'ayah') continue;
        final name = surahs
            .where((s) => s.number == row['surah_number'])
            .firstOrNull
            ?.nameAr;
        if (kind == 'surah_name' && name == null) continue;
        _decoration(
          kind == 'basmallah'
              ? 'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ'
              : 'سُورَةُ $name',
          (row['line_number'] as num).toDouble() + offset,
          rowHeight,
          paddingY,
          size.width * (kind == 'basmallah' ? .045 : .038),
          fontFamily: resources.decorationFontFamily,
        );
      }
      return;
    }
    for (final reference in page.ayahReferences.where((r) => r.ayah == 1)) {
      final firstWord = page.words.firstWhere(
        (w) => w['verse_key'] == reference.key,
      );
      if (firstWord['position_in_verse'] != 1) continue;
      final line = (firstWord['line_number'] as num).toInt();
      if (line <= 1 || lines.containsKey(line - 1)) continue;
      final name = surahs
          .where((s) => s.number == reference.surah)
          .firstOrNull
          ?.nameAr;
      if (reference.surah != 1 && reference.surah != 9) {
        _decoration(
          'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
          line - 1 + offset,
          rowHeight,
          paddingY,
          size.width * .045,
        );
      }
      if (name != null &&
          reference.surah > 2 &&
          line > 2 &&
          !lines.containsKey(line - 2)) {
        _decoration(
          'سُورَةُ $name',
          line - 2 + offset,
          rowHeight,
          paddingY,
          size.width * .038,
        );
      }
    }
  }
  final Size size;
  final words = <_WordPaint>[];
  final decorations = <(TextPainter, Offset)>[];
  void _decoration(
    String value,
    double line,
    double height,
    double top,
    double fontSize, {
    String? fontFamily,
  }) {
    final text = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: mushafInkColor,
          fontSize: fontSize,
          fontFamily: fontFamily,
        ),
      ),
      textDirection: TextDirection.rtl,
    )..layout(maxWidth: size.width * .9);
    decorations.add((
      text,
      Offset(
        (size.width - text.width) / 2,
        top + (line - .5) * height - text.height / 2,
      ),
    ));
  }

  void dispose() {
    for (final word in words) {
      word.painter?.dispose();
    }
    for (final decoration in decorations) {
      decoration.$1.dispose();
    }
  }
}

class FoundationPagePainter extends CustomPainter {
  FoundationPagePainter(
    this.layout,
    this.selected,
    this.playing, {
    this.onlyAyah,
    this.top = 0,
  });
  final FoundationPageLayout layout;
  final QuranAyahReference? selected;
  final QuranAyahReference? playing;
  final QuranAyahReference? onlyAyah;
  final double top;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(0, -top);
    for (final word in layout.words) {
      if (onlyAyah != null && word.reference != onlyAyah) continue;
      if (word.reference == selected || word.reference == playing) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            word.rect.inflate(1.5),
            const Radius.circular(3),
          ),
          Paint()
            ..color = word.reference == playing
                ? const Color(0x40459B73)
                : const Color(0x30857154),
        );
      }
      if (word.image != null) {
        canvas.drawImageRect(
          word.image!,
          Rect.fromLTWH(
            0,
            0,
            word.image!.width.toDouble(),
            word.image!.height.toDouble(),
          ),
          word.rect,
          Paint()..filterQuality = FilterQuality.high,
        );
      } else {
        canvas.save();
        canvas.translate(word.rect.left, word.rect.top);
        canvas.scale(word.rect.width / word.width);
        word.painter!.paint(canvas, Offset.zero);
        canvas.restore();
      }
    }
    if (onlyAyah == null) {
      for (final decoration in layout.decorations) {
        decoration.$1.paint(canvas, decoration.$2);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(FoundationPagePainter oldDelegate) =>
      layout != oldDelegate.layout ||
      selected != oldDelegate.selected ||
      playing != oldDelegate.playing ||
      onlyAyah != oldDelegate.onlyAyah ||
      top != oldDelegate.top;
}
