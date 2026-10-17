import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/design_system/iqro_icon.dart';
import '../../app/providers.dart';
import '../../core/audio/audio_controller.dart';
import '../../core/auth/account_scope.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/design_system/iqro_action_grid.dart';
import '../../core/theme/iqro_theme.dart';
import 'dua_arabic.dart';
import 'dua_presentation.dart';
import 'dua_repository.dart';
import 'dua_topics.dart';
import 'dua_thematic_icon.dart';

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
  DuaTopic? _topic;
  var _favoritesOpen = false;
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
    final sourceEntries = activeCategoryIdentity == null
        ? null
        : ref.watch(duaEntriesByCategoryProvider(activeCategoryIdentity));
    final entries = activeCategoryIdentity != null || _topic == null
        ? sourceEntries
        : ref.watch(duaEntriesByTopicProvider(_topic!.id));
    final accountKey = ref.watch(activeAccountScopeKeyProvider);
    final favorites = accountKey == null
        ? null
        : ref.watch(duaFavoritesProvider(accountKey));
    final inCatalog =
        activeCategoryIdentity == null && _topic == null && !_favoritesOpen;
    final locale = Localizations.localeOf(context).languageCode;
    // A topic made of several chapters lists them first; a topic of one
    // chapter, or a chosen part of one (morning, evening), is read at once.
    final topicChapters = _topic == null
        ? const <DuaCategory>[]
        : (categories.valueOrNull ?? const <DuaCategory>[])
              .where(_topic!.includesCategory)
              .toList(growable: false);
    final showChapters =
        _topic != null &&
        activeCategoryIdentity == null &&
        _topic!.entryNumbers == null &&
        topicChapters.length > 1;
    final String title;
    String? subtitle;
    String? banner;
    if (_favoritesOpen) {
      title = context.l10n.favorites;
      subtitle = context.l10n.duaFavoritesSubtitle;
    } else if (activeCategoryIdentity != null) {
      title = category == null
          ? context.l10n.dua
          : context.l10n.duaChapterNumber(category.sourceNumber);
      subtitle = category == null || category.collectionTitle.isEmpty
          ? category?.collection
          : category.collectionTitle;
      banner = category == null ? null : duaDisplayTitle(category.title);
    } else if (_topic != null) {
      title = _topic!.title(locale);
      if (showChapters) {
        subtitle = _topic!.description(locale);
      } else {
        // One chapter: its own title, as in the book; a part of one or
        // several chapters: what the topic gathers.
        banner = topicChapters.length == 1
            ? duaDisplayTitle(topicChapters.single.title)
            : _topic!.description(locale);
      }
    } else {
      title = context.l10n.dua;
      subtitle = context.l10n.duaSubtitle;
    }
    final searchRequest = (
      query: _submittedQuery,
      collection: null as String?,
      category: null as String?,
    );
    final searchResults = inCatalog && _submittedQuery.length >= 2
        ? ref.watch(duaSearchProvider(searchRequest))
        : null;
    return PopScope(
      canPop: inCatalog,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        appBar: IqroTopBar(
          title: title,
          subtitle: subtitle,
          leading: inCatalog
              ? null
              : IconButton(
                  tooltip: context.l10n.back,
                  onPressed: _goBack,
                  icon: const Icon(Icons.arrow_back),
                ),
        ),
        body: IqroPage(
          scrollable: false,
          child: Column(
            children: [
              Expanded(
                child: inCatalog
                    ? _DuaCatalog(
                        categories: categories,
                        favoritesCount: favorites?.valueOrNull?.length ?? 0,
                        onOpenFavorites: _openFavorites,
                        searchResults: searchResults,
                        searchPending:
                            _query.length >= 2 && _query != _submittedQuery,
                        query: _query,
                        searchController: _searchController,
                        onQueryChanged: _onRootQueryChanged,
                        onOpen: _openCategory,
                        onOpenTopic: _openTopic,
                        onCategoriesRetry: () =>
                            ref.invalidate(duaCategoriesProvider),
                        onSearchRetry: () =>
                            ref.invalidate(duaSearchProvider(searchRequest)),
                      )
                    : showChapters
                    ? _DuaChapterList(
                        chapters: topicChapters,
                        onOpen: _openChapter,
                      )
                    : _DuaFeed(
                        banner: banner,
                        entries: _favoritesOpen
                            ? favorites ??
                                  const AsyncValue<List<DuaEntry>>.data(
                                    <DuaEntry>[],
                                  )
                            : entries!,
                        onRetry: () {
                          if (_favoritesOpen) {
                            if (accountKey != null) {
                              ref.invalidate(duaFavoritesProvider(accountKey));
                            }
                          } else if (activeCategoryIdentity != null ||
                              _topic == null) {
                            ref.invalidate(
                              duaEntriesByCategoryProvider(
                                activeCategoryIdentity!,
                              ),
                            );
                          } else {
                            for (final member
                                in (categories.valueOrNull ?? <DuaCategory>[])
                                    .where(_topic!.includesCategory)) {
                              ref.invalidate(
                                duaEntriesByCategoryProvider(member.identity),
                              );
                            }
                            ref.invalidate(
                              duaEntriesByTopicProvider(_topic!.id),
                            );
                          }
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _goBack() {
    // A chapter opened from its topic's list returns to that list.
    if (_topic != null &&
        (_categoryIdentity != null || _legacyCategorySlug != null)) {
      _openCategory(null);
      return;
    }
    _openCategory(null);
    setState(() {
      _topic = null;
      _favoritesOpen = false;
    });
  }

  void _openChapter(DuaCategory category) => _openCategory(category);

  void _openTopic(DuaTopic topic) {
    _openCategory(null);
    setState(() {
      _topic = topic;
      _favoritesOpen = false;
    });
  }

  void _openFavorites() {
    _openCategory(null);
    setState(() {
      _topic = null;
      _favoritesOpen = true;
    });
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
    required this.favoritesCount,
    required this.onOpenFavorites,
    required this.searchResults,
    required this.searchPending,
    required this.query,
    required this.searchController,
    required this.onQueryChanged,
    required this.onOpen,
    required this.onCategoriesRetry,
    required this.onOpenTopic,
    required this.onSearchRetry,
  });

  final AsyncValue<List<DuaCategory>> categories;
  final int favoritesCount;
  final VoidCallback onOpenFavorites;
  final AsyncValue<List<DuaEntry>>? searchResults;
  final bool searchPending;
  final String query;
  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<DuaCategory> onOpen;
  final ValueChanged<DuaTopic> onOpenTopic;
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
                    : _searchResults(context)
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
                    final locale = Localizations.localeOf(context).languageCode;
                    final topics = duaTopics
                        .where((topic) => items.any(topic.includesCategory))
                        .toList(growable: false);
                    final other = items
                        .where(
                          (category) => !duaTopics.any(
                            (topic) => topic.includesCategory(category),
                          ),
                        )
                        .toList(growable: false);
                    return SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: Column(
                        children: [
                          IqroActionGrid(
                            children: [
                              if (favoritesCount > 0)
                                _DuaFavoritesCard(
                                  count: favoritesCount,
                                  onTap: onOpenFavorites,
                                ),
                              for (final topic in topics)
                                _DuaTopicCard(
                                  topic: topic,
                                  locale: locale,
                                  count: topic.entryCount(items),
                                  onTap: () => onOpenTopic(topic),
                                ),
                            ],
                          ),
                          for (final category in other) ...[
                            const SizedBox(height: 12),
                            IqroCard(
                              onTap: () => onOpen(category),
                              child: Text(category.title),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

extension on _DuaCatalog {
  // The server matches the words of each du'a, so a query such as «сон»
  // misses «сна». Topics whose name or description match are listed first,
  // which leads to the whole chapter.
  Widget _searchResults(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final needle = query.toLowerCase();
    final items = categories.valueOrNull ?? const <DuaCategory>[];
    final matches = duaTopics
        .where(
          (topic) =>
              items.any(topic.includesCategory) &&
              (topic.title(locale).toLowerCase().contains(needle) ||
                  topic.description(locale).toLowerCase().contains(needle)),
        )
        .toList(growable: false);
    final entries = searchPending || searchResults == null
        ? const IqroLoading()
        : _AsyncDuaEntries(
            entries: searchResults!,
            query: '',
            onRetry: onSearchRetry,
            showEmpty: matches.isEmpty,
          );
    if (matches.isEmpty) return entries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final topic in matches) ...<Widget>[
          _DuaTopicTile(
            topic: topic,
            locale: locale,
            count: topic.entryCount(items),
            onTap: () => onOpenTopic(topic),
          ),
          const SizedBox(height: 10),
        ],
        Expanded(child: entries),
      ],
    );
  }
}

class _DuaTopicTile extends StatelessWidget {
  const _DuaTopicTile({
    required this.topic,
    required this.locale,
    required this.count,
    required this.onTap,
  });
  final DuaTopic topic;
  final String locale;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IqroCard(
    key: ValueKey('dua-topic-match-${topic.id}'),
    onTap: onTap,
    child: Row(
      children: <Widget>[
        SizedBox.square(
          dimension: 40,
          child: FittedBox(child: DuaThematicIcon(topic: topic.id)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                topic.title(locale),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                context.l10n.duaCount(count),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right),
      ],
    ),
  );
}

class _DuaFavoritesCard extends StatelessWidget {
  const _DuaFavoritesCard({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IqroCard(
    key: const ValueKey('dua-favorites'),
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DuaThematicIcon(topic: 'favorites'),
        const SizedBox(height: 12),
        Text(
          context.l10n.favorites,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        Text(
          context.l10n.duaFavoritesSubtitle,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Text(
          context.l10n.duaCount(count),
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    ),
  );
}

class _DuaTopicCard extends StatelessWidget {
  const _DuaTopicCard({
    required this.topic,
    required this.locale,
    required this.count,
    required this.onTap,
  });
  final DuaTopic topic;
  final String locale;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IqroCard(
    key: ValueKey('dua-topic-${topic.id}'),
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DuaThematicIcon(topic: topic.id),
        const SizedBox(height: 12),
        Text(
          topic.title(locale),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        Text(
          topic.description(locale),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Text(
          context.l10n.duaCount(count),
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    ),
  );
}

/// The chapters of a topic as rows, as in the printed book's contents.
class _DuaChapterList extends StatelessWidget {
  const _DuaChapterList({required this.chapters, required this.onOpen});

  final List<DuaCategory> chapters;
  final ValueChanged<DuaCategory> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.separated(
      itemCount: chapters.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final chapter = chapters[index];
        return IqroCard(
          key: ValueKey('dua-chapter-${chapter.collection}-${chapter.slug}'),
          onTap: () => onOpen(chapter),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 24,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: IqroIcon(iqroDuaIcon, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      context.l10n.duaChapterNumber(chapter.sourceNumber),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      duaDisplayTitle(chapter.title),
                      style: theme.textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        );
      },
    );
  }
}

/// A chapter, a topic or the favourites read as one column of du'a cards.
class _DuaFeed extends StatelessWidget {
  const _DuaFeed({required this.entries, required this.onRetry, this.banner});

  final AsyncValue<List<DuaEntry>> entries;
  final VoidCallback onRetry;
  final String? banner;

  @override
  Widget build(BuildContext context) {
    return entries.when(
      loading: () => const IqroLoading(),
      error: (error, stack) =>
          IqroAsyncError(title: context.l10n.networkError, onRetry: onRetry),
      data: (items) {
        if (items.isEmpty) return _DuaEmpty(message: context.l10n.noDuaFound);
        final lead = banner == null ? 0 : 1;
        return ListView.separated(
          itemCount: items.length + lead,
          separatorBuilder: (context, index) => const SizedBox(height: 14),
          itemBuilder: (context, index) {
            if (index < lead) return _DuaChapterBanner(title: banner!);
            final entry = items[index - lead];
            return DuaEntryCard(
              key: ValueKey<String>('dua-entry-${entry.id}'),
              entry: entry,
              position: index - lead + 1,
              count: items.length,
            );
          },
        );
      },
    );
  }
}

class _AsyncDuaEntries extends StatelessWidget {
  const _AsyncDuaEntries({
    required this.entries,
    required this.query,
    required this.onRetry,
    this.showEmpty = true,
  });

  final AsyncValue<List<DuaEntry>> entries;
  final String query;
  final VoidCallback onRetry;

  /// False when something else on screen already answers the search.
  final bool showEmpty;

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
          return showEmpty
              ? _DuaEmpty(message: context.l10n.noDuaFound)
              : const SizedBox.shrink();
        }
        return ListView.separated(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          itemCount: visible.length,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final entry = visible[index];
            final startsChapter =
                index == 0 ||
                visible[index - 1].collection != entry.collection ||
                visible[index - 1].categorySlug != entry.categorySlug;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (startsChapter)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      top: 12,
                      bottom: 10,
                    ),
                    child: Text(
                      entry.categoryTitle,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                _DuaEntryCard(entry: entry),
              ],
            );
          },
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
    final locale = Localizations.localeOf(context).languageCode;
    final preview = locale == 'ar' || entry.meaning.trim().isEmpty
        ? entry.arabicText
        : entry.meaning;
    return IqroCard(
      onTap: () => context.push(duaEntryRoute(entry), extra: entry),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '#${entry.sourceNumber}',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textDirection: locale == 'ar' ? TextDirection.rtl : null,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right),
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
            IqroIcon(
              iqroDuaIcon,
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

class DuaEntryScreen extends StatelessWidget {
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
  Widget build(BuildContext context) => Scaffold(
    appBar: IqroTopBar(title: context.l10n.dua),
    body: IqroPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (showCachedWarning) ...<Widget>[
            IqroStatusBanner(
              icon: Icons.cloud_off_outlined,
              title: context.l10n.cachedDuaWarning,
              actionLabel: onRevalidate == null ? null : context.l10n.retry,
              onAction: onRevalidate,
            ),
            const SizedBox(height: 14),
          ],
          _DuaChapterBanner(title: duaDisplayTitle(entry.categoryTitle)),
          const SizedBox(height: 14),
          DuaEntryCard(entry: entry, audioEnabled: audioEnabled),
        ],
      ),
    ),
  );
}

/// One du'a as a card: the opening formulas on their own lines, the Arabic,
/// a repetition counter when it is said several times, the meaning with its
/// source, and the actions — listen, repeat, speed, favourite, share.
class DuaEntryCard extends ConsumerStatefulWidget {
  const DuaEntryCard({
    required this.entry,
    this.audioEnabled = true,
    this.position,
    this.count,
    super.key,
  });
  final DuaEntry entry;
  final bool audioEnabled;

  /// Place of the du'a in its feed, shown as «position/count».
  final int? position;
  final int? count;

  @override
  ConsumerState<DuaEntryCard> createState() => _DuaEntryCardState();
}

bool _sameAccountScope(
  AccountScopeSnapshot? left,
  AccountScopeSnapshot? right,
) => left?.userId == right?.userId && left?.epoch == right?.epoch;

class _DuaEntryCardState extends ConsumerState<DuaEntryCard> {
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
    _ownedAudioId = null;
    // Dua audio belongs to the shared player and can continue after this route
    // closes. The app-shell mini-player controls the current request safely.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final currentController = ref.watch(audioControllerProvider.notifier);
    _synchronizeAccountBinding(currentController);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final repetitions = duaRepetitionStages(
      entry.repetitionLabel,
      entry.repetitions,
    ).fold<int>(0, (sum, stage) => sum + stage);
    final hasAudio = widget.audioEnabled && entry.audio.isNotEmpty;
    final audioId = hasAudio
        ? duaAudioPlaybackId(
            entry,
            entry.audio[_selectedAudioIndex],
            _selectedAudioIndex,
          )
        : null;
    final standalone = ref.watch(
      audioControllerProvider.select((state) => state.standalone),
    );
    final current = standalone != null && standalone.mediaItem.id == audioId
        ? standalone
        : null;
    final owned = current != null && _ownedAudioId == audioId;
    final reference = entry.evidence
        .map((item) => item.sourceReference.trim())
        .where((item) => item.isNotEmpty)
        .firstOrNull;
    final arabicStyle = theme.textTheme.headlineMedium?.copyWith(
      color: scheme.onSurface,
      fontFamily: IqroTheme.arabicFontFamily,
      fontWeight: FontWeight.normal,
      fontSize: 28,
      height: 2.05,
    );
    return IqroCard(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final (index, part) in splitDuaArabic(
            entry.arabicText,
          ).indexed) ...<Widget>[
            if (index > 0) SizedBox(height: part.opening ? 18 : 6),
            Text(
              part.text,
              key: index == 0 ? const ValueKey('dua-arabic') : null,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
              style: part.opening
                  ? arabicStyle?.copyWith(fontSize: 22, color: scheme.primary)
                  : arabicStyle,
            ),
          ],
          if (repetitions > 1) ...<Widget>[
            const SizedBox(height: 18),
            Center(
              child: _RepetitionCounter(
                total: repetitions,
                completed: _completedRepetitions,
                onTap: _incrementPractice,
              ),
            ),
          ],
          if (entry.transliteration.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              entry.transliteration,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
                height: 1.5,
              ),
            ),
          ],
          if (entry.meaning.isNotEmpty) ...<Widget>[
            const SizedBox(height: 18),
            Text(
              entry.meaning,
              key: const ValueKey('dua-meaning'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: scheme.primary,
                height: 1.55,
              ),
            ),
          ],
          const SizedBox(height: 14),
          // The source sits under the text it backs; the full record opens
          // from it.
          InkWell(
            key: const ValueKey('dua-source'),
            borderRadius: BorderRadius.circular(10),
            onTap: () => _showSource(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                '[${reference ?? '${entry.sourceLabel} · #${entry.sourceNumber}'}]',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: .7),
              borderRadius: BorderRadius.circular(22),
            ),
            child: IconButtonTheme(
              data: IconButtonThemeData(
                style: IconButton.styleFrom(foregroundColor: scheme.primary),
              ),
              child: Row(
                children: <Widget>[
                  if (hasAudio) ...<Widget>[
                    Expanded(
                      child: _audioLoadFailed
                          ? IconButton(
                              tooltip: context.l10n.retry,
                              onPressed: _retryAudio,
                              icon: Icon(Icons.refresh, color: scheme.error),
                            )
                          : current?.loading == true
                          ? const Center(
                              child: SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : IconButton(
                              tooltip: current?.playing == true
                                  ? context.l10n.pause
                                  : context.l10n.play,
                              onPressed: _toggleAudio,
                              icon: Icon(
                                current?.playing == true
                                    ? Icons.pause
                                    : Icons.play_arrow,
                              ),
                            ),
                    ),
                    Expanded(
                      child: IconButton(
                        tooltip: context.l10n.repeat,
                        isSelected: owned && current.repeatEnabled,
                        onPressed: owned
                            ? () => unawaited(_toggleAudioRepeat(audioId!))
                            : null,
                        selectedIcon: const Icon(Icons.repeat_one),
                        icon: const Icon(Icons.repeat),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: owned
                            ? () => unawaited(
                                _cycleAudioSpeed(audioId!, current.speed),
                              )
                            : null,
                        child: Text(
                          '${_speedLabel(owned ? current.speed : 1)}×',
                          semanticsLabel: context.l10n.speed,
                        ),
                      ),
                    ),
                  ],
                  Expanded(
                    child: IconButton(
                      tooltip: context.l10n.favorites,
                      isSelected: _favorite,
                      selectedIcon: const Icon(Icons.bookmark),
                      icon: const Icon(Icons.bookmark_border),
                      onPressed: _favoriteBusy ? null : _toggle,
                    ),
                  ),
                  Expanded(
                    child: Builder(
                      builder: (buttonContext) => IconButton(
                        tooltip: context.l10n.shareDua,
                        icon: const Icon(Icons.ios_share_outlined),
                        onPressed: () => unawaited(_share(buttonContext)),
                      ),
                    ),
                  ),
                  if (widget.position != null && widget.count != null)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.surface.withValues(alpha: .7),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Text(
                            '${widget.position}/${widget.count}',
                            style: theme.textTheme.labelLarge,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _speeds = <double>[1, 1.25, 1.5, 0.75];

  static String _speedLabel(double speed) =>
      speed == speed.roundToDouble() ? '${speed.toInt()}' : '$speed';

  Future<void> _cycleAudioSpeed(String id, double speed) {
    final scope = _accountScope;
    final generation = _accountGeneration;
    final controller = _audioController;
    final owner = _audioOwner;
    if (scope == null ||
        _ownedAudioId != id ||
        !_isCurrentAudioBinding(scope, generation, controller, owner)) {
      return Future<void>.value();
    }
    final index = _speeds.indexOf(speed);
    final next = _speeds[(index + 1) % _speeds.length];
    return controller.setStandaloneSpeed(id, next, owner: owner);
  }

  Future<void> _showSource(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: _DuaSourceCard(entry: widget.entry),
      ),
    ),
  );

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
      ref.invalidate(duaFavoritesProvider(accountScopeKey(scope)));
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
    if (_completedRepetitions >= target) {
      // A finished count starts again on the next tap.
      setState(() => _completedRepetitions = 0);
      return;
    }
    final next = _completedRepetitions + 1;
    setState(() => _completedRepetitions = next);
    if (next == target) {
      unawaited(HapticFeedback.heavyImpact());
      unawaited(HapticFeedback.vibrate());
    } else {
      unawaited(HapticFeedback.lightImpact());
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

/// The chapter the du'a belongs to, as a ribbon above the text.
class _DuaChapterBanner extends StatelessWidget {
  const _DuaChapterBanner({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.iqroColors.sand,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurface,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}

/// Counts down the repetitions of a du'a: tap after each one. It vibrates
/// at the end and starts again on the next tap.
class _RepetitionCounter extends StatelessWidget {
  const _RepetitionCounter({
    required this.total,
    required this.completed,
    required this.onTap,
  });

  final int total;
  final int completed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final remaining = (total - completed).clamp(0, total);
    final done = remaining == 0;
    return Semantics(
      button: true,
      label: done
          ? context.l10n.done
          : context.l10n.duaCounterRemaining(remaining),
      excludeSemantics: true,
      child: Material(
        key: const ValueKey('dua-counter'),
        color: done ? scheme.primary : scheme.primaryContainer,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(
            dimension: 112,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                SizedBox.square(
                  dimension: 100,
                  child: CircularProgressIndicator(
                    value: total == 0 ? 0 : completed / total,
                    strokeWidth: 3,
                    color: done ? scheme.onPrimary : scheme.primary,
                    backgroundColor: Colors.transparent,
                  ),
                ),
                done
                    ? Icon(
                        Icons.check_rounded,
                        size: 44,
                        color: scheme.onPrimary,
                      )
                    : Text(
                        '$remaining',
                        style: Theme.of(context).textTheme.displaySmall
                            ?.copyWith(color: scheme.primary),
                      ),
              ],
            ),
          ),
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
        leading: IqroIcon(
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
