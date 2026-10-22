import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import 'announcement_controller.dart';
import 'announcement_logic.dart';

const _icons = <String, IconData>{
  'headphones': Icons.headphones_rounded,
  'sparkle': Icons.auto_awesome_rounded,
  'arrow_up': Icons.arrow_upward_rounded,
  'book': Icons.menu_book_rounded,
  'megaphone': Icons.campaign_rounded,
  'compass': Icons.explore_rounded,
  'mosque': Icons.mosque_rounded,
};

/// The icon of the bubble and pictures; a portrait without a picture falls
/// back to headphones, as on the site.
IconData announcementIcon(String name) =>
    _icons[name == 'portrait' ? 'headphones' : name] ?? _icons['megaphone']!;

/// The face of the bubble and of pictures without an image.
const announcementFaceGradient = RadialGradient(
  center: Alignment(-.36, -.48),
  radius: 1,
  colors: <Color>[Color(0xFF6EE7B7), Color(0xFF059669), Color(0xFF064E3B)],
  stops: <double>[0, .45, 1],
);
const announcementFaceInk = Color(0xFFECFDF5);

/// Announcement pictures, kept in the image disk cache for reading offline.
final announcementImageProvider = Provider<ImageProvider Function(String url)>(
  (ref) =>
      (url) => CachedNetworkImageProvider(url),
);

/// A server picture; [fallback] stands in while it loads or when it cannot.
class AnnouncementNetworkImage extends ConsumerWidget {
  const AnnouncementNetworkImage({
    required this.url,
    required this.fallback,
    this.fit = BoxFit.cover,
    super.key,
  });

  final String url;
  final Widget fallback;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Server images may be CDN URLs or paths of the local API.
    final resolved = Uri.parse(
      ref.watch(appConfigProvider).apiBaseUrl,
    ).resolve(url).toString();
    return Image(
      image: ref.watch(announcementImageProvider)(resolved),
      fit: fit,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, synchronous) =>
          frame == null && !synchronous ? fallback : child,
      errorBuilder: (context, error, stackTrace) => fallback,
    );
  }
}

String announcementKindLabel(BuildContext context, String kind) =>
    switch (kind) {
      'reciter' => context.l10n.newsKindReciter,
      'feature' => context.l10n.newsKindFeature,
      'app_release' => context.l10n.newsKindAppRelease,
      'content' => context.l10n.newsKindContent,
      _ => context.l10n.newsKindGeneral,
    };

String announcementDate(
  BuildContext context,
  Announcement item, {
  bool year = false,
}) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  final format = year ? DateFormat.yMMMMd(locale) : DateFormat.MMMMd(locale);
  return format.format(item.startsAt.toLocal());
}

/// The portrait (or its 96 px thumbnail) when there is one, otherwise the
/// kind's icon.
class AnnouncementPicture extends StatelessWidget {
  const AnnouncementPicture({
    required this.item,
    required this.size,
    this.thumb = false,
    super.key,
  });

  final Announcement item;
  final double size;
  final bool thumb;

  @override
  Widget build(BuildContext context) {
    final image = item.image;
    final source = image == null
        ? null
        : thumb && image.thumbUrl != null
        ? image.thumbUrl!
        : image.url;
    final icon = Icon(
      announcementIcon(item.bubbleIcon),
      size: size * .5,
      color: announcementFaceInk,
    );
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: announcementFaceGradient,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Theme.of(context).colorScheme.primaryContainer,
              spreadRadius: 5,
            ),
          ],
        ),
        child: source == null
            ? icon
            : AnnouncementNetworkImage(url: source, fallback: icon),
      ),
    );
  }
}

/// Paragraphs, "- " lists and **bold**, the subset admins write.
class AnnouncementBody extends StatelessWidget {
  const AnnouncementBody({required this.body, super.key});

  final String body;

  @override
  Widget build(BuildContext context) {
    final blocks = bodyBlocks(body);
    if (blocks.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    TextSpan line(String text) => TextSpan(
      children: <InlineSpan>[
        for (final part in boldSegments(text))
          TextSpan(
            text: part.text,
            style: part.bold
                ? TextStyle(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  )
                : null,
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final (index, block) in blocks.indexed) ...<Widget>[
          if (index > 0) const SizedBox(height: 8),
          if (block.list)
            for (final item in block.lines)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 4, bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('•  ', style: style),
                    Expanded(child: Text.rich(line(item), style: style)),
                  ],
                ),
              )
          else
            Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  for (final (row, item)
                      in block.lines.indexed) ...<InlineSpan>[
                    if (row > 0) const TextSpan(text: '\n'),
                    line(item),
                  ],
                ],
              ),
              style: style,
            ),
        ],
      ],
    );
  }
}

/// Follows the announcement's button: a screen of the app, or an allowed
/// external page through the server's counted redirect.
Future<void> openAnnouncementAction(
  WidgetRef ref,
  GoRouter router,
  Announcement item,
  String surface,
) async {
  final controller = ref.read(announcementsProvider.notifier);
  final route = item.action.appRoute;
  final external = item.action.externalUrl;
  if (route != null) {
    await controller.click(item, surface);
    // Tabs are switched in place; everything else opens over the current
    // screen so Back returns to it.
    if (route.startsWith('/app')) {
      router.go(route);
    } else {
      router.push(route);
    }
    return;
  }
  if (external == null) return;
  await controller.click(item, surface);
  final platform = ref.read(announcementRepositoryProvider).platform;
  final uri = Uri.parse(
    ref.read(appConfigProvider).apiBaseUrl,
  ).resolve('$external?platform=$platform&surface=$surface');
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Object {
    // No browser or store app: nothing else to open.
  }
}

bool announcementHasAction(Announcement item) =>
    item.action.appRoute != null || item.action.externalUrl != null;
