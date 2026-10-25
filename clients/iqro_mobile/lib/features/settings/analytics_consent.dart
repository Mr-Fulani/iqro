import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../core/analytics/analytics.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/share/content_share.dart';

/// The question the site's cookie banner asks, above the tab bar until the
/// user answers. Builds without Firebase IDs never show it.
class AnalyticsConsentCard extends ConsumerWidget {
  const AnalyticsConsentCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consent = ref.watch(analyticsProvider);
    final analytics = ref.read(analyticsProvider.notifier);
    if (!analytics.available || consent != null) return const SizedBox.shrink();
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: IqroCard(
        key: const ValueKey('analytics-consent'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(l10n.analyticsTitle, style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(l10n.analyticsCardText, style: theme.textTheme.bodySmall),
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: <Widget>[
                TextButton(
                  onPressed: () => unawaited(_openPolicy(context)),
                  child: Text(l10n.analyticsPolicy),
                ),
                OutlinedButton(
                  onPressed: () =>
                      analytics.setConsent(AnalyticsConsent.denied),
                  child: Text(l10n.analyticsDecline),
                ),
                FilledButton(
                  onPressed: () =>
                      analytics.setConsent(AnalyticsConsent.granted),
                  child: Text(l10n.analyticsAccept),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPolicy(BuildContext context) async {
    final locale = Localizations.localeOf(context).languageCode;
    await launchUrl(
      Uri.parse('$iqroPublicSite/$locale/privacy'),
      mode: LaunchMode.externalApplication,
    );
  }
}

/// The same choice in Settings, where it can be changed at any time.
class AnalyticsConsentTile extends ConsumerWidget {
  const AnalyticsConsentTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consent = ref.watch(analyticsProvider);
    final analytics = ref.read(analyticsProvider.notifier);
    final l10n = context.l10n;
    return SwitchListTile.adaptive(
      key: const ValueKey('analytics-consent-setting'),
      secondary: const Icon(Icons.insights_outlined),
      title: Text(l10n.analyticsTitle),
      subtitle: Text(switch (consent) {
        AnalyticsConsent.granted => l10n.analyticsStateGranted,
        AnalyticsConsent.denied => l10n.analyticsStateDenied,
        null => l10n.analyticsStateUnset,
      }),
      value: consent == AnalyticsConsent.granted,
      onChanged: (value) => analytics.setConsent(
        value ? AnalyticsConsent.granted : AnalyticsConsent.denied,
      ),
    );
  }
}
