import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/iqro_theme.dart';

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
    this.translation = '',
    this.note = '',
    this.reference = '',
  });

  /// «Аль-Бакара · 2:255», or the du'a's chapter.
  final String title;
  final String arabic;
  final String translation;

  /// A practical line, such as how many times a du'a is said.
  final String note;

  /// Where it comes from: the translation or the du'a's source.
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

/// Shares the text with a picture of it, so messengers show a preview card.
/// Without the picture (rendering failed) the text still goes. True once the
/// user picked where to send it.
Future<bool> shareContent(
  BuildContext context,
  ContentShare share, {
  Rect? origin,
}) async {
  final text = contentShareText(share);
  XFile? picture;
  try {
    final logo = await _decodeAsset('assets/brand/iqro-logo.png');
    if (!context.mounted) return false;
    final bytes = await renderShareCard(context, share, logo: logo);
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/iqro-share.png');
    await file.writeAsBytes(bytes, flush: true);
    picture = XFile(file.path, mimeType: 'image/png', name: 'iqro.png');
  } on Object {
    picture = null;
  }
  final result = await SharePlus.instance.share(
    ShareParams(
      text: text,
      subject: share.title,
      title: share.title,
      files: picture == null ? null : <XFile>[picture],
      sharePositionOrigin: origin,
    ),
  );
  return result.status == ShareResultStatus.success;
}

Future<ui.Image> _decodeAsset(String path) async {
  final data = await rootBundle.load(path);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  return (await codec.getNextFrame()).image;
}

/// Logical size of the card; it is rendered at twice the density.
const shareCardSize = Size(540, 675);

/// Draws [ShareCard] off screen and returns it as PNG.
Future<Uint8List> renderShareCard(
  BuildContext context,
  ContentShare share, {
  required ui.Image logo,
}) async {
  const pixelRatio = 2.0;
  final boundary = RenderRepaintBoundary();
  final renderView = RenderView(
    view: View.of(context),
    configuration: ViewConfiguration(
      logicalConstraints: BoxConstraints.tight(shareCardSize),
      devicePixelRatio: pixelRatio,
    ),
    child: RenderPositionedBox(child: boundary),
  );
  final pipelineOwner = PipelineOwner()..rootNode = renderView;
  renderView.prepareInitialFrame();
  final buildOwner = BuildOwner(focusManager: FocusManager());
  final root = RenderObjectToWidgetAdapter<RenderBox>(
    container: boundary,
    child: MediaQuery(
      data: const MediaQueryData(size: shareCardSize),
      child: Directionality(
        textDirection: Directionality.of(context),
        child: ShareCard(share: share, logo: logo),
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
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// The preview picture: the brand's green with a gold frame, the seal, the
/// title, the Arabic, the meaning, the source and the site.
class ShareCard extends StatelessWidget {
  const ShareCard({required this.share, required this.logo, super.key});

  final ContentShare share;
  final ui.Image logo;

  static const _gold = Color(0xFFE2B665);
  static const _ivory = Color(0xFFF4EDDA);

  // Long du'a get a smaller script so the whole text fits the card.
  double get _arabicSize => switch (share.arabic.length) {
    < 90 => 34,
    < 200 => 28,
    < 360 => 23,
    < 600 => 19,
    _ => 16,
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox.fromSize(
      size: shareCardSize,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0xFF0B4A3C), Color(0xFF062A22)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: _gold.withValues(alpha: .7)),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(26, 22, 26, 20),
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      SizedBox.square(
                        dimension: 44,
                        child: RawImage(image: logo, fit: BoxFit.contain),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          share.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _gold,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        share.arabic,
                        textAlign: TextAlign.center,
                        textDirection: TextDirection.rtl,
                        maxLines: 14,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _ivory,
                          fontFamily: IqroTheme.arabicFontFamily,
                          fontSize: _arabicSize,
                          height: 1.9,
                        ),
                      ),
                    ),
                  ),
                  if (share.translation.isNotEmpty) ...<Widget>[
                    Text(
                      share.translation,
                      textAlign: TextAlign.center,
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .88),
                        fontSize: 15,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (share.reference.isNotEmpty)
                    Text(
                      share.reference,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .6),
                        fontSize: 12,
                      ),
                    ),
                  const SizedBox(height: 14),
                  Container(height: 1, color: _gold.withValues(alpha: .4)),
                  const SizedBox(height: 10),
                  const Text(
                    'www.iqro.forum',
                    style: TextStyle(
                      color: _gold,
                      fontSize: 14,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
