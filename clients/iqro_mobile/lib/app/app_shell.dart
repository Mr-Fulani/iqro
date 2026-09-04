import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design_system/iqro_lazy_indexed_stack.dart';
import '../core/design_system/iqro_widgets.dart';
import '../features/audio/audio_screen.dart';
import '../features/audio/mini_player.dart';
import '../features/home/home_screen.dart';
import '../features/more/more_screen.dart';
import '../features/plan/plan_screen.dart';
import '../features/quran/quran_screen.dart';
import 'providers.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({this.initialIndex = 0, super.key});
  final int initialIndex;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  late var _index = widget.initialIndex.clamp(0, 4);

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialIndex != widget.initialIndex) {
      _index = widget.initialIndex.clamp(0, 4);
    }
  }

  @override
  Widget build(BuildContext context) {
    final playerActive = ref.watch(
      audioControllerProvider.select((value) => value.active),
    );
    return Scaffold(
      extendBody: true,
      body: IqroLazyIndexedStack(
        index: _index,
        builders: <WidgetBuilder>[
          (_) => const HomeScreen(),
          (_) => const QuranScreen(),
          (_) => const PlanScreen(),
          (_) => const AudioScreen(),
          (_) => const MoreScreen(),
        ],
      ),
      bottomNavigationBar: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (playerActive) const IqroMiniPlayer(),
            NavigationBar(
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: .96),
              selectedIndex: _index,
              onDestinationSelected: (value) => setState(() => _index = value),
              destinations: <NavigationDestination>[
                NavigationDestination(
                  icon: const Icon(Icons.home_outlined),
                  selectedIcon: const Icon(Icons.home),
                  label: context.l10n.navHome,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.menu_book_outlined),
                  selectedIcon: const Icon(Icons.menu_book),
                  label: context.l10n.navQuran,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.track_changes_outlined),
                  selectedIcon: const Icon(Icons.track_changes),
                  label: context.l10n.navPlan,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.headphones_outlined),
                  selectedIcon: const Icon(Icons.headphones),
                  label: context.l10n.navAudio,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.grid_view_outlined),
                  selectedIcon: const Icon(Icons.grid_view),
                  label: context.l10n.navMore,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
