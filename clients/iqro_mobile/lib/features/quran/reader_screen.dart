import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/storage/preferences_store.dart';
import '../../core/theme/iqro_theme.dart';
import '../audio/audio_models.dart';
import 'quran_models.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({required this.surah, this.initialAyah = 1, super.key});
  final int surah;
  final int initialAyah;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  final _bookmarks = <int>{};
  var _showTranslation = false;
  var _showTafsir = false;
  var _selectedAyah = 1;

  @override
  void initState() {
    super.initState();
    _selectedAyah = widget.initialAyah;
    _loadBookmarks();
  }

  Future<void> _loadBookmarks() async {
    final rows = await ref.read(quranRepositoryProvider).bookmarks();
    if (!mounted) return;
    setState(() {
      _bookmarks
        ..clear()
        ..addAll(
          rows
              .where((row) => row['surah'] == widget.surah)
              .map((row) => row['ayah']! as int),
        );
    });
  }

  @override
  Widget build(BuildContext context) {
    final ayahs = ref.watch(ayahsProvider(widget.surah));
    final catalog = ref.watch(quranCatalogProvider).valueOrNull;
    final locale = Localizations.localeOf(context).languageCode;
    final surah = catalog?.surahs
        .where((item) => item.number == widget.surah)
        .firstOrNull;
    final title =
        surah?.nameFor(locale) ?? '${context.l10n.surah} ${widget.surah}';
    return Scaffold(
      appBar: IqroTopBar(
        title: title,
        subtitle:
            '${context.l10n.surah} ${widget.surah} · ${surah?.ayahCount ?? ''} ${context.l10n.ayahs}',
        actions: <Widget>[
          IconButton(
            tooltip: context.l10n.readerSettings,
            onPressed: _showSettings,
            icon: const Icon(Icons.tune),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ayahs.when(
        loading: () => const IqroLoading(),
        error: (error, stack) => IqroAsyncError(
          title: context.l10n.noQuranData,
          onRetry: () => ref.invalidate(ayahsProvider(widget.surah)),
        ),
        data: (items) => Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 6, 14, 8),
              child: IqroStatusBanner(
                icon: Icons.sync,
                title: context.l10n.savedAutomatically,
                actionLabel: context.l10n.mushafMode,
                onAction: () async {
                  final page =
                      items
                          .where((item) => item.number == _selectedAyah)
                          .firstOrNull
                          ?.pages
                          .firstOrNull ??
                      surah?.firstPage ??
                      1;
                  await ref
                      .read(appPreferencesProvider.notifier)
                      .setReaderMode(ReaderMode.mushaf);
                  if (!context.mounted) return;
                  context.push(
                    '/mushaf?page=$page&surah=${widget.surah}&ayah=$_selectedAyah',
                  );
                },
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 14, 100),
                itemCount: items.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _ReaderIntro(surah: surah, title: title);
                  }
                  final ayah = items[index - 1];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _AyahCard(
                      ayah: ayah,
                      selected: ayah.number == _selectedAyah,
                      bookmarked: _bookmarks.contains(ayah.number),
                      showTranslation: _showTranslation,
                      showTafsir: _showTafsir,
                      onSelected: () => _select(ayah),
                      onBookmark: () => _toggleBookmark(ayah),
                      onPlay: () => _play(ayah, title),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _select(QuranAyah ayah) async {
    setState(() => _selectedAyah = ayah.number);
    await ref
        .read(quranRepositoryProvider)
        .savePosition(
          surah: ayah.surahNumber,
          ayah: ayah.number,
          page: ayah.pages.firstOrNull ?? 1,
        );
    ref.invalidate(readingPositionProvider);
  }

  Future<void> _toggleBookmark(QuranAyah ayah) async {
    final active = await ref
        .read(quranRepositoryProvider)
        .toggleBookmark(
          ayah.surahNumber,
          ayah.number,
          page: ayah.pages.firstOrNull,
        );
    if (!mounted) return;
    setState(
      () =>
          active ? _bookmarks.add(ayah.number) : _bookmarks.remove(ayah.number),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          active ? context.l10n.bookmarkAdded : context.l10n.bookmarkRemoved,
        ),
      ),
    );
  }

  Future<void> _play(QuranAyah ayah, String surahName) async {
    final reciters = await ref.read(audioRepositoryProvider).reciters();
    final Reciter? reciter = reciters.firstOrNull;
    if (reciter == null) return;
    final track = await ref
        .read(audioRepositoryProvider)
        .track(reciterId: reciter.id, surah: ayah.surahNumber);
    if (track == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.noAudio)));
      }
      return;
    }
    await ref
        .read(audioControllerProvider.notifier)
        .load(track: track, reciter: reciter, surahName: surahName);
  }

  Future<void> _showSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        context.l10n.readerSettings,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10n.translation),
                  subtitle: Text(context.l10n.translationUnavailable),
                  value: _showTranslation,
                  onChanged: (value) {
                    setState(() => _showTranslation = value);
                    setSheetState(() {});
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10n.tafsir),
                  subtitle: Text(context.l10n.loadOnDemand),
                  value: _showTafsir,
                  onChanged: (value) {
                    setState(() => _showTafsir = value);
                    setSheetState(() {});
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ReaderIntro extends StatelessWidget {
  const _ReaderIntro({required this.surah, required this.title});
  final Surah? surah;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 18),
      decoration: BoxDecoration(
        color: context.iqroColors.ink,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: <Widget>[
          Text(
            surah?.nameAr ?? title,
            textDirection: TextDirection.rtl,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontFamily: 'serif',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            surah?.revelationType == 'meccan'
                ? context.l10n.meccan
                : context.l10n.medinan,
            style: TextStyle(color: Colors.white.withValues(alpha: .72)),
          ),
        ],
      ),
    );
  }
}

class _AyahCard extends StatelessWidget {
  const _AyahCard({
    required this.ayah,
    required this.selected,
    required this.bookmarked,
    required this.showTranslation,
    required this.showTafsir,
    required this.onSelected,
    required this.onBookmark,
    required this.onPlay,
  });
  final QuranAyah ayah;
  final bool selected;
  final bool bookmarked;
  final bool showTranslation;
  final bool showTafsir;
  final VoidCallback onSelected;
  final VoidCallback onBookmark;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      child: IqroCard(
        onTap: onSelected,
        borderColor: selected ? Theme.of(context).colorScheme.primary : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${ayah.surahNumber}:${ayah.number}',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: context.l10n.listen,
                  onPressed: onPlay,
                  icon: const Icon(Icons.play_arrow),
                ),
                IconButton(
                  tooltip: context.l10n.favorites,
                  isSelected: bookmarked,
                  onPressed: onBookmark,
                  selectedIcon: const Icon(Icons.bookmark),
                  icon: const Icon(Icons.bookmark_border),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '${ayah.textUthmani}  ﴿${ayah.number}﴾',
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontFamily: 'serif',
                fontSize: 30,
                height: 1.9,
              ),
            ),
            if (showTranslation) ...<Widget>[
              const Divider(height: 28),
              IqroStatusBanner(
                icon: Icons.translate,
                title: context.l10n.translation,
                message: context.l10n.translationUnavailable,
              ),
            ],
            if (showTafsir) ...<Widget>[
              const SizedBox(height: 8),
              IqroStatusBanner(
                icon: Icons.auto_stories_outlined,
                title: context.l10n.tafsir,
                message: context.l10n.tafsirUnavailable,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
