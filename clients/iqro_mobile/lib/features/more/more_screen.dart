import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_system/iqro_icon.dart';
import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/design_system/iqro_action_grid.dart';
import '../dua/dua_thematic_icon.dart';
import '../../core/theme/iqro_theme.dart';
import '../announcements/announcement_controller.dart';
import '../audio/mini_player.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerActive = ref.watch(
      audioControllerProvider.select((value) => value.active),
    );
    return Scaffold(
      appBar: IqroTopBar(
        title: context.l10n.navMore,
        subtitle: context.l10n.moreTools,
      ),
      body: IqroPage(
        padding: iqroRootTabPadding(
          context,
          playerActive: playerActive,
          playerCollapsed: ref.watch(miniPlayerCollapsedProvider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const _NewsEntry(),
            const SizedBox(height: 16),
            const MoreToolsGrid(),
            const SizedBox(height: 24),
            IqroSectionHeader(title: context.l10n.account),
            const SizedBox(height: 10),
            IqroCard(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              child: Column(
                children: <Widget>[
                  IqroListTile(
                    icon: Icons.person_outline,
                    title: context.l10n.personalProfile,
                    subtitle: context.l10n.guestSyncHint,
                    onTap: () => context.push('/account'),
                  ),
                  const Divider(height: 1),
                  IqroListTile(
                    icon: Icons.ios_share_outlined,
                    title: context.l10n.shareApp,
                    subtitle: context.l10n.shareBody,
                    onTap: () => context.push('/share'),
                  ),
                  const Divider(height: 1),
                  IqroListTile(
                    icon: Icons.settings_outlined,
                    title: context.l10n.settings,
                    subtitle:
                        '${context.l10n.language} · ${context.l10n.theme}',
                    onTap: () => context.push('/settings'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            IqroCard(
              color: context.iqroColors.sand,
              borderColor: Colors.transparent,
              child: Row(
                children: <Widget>[
                  IqroIcon(
                    Icons.auto_stories_outlined,
                    color: context.iqroColors.gold,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${context.l10n.books} · ${context.l10n.quizzes}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          context.l10n.soon,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Chip(label: Text(context.l10n.soon)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// «What's new», with a dot while something on the home screen is unread.
class _NewsEntry extends ConsumerStatefulWidget {
  const _NewsEntry();

  @override
  ConsumerState<_NewsEntry> createState() => _NewsEntryState();
}

class _NewsEntryState extends ConsumerState<_NewsEntry> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context).languageCode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !ref.read(announcementsProvider).loaded) {
        ref.read(announcementsProvider.notifier).load(locale);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = announcementSignedIn(
      ref.watch(sessionProvider.select((value) => value.valueOrNull)),
    );
    final unread = ref.watch(
      announcementsProvider.select((value) => value.unread(signedIn: signedIn)),
    );
    return IqroCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: IqroListTile(
        key: const ValueKey('more-news'),
        icon: Icons.auto_awesome_outlined,
        title: context.l10n.newsTitle,
        subtitle: context.l10n.newsDescription,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (unread > 0)
              Semantics(
                label: context.l10n.newsUnread,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => context.push('/news'),
      ),
    );
  }
}

class MoreToolsGrid extends StatelessWidget {
  const MoreToolsGrid({super.key});

  @override
  Widget build(BuildContext context) => IqroActionGrid(
    children: <Widget>[
      _ToolCard(
        art: 'hijri-calendar',
        title: context.l10n.hijriCalendar,
        color: context.iqroColors.sand,
        onTap: () => context.push('/calendar'),
      ),
      _ToolCard(
        art: 'prayer',
        title: context.l10n.prayer,
        color: context.iqroColors.sand,
        onTap: () => context.push('/prayer'),
      ),
      _ToolCard(
        key: const ValueKey('more-courses'),
        art: 'courses',
        title: context.l10n.coursesTitle,
        hint: context.l10n.coursesSubtitle,
        color: context.iqroColors.sand,
        onTap: () => context.push('/courses'),
      ),
      _ToolCard(
        art: 'memorization',
        title: context.l10n.memorization,
        color: context.iqroColors.lavender,
        onTap: () => context.push('/memorization'),
      ),
      _ToolCard(
        art: 'dua',
        title: context.l10n.dua,
        color: Theme.of(context).colorScheme.primaryContainer,
        onTap: () => context.push('/dua'),
      ),
      _ToolCard(
        art: 'favorites',
        title: context.l10n.favorites,
        color: context.iqroColors.panelSoft,
        onTap: () => context.push('/favorites'),
      ),
      _ToolCard(
        art: 'notes',
        title: context.l10n.notes,
        color: context.iqroColors.panelSoft,
        onTap: () => context.push('/notes'),
      ),
      _ToolCard(
        key: const ValueKey('more-names-of-allah'),
        art: 'quran',
        title: context.l10n.namesOfAllah,
        color: context.iqroColors.panelSoft,
      ),
    ],
  );
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    super.key,
    required this.art,
    required this.title,
    required this.color,
    this.hint,
    this.onTap,
  });

  /// A key of the shared topic illustrations (`dua-topic-icons.json`).
  final String art;
  final String title;
  final Color color;

  /// Read out by screen readers after the title.
  final String? hint;

  /// Null for a section that is announced but not open yet: the card shows
  /// "Soon" instead of the arrow and does not react to taps.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final soon = onTap == null;
    final card = IqroCard(
      color: color,
      borderColor: Colors.transparent,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // The light tile keeps the mint of the art apart from tinted cards.
          Container(
            width: 64,
            height: 64,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: .8),
              borderRadius: BorderRadius.circular(18),
            ),
            child: FittedBox(child: DuaThematicIcon(topic: art)),
          ),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          if (soon)
            Text(
              context.l10n.soon,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: context.iqroColors.gold),
            )
          else
            const Icon(Icons.arrow_forward, size: 18),
        ],
      ),
    );
    return hint == null ? card : Semantics(hint: hint, child: card);
  }
}
