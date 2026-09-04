import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../core/audio/audio_controller.dart';
import '../../core/auth/account_scope.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import 'dua_presentation.dart';
import 'dua_repository.dart';

class DuaScreen extends ConsumerStatefulWidget {
  const DuaScreen({this.initialCollection, this.initialCategory, super.key});

  final String? initialCollection;
  final String? initialCategory;

  @override
  ConsumerState<DuaScreen> createState() => _DuaScreenState();
}

class _DuaScreenState extends ConsumerState<DuaScreen> {
  final _searchController = TextEditingController();
  DuaCategoryIdentity? _categoryIdentity;
  String? _legacyCategorySlug;
  var _query = '';
  var _submittedQuery = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    final collection = widget.initialCollection?.trim() ?? '';
    final category = widget.initialCategory?.trim() ?? '';
    if (collection.isNotEmpty && category.isNotEmpty) {
      _categoryIdentity = (collection: collection, slug: category);
    } else if (category.isNotEmpty) {
      _legacyCategorySlug = category;
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(duaCategoriesProvider);
    final legacyMatches = _legacyCategorySlug == null
        ? const <DuaCategory>[]
        : categories.valueOrNull
                  ?.where((item) => item.slug == _legacyCategorySlug)
                  .toList(growable: false) ??
              const <DuaCategory>[];
    final activeCategoryIdentity =
        _categoryIdentity ??
        (legacyMatches.length == 1 ? legacyMatches.single.identity : null);
    final category = activeCategoryIdentity == null
        ? null
        : categories.valueOrNull
              ?.where((item) => item.identity == activeCategoryIdentity)
              .firstOrNull;
    final entries = activeCategoryIdentity == null
        ? null
        : ref.watch(duaEntriesByCategoryProvider(activeCategoryIdentity));
    final searchRequest = (
      query: _submittedQuery,
      collection: null as String?,
      category: null as String?,
    );
    final searchResults =
        activeCategoryIdentity == null && _submittedQuery.length >= 2
        ? ref.watch(duaSearchProvider(searchRequest))
        : null;
    return PopScope(
      canPop: activeCategoryIdentity == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && activeCategoryIdentity != null) _openCategory(null);
      },
      child: Scaffold(
        appBar: IqroTopBar(
          title: category?.title ?? context.l10n.dua,
          subtitle: category == null
              ? context.l10n.duaSubtitle
              : category.collectionTitle.isEmpty
              ? category.collection
              : category.collectionTitle,
          leading: activeCategoryIdentity == null
              ? null
              : IconButton(
                  tooltip: context.l10n.back,
                  onPressed: () => _openCategory(null),
                  icon: const Icon(Icons.arrow_back),
                ),
        ),
        body: IqroPage(
          scrollable: false,
          child: activeCategoryIdentity == null
              ? _DuaCatalog(
                  categories: categories,
                  searchResults: searchResults,
                  searchPending:
                      _query.length >= 2 && _query != _submittedQuery,
                  query: _query,
                  searchController: _searchController,
                  onQueryChanged: _onRootQueryChanged,
                  onOpen: _openCategory,
                  onCategoriesRetry: () =>
                      ref.invalidate(duaCategoriesProvider),
                  onSearchRetry: () =>
                      ref.invalidate(duaSearchProvider(searchRequest)),
                )
              : _EntryList(
                  entries: entries!,
                  query: _query,
                  searchController: _searchController,
                  onQueryChanged: (value) =>
                      setState(() => _query = value.trim()),
                  onRetry: () => ref.invalidate(
                    duaEntriesByCategoryProvider(activeCategoryIdentity),
                  ),
                ),
        ),
      ),
    );
  }

  void _openCategory(DuaCategory? category) {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _categoryIdentity = category?.identity;
      _legacyCategorySlug = null;
      _query = '';
      _submittedQuery = '';
    });
  }

  void _onRootQueryChanged(String value) {
    final query = value.trim();
    _searchDebounce?.cancel();
    setState(() {
      _query = query;
      if (query.length < 2) _submittedQuery = '';
    });
    if (query.length < 2) return;
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted || _query != query) return;
      setState(() => _submittedQuery = query);
    });
  }
}

class _DuaCatalog extends StatelessWidget {
  const _DuaCatalog({
    required this.categories,
    required this.searchResults,
    required this.searchPending,
    required this.query,
    required this.searchController,
    required this.onQueryChanged,
    required this.onOpen,
    required this.onCategoriesRetry,
    required this.onSearchRetry,
  });

  final AsyncValue<List<DuaCategory>> categories;
  final AsyncValue<List<DuaEntry>>? searchResults;
  final bool searchPending;
  final String query;
  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<DuaCategory> onOpen;
  final VoidCallback onCategoriesRetry;
  final VoidCallback onSearchRetry;

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
        Expanded(
          child: query.isNotEmpty
              ? query.length < 2
                    ? _DuaEmpty(message: context.l10n.duaSearchMinCharacters)
                    : searchPending || searchResults == null
                    ? const IqroLoading()
                    : _AsyncDuaEntries(
                        entries: searchResults!,
                        query: '',
                        onRetry: onSearchRetry,
                      )
              : categories.when(
                  loading: () => const IqroLoading(),
                  error: (error, stack) => IqroAsyncError(
                    title: context.l10n.networkError,
                    onRetry: onCategoriesRetry,
                  ),
                  data: (items) {
                    if (items.isEmpty) {
                      return _DuaEmpty(message: context.l10n.noDuaCategories);
                    }
                    final showCollection =
                        items.map((item) => item.collection).toSet().length > 1;
                    return ListView.separated(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: items.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final category = items[index];
                        return IqroCard(
                          color: index.isEven
                              ? context.iqroColors.sand
                              : context.iqroColors.lavender,
                          borderColor: Colors.transparent,
                          onTap: () => onOpen(category),
                          child: Row(
                            children: <Widget>[
                              const Icon(Icons.auto_awesome_outlined),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      category.title,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleSmall,
                                    ),
                                    if (showCollection) ...<Widget>[
                                      const SizedBox(height: 3),
                                      Text(
                                        category.collectionTitle.isEmpty
                                            ? category.collection
                                            : category.collectionTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelSmall,
                                      ),
                                    ],
                                    const SizedBox(height: 4),
                                    Text(
                                      context.l10n.duaCount(
                                        category.entryCount,
                                      ),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
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
        Expanded(
          child: _AsyncDuaEntries(
            entries: entries,
            query: query,
            onRetry: onRetry,
          ),
        ),
      ],
    );
  }
}

class _AsyncDuaEntries extends StatelessWidget {
  const _AsyncDuaEntries({
    required this.entries,
    required this.query,
    required this.onRetry,
  });

  final AsyncValue<List<DuaEntry>> entries;
  final String query;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return entries.when(
      loading: () => const IqroLoading(),
      error: (error, stack) =>
          IqroAsyncError(title: context.l10n.networkError, onRetry: onRetry),
      data: (items) {
        final normalizedQuery = query.toLowerCase();
        final visible = items
            .where((entry) {
              if (normalizedQuery.isEmpty) return true;
              return entry.meaning.toLowerCase().contains(normalizedQuery) ||
                  entry.transliteration.toLowerCase().contains(
                    normalizedQuery,
                  ) ||
                  entry.arabicText.contains(query);
            })
            .toList(growable: false);
        if (visible.isEmpty) {
          return _DuaEmpty(message: context.l10n.noDuaFound);
        }
        return ListView.separated(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          itemCount: visible.length,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) => _DuaEntryCard(entry: visible[index]),
        );
      },
    );
  }
}

class _DuaEntryCard extends StatelessWidget {
  const _DuaEntryCard({required this.entry});

  final DuaEntry entry;

  @override
  Widget build(BuildContext context) {
    return IqroCard(
      onTap: () => context.push(duaEntryRoute(entry), extra: entry),
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
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontFamily: 'serif', height: 1.8),
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
                  entry.sourceLabel.isEmpty
                      ? context.l10n.sourceUnavailable
                      : entry.sourceLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (entry.catalogVersionVerified &&
                  entry.audio.isNotEmpty) ...<Widget>[
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
  }
}

class _DuaEmpty extends StatelessWidget {
  const _DuaEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.auto_awesome_outlined,
              size: 42,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class DuaEntryRouteScreen extends ConsumerWidget {
  const DuaEntryRouteScreen({
    this.entryId,
    this.collection,
    this.sourceNumber,
    this.initialEntry,
    super.key,
  }) : assert(entryId != null || (collection != null && sourceNumber != null));

  final String? entryId;
  final String? collection;
  final int? sourceNumber;
  final DuaEntry? initialEntry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The audio controller is account-owned. Watching its identity makes this
    // route rebuild at the same boundary as the rest of the private UI while
    // keeping the public dua request independent from authentication.
    ref.watch(audioControllerProvider.notifier);
    final accountScope = ref.watch(localDatabaseProvider).accountScope;
    final activeAccount = accountScope.current;
    final accountKey = activeAccount == null
        ? '__no_account__:${accountScope.epoch}'
        : '${activeAccount.userId}:${activeAccount.epoch}';
    final identity = collection == null || sourceNumber == null
        ? null
        : (collection: collection!, sourceNumber: sourceNumber!);
    final result = identity == null
        ? ref.watch(duaEntryProvider(entryId ?? ''))
        : ref.watch(duaEntryByReferenceProvider(identity));
    void retry() {
      if (identity == null) {
        ref.invalidate(duaEntryProvider(entryId ?? ''));
      } else {
        ref.invalidate(duaEntryByReferenceProvider(identity));
      }
    }

    final error = result.hasError ? result.error : null;
    final resolved = error == null ? result.valueOrNull : null;
    final mayUseInitialEntry =
        result.isLoading ||
        (error != null && canUseUnverifiedDuaFallback(error));
    final fallback = resolved ?? (mayUseInitialEntry ? initialEntry : null);
    if (fallback != null) {
      final trusted = resolved?.catalogVersionVerified == true;
      final canRetry = !trusted && !result.isLoading;
      return DuaEntryScreen(
        key: ValueKey<String>(
          '$accountKey:${fallback.id}:'
          '${fallback.collectionVersion}:$trusted',
        ),
        entry: fallback,
        audioEnabled: trusted,
        showCachedWarning: !trusted,
        onRevalidate: canRetry ? retry : null,
      );
    }
    return Scaffold(
      appBar: IqroTopBar(title: context.l10n.dua),
      body: result.when(
        loading: () => const IqroLoading(),
        error: (error, stack) =>
            IqroAsyncError(title: context.l10n.duaUnavailable, onRetry: retry),
        data: (_) => _DuaEmpty(message: context.l10n.noDuaFound),
      ),
    );
  }
}

class DuaEntryScreen extends ConsumerStatefulWidget {
  const DuaEntryScreen({
    required this.entry,
    this.audioEnabled = true,
    this.showCachedWarning = false,
    this.onRevalidate,
    super.key,
  });
  final DuaEntry entry;
  final bool audioEnabled;
  final bool showCachedWarning;
  final VoidCallback? onRevalidate;

  @override
  ConsumerState<DuaEntryScreen> createState() => _DuaEntryScreenState();
}

bool _sameAccountScope(
  AccountScopeSnapshot? left,
  AccountScopeSnapshot? right,
) => left?.userId == right?.userId && left?.epoch == right?.epoch;

class _DuaEntryScreenState extends ConsumerState<DuaEntryScreen> {
  var _favorite = false;
  var _favoriteBusy = true;
  var _completedRepetitions = 0;
  var _selectedAudioIndex = 0;
  String? _ownedAudioId;
  Object _audioOwner = Object();
  var _audioLoadFailed = false;
  late AudioController _audioController;
  AccountScopeSnapshot? _accountScope;
  var _accountGeneration = 0;
  var _favoriteRequest = 0;
  var _audioRequest = 0;

  @override
  void initState() {
    super.initState();
    _accountScope = ref.read(localDatabaseProvider).accountScope.current;
    _audioController = ref.read(audioControllerProvider.notifier);
    final scope = _accountScope;
    if (scope != null) {
      unawaited(_loadFavorite(scope, _accountGeneration));
    }
  }

  Future<void> _loadFavorite(AccountScopeSnapshot scope, int generation) async {
    final request = ++_favoriteRequest;
    try {
      final value = await ref
          .read(duaRepositoryProvider)
          .isFavorite(widget.entry, accountScope: scope);
      if (!_isCurrentAccount(scope, generation) ||
          request != _favoriteRequest) {
        return;
      }
      setState(() {
        _favorite = value;
        _favoriteBusy = false;
      });
    } on Object {
      if (_isCurrentAccount(scope, generation) && request == _favoriteRequest) {
        setState(() => _favoriteBusy = false);
      }
    }
  }

  @override
  void dispose() {
    _accountGeneration += 1;
    _favoriteRequest += 1;
    _audioRequest += 1;
    final audioId = _ownedAudioId;
    _ownedAudioId = null;
    if (audioId != null) {
      unawaited(_audioController.stopStandalone(audioId, owner: _audioOwner));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final currentController = ref.watch(audioControllerProvider.notifier);
    _synchronizeAccountBinding(currentController);
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
            if (widget.showCachedWarning) ...<Widget>[
              IqroStatusBanner(
                icon: Icons.cloud_off_outlined,
                title: context.l10n.cachedDuaWarning,
                actionLabel: widget.onRevalidate == null
                    ? null
                    : context.l10n.retry,
                onAction: widget.onRevalidate,
              ),
              const SizedBox(height: 14),
            ],
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
            if (widget.audioEnabled && entry.audio.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              _DuaAudioCard(
                entry: entry,
                selectedIndex: _selectedAudioIndex,
                loadFailed: _audioLoadFailed,
                onSelected: _selectAudio,
                onToggle: _toggleAudio,
                onRetry: _retryAudio,
                onSeek: _seekAudio,
                onRepeat: _toggleAudioRepeat,
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
    final scope = _accountScope;
    final generation = _accountGeneration;
    if (scope == null || !_isCurrentAccount(scope, generation)) return;
    final request = ++_favoriteRequest;
    final addedMessage = context.l10n.bookmarkAdded;
    final removedMessage = context.l10n.bookmarkRemoved;
    setState(() => _favoriteBusy = true);
    try {
      final active = await ref
          .read(duaRepositoryProvider)
          .toggleFavorite(widget.entry, accountScope: scope);
      if (!_isCurrentAccount(scope, generation) ||
          request != _favoriteRequest) {
        return;
      }
      if (!mounted) return;
      setState(() => _favorite = active);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(active ? addedMessage : removedMessage)),
      );
    } on AccountScopeChanged {
      // Account handoff is an expected cancellation, not a user-facing error.
    } finally {
      if (_isCurrentAccount(scope, generation) && request == _favoriteRequest) {
        setState(() => _favoriteBusy = false);
      }
    }
  }

  void _selectAudio(int index) {
    final scope = _accountScope;
    final generation = _accountGeneration;
    final controller = _audioController;
    final owner = _audioOwner;
    if (scope == null ||
        !_isCurrentAudioBinding(scope, generation, controller, owner)) {
      return;
    }
    if (index == _selectedAudioIndex) return;
    final audioId = _ownedAudioId;
    _ownedAudioId = null;
    _audioRequest += 1;
    setState(() {
      _selectedAudioIndex = index;
      _audioLoadFailed = false;
    });
    if (audioId != null) {
      unawaited(controller.stopStandalone(audioId, owner: owner));
    }
  }

  Future<void> _toggleAudio() => _playAudio(forceReload: false);

  Future<void> _retryAudio() => _playAudio(forceReload: true);

  Future<void> _playAudio({required bool forceReload}) async {
    if (!widget.audioEnabled) return;
    final scope = _accountScope;
    final generation = _accountGeneration;
    final controller = _audioController;
    final owner = _audioOwner;
    if (scope == null ||
        !_isCurrentAudioBinding(scope, generation, controller, owner)) {
      return;
    }
    final entry = widget.entry;
    if (entry.audio.isEmpty || _selectedAudioIndex >= entry.audio.length) {
      return;
    }
    final asset = entry.audio[_selectedAudioIndex];
    final id = duaAudioPlaybackId(entry, asset, _selectedAudioIndex);
    final request = ++_audioRequest;
    final current = ref.read(audioControllerProvider).standalone;
    final locale = Localizations.localeOf(context).languageCode;
    final album = 'IQRO · ${context.l10n.dua}';
    try {
      if (!forceReload && current?.mediaItem.id == id && _ownedAudioId == id) {
        _ownedAudioId = id;
        await controller.toggleStandalone(id, owner: owner);
      } else {
        _ownedAudioId = id;
        if (_audioLoadFailed) {
          setState(() => _audioLoadFailed = false);
        }
        await controller.loadStandalone(
          id: id,
          url: asset.url,
          title: '${entry.categoryTitle} · #${entry.sourceNumber}',
          album: album,
          contentType: 'dua',
          artist: _duaAudioReader(asset, locale),
          extras: <String, dynamic>{
            'collection': entry.collection,
            'source_number': entry.sourceNumber,
          },
          owner: owner,
        );
      }
    } on Object {
      if (_isCurrentAudioRequest(
        scope,
        generation,
        controller,
        owner,
        request,
        id,
      )) {
        setState(() => _audioLoadFailed = true);
      }
    }
  }

  Future<void> _seekAudio(String id, Duration position) {
    final scope = _accountScope;
    final generation = _accountGeneration;
    final controller = _audioController;
    final owner = _audioOwner;
    if (scope == null ||
        _ownedAudioId != id ||
        !_isCurrentAudioBinding(scope, generation, controller, owner)) {
      return Future<void>.value();
    }
    return controller.seekStandalone(id, position, owner: owner);
  }

  Future<void> _toggleAudioRepeat(String id) {
    final scope = _accountScope;
    final generation = _accountGeneration;
    final controller = _audioController;
    final owner = _audioOwner;
    if (scope == null ||
        _ownedAudioId != id ||
        !_isCurrentAudioBinding(scope, generation, controller, owner)) {
      return Future<void>.value();
    }
    return controller.toggleStandaloneRepeat(id, owner: owner);
  }

  void _synchronizeAccountBinding(AudioController currentController) {
    final accountScope = ref.read(localDatabaseProvider).accountScope;
    final currentScope = accountScope.current;
    if (_sameAccountScope(_accountScope, currentScope) &&
        identical(_audioController, currentController)) {
      return;
    }

    final oldController = _audioController;
    final oldOwner = _audioOwner;
    final oldAudioId = _ownedAudioId;
    _accountScope = currentScope;
    _audioController = currentController;
    _audioOwner = Object();
    _accountGeneration += 1;
    _favoriteRequest += 1;
    _audioRequest += 1;
    _favorite = false;
    _favoriteBusy = true;
    _completedRepetitions = 0;
    _selectedAudioIndex = 0;
    _ownedAudioId = null;
    _audioLoadFailed = false;

    if (oldAudioId != null) {
      unawaited(oldController.stopStandalone(oldAudioId, owner: oldOwner));
    }
    if (currentScope == null) return;
    final generation = _accountGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isCurrentAccount(currentScope, generation)) {
        unawaited(_loadFavorite(currentScope, generation));
      }
    });
  }

  bool _isCurrentAccount(AccountScopeSnapshot scope, int generation) {
    if (!mounted || generation != _accountGeneration) return false;
    final bound = _accountScope;
    if (!_sameAccountScope(bound, scope)) return false;
    return ref.read(localDatabaseProvider).accountScope.isCurrent(scope);
  }

  bool _isCurrentAudioBinding(
    AccountScopeSnapshot scope,
    int generation,
    AudioController controller,
    Object owner,
  ) =>
      _isCurrentAccount(scope, generation) &&
      identical(_audioController, controller) &&
      identical(_audioOwner, owner) &&
      identical(ref.read(audioControllerProvider.notifier), controller);

  bool _isCurrentAudioRequest(
    AccountScopeSnapshot scope,
    int generation,
    AudioController controller,
    Object owner,
    int request,
    String id,
  ) =>
      request == _audioRequest &&
      _ownedAudioId == id &&
      _isCurrentAudioBinding(scope, generation, controller, owner);

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
    canonicalUrl:
        '${ref.read(appConfigProvider).apiBaseUrl}${duaEntryRoute(widget.entry)}',
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

class _DuaAudioCard extends ConsumerWidget {
  const _DuaAudioCard({
    required this.entry,
    required this.selectedIndex,
    required this.loadFailed,
    required this.onSelected,
    required this.onToggle,
    required this.onRetry,
    required this.onSeek,
    required this.onRepeat,
  });

  final DuaEntry entry;
  final int selectedIndex;
  final bool loadFailed;
  final ValueChanged<int> onSelected;
  final Future<void> Function() onToggle;
  final Future<void> Function() onRetry;
  final Future<void> Function(String, Duration) onSeek;
  final Future<void> Function(String) onRepeat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(
      audioControllerProvider.select((value) => value.standalone),
    );
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
