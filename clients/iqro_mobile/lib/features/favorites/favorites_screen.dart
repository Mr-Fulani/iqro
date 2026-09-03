import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/auth/account_scope.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../dua/dua_repository.dart';

class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  Future<(List<Map<String, Object?>>, List<DuaEntry>)>? _data;
  AccountScopeKey? _accountKey;
  String? _locale;
  var _filter = 0;
  var _requestGeneration = 0;

  Future<(List<Map<String, Object?>>, List<DuaEntry>)> _load(
    AccountScopeSnapshot scope,
    String locale,
    int generation,
  ) async {
    final database = ref.read(localDatabaseProvider);
    final quran = ref.read(quranRepositoryProvider);
    final dua = ref.read(duaRepositoryProvider);
    database.ensureCurrent(scope);
    final result = await (
      quran.bookmarks(accountScope: scope),
      dua.favorites(locale: locale, accountScope: scope),
    ).wait;
    database.ensureCurrent(scope);
    if (generation != _requestGeneration) throw const AccountScopeChanged();
    return result;
  }

  void _reload(AccountScopeSnapshot scope, AccountScopeKey key, String locale) {
    if (!_isCurrent(scope, key, locale)) return;
    final generation = ++_requestGeneration;
    setState(() => _data = _load(scope, locale, generation));
  }

  bool _isCurrent(
    AccountScopeSnapshot scope,
    AccountScopeKey key,
    String locale,
  ) {
    return mounted &&
        _accountKey == key &&
        _locale == locale &&
        ref.read(localDatabaseProvider).accountScope.isCurrent(scope) &&
        ref.read(activeAccountScopeKeyProvider) == key;
  }

  @override
  Widget build(BuildContext context) {
    final accountKey = ref.watch(activeAccountScopeKeyProvider);
    final locale = ref.watch(
      appPreferencesProvider.select((value) => value.locale),
    );
    final database = ref.watch(localDatabaseProvider);
    final currentScope = database.accountScope.current;
    final scope =
        currentScope != null &&
            accountKey != null &&
            accountScopeKey(currentScope) == accountKey
        ? currentScope
        : null;
    if (_accountKey != accountKey || _locale != locale) {
      _accountKey = accountKey;
      _locale = locale;
      _requestGeneration++;
      _data = scope == null ? null : _load(scope, locale, _requestGeneration);
    }
    final boundKey = accountKey;
    final boundScope = scope;
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
              child: boundKey == null || boundScope == null || _data == null
                  ? const IqroLoading()
                  : FutureBuilder<(List<Map<String, Object?>>, List<DuaEntry>)>(
                      key: ValueKey<String>(
                        '${boundKey.userId}:${boundKey.epoch}:$locale',
                      ),
                      future: _data,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return IqroAsyncError(
                            title: context.l10n.networkError,
                            onRetry: () =>
                                _reload(boundScope, boundKey, locale),
                          );
                        }
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
                              onAction: () {
                                if (_isCurrent(boundScope, boundKey, locale)) {
                                  context.go('/app?tab=1');
                                }
                              },
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
                                    onTap: () {
                                      if (!_isCurrent(
                                        boundScope,
                                        boundKey,
                                        locale,
                                      )) {
                                        return;
                                      }
                                      context.push(
                                        '/reader/${item['surah']}?ayah=${item['ayah']}',
                                      );
                                    },
                                    child: ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: const Icon(
                                        Icons.menu_book_outlined,
                                      ),
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
                                    onTap: entry.available
                                        ? () {
                                            if (!_isCurrent(
                                              boundScope,
                                              boundKey,
                                              locale,
                                            )) {
                                              return;
                                            }
                                            context.push(
                                              duaEntryRoute(entry),
                                              extra: entry,
                                            );
                                          }
                                        : null,
                                    child: ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: const Icon(
                                        Icons.auto_awesome_outlined,
                                      ),
                                      title: Text(
                                        entry.available
                                            ? entry.categoryTitle
                                            : context.l10n.duaUnavailable,
                                      ),
                                      subtitle: Text(
                                        entry.available
                                            ? entry.arabicText
                                            : '${entry.collection} · ${entry.sourceNumber}',
                                        textDirection: TextDirection.rtl,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      trailing: entry.available
                                          ? const Icon(Icons.chevron_right)
                                          : IconButton(
                                              icon: const Icon(
                                                Icons.bookmark_remove_outlined,
                                              ),
                                              onPressed: () =>
                                                  _removeUnavailableFavorite(
                                                    entry: entry,
                                                    scope: boundScope,
                                                    key: boundKey,
                                                    locale: locale,
                                                  ),
                                            ),
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

  Future<void> _removeUnavailableFavorite({
    required DuaEntry entry,
    required AccountScopeSnapshot scope,
    required AccountScopeKey key,
    required String locale,
  }) async {
    if (!_isCurrent(scope, key, locale)) return;
    final repository = ref.read(duaRepositoryProvider);
    try {
      await repository.toggleFavorite(entry, accountScope: scope);
    } on AccountScopeChanged {
      return;
    }
    if (!_isCurrent(scope, key, locale)) return;
    _reload(scope, key, locale);
  }
}
