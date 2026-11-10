import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import 'analytics_consent.dart';
import 'home_widgets_settings.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(appPreferencesProvider);
    return Scaffold(
      appBar: IqroTopBar(title: context.l10n.settings),
      body: IqroPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            IqroSectionHeader(title: context.l10n.language),
            const SizedBox(height: 10),
            IqroCard(
              padding: const EdgeInsets.all(10),
              child: DropdownButtonFormField<String>(
                initialValue: preferences.locale,
                decoration: InputDecoration(labelText: context.l10n.language),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: 'ru', child: Text('Русский')),
                  DropdownMenuItem(value: 'en', child: Text('English')),
                  DropdownMenuItem(
                    value: 'ar',
                    child: Text('العربية', textDirection: TextDirection.rtl),
                  ),
                  DropdownMenuItem(value: 'tr', child: Text('Türkçe')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    ref.read(appPreferencesProvider.notifier).setLocale(value);
                  }
                },
              ),
            ),
            const SizedBox(height: 22),
            IqroSectionHeader(title: context.l10n.theme),
            const SizedBox(height: 10),
            IqroCard(
              padding: const EdgeInsets.all(10),
              child: _ThemeModeSwitch(
                mode: preferences.themeMode,
                onChanged: ref.read(appPreferencesProvider.notifier).setTheme,
              ),
            ),
            const SizedBox(height: 22),
            IqroSectionHeader(title: context.l10n.homeWidgets),
            const SizedBox(height: 10),
            const HomeWidgetsSettingsCard(),
            const SizedBox(height: 22),
            IqroSectionHeader(title: context.l10n.moreTools),
            const SizedBox(height: 10),
            IqroCard(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Column(
                children: <Widget>[
                  // The same row as the others in this card, with a switch.
                  IqroListTile(
                    key: const Key('settings-reader-haptics'),
                    icon: Icons.vibration_rounded,
                    title: context.l10n.readerHaptics,
                    subtitle: context.l10n.readerHapticsHint,
                    trailing: Switch.adaptive(
                      value: preferences.readerHaptics,
                      onChanged: ref
                          .read(appPreferencesProvider.notifier)
                          .setReaderHaptics,
                    ),
                    onTap: () => ref
                        .read(appPreferencesProvider.notifier)
                        .setReaderHaptics(!preferences.readerHaptics),
                  ),
                  const Divider(height: 1),
                  IqroListTile(
                    key: const Key('settings-onboarding-replay'),
                    icon: Icons.tour_outlined,
                    title: context.l10n.onboardingReplay,
                    subtitle: context.l10n.onboardingReplayHint,
                    onTap: () => context.push('/onboarding?replay=1'),
                  ),
                  if (kDebugMode) ...[
                    const Divider(height: 1),
                    // Debug builds: test the real first launch without
                    // clearing app data.
                    IqroListTile(
                      icon: Icons.restart_alt,
                      title: 'Debug: reset onboarding',
                      subtitle: 'Opens the first-launch flow now',
                      onTap: () async {
                        await ref
                            .read(appPreferencesProvider.notifier)
                            .resetOnboarding();
                        if (context.mounted) context.go('/onboarding');
                      },
                    ),
                  ],
                  const Divider(height: 1),
                  IqroListTile(
                    icon: Icons.ios_share_outlined,
                    title: context.l10n.shareApp,
                    subtitle: context.l10n.shareBody,
                    onTap: () => context.push('/share'),
                  ),
                  const Divider(height: 1),
                  IqroListTile(
                    icon: Icons.person_outline,
                    title: context.l10n.account,
                    subtitle: context.l10n.syncHint,
                    onTap: () => context.push('/account'),
                  ),
                  const Divider(height: 1),
                  IqroListTile(
                    icon: Icons.offline_pin_outlined,
                    title: context.l10n.offlineStorage,
                    subtitle: context.l10n.offlineStorageSettingsSubtitle,
                    onTap: () => context.push('/settings/offline-storage'),
                  ),
                  const Divider(height: 1),
                  IqroListTile(
                    icon: Icons.privacy_tip_outlined,
                    title: context.l10n.privacy,
                    subtitle: context.l10n.prayerLocationPrivacy,
                  ),
                  if (ref.read(analyticsProvider.notifier).available) ...[
                    const Divider(height: 1),
                    const AnalyticsConsentTile(),
                  ],
                  const Divider(height: 1),
                  IqroListTile(
                    icon: Icons.description_outlined,
                    title: context.l10n.appLicenses,
                    subtitle: 'IQRO',
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: 'IQRO',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// System, light, dark. The icons go when a label would not fit beside its
/// icon on one line: «Системная» broke into «Системн / ая» on a phone.
class _ThemeModeSwitch extends StatelessWidget {
  const _ThemeModeSwitch({required this.mode, required this.onChanged});

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  // The Material 3 segment: 12 dp padding on each side, an 18 dp icon and
  // an 8 dp gap before the label, a 1 dp border.
  static const _segmentPadding = 24.0 + 2;
  static const _iconSpace = 18.0 + 8;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final options = <(ThemeMode, IconData, String)>[
      (ThemeMode.system, Icons.brightness_auto_outlined, l10n.systemTheme),
      (ThemeMode.light, Icons.light_mode_outlined, l10n.lightTheme),
      (ThemeMode.dark, Icons.dark_mode_outlined, l10n.darkTheme),
    ];
    final style = Theme.of(context).textTheme.labelLarge;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final room = constraints.maxWidth / options.length - _segmentPadding;
        final withIcons = options.every((option) {
          final painter = TextPainter(
            text: TextSpan(text: option.$3, style: style),
            textScaler: scaler,
            textDirection: direction,
            maxLines: 1,
          )..layout();
          final fits = painter.width + _iconSpace <= room;
          painter.dispose();
          return fits;
        });
        // Full width as before, with or without the icons.
        final button = SegmentedButton<ThemeMode>(
          key: const Key('settings-theme'),
          segments: <ButtonSegment<ThemeMode>>[
            for (final (value, icon, label) in options)
              ButtonSegment(
                value: value,
                icon: withIcons ? Icon(icon) : null,
                tooltip: withIcons ? null : label,
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label, maxLines: 1, softWrap: false),
                ),
              ),
          ],
          selected: <ThemeMode>{mode},
          showSelectedIcon: false,
          onSelectionChanged: (value) => onChanged(value.first),
        );
        return SizedBox(width: double.infinity, child: button);
      },
    );
  }
}
