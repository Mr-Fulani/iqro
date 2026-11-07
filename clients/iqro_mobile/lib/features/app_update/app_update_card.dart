import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import 'app_release_source.dart';
import 'app_update_controller.dart';

/// A new version from Google Play, above the tab bar next to the statistics
/// card: «Позже» / «Обновить» with the installed version, a loading bar while
/// Play downloads it, then «Перезапустить». A version known only from the
/// server opens Google Play instead.
class AppUpdateCard extends ConsumerWidget {
  const AppUpdateCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = ref.watch(appUpdateProvider);
    final controller = ref.read(appUpdateProvider.notifier);
    final l10n = context.l10n;
    final stage = update.stage;
    // After «Позже» the update stays in More's account list only.
    if (stage == AppUpdateStage.none || update.hidden) {
      return const SizedBox.shrink();
    }
    final ready = stage == AppUpdateStage.readyToInstall;
    final downloading = stage == AppUpdateStage.downloading;
    final offer = stage == AppUpdateStage.offer;
    final installed = offer
        ? ref.watch(appVersionLabelProvider).valueOrNull
        : null;
    final theme = Theme.of(context);
    final colors = context.iqroColors;
    final scheme = theme.colorScheme;
    final title = ready
        ? l10n.appUpdateReadyTitle
        : downloading
        ? l10n.appUpdateDownloadingTitle
        : l10n.appUpdateTitle;
    final text = ready
        ? l10n.appUpdateReadyText
        : downloading
        ? l10n.appUpdateDownloadingText
        : update.mandatory
        ? l10n.appUpdateRequiredText
        : update.viaStore
        ? l10n.appUpdateStoreText
        : l10n.appUpdateText;
    final action = ready
        ? l10n.appUpdateRestart
        : update.viaStore
        ? l10n.appUpdateOpenStore
        : l10n.appUpdateInstall;
    final canWait = ready || !update.mandatory;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: theme.brightness == Brightness.dark
                  ? const Color(0x73000000)
                  : const Color(0x2417201D),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: IqroCard(
          key: const ValueKey('app-update'),
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[scheme.primary, colors.gold],
                  ),
                ),
                child: const SizedBox(height: 5),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: colors.sand,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: colors.line),
                          ),
                          child: Icon(
                            ready
                                ? Icons.restart_alt_rounded
                                : Icons.download_rounded,
                            size: 20,
                            color: colors.gold,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(title, style: theme.textTheme.titleSmall),
                              const SizedBox(height: 2),
                              Text(
                                text,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              if (installed != null) ...<Widget>[
                                const SizedBox(height: 6),
                                _VersionChip(
                                  l10n.appUpdateInstalled(installed),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (downloading || ready) ...<Widget>[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          key: const ValueKey('app-update-progress'),
                          value: ready ? 1 : null,
                          minHeight: 4,
                          backgroundColor: colors.panelSoft,
                        ),
                      ),
                    ],
                    if (!downloading) ...<Widget>[
                      const SizedBox(height: 10),
                      Row(
                        children: <Widget>[
                          if (canWait) ...<Widget>[
                            Expanded(
                              child: FilledButton.tonal(
                                // Green like the version chip: the theme's
                                // tonal gold would compete with the main button.
                                style: FilledButton.styleFrom(
                                  backgroundColor: scheme.primaryContainer,
                                  foregroundColor: scheme.onPrimaryContainer,
                                ),
                                onPressed: ready
                                    ? controller.postponeRestart
                                    : () => unawaited(controller.later()),
                                child: Text(
                                  l10n.appUpdateLater,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: FilledButton(
                              onPressed: () => unawaited(
                                ready
                                    ? controller.restart()
                                    : controller.update(),
                              ),
                              child: Text(action, textAlign: TextAlign.center),
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
        ),
      ),
    );
  }
}

/// «У вас 1.0.5 (6)»: the installed build, to compare with Google Play.
class _VersionChip extends StatelessWidget {
  const _VersionChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      key: const ValueKey('app-update-version'),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onPrimaryContainer,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
