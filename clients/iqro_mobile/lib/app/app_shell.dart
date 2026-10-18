import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/design_system/iqro_icon.dart';
import '../core/design_system/iqro_lazy_indexed_stack.dart';
import '../core/design_system/iqro_widgets.dart';
import '../features/audio/audio_screen.dart';
import '../features/audio/mini_player.dart';
import '../features/home/home_screen.dart';
import '../features/more/more_screen.dart';
import '../features/plan/plan_screen.dart';
import '../features/quran/quran_screen.dart';
import '../features/quran/surah_name_art.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({this.initialIndex = 0, this.child, super.key});
  final int initialIndex;
  final Widget? child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  late var _index = widget.initialIndex.clamp(0, 4);

  @override
  void initState() {
    super.initState();
    // The Audio tab is built only when first opened; warm what it shows.
    // The Mushaf's surah-name font is fetched once (on the first launch) and
    // then read from disk, so surah lists open with the calligraphy.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(warmAudioCatalog(context, ref));
      unawaited(ref.read(surahHeaderFontProvider.future));
    });
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialIndex != widget.initialIndex) {
      _index = widget.initialIndex.clamp(0, 4);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Tabs switch with `go`, so the system back button found nothing to pop and
    // closed the app from any tab. Back from another tab now returns Home;
    // from Home it exits as before. Screens pushed over the shell pop first.
    final backToHome = widget.child == null && _index != 0;
    return PopScope(
      canPop: !backToHome,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && backToHome) context.go('/app?tab=0');
      },
      child: _buildShell(context),
    );
  }

  Widget _buildShell(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: <Widget>[
          widget.child ??
              IqroLazyIndexedStack(
                index: _index,
                builders: <WidgetBuilder>[
                  (_) => const HomeScreen(),
                  (_) => const QuranScreen(),
                  (_) => const PlanScreen(),
                  (_) => const AudioScreen(),
                  (_) => const MoreScreen(),
                ],
              ),
          const PositionedDirectional(
            start: 0,
            end: 0,
            bottom: 72,
            child: IqroMiniPlayer(),
          ),
        ],
      ),
      bottomNavigationBar: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            NavigationBar(
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: .96),
              selectedIndex: _index,
              onDestinationSelected: (value) => context.go('/app?tab=$value'),
              destinations: <NavigationDestination>[
                NavigationDestination(
                  icon: const Icon(Icons.home_outlined),
                  selectedIcon: const Icon(Icons.home),
                  label: context.l10n.navHome,
                ),
                NavigationDestination(
                  icon: const IqroIcon(Icons.menu_book_outlined),
                  selectedIcon: const IqroIcon(Icons.menu_book),
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
