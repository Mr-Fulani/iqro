import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_system/iqro_icon.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import 'app_release_source.dart';
import 'app_update_controller.dart';

/// A new version from Google Play, first in the account list for as long as
/// it is not installed, also after «Позже» hid the card above the tab bar.
class AppUpdateTile extends ConsumerWidget {
  const AppUpdateTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = ref.watch(appUpdateProvider);
    if (update.stage == AppUpdateStage.none) return const SizedBox.shrink();
    final controller = ref.read(appUpdateProvider.notifier);
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ready = update.stage == AppUpdateStage.readyToInstall;
    final downloading = update.stage == AppUpdateStage.downloading;
    final installed = ref.watch(appVersionLabelProvider).valueOrNull;
    final title = ready
        ? l10n.appUpdateReadyTitle
        : downloading
        ? l10n.appUpdateDownloadingTitle
        : l10n.appUpdateTitle;
    final action = ready
        ? l10n.appUpdateRestart
        : update.viaStore
        ? l10n.appUpdateOpenStore
        : l10n.appUpdateInstall;
    void act() => unawaited(ready ? controller.restart() : controller.update());
    return Column(
      key: const ValueKey('more-app-update'),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ListTile(
          minTileHeight: 64,
          contentPadding: const EdgeInsetsDirectional.symmetric(horizontal: 4),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: IqroIcon(
              ready ? Icons.restart_alt_rounded : Icons.download_rounded,
              color: scheme.primary,
            ),
          ),
          title: Row(
            children: <Widget>[
              Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
              if (!ready && !downloading)
                // Waiting to be installed, as the news dot.
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: context.iqroColors.gold,
                      shape: BoxShape.circle,
                    ),
                    child: const SizedBox.square(dimension: 8),
                  ),
                ),
            ],
          ),
          // The button sits under the text, so a long label («Открыть Google
          // Play», other languages) never squeezes the title.
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (downloading)
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      minHeight: 4,
                      backgroundColor: context.iqroColors.panelSoft,
                    ),
                  ),
                )
              else ...<Widget>[
                if (ready)
                  Text(l10n.appUpdateReadyText)
                else if (installed != null)
                  Text(l10n.appUpdateInstalled(installed)),
                const SizedBox(height: 8),
                FilledButton(onPressed: act, child: Text(action)),
                const SizedBox(height: 4),
              ],
            ],
          ),
          onTap: downloading ? null : act,
        ),
        const Divider(height: 1),
      ],
    );
  }
}
