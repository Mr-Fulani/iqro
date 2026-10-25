import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import 'course_models.dart';
import 'lesson_media_cache.dart';

/// A slide frame is never taller than 5:4.
const _maxSlideHeight = 1.25;
const _radius = 22.0;

/// The media of a lesson above its notes, in order: videos, slides and
/// banners, each followed by a gap. Blocks with a picture from another host
/// are left out. The lesson draws its videos with [videoBuilder].
class LessonMediaView extends ConsumerWidget {
  const LessonMediaView({
    required this.media,
    required this.videoBuilder,
    super.key,
  });

  final List<LessonMedia> media;
  final Widget Function(BuildContext context, CourseVideo video) videoBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base = Uri.parse(ref.watch(appConfigProvider).apiBaseUrl);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final block in approvedLessonMedia(media, base))
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: switch (block) {
              LessonVideoMedia(:final video) => videoBuilder(context, video),
              LessonSlidesMedia(:final slides) => LessonSlides(slides: slides),
              LessonBannerMedia(:final picture) => LessonBanner(
                picture: picture,
              ),
            },
          ),
      ],
    );
  }
}

/// One slide at a time: swipe, the arrows or the dots turn them, mirrored in
/// a right-to-left interface. The frame is as tall as the tallest slide, up
/// to 5:4; the others fit in its middle. Only the current slide and its
/// neighbours are loaded.
class LessonSlides extends StatefulWidget {
  const LessonSlides({required this.slides, super.key});

  final List<LessonPicture> slides;

  @override
  State<LessonSlides> createState() => _LessonSlidesState();
}

class _LessonSlidesState extends State<LessonSlides> {
  final _pages = PageController();
  var _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _show(int index) {
    if (index < 0 || index >= widget.slides.length) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(index);
    } else {
      _pages.animateToPage(
        index,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final slides = widget.slides;
    final total = slides.length;
    final index = math.min(_index, total - 1);
    final slide = slides[index];
    final height = math.min(
      _maxSlideHeight,
      slides
          .map((slide) => slide.image.height / slide.image.width)
          .reduce(math.max),
    );
    return Semantics(
      key: const ValueKey('lesson-media-slides'),
      container: true,
      explicitChildNodes: true,
      label: l10n.lessonMediaSlides,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(_radius),
            child: ColoredBox(
              color: context.iqroColors.panelSoft,
              child: AspectRatio(
                aspectRatio: 1 / height,
                child: PageView.builder(
                  key: const ValueKey('lesson-media-slide-pages'),
                  controller: _pages,
                  // Builds the neighbours too, so they are loaded ahead.
                  allowImplicitScrolling: true,
                  itemCount: total,
                  onPageChanged: (page) => setState(() => _index = page),
                  itemBuilder: (context, page) => Semantics(
                    container: true,
                    label: l10n.lessonMediaSlideOf(page + 1, total),
                    child: LessonMediaImage(
                      key: ValueKey('lesson-media-slide-$page'),
                      picture: slides[page],
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (slide.caption.isNotEmpty || total > 1)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: _Caption(picture: slide)),
                  if (total > 1) ...<Widget>[
                    const SizedBox(width: 12),
                    ExcludeSemantics(
                      child: Text(
                        l10n.lessonMediaSlideCounter(index + 1, total),
                        key: const ValueKey('lesson-media-slide-counter'),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (total > 1)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  _Arrow(
                    key: const ValueKey('lesson-media-slide-previous'),
                    icon: Icons.chevron_left,
                    label: l10n.lessonMediaPreviousSlide,
                    onPressed: index > 0 ? () => _show(index - 1) : null,
                  ),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        children: <Widget>[
                          for (var page = 0; page < total; page++)
                            _Dot(
                              key: ValueKey('lesson-media-slide-dot-$page'),
                              label: l10n.lessonMediaSlideOf(page + 1, total),
                              current: page == index,
                              onTap: () => _show(page),
                            ),
                        ],
                      ),
                    ),
                  ),
                  _Arrow(
                    key: const ValueKey('lesson-media-slide-next'),
                    icon: Icons.chevron_right,
                    label: l10n.lessonMediaNextSlide,
                    onPressed: index + 1 < total
                        ? () => _show(index + 1)
                        : null,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A 16:9 picture with its caption under it.
class LessonBanner extends StatelessWidget {
  const LessonBanner({required this.picture, super.key});

  final LessonPicture picture;

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('lesson-media-banner'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      ClipRRect(
        borderRadius: BorderRadius.circular(_radius),
        child: ColoredBox(
          color: context.iqroColors.panelSoft,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: LessonMediaImage(picture: picture, fit: BoxFit.cover),
          ),
        ),
      ),
      if (picture.caption.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _Caption(picture: picture),
        ),
    ],
  );
}

/// The picture in the copy that suits the frame: the 800 px one while it is
/// not scaled up, otherwise the large one. If the chosen copy cannot be had,
/// offline for example, the other one is tried.
class LessonMediaImage extends ConsumerWidget {
  const LessonMediaImage({required this.picture, required this.fit, super.key});

  final LessonPicture picture;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base = Uri.parse(ref.watch(appConfigProvider).apiBaseUrl);
    final images = ref.watch(lessonMediaImageProvider);
    final image = picture.image;
    final placeholder = Center(
      child: Icon(
        Icons.image_outlined,
        size: 40,
        color: Theme.of(
          context,
        ).colorScheme.onSurfaceVariant.withValues(alpha: .4),
      ),
    );
    Widget copy(String url, Widget Function() failed) => Image(
      image: images(base.resolve(url).toString()),
      fit: fit,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      frameBuilder: (context, child, frame, synchronous) =>
          frame == null && !synchronous ? placeholder : child,
      errorBuilder: (context, error, stackTrace) => failed(),
    );
    final alt = picture.alt;
    return Semantics(
      image: alt.isNotEmpty,
      label: alt.isEmpty ? null : alt,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pixels =
              constraints.maxWidth * MediaQuery.devicePixelRatioOf(context);
          return SizedBox.expand(
            child: copy(
              lessonImageUrl(image, pixels),
              () => copy(lessonImageOtherUrl(image, pixels), () => placeholder),
            ),
          );
        },
      ),
    );
  }
}

/// In the caption's own direction, whatever the interface's.
class _Caption extends StatelessWidget {
  const _Caption({required this.picture});

  final LessonPicture picture;

  @override
  Widget build(BuildContext context) {
    if (picture.caption.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Directionality(
      textDirection: picture.direction,
      child: Text(
        picture.caption,
        textAlign: TextAlign.start,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontFamilyFallback: const [IqroTheme.arabicFontFamily],
        ),
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton.outlined(
    onPressed: onPressed,
    tooltip: label,
    style: IconButton.styleFrom(minimumSize: const Size.square(48)),
    icon: Icon(icon),
  );
}

/// «Slide 2 of 5»; the current one is longer.
class _Dot extends StatelessWidget {
  const _Dot({
    required this.label,
    required this.current,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: current,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkResponse(
        onTap: onTap,
        radius: 16,
        child: SizedBox(
          width: 24,
          height: 32,
          child: Center(
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              width: current ? 16 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: current ? colors.primary : colors.outlineVariant,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
