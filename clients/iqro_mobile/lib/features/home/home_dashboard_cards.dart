import 'package:flutter/material.dart';

import '../../core/design_system/iqro_icon.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';

class HomeContinueReadingCard extends StatelessWidget {
  const HomeContinueReadingCard({
    required this.surahName,
    required this.ayah,
    required this.page,
    required this.onTap,
    this.footer,
    this.error = false,
    super.key,
  });
  final String surahName;
  final int? ayah;
  final int? page;
  final bool error;
  final VoidCallback? onTap;

  /// Below a divider: the day's plan on Home.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      child: IqroCard(
        key: const ValueKey('home-reading'),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked =
                    constraints.maxWidth < 280 ||
                    MediaQuery.textScalerOf(context).scale(16) > 20;
                final summary = Row(
                  children: [
                    IqroIcon(
                      Icons.menu_book_outlined,
                      color: theme.colorScheme.primary,
                      size: 36,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.continueReading,
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            error ? context.l10n.networkError : surahName,
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 5),
                          if (!error)
                            Text(
                              ayah == null || page == null
                                  ? context.l10n.loading
                                  : '${context.l10n.ayah} $ayah · ${context.l10n.page} $page',
                              style: theme.textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                  ],
                );
                final read = FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.brightness == Brightness.dark
                        ? const Color(0xFFFFFCF5)
                        : theme.colorScheme.primary,
                    foregroundColor: theme.brightness == Brightness.dark
                        ? context.iqroColors.ink
                        : theme.colorScheme.onPrimary,
                  ),
                  onPressed: onTap,
                  icon: IqroIcon(
                    error ? Icons.refresh_rounded : Icons.menu_book_outlined,
                    size: 20,
                  ),
                  label: Text(error ? context.l10n.retry : context.l10n.read),
                );
                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [summary, const SizedBox(height: 12), read],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: summary),
                    const SizedBox(width: 12),
                    read,
                  ],
                );
              },
            ),
            if (footer case final footer?) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 6),
              footer,
            ],
          ],
        ),
      ),
    );
  }
}
