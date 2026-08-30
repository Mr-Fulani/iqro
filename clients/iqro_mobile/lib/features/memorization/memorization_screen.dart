import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';

class MemorizationScreen extends ConsumerWidget {
  const MemorizationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(memorizationProvider);
    return Scaffold(
      appBar: IqroTopBar(title: context.l10n.memorizationTitle),
      body: state.when(
        loading: () => const IqroLoading(),
        error: (error, stack) => IqroAsyncError(
          title: context.l10n.networkError,
          onRetry: ref.read(memorizationProvider.notifier).reload,
        ),
        data: (value) => IqroPage(
          child: Column(
            children: <Widget>[
              IqroCard(
                color: context.iqroColors.ink,
                borderColor: Colors.transparent,
                child: Column(
                  children: <Widget>[
                    Text(
                      'الفاتحة',
                      textDirection: TextDirection.rtl,
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: Colors.white,
                        fontFamily: 'serif',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${context.l10n.ayah} ${value.startAyah}–${value.endAyah}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .72),
                      ),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: 118,
                      height: 118,
                      child: Stack(
                        alignment: Alignment.center,
                        children: <Widget>[
                          CircularProgressIndicator(
                            value: value.target == 0
                                ? 0
                                : value.completed / value.target,
                            strokeWidth: 9,
                            backgroundColor: Colors.white.withValues(
                              alpha: .15,
                            ),
                          ),
                          Text(
                            '${value.completed} / ${value.target}',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              IqroCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    IqroEyebrow(context.l10n.repetitionTarget),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => ref
                                .read(memorizationProvider.notifier)
                                .assess('again'),
                            child: Text(context.l10n.again),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => ref
                                .read(memorizationProvider.notifier)
                                .assess('hard'),
                            child: Text(context.l10n.hard),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => ref
                                .read(memorizationProvider.notifier)
                                .assess('good'),
                            child: Text(context.l10n.good),
                          ),
                        ),
                      ],
                    ),
                    if (value.assessment != null) ...<Widget>[
                      const SizedBox(height: 12),
                      IqroStatusBanner(
                        icon: Icons.check_circle_outline,
                        title: switch (value.assessment) {
                          'again' => context.l10n.again,
                          'hard' => context.l10n.hard,
                          _ => context.l10n.good,
                        },
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              TextButton.icon(
                onPressed: () => _confirmReset(context, ref),
                icon: const Icon(Icons.restart_alt),
                label: Text(context.l10n.resetToday),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.resetToday),
        content: Text(context.l10n.resetConfirm),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.resetToday),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(memorizationProvider.notifier).reset();
    }
  }
}
