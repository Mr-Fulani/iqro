import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
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
                          const Icon(Icons.verified_outlined, size: 17),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              entry.sourceLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
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

  @override
  void initState() {
    super.initState();
    ref.read(duaRepositoryProvider).isFavorite(widget.entry).then((value) {
      if (mounted) setState(() => _favorite = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    return Scaffold(
      appBar: IqroTopBar(
        title: entry.categoryTitle,
        subtitle: '#${entry.sourceNumber}',
        actions: <Widget>[
          IconButton(
            tooltip: context.l10n.favorites,
            isSelected: _favorite,
            selectedIcon: const Icon(Icons.bookmark),
            icon: const Icon(Icons.bookmark_border),
            onPressed: _toggle,
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
            const SizedBox(height: 14),
            IqroStatusBanner(
              icon: Icons.verified_outlined,
              title: entry.sourceLabel.isEmpty
                  ? context.l10n.duaSubtitle
                  : entry.sourceLabel,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggle() async {
    final active = await ref
        .read(duaRepositoryProvider)
        .toggleFavorite(widget.entry);
    if (mounted) {
      setState(() => _favorite = active);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            active ? context.l10n.bookmarkAdded : context.l10n.bookmarkRemoved,
          ),
        ),
      );
    }
  }
}
