import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import 'mushaf_edition.dart';
import 'mushaf_paper.dart';
import 'mushaf_thumbnail_cache.dart';
import 'native_mushaf_page.dart';
import 'quran_models.dart';

/// Phone-sized page the miniatures are laid out at before being scaled down,
/// so every edition is drawn exactly as the reader draws it.
const mushafEditionPageSize = Size(360, 620);

/// One page of [edition] rendered by the reader's own page widget, from the
/// edition's fonts or rasters. The last page (Al-Ikhlas, Al-Falaq, An-Nas)
/// is recognisable in every layout.
class MushafEditionPage extends ConsumerStatefulWidget {
  const MushafEditionPage({required this.edition, this.onPainted, super.key});

  final NativeMushafEdition edition;

  /// Called after the frame that first paints the whole page: its text or
  /// picture and its surah and juz labels.
  final VoidCallback? onPainted;

  @override
  ConsumerState<MushafEditionPage> createState() => _MushafEditionPageState();
}

class _MushafEditionPageState extends ConsumerState<MushafEditionPage> {
  final _controller = NativeMushafPageController();
  var _pagePainted = false;
  var _labelled = false;
  var _reported = false;

  void _pageReady() {
    _pagePainted = true;
    if (_labelled && !_reported) {
      _reported = true;
      widget.onPainted?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final identity = widget.edition.identity;
    final surahs =
        ref.watch(quranCatalogProvider).valueOrNull?.surahs ?? const <Surah>[];
    final divisions =
        ref.watch(quranJuzProvider).valueOrNull ?? const <QuranDivision>[];
    _labelled = surahs.isNotEmpty && divisions.isNotEmpty;
    if (_pagePainted && _labelled && !_reported) {
      // The page was drawn before its labels arrived.
      _reported = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onPainted?.call();
      });
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = constraints.maxWidth / mushafEditionPageSize.width;
        final media = MediaQuery.of(context);
        return ClipRect(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox.fromSize(
              size: mushafEditionPageSize,
              child: MediaQuery(
                // Request page artwork for the drawn size, not the phone's.
                data: media.copyWith(
                  size: mushafEditionPageSize,
                  devicePixelRatio: media.devicePixelRatio * scale,
                  padding: EdgeInsets.zero,
                  viewPadding: EdgeInsets.zero,
                  viewInsets: EdgeInsets.zero,
                  textScaler: TextScaler.noScaling,
                ),
                child: IgnorePointer(
                  child: ProviderScope(
                    key: ValueKey(identity),
                    overrides: [
                      selectedMushafIdentityProvider.overrideWithValue(
                        identity,
                      ),
                      selectedMushafRepositoryProvider.overrideWith(
                        (ref) => ref.watch(mushafRepositoryProvider(identity)),
                      ),
                      mushafPageProvider.overrideWith(
                        (ref, page) => ref
                            .watch(mushafRepositoryProvider(identity))
                            .mushafPage(page),
                      ),
                    ],
                    child: NativeMushafPage(
                      page: widget.edition.pagesCount,
                      controller: _controller,
                      selectedAyah: null,
                      playingAyah: null,
                      surahs: surahs,
                      divisions: divisions,
                      onSelectAyah: (_) {},
                      onOpenAyah: (_) {},
                      onBackgroundTap: () {},
                      onScale: (_) {},
                      onPainted: widget.onPainted == null ? null : _pageReady,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Miniature of [edition]'s page on paper, outlined when it is the primary one.
/// It is drawn once per edition version and size, then shown as a picture.
class MushafEditionThumbnail extends StatelessWidget {
  const MushafEditionThumbnail({
    required this.edition,
    this.selected = false,
    this.live = false,
    super.key,
  });

  final NativeMushafEdition edition;
  final bool selected;

  /// Draws the page itself every time instead of its picture.
  final bool live;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: mushafEditionPageSize.aspectRatio,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? scheme.primary : context.iqroColors.line,
            width: selected ? 2.5 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: ColoredBox(
            color: mushafPaperColor,
            child: live
                ? MushafEditionPage(edition: edition)
                : _StoredEditionPage(edition: edition),
          ),
        ),
      ),
    );
  }
}

/// [MushafEditionPage] drawn once, then shown as its picture, so reopening the
/// picker or the Quran tab does not load and lay out every page again.
class _StoredEditionPage extends ConsumerStatefulWidget {
  const _StoredEditionPage({required this.edition});

  final NativeMushafEdition edition;

  @override
  ConsumerState<_StoredEditionPage> createState() => _StoredEditionPageState();
}

class _StoredEditionPageState extends ConsumerState<_StoredEditionPage> {
  final _boundary = GlobalKey();
  MushafThumbnailKey? _key;
  ui.Image? _picture;
  var _live = false;
  var _pixelRatio = 1.0;

  @override
  void dispose() {
    _key = null;
    _picture?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    _pixelRatio = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final version = widget.edition.sourceChecksum;
        if (version.isEmpty || !constraints.hasBoundedWidth) {
          return MushafEditionPage(edition: widget.edition);
        }
        final key = MushafThumbnailKey(
          edition: widget.edition.identity.code,
          version: version,
          locale: locale,
          width: (constraints.maxWidth * _pixelRatio).round(),
        );
        if (key != _key) _show(key);
        final picture = _picture;
        if (picture != null) {
          return RawImage(
            image: picture,
            fit: BoxFit.fill,
            filterQuality: FilterQuality.medium,
          );
        }
        // The stored picture decodes within a few frames; paper meanwhile.
        if (!_live) return const SizedBox.expand();
        return RepaintBoundary(
          key: _boundary,
          child: MushafEditionPage(
            edition: widget.edition,
            onPainted: () => _capture(key),
          ),
        );
      },
    );
  }

  void _show(MushafThumbnailKey key) {
    final cache = ref.read(mushafThumbnailCacheProvider);
    _key = key;
    _picture?.dispose();
    _picture = cache.picture(key);
    _live = _picture == null && !cache.isStored(key);
    if (_picture != null || _live) return;
    unawaited(
      cache.load(key).then((picture) {
        if (!mounted || _key != key) {
          picture?.dispose();
          return;
        }
        setState(() {
          _picture = picture;
          _live = picture == null;
        });
      }),
    );
  }

  Future<void> _capture(MushafThumbnailKey key) async {
    final boundary = _boundary.currentContext?.findRenderObject();
    if (!mounted || _key != key || boundary is! RenderRepaintBoundary) return;
    if (kDebugMode && boundary.debugNeedsPaint) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _capture(key));
      return;
    }
    final cache = ref.read(mushafThumbnailCacheProvider);
    final ui.Image image;
    try {
      image = await boundary.toImage(pixelRatio: _pixelRatio);
    } on Object {
      return;
    }
    unawaited(cache.save(key, image));
    if (!mounted || _key != key) return;
    setState(() {
      _picture?.dispose();
      _picture = cache.picture(key);
    });
  }
}

/// Every edition as a miniature of its page. Tapping one opens it larger,
/// where the reader can make it their primary Mushaf.
class MushafEditionGrid extends StatelessWidget {
  const MushafEditionGrid({
    required this.editions,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  final List<NativeMushafEdition> editions;
  final MushafIdentity selected;
  final ValueChanged<NativeMushafEdition> onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 170).floor().clamp(2, 5);
        return Column(
          children: <Widget>[
            for (var start = 0; start < editions.length; start += columns)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (var i = start; i < start + columns; i++) ...<Widget>[
                      if (i > start) const SizedBox(width: 12),
                      Expanded(
                        child: i < editions.length
                            ? _EditionTile(
                                edition: editions[i],
                                selected: editions[i].identity == selected,
                                onTap: () => _preview(context, i),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _preview(BuildContext context, int index) async {
    final chosen = await Navigator.of(context).push<NativeMushafEdition>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => MushafEditionPreviewScreen(
          editions: editions,
          initialIndex: index,
          selected: selected,
        ),
      ),
    );
    if (chosen != null) onSelect(chosen);
  }
}

class _EditionTile extends StatelessWidget {
  const _EditionTile({
    required this.edition,
    required this.selected,
    required this.onTap,
  });

  final NativeMushafEdition edition;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        key: ValueKey('mushaf-edition-${edition.identity.code}'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Stack(
                children: <Widget>[
                  MushafEditionThumbnail(edition: edition, selected: selected),
                  if (selected)
                    PositionedDirectional(
                      top: 6,
                      end: 6,
                      child: Icon(
                        Icons.check_circle,
                        color: theme.colorScheme.primary,
                        semanticLabel: context.l10n.mushafIsPrimary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                edition.nameFor(locale),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: selected ? theme.colorScheme.primary : null,
                ),
              ),
              if (edition.stagingOnly)
                Text(
                  context.l10n.mushafPreviewDescription,
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A larger look at each edition's page; swiping compares editions. Pops with
/// the edition made primary, or nothing.
class MushafEditionPreviewScreen extends StatefulWidget {
  const MushafEditionPreviewScreen({
    required this.editions,
    required this.initialIndex,
    required this.selected,
    super.key,
  });

  final List<NativeMushafEdition> editions;
  final int initialIndex;
  final MushafIdentity selected;

  @override
  State<MushafEditionPreviewScreen> createState() =>
      _MushafEditionPreviewScreenState();
}

class _MushafEditionPreviewScreenState
    extends State<MushafEditionPreviewScreen> {
  late final _pages = PageController(initialPage: widget.initialIndex);
  late var _index = widget.initialIndex;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final edition = widget.editions[_index];
    final primary = edition.identity == widget.selected;
    final locale = Localizations.localeOf(context).languageCode;
    return Scaffold(
      appBar: AppBar(
        title: Text(edition.nameFor(locale)),
        actions: <Widget>[
          if (widget.editions.length > 1)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 16),
              child: Center(
                child: Text('${_index + 1} / ${widget.editions.length}'),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: widget.editions.length,
                onPageChanged: (index) => setState(() => _index = index),
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Center(
                    child: MushafEditionThumbnail(
                      edition: widget.editions[index],
                      selected:
                          widget.editions[index].identity == widget.selected,
                      live: true,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: primary
                    ? OutlinedButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.check_circle_outline),
                        label: Text(context.l10n.mushafIsPrimary),
                      )
                    : FilledButton.icon(
                        onPressed: () => Navigator.of(context).pop(edition),
                        icon: const Icon(Icons.check),
                        label: Text(context.l10n.mushafMakePrimary),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
