import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design_system/iqro_widgets.dart';
import '../theme/iqro_theme.dart';
import 'share_card_layout.dart';

/// Shared links always point at the public site, whatever API the build
/// talks to: a local or staging address means nothing to the recipient.
/// With the app installed the site's app links open it instead.
const iqroPublicSite = 'https://iqro.forum';

String ayahShareUrl(String locale, int surah, int ayah) =>
    '$iqroPublicSite/$locale/quran/madani-hafs/surah/$surah/ayah/$ayah';

String duaShareUrl(String locale, String collection, int sourceNumber) =>
    '$iqroPublicSite/$locale/dua/$collection/$sourceNumber';

/// What is shared: an ayah or a du'a, already in the reader's language.
class ContentShare {
  const ContentShare({
    required this.title,
    required this.arabic,
    required this.url,
    required this.readInIqro,
    this.arabicGlyphs = const [],
    this.arabicEnd = '',
    this.cardReference = '',
    this.translation = '',
    this.note = '',
    this.reference = '',
  });

  /// «Аль-Бакара · 2:255», or the du'a's chapter.
  final String title;
  final String arabic;

  /// The picture's Arabic word by word in the fonts of the selected Mushaf,
  /// the ayah's end sign with the last word; empty draws [arabic].
  final List<InlineSpan> arabicGlyphs;

  /// The end sign of an ayah drawn from [arabic], «۝٢٨٦»: the picture has
  /// it, the message does not.
  final String arabicEnd;

  /// The line under the meaning on the picture: «Аль-Бакара · 2:286», or
  /// the du'a's source.
  final String cardReference;
  final String translation;

  /// A practical line, such as how many times a du'a is said.
  final String note;

  /// Where it comes from: the du'a's source, shown under the meaning.
  final String reference;
  final String url;

  /// «Читать в IQRO» in the reader's language.
  final String readInIqro;
}

/// The message: the title, the Arabic, the meaning in quotes, the source
/// and the link.
String contentShareText(ContentShare share) {
  final blocks = <String>[
    share.title.trim(),
    share.arabic.trim(),
    if (share.translation.trim().isNotEmpty) '«${share.translation.trim()}»',
    if (share.note.trim().isNotEmpty) share.note.trim(),
    if (share.reference.trim().isNotEmpty) share.reference.trim(),
    '${share.readInIqro}: ${share.url}',
  ];
  return blocks.where((block) => block.isNotEmpty).join('\n\n');
}

/// Opens the share sheet: the picture of the text on silk, one card or a
/// series, in the shape and colour the user picks; «Share» sends the cards
/// with the message. A text too long for a series, or a picture that cannot
/// be drawn, goes as the message alone. True once the user picked where to
/// send it.
Future<bool> shareContent(
  BuildContext context,
  ContentShare share, {
  Rect? origin,
}) async {
  final shared = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ShareCardSheet(share: share, origin: origin),
  );
  return shared ?? false;
}

/// The fabric colours of the card, as `layout.json` names them.
const shareCardColours = <String, Color>{
  'emerald': Color(0xFF074D45),
  'turquoise': Color(0xFF2E6A63),
  'midnight': Color(0xFF1A2A4B),
};

const _stylePreference = 'iqro_share_card_style_v1';

/// The card's backgrounds and layout, loaded once from the app's assets.
class ShareCardAssets {
  ShareCardAssets._();

  static ShareCardLayout? _layout;
  static final _backgrounds = <String, ui.Image>{};

  static Future<ShareCardLayout> layout() async =>
      _layout ??= ShareCardLayout.parse(
        await rootBundle.loadString('assets/share_card/layout.json'),
      );

  static Future<ui.Image> background(
    ShareCardFormat format,
    String colour,
  ) async {
    final name = '${format.name}-$colour';
    final cached = _backgrounds[name];
    if (cached != null) return cached;
    final data = await rootBundle.load('assets/share_card/$name.webp');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    return _backgrounds[name] = (await codec.getNextFrame()).image;
  }
}

/// A text measured for the card: its words and their widths in em.
class ShareCardText {
  ShareCardText(ContentShare share)
    : arabicWords = share.arabicGlyphs.isNotEmpty
          ? share.arabicGlyphs
          : _plainArabic(share),
      translationWords = share.translation.trim().isEmpty
          ? const []
          : '«${share.translation.trim()}»'.split(_spaces);

  static final _spaces = RegExp(r'\s+');

  // The end sign stays with the last word.
  static List<InlineSpan> _plainArabic(ContentShare share) {
    final words = share.arabic.trim().split(_spaces);
    if (share.arabicEnd.isNotEmpty) {
      words.last = '${words.last} ${share.arabicEnd}';
    }
    return [for (final word in words) TextSpan(text: word)];
  }

  final List<InlineSpan> arabicWords;
  final List<String> translationWords;

  static double _em(InlineSpan span, String family, TextDirection direction) {
    final painter = TextPainter(
      text: TextSpan(
        style: TextStyle(fontFamily: family, fontSize: 100),
        children: [span],
      ),
      textDirection: direction,
      maxLines: 1,
    )..layout();
    final width = painter.width / 100;
    painter.dispose();
    return width;
  }

  late final ShareCardWords arabic = (
    widths: [
      for (final word in arabicWords)
        _em(word, IqroTheme.arabicFontFamily, TextDirection.rtl),
    ],
    space: _em(
      const TextSpan(text: ' '),
      IqroTheme.arabicFontFamily,
      TextDirection.rtl,
    ),
  );

  late final ShareCardWords translation = (
    widths: [
      for (final word in translationWords)
        _em(TextSpan(text: word), shareCardTextFont, TextDirection.ltr),
    ],
    space: _em(const TextSpan(text: ' '), shareCardTextFont, TextDirection.ltr),
  );
}

/// The serif of the meaning, the reference and the signature.
const shareCardTextFont = 'PT Serif';

/// Draws [widget] off screen, a logical pixel to a pixel of the picture.
Future<ui.Image> _renderWidget(
  BuildContext context,
  Widget widget,
  Size size,
) async {
  final boundary = RenderRepaintBoundary();
  final renderView = RenderView(
    view: View.of(context),
    configuration: ViewConfiguration(
      logicalConstraints: BoxConstraints.tight(size),
      devicePixelRatio: 1,
    ),
    child: RenderPositionedBox(child: boundary),
  );
  final pipelineOwner = PipelineOwner()..rootNode = renderView;
  renderView.prepareInitialFrame();
  final buildOwner = BuildOwner(focusManager: FocusManager());
  final root = RenderObjectToWidgetAdapter<RenderBox>(
    container: boundary,
    child: MediaQuery(
      data: MediaQueryData(size: size),
      child: Directionality(
        textDirection: Directionality.of(context),
        child: widget,
      ),
    ),
  ).attachToRenderTree(buildOwner);
  buildOwner
    ..buildScope(root)
    ..finalizeTree();
  pipelineOwner
    ..flushLayout()
    ..flushCompositingBits()
    ..flushPaint();
  return boundary.toImage();
}

/// The cards of [share] as pictures; null when the text needs more cards
/// than a series may have.
Future<List<ui.Image>?> renderShareCards(
  BuildContext context,
  ContentShare share, {
  required ShareCardFormat format,
  required String colour,
}) async {
  final layout = await ShareCardAssets.layout();
  final background = await ShareCardAssets.background(format, colour);
  final text = ShareCardText(share);
  final pages = composeShareCard(layout, format, text.arabic, text.translation);
  if (pages == null || !context.mounted) return null;
  final pictures = <ui.Image>[];
  for (final (index, page) in pages.indexed) {
    if (!context.mounted) return null;
    pictures.add(
      await _renderWidget(
        context,
        ShareCard(
          share: share,
          text: text,
          page: page,
          part: index + 1,
          parts: pages.length,
          layout: layout,
          format: format,
          background: background,
        ),
        layout.size(format),
      ),
    );
  }
  return pictures;
}

/// A picture as a JPEG: the silk is a photograph, and a PNG of it is
/// several megabytes.
Future<Uint8List> encodeShareCard(ui.Image picture) async {
  final data = await picture.toByteData(format: ui.ImageByteFormat.rawRgba);
  return compute(_encodeJpeg, (
    data!.buffer.asUint8List(),
    picture.width,
    picture.height,
  ));
}

Uint8List _encodeJpeg((Uint8List, int, int) picture) => img.encodeJpg(
  img.Image.fromBytes(
    width: picture.$2,
    height: picture.$3,
    bytes: picture.$1.buffer,
    numChannels: 4,
  ),
  quality: 90,
);

/// One card: the silk with its frame, and in the frame the Arabic, a rule
/// with a rosette, the meaning, the reference between two rules and the
/// site. Sizes are pixels of the picture (docs/share-card).
class ShareCard extends StatelessWidget {
  const ShareCard({
    required this.share,
    required this.text,
    required this.page,
    required this.part,
    required this.parts,
    required this.layout,
    required this.format,
    required this.background,
    super.key,
  });

  final ContentShare share;
  final ShareCardText text;
  final ShareCardPage page;
  final int part;
  final int parts;
  final ShareCardLayout layout;
  final ShareCardFormat format;
  final ui.Image background;

  // One line, never wrapped; a word wider than the field is scaled down.
  Widget _line(InlineSpan span, TextStyle style, TextDirection direction) =>
      SizedBox(
        height: style.fontSize! * style.height!,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text.rich(
            span,
            style: style,
            textDirection: direction,
            maxLines: 1,
            softWrap: false,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final ink = layout.ink;
    final shadows = [layout.shadow];
    final field = layout.field(format);
    final arabicStyle = TextStyle(
      color: ink,
      fontFamily: IqroTheme.arabicFontFamily,
      fontSize: page.arabicSize,
      height: layout.arabic.lineHeight,
      shadows: shadows,
    );
    final serif = TextStyle(
      color: ink,
      fontFamily: shareCardTextFont,
      fontFamilyFallback: const [IqroTheme.arabicFontFamily],
      shadows: shadows,
    );
    final reference = parts > 1
        ? '${share.cardReference} · $part/$parts'
        : share.cardReference;
    final rule = CustomPaint(
      size: Size(layout.reference('rule'), layout.divider('thickness')),
      painter: _OrnamentPainter(ink, layout.shadow, rosette: 0),
    );
    return SizedBox.fromSize(
      size: layout.size(format),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: RawImage(image: background, fit: BoxFit.fill),
          ),
          Positioned.fromRect(
            rect: field,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (final line in page.arabicLines)
                  _line(
                    TextSpan(
                      children: <InlineSpan>[
                        for (
                          var word = line.start;
                          word < line.end;
                          word++
                        ) ...[
                          if (word > line.start) const TextSpan(text: ' '),
                          text.arabicWords[word],
                        ],
                      ],
                    ),
                    arabicStyle,
                    TextDirection.rtl,
                  ),
                if (page.arabicLines.isNotEmpty &&
                    page.translationLines.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: layout.gap),
                    child: CustomPaint(
                      size: Size(
                        layout.divider('width'),
                        layout.divider('height'),
                      ),
                      painter: _OrnamentPainter(
                        ink,
                        layout.shadow,
                        rosette: layout.divider('rosette'),
                        thickness: layout.divider('thickness'),
                      ),
                    ),
                  ),
                for (final line in page.translationLines)
                  _line(
                    TextSpan(
                      text: text.translationWords
                          .sublist(line.start, line.end)
                          .join(' '),
                    ),
                    serif.copyWith(
                      fontSize: page.translationSize,
                      height: layout.translation.lineHeight,
                    ),
                    TextDirection.ltr,
                  ),
                SizedBox(height: layout.gap),
                SizedBox(
                  height:
                      layout.reference('size') * layout.reference('lineHeight'),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      rule,
                      SizedBox(width: layout.reference('ruleGap')),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            reference,
                            maxLines: 1,
                            style: serif.copyWith(
                              fontSize: layout.reference('size'),
                              height: layout.reference('lineHeight'),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: layout.reference('ruleGap')),
                      rule,
                    ],
                  ),
                ),
                SizedBox(height: layout.signature('gap')),
                Text(
                  layout.signatureText,
                  textDirection: TextDirection.ltr,
                  style: serif.copyWith(
                    color: ink.withValues(alpha: layout.signature('opacity')),
                    fontSize: layout.signature('size'),
                    height: layout.signature('lineHeight'),
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

/// A rule that thins to its ends; with a [rosette], two of them and an
/// eight-petal flower between. The site draws the same shapes
/// (lib/share-card.ts).
class _OrnamentPainter extends CustomPainter {
  const _OrnamentPainter(
    this.ink,
    this.shadow, {
    required this.rosette,
    this.thickness,
  });

  final Color ink;
  final Shadow shadow;
  final double rosette;
  final double? thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final middle = size.height / 2;
    final weight = thickness ?? size.height;
    final path = Path();
    void rule(double from, double to) => path
      ..moveTo(from, middle)
      ..quadraticBezierTo((from + to) / 2, middle - weight, to, middle)
      ..quadraticBezierTo((from + to) / 2, middle + weight, from, middle);
    if (rosette == 0) {
      rule(0, size.width);
    } else {
      final centre = size.width / 2;
      final reach = rosette * .8;
      rule(0, centre - reach);
      rule(centre + reach, size.width);
      for (var petal = 0; petal < 8; petal += 1) {
        final angle = petal * math.pi / 4;
        final oval = Path()
          ..addOval(
            Rect.fromCenter(
              center: Offset(0, -rosette * .27),
              width: rosette * .2,
              height: rosette * .42,
            ),
          );
        path.addPath(
          oval,
          Offset(centre, middle),
          matrix4: Matrix4.rotationZ(angle).storage,
        );
      }
      path.addOval(
        Rect.fromCircle(center: Offset(centre, middle), radius: rosette * .1),
      );
    }
    canvas
      ..drawPath(
        path.shift(shadow.offset),
        Paint()
          ..color = shadow.color
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            shadow.blurRadius / 2,
          ),
      )
      ..drawPath(path, Paint()..color = ink);
  }

  @override
  bool shouldRepaint(_OrnamentPainter old) => false;
}

/// The share sheet: the cards, the picture's shape and fabric colour, and
/// «Share».
class ShareCardSheet extends StatefulWidget {
  const ShareCardSheet({required this.share, this.origin, super.key});

  final ContentShare share;
  final Rect? origin;

  @override
  State<ShareCardSheet> createState() => _ShareCardSheetState();
}

class _ShareCardSheetState extends State<ShareCardSheet> {
  var _format = ShareCardFormat.story;
  var _colour = shareCardColours.keys.first;

  /// Null while the cards are drawn.
  List<ui.Image>? _pictures;
  var _tooLong = false;
  var _failed = false;
  var _sending = false;
  var _generation = 0;
  var _shown = 0;

  @override
  void initState() {
    super.initState();
    _restoreStyle();
  }

  // The shape and the colour picked last time, on this phone.
  Future<void> _restoreStyle() async {
    try {
      final stored = (await SharedPreferences.getInstance())
          .getString(_stylePreference)
          ?.split(':');
      if (stored != null && stored.length == 2 && mounted) {
        _format = ShareCardFormat.values.asNameMap()[stored.first] ?? _format;
        if (shareCardColours.containsKey(stored.last)) _colour = stored.last;
      }
    } on Object {
      // The first style stays.
    }
    if (mounted) await _draw();
  }

  Future<void> _draw() async {
    final generation = ++_generation;
    setState(() {
      _pictures = null;
      _tooLong = false;
      _failed = false;
      _shown = 0;
    });
    List<ui.Image>? pictures;
    var failed = false;
    try {
      pictures = await renderShareCards(
        context,
        widget.share,
        format: _format,
        colour: _colour,
      );
    } on Object {
      failed = true;
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      _pictures = pictures ?? const [];
      _tooLong = pictures == null && !failed;
      _failed = failed;
    });
  }

  void _restyle({ShareCardFormat? format, String? colour}) {
    _format = format ?? _format;
    _colour = colour ?? _colour;
    SharedPreferences.getInstance().then(
      (preferences) =>
          preferences.setString(_stylePreference, '${_format.name}:$_colour'),
      onError: (_) {},
    );
    _draw();
  }

  Future<void> _send() async {
    final pictures = _pictures ?? const <ui.Image>[];
    setState(() => _sending = true);
    final files = <XFile>[];
    try {
      final directory = await getTemporaryDirectory();
      for (final (index, picture) in pictures.indexed) {
        final name = pictures.length > 1 ? 'iqro-${index + 1}.jpg' : 'iqro.jpg';
        final file = File('${directory.path}/$name');
        await file.writeAsBytes(await encodeShareCard(picture), flush: true);
        files.add(XFile(file.path, mimeType: 'image/jpeg', name: name));
      }
    } on Object {
      // The message goes without the pictures.
      files.clear();
    }
    final result = await SharePlus.instance.share(
      ShareParams(
        text: contentShareText(widget.share),
        subject: widget.share.title,
        title: widget.share.title,
        files: files.isEmpty ? null : files,
        sharePositionOrigin: widget.origin,
      ),
    );
    if (!mounted) return;
    if (result.status == ShareResultStatus.success) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _sending = false);
    }
  }

  String _colourName(String colour) => switch (colour) {
    'turquoise' => context.l10n.shareCardColourTurquoise,
    'midnight' => context.l10n.shareCardColourMidnight,
    _ => context.l10n.shareCardColourEmerald,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final pictures = _pictures;
    final ready = pictures != null;
    final withoutPicture = _tooLong || _failed;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              widget.share.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: MediaQuery.sizeOf(context).height * .46,
              child: !ready
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                          Text(l10n.shareCardPreparing),
                        ],
                      ),
                    )
                  : withoutPicture
                  ? Center(
                      child: Text(
                        _failed ? l10n.shareCardFailed : l10n.shareCardTooLong,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge,
                      ),
                    )
                  : PageView(
                      onPageChanged: (index) => setState(() => _shown = index),
                      children: <Widget>[
                        for (final picture in pictures)
                          Center(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: RawImage(image: picture),
                            ),
                          ),
                      ],
                    ),
            ),
            SizedBox(
              height: 28,
              child: ready && pictures.length > 1
                  ? Center(
                      child: Text(
                        l10n.shareCardPart(_shown + 1, pictures.length),
                        style: theme.textTheme.bodySmall,
                      ),
                    )
                  : null,
            ),
            Row(
              children: <Widget>[
                SegmentedButton<ShareCardFormat>(
                  showSelectedIcon: false,
                  segments: <ButtonSegment<ShareCardFormat>>[
                    ButtonSegment(
                      value: ShareCardFormat.story,
                      label: Text(l10n.shareCardStory),
                    ),
                    ButtonSegment(
                      value: ShareCardFormat.post,
                      label: Text(l10n.shareCardPost),
                    ),
                  ],
                  selected: {_format},
                  onSelectionChanged: (selected) =>
                      _restyle(format: selected.first),
                ),
                const Spacer(),
                for (final MapEntry(key: colour, value: tint)
                    in shareCardColours.entries)
                  Semantics(
                    button: true,
                    selected: colour == _colour,
                    label: _colourName(colour),
                    child: InkResponse(
                      onTap: () => _restyle(colour: colour),
                      radius: 24,
                      child: Container(
                        width: 32,
                        height: 32,
                        margin: const EdgeInsetsDirectional.only(start: 12),
                        decoration: BoxDecoration(
                          color: tint,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colour == _colour
                                ? theme.colorScheme.secondary
                                : theme.colorScheme.outlineVariant,
                            width: colour == _colour ? 3 : 1,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: ready && !_sending ? _send : null,
                icon: const Icon(Icons.share_outlined),
                label: Text(
                  withoutPicture ? l10n.shareCardSendText : l10n.shareCardSend,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
