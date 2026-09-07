import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/storage/offline_storage_quota.dart';
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
    final accountScopeKey = ref.watch(activeAccountScopeKeyProvider);
    final position = accountScopeKey == null
        ? null
        : ref.watch(readingPositionProvider(accountScopeKey)).valueOrNull;
    final locale = Localizations.localeOf(context).languageCode;
    final identity = ref.watch(selectedMushafIdentityProvider);
    final rendition = identity.isCanonical
        ? null
        : ref
              .watch(mushafRenditionsProvider)
              .valueOrNull
              ?.where((item) => item.identity == identity)
              .firstOrNull;
    final positionSurah = catalog.valueOrNull?.surahs
        .where((surah) => surah.number == (position?.surah ?? 1))
        .firstOrNull;
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
                              identity.isCanonical
                                  ? context.l10n.mushafScanName
                                  : rendition?.nameFor(locale) ??
                                        'QCF V2 · IQRO',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              identity.isCanonical
                                  ? context.l10n.mushafScanDescription
                                  : context.l10n.mushafPreviewDescription,
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
              onTap: position == null
                  ? null
                  : () => _openPosition(
                      preferences.readerMode,
                      position.surah,
                      position.ayah,
                      position.page,
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
                          position == null
                              ? context.l10n.loading
                              : '${positionSurah?.nameFor(locale) ?? '${context.l10n.surah} ${position.surah}'}'
                                    ' · ${context.l10n.ayah} ${position.ayah}',
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
                                  1,
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

  void _openPosition(ReaderMode mode, int surah, int ayah, int page) {
    if (mode == ReaderMode.mushaf) {
      context.push('/mushaf?page=$page&surah=$surah&ayah=$ayah');
    } else {
      context.push('/reader/$surah?ayah=$ayah');
    }
  }

  Future<void> _showMushafPicker(BuildContext context) async {
    ref.invalidate(mushafRenditionsProvider);
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => Consumer(
        builder: (context, sheetRef, _) {
          final current = sheetRef.watch(selectedMushafIdentityProvider);
          final catalog = sheetRef.watch(mushafRenditionsProvider);
          final locale = Localizations.localeOf(context).languageCode;
          return RadioGroup<String>(
            groupValue: current.preference,
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
                ...catalog.when(
                  loading: () => <Widget>[
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: IqroLoading(),
                    ),
                  ],
                  error: (_, _) => <Widget>[
                    ListTile(
                      title: Text(context.l10n.networkError),
                      trailing: IconButton(
                        tooltip: context.l10n.retry,
                        icon: const Icon(Icons.refresh),
                        onPressed: () =>
                            sheetRef.invalidate(mushafRenditionsProvider),
                      ),
                    ),
                  ],
                  data: (editions) => <Widget>[
                    for (final edition in editions)
                      if (edition.availableIn(
                        isProduction: sheetRef
                            .read(appConfigProvider)
                            .isProduction,
                      ))
                        RadioListTile<String>(
                          value: edition.identity.preference,
                          title: Text(edition.nameFor(locale)),
                          subtitle: Text(
                            edition.stagingOnly
                                ? context.l10n.mushafPreviewDescription
                                : context.l10n.mushafPublishedDescription,
                          ),
                          secondary: const Icon(Icons.auto_stories_outlined),
                        ),
                  ],
                ),
                const Divider(height: 28),
                const _OfflineMushafCard(),
                const SizedBox(height: 12),
              ],
            ),
          );
        },
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
      final results = await Future.wait<Object?>(<Future<Object?>>[
        _optionalQuickJumpData(repository.surahs()),
        _optionalQuickJumpData(repository.juz()),
        _optionalQuickJumpData(repository.hizb()),
        _optionalQuickJumpData(repository.rubElHizb()),
      ]);
      final catalog = results[0] as QuranCatalog?;
      final juz = results[1] as List<QuranDivision>?;
      final hizb = results[2] as List<QuranDivision>?;
      final rubElHizb = results[3] as List<QuranDivision>?;
      if (!context.mounted) return;
      final selection = await showModalBottomSheet<QuranQuickJumpSelection>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => QuranQuickJumpSheet(
          surahs: catalog?.surahs ?? const <Surah>[],
          juz: juz ?? const <QuranDivision>[],
          hizb: hizb ?? const <QuranDivision>[],
          rubElHizb: rubElHizb ?? const <QuranDivision>[],
        ),
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

  Future<T?> _optionalQuickJumpData<T>(Future<T> request) async {
    try {
      return await request;
    } on Object {
      return null;
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

class _OfflineMushafCard extends ConsumerStatefulWidget {
  const _OfflineMushafCard();

  @override
  ConsumerState<_OfflineMushafCard> createState() => _OfflineMushafCardState();
}

class _OfflineMushafCardState extends ConsumerState<_OfflineMushafCard> {
  var _preparing = false;

  @override
  Widget build(BuildContext context) {
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
                    : _preparing
                    ? null
                    : _prepareDownload,
                icon: _preparing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(failed ? Icons.refresh : Icons.download_outlined),
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

  Future<void> _prepareDownload() async {
    if (_preparing) return;
    setState(() => _preparing = true);
    try {
      final estimate = await ref
          .read(selectedMushafOfflineRepositoryProvider)
          .estimate();
      await ensureOfflineStorageCapacity(
        ref.read(localDatabaseProvider),
        packageId: estimate.packageId!,
        packageBytes: estimate.totalBytes,
      );
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.downloadForOffline),
          content: Text(
            context.l10n.downloadOfflineConfirmation(
              _formatMegabytes(estimate.totalBytes),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.downloadForOffline),
            ),
          ],
        ),
      );
      if (confirmed == true && mounted) {
        unawaited(
          ref.read(selectedMushafDownloadControllerProvider).download(),
        );
      }
    } on OfflineStorageQuotaExceeded {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.offlineStorageQuotaExceeded)),
      );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.networkError)));
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
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
