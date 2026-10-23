import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import 'announcement_controller.dart';
import 'announcement_dialog.dart';
import 'announcement_logic.dart';
import 'announcement_parts.dart';

/// Kinds the app filters by. Fundraising is a site-only kind.
const _filters = <String?>[
  null,
  'reciter',
  'feature',
  'content',
  'app_release',
  'general',
];

/// «What's new»: the whole history, newest first, pinned items on top.
/// Read and closed announcements stay here.
class NewsScreen extends ConsumerStatefulWidget {
  const NewsScreen({super.key});

  @override
  ConsumerState<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends ConsumerState<NewsScreen> {
  String? _kind;
  AnnouncementFeedPage? _page;
  var _loading = false;
  var _failed = false;
  var _offline = false;
  var _request = 0;
  String? _locale;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context).languageCode;
    if (locale == _locale) return;
    _locale = locale;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // The marks and the signed-in person's receipts decide the dots.
      unawaited(ref.read(announcementsProvider.notifier).load(locale));
      unawaited(_load(_kind, null));
    });
  }

  Future<void> _load(String? kind, String? cursor) async {
    final locale = _locale;
    if (locale == null) return;
    final request = ++_request;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final result = await ref
          .read(announcementRepositoryProvider)
          .feed(locale: locale, kind: kind, cursor: cursor);
      if (!mounted || request != _request) return;
      setState(() {
        final previous = _page;
        _page = cursor == null || previous == null
            ? result.page
            : AnnouncementFeedPage(
                nextCursor: result.page.nextCursor,
                results: <Announcement>[
                  ...previous.results,
                  ...result.page.results,
                ],
              );
        _offline = result.fromCache;
      });
    } on Object {
      if (!mounted || request != _request) return;
      setState(() => _failed = true);
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  void _select(String? kind) {
    if (kind == _kind) return;
    setState(() {
      _kind = kind;
      _page = null;
    });
    unawaited(_load(kind, null));
  }

  String _filterLabel(String? kind) => switch (kind) {
    'reciter' => context.l10n.newsFilterReciter,
    'feature' => context.l10n.newsFilterFeature,
    'content' => context.l10n.newsFilterContent,
    'app_release' => context.l10n.newsFilterAppRelease,
    'general' => context.l10n.newsFilterGeneral,
    _ => context.l10n.newsAll,
  };

  @override
  Widget build(BuildContext context) {
    final signedIn = announcementSignedIn(
      ref.watch(sessionProvider.select((value) => value.valueOrNull)),
    );
    final local = ref.watch(
      announcementsProvider.select((value) => value.local),
    );
    final page = _page;
    final items = page == null
        ? const <Announcement>[]
        : forAudience(page.results, signedIn);
    return Scaffold(
      appBar: IqroTopBar(
        title: context.l10n.newsTitle,
        subtitle: context.l10n.newsDescription,
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => _load(_kind, null),
          child: ListView(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 32),
            children: <Widget>[
              Semantics(
                container: true,
                label: context.l10n.newsFilterLabel,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final kind in _filters)
                      ChoiceChip(
                        label: Text(_filterLabel(kind)),
                        selected: _kind == kind,
                        onSelected: (_) => _select(kind),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (_offline) ...<Widget>[
                IqroStatusBanner(
                  icon: Icons.cloud_off_outlined,
                  title: context.l10n.offlineUsingCache,
                ),
                const SizedBox(height: 12),
              ],
              if (_failed && items.isEmpty)
                IqroAsyncError(
                  title: context.l10n.newsLoadError,
                  onRetry: () => unawaited(_load(_kind, null)),
                )
              else if (page == null && _loading)
                const IqroLoading()
              else if (items.isEmpty && !_loading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    context.l10n.newsEmpty,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              for (final item in items) ...<Widget>[
                _NewsItem(item: item, unread: local.read[item.id] == null),
                const SizedBox(height: 12),
              ],
              if (_failed && items.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    context.l10n.newsLoadError,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (page?.nextCursor != null)
                OutlinedButton(
                  onPressed: _loading
                      ? null
                      : () => unawaited(_load(_kind, page!.nextCursor)),
                  child: Text(context.l10n.newsLoadMore),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewsItem extends ConsumerWidget {
  const _NewsItem({required this.item, required this.unread});

  final Announcement item;
  final bool unread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final label = item.action.label;
    final details = item.steps.isNotEmpty || item.body.trim().isNotEmpty;
    return IqroCard(
      key: ValueKey('news-item-${item.id}'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AnnouncementPicture(item: item, size: 56, thumb: true),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    if (unread)
                      Semantics(
                        label: context.l10n.newsUnread,
                        child: Container(
                          key: const ValueKey('news-unread'),
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        announcementKindLabel(context, item.kind),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      announcementDate(context, item, year: true),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Semantics(
                  header: true,
                  child: Text(item.title, style: theme.textTheme.titleMedium),
                ),
                const SizedBox(height: 2),
                Text(item.summary, style: theme.textTheme.bodyMedium),
                if ((announcementHasAction(item) && label.isNotEmpty) ||
                    details) ...<Widget>[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      if (announcementHasAction(item) && label.isNotEmpty)
                        FilledButton(
                          onPressed: () => unawaited(
                            openAnnouncementAction(
                              ref,
                              GoRouter.of(context),
                              item,
                              'feed',
                            ),
                          ),
                          child: Text(
                            item.action.externalUrl != null &&
                                    item.action.appRoute == null
                                ? '$label ↗'
                                : label,
                          ),
                        ),
                      if (details)
                        OutlinedButton(
                          onPressed: () {
                            unawaited(
                              ref
                                  .read(announcementsProvider.notifier)
                                  .read(item, 'feed'),
                            );
                            unawaited(
                              showAnnouncementDialog(
                                context,
                                items: <Announcement>[item],
                                surface: 'feed',
                              ),
                            );
                          },
                          child: Text(
                            item.steps.isNotEmpty
                                ? context.l10n.newsHowTo
                                : context.l10n.newsMore,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
