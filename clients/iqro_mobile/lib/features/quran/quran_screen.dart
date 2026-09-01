import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/storage/preferences_store.dart';
import '../../core/theme/iqro_theme.dart';
import 'mushaf_offline_repository.dart';
import 'quick_jump_sheet.dart';
import 'quran_models.dart';

class QuranScreen extends ConsumerStatefulWidget {
  const QuranScreen({super.key});

  @override
  ConsumerState<QuranScreen> createState() => _QuranScreenState();
}

class _QuranScreenState extends ConsumerState<QuranScreen> {
  final _searchController = TextEditingController();
  var _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(appPreferencesProvider);
    final catalog = ref.watch(quranCatalogProvider);
    final position = ref.watch(readingPositionProvider).valueOrNull;
    final playerActive = ref.watch(
      audioControllerProvider.select((value) => value.active),
    );
    return Scaffold(
      appBar: IqroTopBar(
        title: context.l10n.navQuran,
        subtitle: context.l10n.quranSubtitle,
        actions: <Widget>[
          IconButton(
            tooltip: context.l10n.quickJump,
            onPressed: () => _showQuickJump(context),
            icon: const Icon(Icons.layers_outlined),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: IqroPage(
        scrollable: false,
        padding: iqroRootTabPadding(playerActive: playerActive),
        child: Column(
          children: <Widget>[
            IqroCard(
              onTap: () => _showMushafPicker(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ReaderMode>(
                      segments: <ButtonSegment<ReaderMode>>[
                        ButtonSegment(
                          value: ReaderMode.text,
                          icon: const Icon(Icons.format_list_bulleted),
                          label: Text(context.l10n.textMode),
                        ),
                        ButtonSegment(
                          value: ReaderMode.mushaf,
                          icon: const Icon(Icons.menu_book_outlined),
                          label: Text(context.l10n.mushafMode),
                        ),
                      ],
                      selected: <ReaderMode>{preferences.readerMode},
                      showSelectedIcon: false,
                      onSelectionChanged: (values) {
                        ref
                            .read(appPreferencesProvider.notifier)
                            .setReaderMode(values.first);
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              context.l10n.selectedMushaf,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              context.l10n.mushafScanName,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              context.l10n.mushafScanDescription,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const _MushafOfflineIndicator(),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            IqroCard(
              color: context.iqroColors.ink,
              borderColor: Colors.transparent,
              onTap: () => _openPosition(
                preferences.readerMode,
                position?.surah ?? 1,
                position?.page ?? 1,
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .25),
                      ),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      preferences.readerMode == ReaderMode.text
                          ? Icons.format_list_bulleted
                          : Icons.menu_book_outlined,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          context.l10n.continueSaved,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .7),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${context.l10n.alFatiha} · ${position?.ayah ?? 1}',
                          style: Theme.of(
                            context,
                          ).textTheme.titleSmall?.copyWith(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SearchBar(
              controller: _searchController,
              hintText:
                  '${context.l10n.surah}, ${context.l10n.ayah}, ${context.l10n.juz}…',
              leading: const Icon(Icons.search),
              trailing: _query.isEmpty
                  ? null
                  : <Widget>[
                      IconButton(
                        tooltip: context.l10n.close,
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close),
                      ),
                    ],
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: catalog.when(
                loading: () => const IqroLoading(),
                error: (error, stack) => IqroAsyncError(
                  title: context.l10n.noQuranData,
                  message: context.l10n.networkError,
                  onRetry: () => ref.invalidate(quranCatalogProvider),
                ),
                data: (data) {
                  final locale = Localizations.localeOf(context).languageCode;
                  final filtered = data.surahs
                      .where((surah) {
                        if (_query.isEmpty) return true;
                        return '${surah.number} ${surah.nameAr} ${surah.nameEn} ${surah.nameRu}'
                            .toLowerCase()
                            .contains(_query);
                      })
                      .toList(growable: false);
                  return Column(
                    children: <Widget>[
                      if (data.fromCache)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: IqroStatusBanner(
                            icon: Icons.cloud_off_outlined,
                            title: context.l10n.offlineUsingCache,
                          ),
                        ),
                      Expanded(
                        child: IqroCard(
                          padding: EdgeInsets.zero,
                          child: ListView.separated(
                            padding: EdgeInsets.zero,
                            itemCount: filtered.length,
                            separatorBuilder: (context, index) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final surah = filtered[index];
                              return _SurahRow(
                                surah: surah,
                                locale: locale,
                                onTap: () => _openPosition(
                                  preferences.readerMode,
                                  surah.number,
                                  surah.firstPage ?? 1,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openPosition(ReaderMode mode, int surah, int page) {
    if (mode == ReaderMode.mushaf) {
      context.push('/mushaf?page=$page&surah=$surah&ayah=1');
    } else {
      context.push('/reader/$surah');
    }
  }

  Future<void> _showMushafPicker(BuildContext context) async {
    final current = ref.read(appPreferencesProvider).mushafVariant;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => RadioGroup<String>(
        groupValue: current,
        onChanged: (value) => _selectMushaf(context, value),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 20),
          children: <Widget>[
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 12, 12),
              child: Text(
                context.l10n.chooseMushaf,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            RadioListTile<String>(
              value: defaultMushafVariant,
              title: Text(context.l10n.mushafScanName),
              subtitle: Text(context.l10n.mushafScanDescription),
              secondary: const Icon(Icons.image_outlined),
            ),
            const Divider(height: 28),
            const _OfflineMushafCard(),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(context.l10n.mushafUnavailable),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectMushaf(BuildContext context, String? value) async {
    if (value == null) return;
    await ref.read(appPreferencesProvider.notifier).setMushafVariant(value);
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _showQuickJump(BuildContext context) async {
    try {
      final repository = ref.read(quranRepositoryProvider);
      final results = await Future.wait<Object>(<Future<Object>>[
        repository.surahs(),
        repository.juz(),
      ]);
      final catalog = results[0] as QuranCatalog;
      final juz = results[1] as List<QuranDivision>;
      if (!context.mounted) return;
      final selection = await showModalBottomSheet<QuranQuickJumpSelection>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) =>
            QuranQuickJumpSheet(surahs: catalog.surahs, juz: juz),
      );
      if (selection == null || !context.mounted) return;
      final readerMode = ref.read(appPreferencesProvider).readerMode;
      if (selection.mode == QuranQuickJumpMode.ayah &&
          readerMode == ReaderMode.text) {
        context.push('/reader/${selection.surah}?ayah=${selection.ayah}');
        return;
      }
      var page = selection.page;
      if (selection.mode == QuranQuickJumpMode.ayah) {
        final ayahs = await repository.ayahs(selection.surah);
        final target = ayahs
            .where((item) => item.number == selection.ayah)
            .firstOrNull;
        page = target?.pages.firstOrNull ?? page;
      }
      if (!context.mounted) return;
      context.push(
        '/mushaf?page=$page&surah=${selection.surah}&ayah=${selection.ayah}',
      );
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.networkError)));
    }
  }
}

class _MushafOfflineIndicator extends ConsumerWidget {
  const _MushafOfflineIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(
      mushafDownloadProvider.select((value) => value.status),
    );
    return Icon(
      switch (status) {
        MushafDownloadStatus.ready => Icons.offline_pin_outlined,
        MushafDownloadStatus.downloading => Icons.downloading_outlined,
        MushafDownloadStatus.failed => Icons.cloud_off_outlined,
        MushafDownloadStatus.notDownloaded => Icons.cloud_download_outlined,
      },
      color: status == MushafDownloadStatus.ready
          ? Theme.of(context).colorScheme.primary
          : null,
    );
  }
}

class _OfflineMushafCard extends ConsumerWidget {
  const _OfflineMushafCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mushafDownloadProvider);
    final downloading = state.status == MushafDownloadStatus.downloading;
    final ready = state.status == MushafDownloadStatus.ready;
    final failed = state.status == MushafDownloadStatus.failed;
    final progressLabel = state.totalPages <= 0
        ? null
        : '${state.completedPages} / ${state.totalPages} · '
              '${_formatMegabytes(state.downloadedBytes)} / '
              '${_formatMegabytes(state.totalBytes)}';
    return IqroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                ready ? Icons.offline_pin_outlined : Icons.download_outlined,
                color: ready ? Theme.of(context).colorScheme.primary : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ready
                      ? context.l10n.mushafAvailableOffline
                      : downloading
                      ? context.l10n.mushafDownloading
                      : context.l10n.offlineMushaf,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            failed
                ? context.l10n.mushafDownloadFailed
                : context.l10n.offlineMushafDescription,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (downloading) ...<Widget>[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: state.totalBytes > 0 ? state.progress : null,
            ),
          ],
          if (progressLabel != null) ...<Widget>[
            const SizedBox(height: 7),
            Text(progressLabel, style: Theme.of(context).textTheme.bodySmall),
          ],
          if (!ready) ...<Widget>[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: downloading
                    ? null
                    : () =>
                          ref.read(mushafDownloadProvider.notifier).download(),
                icon: Icon(failed ? Icons.refresh : Icons.download_outlined),
                label: Text(
                  failed
                      ? context.l10n.resumeDownload
                      : context.l10n.downloadForOffline,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _formatMegabytes(int bytes) {
  final value = bytes / (1024 * 1024);
  return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} MB';
}

class _SurahRow extends StatelessWidget {
  const _SurahRow({
    required this.surah,
    required this.locale,
    required this.onTap,
  });
  final Surah surah;
  final String locale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minTileHeight: 72,
      contentPadding: const EdgeInsetsDirectional.symmetric(
        horizontal: 14,
        vertical: 3,
      ),
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: context.iqroColors.panelSoft,
        child: Text(
          '${surah.number}',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
      title: Text(
        surah.nameFor(locale),
        style: Theme.of(context).textTheme.titleSmall,
      ),
      subtitle: Text(
        '${surah.ayahCount} ${context.l10n.ayahs} · ${surah.revelationType == 'meccan' ? context.l10n.meccan : context.l10n.medinan}',
      ),
      trailing: Text(
        surah.nameAr,
        textDirection: TextDirection.rtl,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontFamily: 'serif',
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      onTap: onTap,
    );
  }
}
