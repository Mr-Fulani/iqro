import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/design_system/iqro_action_grid.dart';
import '../../core/theme/iqro_theme.dart';
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
          playerActive: playerActive,
          playerCollapsed: ref.watch(miniPlayerCollapsedProvider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
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
                  Icon(
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

class MoreToolsGrid extends StatelessWidget {
  const MoreToolsGrid({super.key});

  @override
  Widget build(BuildContext context) => IqroActionGrid(
    children: <Widget>[
      _ToolCard(
        icon: Icons.calendar_month_outlined,
        title: context.l10n.hijriCalendar,
        color: context.iqroColors.sand,
        onTap: () => context.push('/calendar'),
      ),
      _ToolCard(
        icon: Icons.mosque_outlined,
        title: context.l10n.prayer,
        color: context.iqroColors.sand,
        onTap: () => context.push('/prayer'),
      ),
      _ToolCard(
        icon: Icons.repeat,
        title: context.l10n.memorization,
        color: context.iqroColors.lavender,
        onTap: () => context.push('/memorization'),
      ),
      _ToolCard(
        icon: Icons.auto_awesome_outlined,
        title: context.l10n.dua,
        color: Theme.of(context).colorScheme.primaryContainer,
        onTap: () => context.push('/dua'),
      ),
      _ToolCard(
        icon: Icons.bookmarks_outlined,
        title: context.l10n.favorites,
        color: context.iqroColors.panelSoft,
        onTap: () => context.push('/favorites'),
      ),
    ],
  );
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IqroCard(
      color: color,
      borderColor: Colors.transparent,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: .65),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(height: 20),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Icon(Icons.arrow_forward, size: 18),
        ],
      ),
    );
  }
}
