import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_system/iqro_widgets.dart';
import 'app_update_controller.dart';

/// A new version from Google Play, above the tab bar next to the statistics
/// card: first «Обновить» / «Позже», then «Перезапустить» once downloaded.
class AppUpdateCard extends ConsumerWidget {
  const AppUpdateCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = ref.watch(appUpdateProvider);
    final controller = ref.read(appUpdateProvider.notifier);
    final l10n = context.l10n;
    final ready = update.stage == AppUpdateStage.readyToInstall;
    if (!ready && update.stage != AppUpdateStage.offer) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final text = ready
        ? l10n.appUpdateReadyText
        : update.mandatory
        ? l10n.appUpdateRequiredText
        : l10n.appUpdateText;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: IqroCard(
        key: const ValueKey('app-update'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.system_update_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ready ? l10n.appUpdateReadyTitle : l10n.appUpdateTitle,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(text, style: theme.textTheme.bodySmall),
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: <Widget>[
                if (ready)
                  TextButton(
                    onPressed: controller.postponeRestart,
                    child: Text(l10n.appUpdateLater),
                  )
                else if (!update.mandatory)
                  TextButton(
                    onPressed: () => unawaited(controller.later()),
                    child: Text(l10n.appUpdateLater),
                  ),
                FilledButton(
                  onPressed: () => unawaited(
                    ready ? controller.restart() : controller.update(),
                  ),
                  child: Text(
                    ready ? l10n.appUpdateRestart : l10n.appUpdateInstall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
