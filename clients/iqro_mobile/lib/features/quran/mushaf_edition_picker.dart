import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import 'mushaf_edition.dart';
import 'mushaf_paper.dart';
import 'native_mushaf_page.dart';
import 'quran_models.dart';

/// Phone-sized page the miniatures are laid out at before being scaled down,
/// so every edition is drawn exactly as the reader draws it.
const mushafEditionPageSize = Size(360, 620);

/// One page of [edition] rendered by the reader's own page widget, from the
/// edition's fonts or rasters. The last page (Al-Ikhlas, Al-Falaq, An-Nas)
/// is recognisable in every layout.
class MushafEditionPage extends ConsumerStatefulWidget {
  const MushafEditionPage({required this.edition, super.key});

  final NativeMushafEdition edition;

  @override
  ConsumerState<MushafEditionPage> createState() => _MushafEditionPageState();
}

class _MushafEditionPageState extends ConsumerState<MushafEditionPage> {
  final _controller = NativeMushafPageController();

  @override
  Widget build(BuildContext context) {
    final identity = widget.edition.identity;
    final surahs =
        ref.watch(quranCatalogProvider).valueOrNull?.surahs ?? const <Surah>[];
    final divisions =
        ref.watch(quranJuzProvider).valueOrNull ?? const <QuranDivision>[];
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
class MushafEditionThumbnail extends StatelessWidget {
  const MushafEditionThumbnail({
    required this.edition,
    this.selected = false,
    super.key,
  });

  final NativeMushafEdition edition;
  final bool selected;

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
            child: MushafEditionPage(edition: edition),
          ),
        ),
      ),
    );
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
