import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../core/audio/audio_controller.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import 'dua_presentation.dart';
import 'dua_repository.dart';

class DuaScreen extends ConsumerStatefulWidget {
  const DuaScreen({super.key});

  @override
  ConsumerState<DuaScreen> createState() => _DuaScreenState();
}

class _DuaScreenState extends ConsumerState<DuaScreen> {
  final _searchController = TextEditingController();
  DuaCategory? _category;
  var _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(duaCategoriesProvider);
    final entries = _category == null
        ? null
        : ref.watch(duaEntriesByCategoryProvider(_category!.slug));
    return PopScope(
      canPop: _category == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _category != null) _openCategory(null);
      },
      child: Scaffold(
        appBar: IqroTopBar(
          title: _category?.title ?? context.l10n.dua,
          subtitle: context.l10n.duaSubtitle,
          leading: _category == null
              ? null
              : IconButton(
                  tooltip: context.l10n.back,
                  onPressed: () => _openCategory(null),
                  icon: const Icon(Icons.arrow_back),
                ),
        ),
        body: IqroPage(
          child: _category == null
              ? _CategoryGrid(
                  categories: categories,
                  query: _query,
                  searchController: _searchController,
                  onQueryChanged: (value) =>
                      setState(() => _query = value.trim().toLowerCase()),
                  onOpen: _openCategory,
                  onRetry: () => ref.invalidate(duaCategoriesProvider),
                )
              : _EntryList(
                  entries: entries!,
                  query: _query,
                  searchController: _searchController,
                  onQueryChanged: (value) =>
                      setState(() => _query = value.trim().toLowerCase()),
                  onRetry: () => ref.invalidate(
                    duaEntriesByCategoryProvider(_category!.slug),
                  ),
                ),
        ),
      ),
    );
  }

  void _openCategory(DuaCategory? category) {
    _searchController.clear();
    setState(() {
      _category = category;
      _query = '';
    });
  }
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({
    required this.categories,
    required this.query,
    required this.searchController,
    required this.onQueryChanged,
    required this.onOpen,
    required this.onRetry,
  });

  final AsyncValue<List<DuaCategory>> categories;
  final String query;
  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<DuaCategory> onOpen;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SearchBar(
          controller: searchController,
          hintText: context.l10n.search,
          leading: const Icon(Icons.search),
          onChanged: onQueryChanged,
        ),
        const SizedBox(height: 18),
        categories.when(
          loading: () => const IqroLoading(),
          error: (error, stack) => IqroAsyncError(
            title: context.l10n.networkError,
            onRetry: onRetry,
          ),
          data: (items) {
            final visible = items
                .where((item) => item.title.toLowerCase().contains(query))
                .toList(growable: false);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.18,
              ),
              itemCount: visible.length,
              itemBuilder: (context, index) {
                final category = visible[index];
                return IqroCard(
                  color: index.isEven
                      ? context.iqroColors.sand
                      : context.iqroColors.lavender,
                  borderColor: Colors.transparent,
                  onTap: () => onOpen(category),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Icon(Icons.auto_awesome_outlined),
                      const Spacer(),
                      Text(
                        category.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${category.entryCount}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _EntryList extends StatelessWidget {
  const _EntryList({
    required this.entries,
    required this.query,
    required this.searchController,
    required this.onQueryChanged,
    required this.onRetry,
  });

  final AsyncValue<List<DuaEntry>> entries;
  final String query;
  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        SearchBar(
          controller: searchController,
          hintText: context.l10n.search,
          leading: const Icon(Icons.search),
          onChanged: onQueryChanged,
        ),
        const SizedBox(height: 18),
        entries.when(
          loading: () => const IqroLoading(),
          error: (error, stack) => IqroAsyncError(
            title: context.l10n.networkError,
            onRetry: onRetry,
          ),
          data: (items) {
            final visible = items
                .where((entry) {
                  if (query.isEmpty) return true;
                  return entry.meaning.toLowerCase().contains(query) ||
                      entry.transliteration.toLowerCase().contains(query) ||
                      entry.arabicText.contains(query);
                })
                .toList(growable: false);
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: visible.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final entry = visible[index];
                return IqroCard(
                  onTap: () => context.push('/dua/${entry.id}', extra: entry),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              entry.categoryTitle,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          Text(
                            '#${entry.sourceNumber}',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        entry.arabicText,
                        textDirection: TextDirection.rtl,
                        textAlign: TextAlign.right,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontFamily: 'serif',
                          height: 1.8,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: <Widget>[
                          Icon(
                            entry.isEditoriallyVerified
                                ? Icons.verified_outlined
                                : Icons.menu_book_outlined,
                            size: 17,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              entry.sourceLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          if (entry.audio.isNotEmpty) ...<Widget>[
                            const SizedBox(width: 8),
                            const Icon(Icons.headphones_outlined, size: 17),
                          ],
                          if (entry.repetitions > 1 ||
                              entry.repetitionLabel.isNotEmpty) ...<Widget>[
                            const SizedBox(width: 8),
                            const Icon(Icons.repeat, size: 17),
                          ],
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class DuaEntryScreen extends ConsumerStatefulWidget {
  const DuaEntryScreen({required this.entry, super.key});
  final DuaEntry entry;

  @override
  ConsumerState<DuaEntryScreen> createState() => _DuaEntryScreenState();
}

class _DuaEntryScreenState extends ConsumerState<DuaEntryScreen> {
  var _favorite = false;
  var _favoriteBusy = true;
  var _completedRepetitions = 0;
  var _selectedAudioIndex = 0;
  String? _ownedAudioId;
  final Object _audioOwner = Object();
  var _audioLoadFailed = false;
  late final AudioController _audioController;

  @override
  void initState() {
    super.initState();
    _audioController = ref.read(audioControllerProvider.notifier);
    unawaited(_loadFavorite());
  }

  Future<void> _loadFavorite() async {
    try {
      final value = await ref
          .read(duaRepositoryProvider)
          .isFavorite(widget.entry);
      if (!mounted) return;
      setState(() {
        _favorite = value;
        _favoriteBusy = false;
      });
    } on Object {
      if (mounted) setState(() => _favoriteBusy = false);
    }
  }

  @override
  void dispose() {
    final audioId = _ownedAudioId;
    if (audioId != null) {
      unawaited(_audioController.stopStandalone(audioId, owner: _audioOwner));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final audioState = ref.watch(audioControllerProvider).standalone;
    final stages = duaRepetitionStages(
      entry.repetitionLabel,
      entry.repetitions,
    );
    final progress = DuaPracticeProgress(
      stages: stages,
      completed: _completedRepetitions,
    );
    return Scaffold(
      appBar: IqroTopBar(
        title: entry.categoryTitle,
        subtitle: '#${entry.sourceNumber}',
        actions: <Widget>[
          Builder(
            builder: (buttonContext) => IconButton(
              tooltip: context.l10n.shareDua,
              icon: const Icon(Icons.ios_share_outlined),
              onPressed: () => unawaited(_share(buttonContext)),
            ),
          ),
          IconButton(
            tooltip: context.l10n.favorites,
            isSelected: _favorite,
            selectedIcon: const Icon(Icons.bookmark),
            icon: const Icon(Icons.bookmark_border),
            onPressed: _favoriteBusy ? null : _toggle,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: IqroPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            IqroCard(
              color: context.iqroColors.ink,
              borderColor: Colors.transparent,
              padding: const EdgeInsets.all(22),
              child: Text(
                entry.arabicText,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontFamily: 'serif',
                  height: 1.9,
                ),
              ),
            ),
            if (entry.transliteration.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              IqroCard(
                child: Text(
                  entry.transliteration,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ],
            if (entry.meaning.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              IqroCard(
                color: context.iqroColors.sand,
                borderColor: Colors.transparent,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    IqroEyebrow(context.l10n.translation),
                    const SizedBox(height: 8),
                    Text(
                      entry.meaning,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            ],
            if (entry.audio.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              _DuaAudioCard(
                entry: entry,
                selectedIndex: _selectedAudioIndex,
                state: audioState,
                loadFailed: _audioLoadFailed,
                onSelected: _selectAudio,
                onToggle: _toggleAudio,
                onRetry: _retryAudio,
                onSeek: (id, position) => ref
                    .read(audioControllerProvider.notifier)
                    .seekStandalone(id, position, owner: _audioOwner),
                onRepeat: (id) => ref
                    .read(audioControllerProvider.notifier)
                    .toggleStandaloneRepeat(id, owner: _audioOwner),
              ),
            ],
            if (progress.total > 1 ||
                entry.repetitionLabel.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              _DuaPracticeCard(
                progress: progress,
                onIncrement: _incrementPractice,
                onReset: _completedRepetitions == 0
                    ? null
                    : () => setState(() => _completedRepetitions = 0),
              ),
            ],
            const SizedBox(height: 14),
            _DuaSourceCard(entry: entry),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _copy,
                    icon: const Icon(Icons.copy_outlined),
                    label: Text(context.l10n.copyText),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Builder(
                    builder: (buttonContext) => FilledButton.icon(
                      onPressed: () => unawaited(_share(buttonContext)),
                      icon: const Icon(Icons.ios_share_outlined),
                      label: Text(context.l10n.shareDua),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggle() async {
    if (_favoriteBusy) return;
    setState(() => _favoriteBusy = true);
    try {
      final active = await ref
          .read(duaRepositoryProvider)
          .toggleFavorite(widget.entry);
      if (!mounted) return;
      setState(() => _favorite = active);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            active ? context.l10n.bookmarkAdded : context.l10n.bookmarkRemoved,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _favoriteBusy = false);
    }
  }

  void _selectAudio(int index) {
    if (index == _selectedAudioIndex) return;
    final audioId = _ownedAudioId;
    _ownedAudioId = null;
    setState(() {
      _selectedAudioIndex = index;
      _audioLoadFailed = false;
    });
    if (audioId != null) {
      unawaited(_audioController.stopStandalone(audioId, owner: _audioOwner));
    }
  }

  Future<void> _toggleAudio() => _playAudio(forceReload: false);

  Future<void> _retryAudio() => _playAudio(forceReload: true);

  Future<void> _playAudio({required bool forceReload}) async {
    final entry = widget.entry;
    if (entry.audio.isEmpty || _selectedAudioIndex >= entry.audio.length) {
      return;
    }
    final asset = entry.audio[_selectedAudioIndex];
    final id = duaAudioPlaybackId(entry, asset, _selectedAudioIndex);
    final controller = _audioController;
    final current = ref.read(audioControllerProvider).standalone;
    try {
      if (!forceReload && current?.mediaItem.id == id) {
        _ownedAudioId = id;
        await controller.toggleStandalone(id, owner: _audioOwner);
      } else {
        final locale = Localizations.localeOf(context).languageCode;
        _ownedAudioId = id;
        if (mounted && _audioLoadFailed) {
          setState(() => _audioLoadFailed = false);
        }
        await controller.loadStandalone(
          id: id,
          url: asset.url,
          title: '${entry.categoryTitle} · #${entry.sourceNumber}',
          album: 'IQRO · ${context.l10n.dua}',
          contentType: 'dua',
          artist: _duaAudioReader(asset, locale),
          extras: <String, dynamic>{
            'collection': entry.collection,
            'source_number': entry.sourceNumber,
          },
          owner: _audioOwner,
        );
      }
    } on Object {
      if (mounted) setState(() => _audioLoadFailed = true);
    }
  }

  void _incrementPractice() {
    final stages = duaRepetitionStages(
      widget.entry.repetitionLabel,
      widget.entry.repetitions,
    );
    final target = stages.fold<int>(0, (sum, stage) => sum + stage);
    if (_completedRepetitions >= target) return;
    final next = _completedRepetitions + 1;
    setState(() => _completedRepetitions = next);
    if (next == target) {
      unawaited(HapticFeedback.mediumImpact());
    } else {
      unawaited(HapticFeedback.selectionClick());
    }
  }

  String _shareText() => duaShareText(
    widget.entry,
    translationLabel: context.l10n.translation,
    repetitionLabel: context.l10n.repetitionTarget,
    sourceLabel: context.l10n.sourceAndVerification,
  );

  Future<void> _copy() async {
    final confirmation = context.l10n.textCopied;
    await Clipboard.setData(ClipboardData(text: _shareText()));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(confirmation)));
  }

  Future<void> _share(BuildContext buttonContext) async {
    final box = buttonContext.findRenderObject();
    final origin = box is RenderBox
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    await SharePlus.instance.share(
      ShareParams(
        subject: widget.entry.categoryTitle,
        title: context.l10n.shareDua,
        text: _shareText(),
        sharePositionOrigin: origin,
      ),
    );
  }
}

class _DuaAudioCard extends StatelessWidget {
  const _DuaAudioCard({
    required this.entry,
    required this.selectedIndex,
    required this.state,
    required this.loadFailed,
    required this.onSelected,
    required this.onToggle,
    required this.onRetry,
    required this.onSeek,
    required this.onRepeat,
  });

  final DuaEntry entry;
  final int selectedIndex;
  final IqroStandaloneAudioState? state;
  final bool loadFailed;
  final ValueChanged<int> onSelected;
  final Future<void> Function() onToggle;
  final Future<void> Function() onRetry;
  final Future<void> Function(String, Duration) onSeek;
  final Future<void> Function(String) onRepeat;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final safeIndex = selectedIndex.clamp(0, entry.audio.length - 1);
    final asset = entry.audio[safeIndex];
    final playbackId = duaAudioPlaybackId(entry, asset, safeIndex);
    final active = state?.mediaItem.id == playbackId;
    final duration = active ? state!.duration : Duration.zero;
    final position = active
        ? clampIqroAudioPosition(state!.position, duration)
        : Duration.zero;
    final loading = active && state!.loading;
    final playbackFailed = active && state!.error != null;
    final repeating = active && state!.repeatEnabled;
    return IqroCard(
      color: context.iqroColors.ink,
      borderColor: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.headphones_outlined, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.l10n.duaAudio,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: Colors.white),
                ),
              ),
              if (asset.provider.isNotEmpty)
                Text(
                  asset.provider,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .55),
                    fontSize: 11,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (entry.audio.length > 1)
            DropdownButtonFormField<int>(
              key: ValueKey<String>('dua-audio-${entry.id}-$safeIndex'),
              initialValue: safeIndex,
              dropdownColor: context.iqroColors.ink,
              style: const TextStyle(color: Colors.white),
              iconEnabledColor: Colors.white,
              decoration: InputDecoration(
                labelText: context.l10n.duaReader,
                labelStyle: TextStyle(
                  color: Colors.white.withValues(alpha: .7),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: .22),
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              items: <DropdownMenuItem<int>>[
                for (var index = 0; index < entry.audio.length; index += 1)
                  DropdownMenuItem<int>(
                    value: index,
                    child: Text(
                      _duaAudioReader(entry.audio[index], locale),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) onSelected(value);
              },
            )
          else
            Text(
              _duaAudioReader(asset, locale),
              style: TextStyle(color: Colors.white.withValues(alpha: .72)),
            ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              SizedBox.square(
                dimension: 54,
                child: IconButton.filled(
                  tooltip: active && state?.playing == true
                      ? context.l10n.pause
                      : context.l10n.play,
                  onPressed: loading ? null : () => unawaited(onToggle()),
                  icon: loading
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          active && state?.playing == true
                              ? Icons.pause
                              : Icons.play_arrow,
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DuaSeekSlider(
                  mediaId: playbackId,
                  active: active,
                  position: position,
                  duration: duration,
                  onSeek: onSeek,
                ),
              ),
              IconButton(
                tooltip: repeating
                    ? context.l10n.repeatOn
                    : context.l10n.repeatOff,
                color: repeating
                    ? Theme.of(context).colorScheme.tertiary
                    : Colors.white,
                onPressed: active
                    ? () => unawaited(onRepeat(playbackId))
                    : null,
                icon: const Icon(Icons.repeat),
              ),
            ],
          ),
          if (loadFailed || playbackFailed) ...<Widget>[
            const SizedBox(height: 10),
            _DuaAudioError(onRetry: () => unawaited(onRetry())),
          ],
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Icon(
                Icons.wifi_outlined,
                color: Colors.white.withValues(alpha: .5),
                size: 16,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  context.l10n.duaAudioStreaming,
                  style: _audioMetaStyle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static const _audioMetaStyle = TextStyle(
    color: Color(0x99FFFFFF),
    fontSize: 11,
  );
}

class _DuaSeekSlider extends StatefulWidget {
  const _DuaSeekSlider({
    required this.mediaId,
    required this.active,
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  final String mediaId;
  final bool active;
  final Duration position;
  final Duration duration;
  final Future<void> Function(String, Duration) onSeek;

  @override
  State<_DuaSeekSlider> createState() => _DuaSeekSliderState();
}

class _DuaSeekSliderState extends State<_DuaSeekSlider> {
  double? _previewMilliseconds;

  @override
  void didUpdateWidget(covariant _DuaSeekSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaId != widget.mediaId || !widget.active) {
      _previewMilliseconds = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final durationMs = widget.duration.inMilliseconds;
    final maximum = durationMs <= 0 ? 1 : durationMs;
    final livePosition = widget.position.inMilliseconds.clamp(0, maximum);
    final shownPosition = (_previewMilliseconds ?? livePosition.toDouble())
        .clamp(0, maximum.toDouble())
        .toDouble();
    return Column(
      children: <Widget>[
        Slider(
          value: shownPosition,
          min: 0,
          max: maximum.toDouble(),
          onChanged: widget.active && durationMs > 0
              ? (value) => setState(() => _previewMilliseconds = value)
              : null,
          onChangeEnd: widget.active && durationMs > 0
              ? (value) {
                  setState(() => _previewMilliseconds = null);
                  unawaited(
                    widget.onSeek(
                      widget.mediaId,
                      Duration(milliseconds: value.round()),
                    ),
                  );
                }
              : null,
        ),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                _duaDuration(Duration(milliseconds: shownPosition.round())),
                style: _DuaAudioCard._audioMetaStyle,
              ),
              Text(
                durationMs > 0 ? _duaDuration(widget.duration) : '--:--',
                style: _DuaAudioCard._audioMetaStyle,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DuaAudioError extends StatelessWidget {
  const _DuaAudioError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.error_outline,
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.l10n.duaAudioFailed,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(context.l10n.retry)),
        ],
      ),
    );
  }
}

class _DuaPracticeCard extends StatelessWidget {
  const _DuaPracticeCard({
    required this.progress,
    required this.onIncrement,
    required this.onReset,
  });

  final DuaPracticeProgress progress;
  final VoidCallback onIncrement;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return IqroCard(
      color: context.iqroColors.sand,
      borderColor: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.repeat),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.l10n.duaPractice,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                '${progress.completed} / ${progress.total}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Semantics(
            value: '${progress.completed} / ${progress.total}',
            child: LinearProgressIndicator(value: progress.fraction),
          ),
          if (progress.stages.length > 1) ...<Widget>[
            const SizedBox(height: 12),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: <Widget>[
                for (var index = 0; index < progress.stages.length; index += 1)
                  _PracticeStage(
                    label: '${context.l10n.practiceStage} ${index + 1}',
                    target: progress.stages[index],
                    active: index == progress.stageIndex,
                    complete:
                        index < progress.stageIndex || progress.isComplete,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${context.l10n.practiceStage} ${progress.stageIndex + 1}: '
              '${progress.completedInStage} / ${progress.stageTarget}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: progress.isComplete ? null : onIncrement,
            icon: Icon(
              progress.isComplete ? Icons.check_circle : Icons.add_circle,
            ),
            label: Text(
              progress.isComplete
                  ? context.l10n.completed
                  : context.l10n.markRepetition,
            ),
          ),
          TextButton(onPressed: onReset, child: Text(context.l10n.reset)),
          Text(
            context.l10n.duaPracticeHint,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _PracticeStage extends StatelessWidget {
  const _PracticeStage({
    required this.label,
    required this.target,
    required this.active,
    required this.complete,
  });

  final String label;
  final int target;
  final bool active;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: active,
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: 10,
          vertical: 7,
        ),
        decoration: BoxDecoration(
          color: active
              ? colorScheme.primary
              : complete
              ? colorScheme.primaryContainer
              : colorScheme.surface.withValues(alpha: .7),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (complete) ...<Widget>[
              Icon(
                Icons.check,
                size: 14,
                color: active ? colorScheme.onPrimary : colorScheme.primary,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              '$label · $target',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: active ? colorScheme.onPrimary : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DuaSourceCard extends StatelessWidget {
  const _DuaSourceCard({required this.entry});

  final DuaEntry entry;

  @override
  Widget build(BuildContext context) {
    final source = entry.source;
    final verified = entry.isEditoriallyVerified;
    return IqroCard(
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsetsDirectional.only(top: 4, bottom: 4),
        leading: Icon(
          verified ? Icons.verified_outlined : Icons.menu_book_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Text(context.l10n.sourceAndVerification),
        subtitle: Text(
          verified
              ? context.l10n.editoriallyVerified
              : entry.hasDeclaredSource
              ? context.l10n.sourceDeclared
              : context.l10n.sourceUnavailable,
        ),
        children: <Widget>[
          const Divider(),
          if (entry.sourceLabel.isNotEmpty)
            _SourceValue(
              label: context.l10n.sourceAndVerification,
              value: entry.sourceLabel,
            ),
          if (source != null) ...<Widget>[
            _SourceValue(label: context.l10n.author, value: source.author),
            _SourceValue(
              label: context.l10n.translator,
              value: source.translator,
            ),
            _SourceValue(label: context.l10n.reviewer, value: source.reviewer),
            _SourceValue(
              label: context.l10n.sourceVersion,
              value: source.sourceVersion,
            ),
            _SourceValue(
              label: context.l10n.sourceReference,
              value: source.sourceUrl,
              selectable: true,
            ),
            _SourceValue(
              label: context.l10n.rights,
              value: source.rightsUrl,
              selectable: true,
            ),
          ],
          for (final evidence in entry.evidence) ...<Widget>[
            const Divider(height: 24),
            _SourceValue(
              label: evidence.sourceName.isEmpty
                  ? context.l10n.sourceReference
                  : evidence.sourceName,
              value: evidence.sourceReference,
            ),
            _SourceValue(label: context.l10n.grade, value: evidence.grade),
            _SourceValue(
              label: context.l10n.sourceReference,
              value: evidence.sourceUrl,
              selectable: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _SourceValue extends StatelessWidget {
  const _SourceValue({
    required this.label,
    required this.value,
    this.selectable = false,
  });

  final String label;
  final String value;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    final valueStyle = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 112,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: selectable
                ? SelectableText(value, style: valueStyle)
                : Text(value, style: valueStyle),
          ),
        ],
      ),
    );
  }
}

String _duaAudioReader(DuaAudioAsset asset, String locale) {
  if (locale == 'ar' && asset.readerNameAr.trim().isNotEmpty) {
    return asset.readerNameAr.trim();
  }
  if (asset.readerName.trim().isNotEmpty) return asset.readerName.trim();
  if (asset.provider.trim().isNotEmpty) return asset.provider.trim();
  return 'IQRO';
}

String _duaDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
