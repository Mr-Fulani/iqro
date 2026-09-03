import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../dua/dua_repository.dart';

class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  late Future<(List<Map<String, Object?>>, List<DuaEntry>)> _data;
  var _filter = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _data = (
      ref.read(quranRepositoryProvider).bookmarks(),
      ref.read(duaRepositoryProvider).favorites(),
    ).wait;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: IqroTopBar(title: context.l10n.favorites),
      body: IqroPage(
        scrollable: false,
        child: Column(
          children: <Widget>[
            SegmentedButton<int>(
              segments: <ButtonSegment<int>>[
                ButtonSegment(value: 0, label: Text(context.l10n.all)),
                ButtonSegment(value: 1, label: Text(context.l10n.navQuran)),
                ButtonSegment(value: 2, label: Text(context.l10n.dua)),
              ],
              selected: <int>{_filter},
              showSelectedIcon: false,
              onSelectionChanged: (value) =>
                  setState(() => _filter = value.first),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: FutureBuilder<(List<Map<String, Object?>>, List<DuaEntry>)>(
                future: _data,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const IqroLoading();
                  final quran = snapshot.data!.$1;
                  final dua = snapshot.data!.$2;
                  if ((_filter == 0 && quran.isEmpty && dua.isEmpty) ||
                      (_filter == 1 && quran.isEmpty) ||
                      (_filter == 2 && dua.isEmpty)) {
                    return Center(
                      child: IqroStatusBanner(
                        icon: Icons.bookmark_add_outlined,
                        title: context.l10n.emptyFavorites,
                        actionLabel: context.l10n.navQuran,
                        onAction: () => context.go('/app?tab=1'),
                      ),
                    );
                  }
                  return ListView(
                    children: <Widget>[
                      if (_filter != 2)
                        for (final item in quran)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: IqroCard(
                              onTap: () => context.push(
                                '/reader/${item['surah']}?ayah=${item['ayah']}',
                              ),
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.menu_book_outlined),
                                title: Text(
                                  '${context.l10n.surah} ${item['surah']} · ${context.l10n.ayah} ${item['ayah']}',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                              ),
                            ),
                          ),
                      if (_filter != 1)
                        for (final entry in dua)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: IqroCard(
                              onTap: () => context.push(
                                duaEntryRoute(entry),
                                extra: entry,
                              ),
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(
                                  Icons.auto_awesome_outlined,
                                ),
                                title: Text(entry.categoryTitle),
                                subtitle: Text(
                                  entry.arabicText,
                                  textDirection: TextDirection.rtl,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: const Icon(Icons.chevron_right),
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
}
