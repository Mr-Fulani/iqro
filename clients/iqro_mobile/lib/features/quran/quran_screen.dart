import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/storage/preferences_store.dart';
import '../../core/theme/iqro_theme.dart';
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
    final mushafVariants = ref.watch(mushafVariantsProvider).valueOrNull;
    final position = ref.watch(readingPositionProvider).valueOrNull;
    final selectedVariant = mushafVariants
        ?.where(
          (variant) => variant.preferenceValue == preferences.mushafVariant,
        )
        .firstOrNull;
    final selectedMushafName = preferences.mushafVariant == defaultMushafVariant
        ? context.l10n.mushafScanName
        : selectedVariant == null
        ? 'KFGQPC HAFS · Hafs'
        : '${selectedVariant.name} · ${selectedVariant.qiratName}';
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
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 0),
        child: Column(
          children: <Widget>[
            IqroCard(
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
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _showMushafPicker(
                        context,
                        selected: preferences.mushafVariant,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    context.l10n.selectedMushaf,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    selectedMushafName,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                    ),
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

  Future<void> _showQuickJump(BuildContext context) async {
    final catalog = await ref.read(quranRepositoryProvider).surahs();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _QuickJumpSheet(
        surahs: catalog.surahs,
        readerMode: ref.read(appPreferencesProvider).readerMode,
      ),
    );
  }

  Future<void> _showMushafPicker(
    BuildContext context, {
    required String selected,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _MushafPickerSheet(selected: selected),
    );
  }
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

class _QuickJumpSheet extends StatefulWidget {
  const _QuickJumpSheet({required this.surahs, required this.readerMode});
  final List<Surah> surahs;
  final ReaderMode readerMode;

  @override
  State<_QuickJumpSheet> createState() => _QuickJumpSheetState();
}

class _QuickJumpSheetState extends State<_QuickJumpSheet> {
  var _mode = 0;
  var _surah = 1;
  var _ayah = 1;
  var _number = 1;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        20,
        12,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 18),
          IqroEyebrow(context.l10n.navigation),
          Text(
            context.l10n.quickJump,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 18),
          SegmentedButton<int>(
            segments: <ButtonSegment<int>>[
              ButtonSegment(value: 0, label: Text(context.l10n.ayah)),
              ButtonSegment(value: 1, label: Text(context.l10n.juz)),
              ButtonSegment(value: 2, label: Text(context.l10n.page)),
            ],
            selected: <int>{_mode},
            onSelectionChanged: (value) => setState(() => _mode = value.first),
            showSelectedIcon: false,
          ),
          const SizedBox(height: 18),
          if (_mode == 0)
            Row(
              children: <Widget>[
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<int>(
                    initialValue: _surah,
                    decoration: InputDecoration(labelText: context.l10n.surah),
                    items: widget.surahs
                        .map(
                          (surah) => DropdownMenuItem(
                            value: surah.number,
                            child: Text(
                              '${surah.number}. ${surah.nameFor(Localizations.localeOf(context).languageCode)}',
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) => setState(() => _surah = value ?? 1),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    initialValue: '1',
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: context.l10n.ayah),
                    onChanged: (value) => _ayah = int.tryParse(value) ?? 1,
                  ),
                ),
              ],
            )
          else
            TextFormField(
              initialValue: '1',
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: _mode == 1 ? context.l10n.juz : context.l10n.page,
              ),
              onChanged: (value) => _number = int.tryParse(value) ?? 1,
            ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                if (_mode == 2) {
                  context.push(
                    '/mushaf?page=${_number.clamp(1, 604)}&surah=1&ayah=1',
                  );
                } else if (_mode == 1) {
                  final page = ((_number.clamp(1, 30) - 1) * 20) + 1;
                  context.push('/mushaf?page=$page&surah=1&ayah=1');
                } else if (widget.readerMode == ReaderMode.mushaf) {
                  final surah = widget.surahs
                      .where((item) => item.number == _surah)
                      .firstOrNull;
                  context.push(
                    '/mushaf?page=${surah?.firstPage ?? 1}&surah=$_surah&ayah=$_ayah',
                  );
                } else {
                  context.push('/reader/$_surah?ayah=$_ayah');
                }
              },
              icon: const Icon(Icons.arrow_forward),
              label: Text(context.l10n.open),
            ),
          ),
        ],
      ),
    );
  }
}

class _MushafPickerSheet extends ConsumerWidget {
  const _MushafPickerSheet({required this.selected});

  final String selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final variants = ref.watch(mushafVariantsProvider);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            context.l10n.chooseMushaf,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          _MushafChoice(
            value: defaultMushafVariant,
            selected: selected,
            title: context.l10n.mushafScanName,
            subtitle: context.l10n.mushafScanDescription,
            enabled: true,
            onSelected: (value) => _select(context, ref, value),
          ),
          variants.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stack) => IqroAsyncError(
              title: context.l10n.noQuranData,
              message: context.l10n.networkError,
              onRetry: () => ref.invalidate(mushafVariantsProvider),
            ),
            data: (items) => Flexible(
              child: ListView(
                shrinkWrap: true,
                children: items
                    .map((variant) {
                      final available = variant.supportedOnMobile;
                      final subtitle = available
                          ? context.l10n.mushafTextDescription
                          : variant.renderingAvailable
                          ? context.l10n.mushafWebOnly
                          : context.l10n.mushafUnavailable;
                      return _MushafChoice(
                        value: variant.preferenceValue,
                        selected: selected,
                        title: '${variant.name} · ${variant.qiratName}',
                        subtitle: subtitle,
                        enabled: available,
                        onSelected: (value) => _select(context, ref, value),
                      );
                    })
                    .toList(growable: false),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _select(
    BuildContext context,
    WidgetRef ref,
    String value,
  ) async {
    await ref.read(appPreferencesProvider.notifier).setMushafVariant(value);
    if (context.mounted) Navigator.pop(context);
  }
}

class _MushafChoice extends StatelessWidget {
  const _MushafChoice({
    required this.value,
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onSelected,
  });

  final String value;
  final String selected;
  final String title;
  final String subtitle;
  final bool enabled;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final isSelected = value == selected;
    return ListTile(
      enabled: enabled,
      minTileHeight: 72,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        isSelected ? Icons.check_circle : Icons.circle_outlined,
        color: isSelected ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: enabled ? () => onSelected(value) : null,
    );
  }
}
