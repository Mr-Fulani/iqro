import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';

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
              child: SegmentedButton<ThemeMode>(
                segments: <ButtonSegment<ThemeMode>>[
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: const Icon(Icons.brightness_auto_outlined),
                    label: Text(context.l10n.systemTheme),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: const Icon(Icons.light_mode_outlined),
                    label: Text(context.l10n.lightTheme),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: const Icon(Icons.dark_mode_outlined),
                    label: Text(context.l10n.darkTheme),
                  ),
                ],
                selected: <ThemeMode>{preferences.themeMode},
                showSelectedIcon: false,
                onSelectionChanged: (value) => ref
                    .read(appPreferencesProvider.notifier)
                    .setTheme(value.first),
              ),
            ),
            const SizedBox(height: 22),
            IqroSectionHeader(title: context.l10n.moreTools),
            const SizedBox(height: 10),
            IqroCard(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Column(
                children: <Widget>[
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
                    icon: Icons.privacy_tip_outlined,
                    title: context.l10n.privacy,
                    subtitle: context.l10n.prayerLocationPrivacy,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            IqroStatusBanner(
              icon: Icons.storage_outlined,
              title: preferences.onboardingComplete
                  ? context.l10n.savedAutomatically
                  : context.l10n.guestNote,
              message: context.l10n.offlineUsingCache,
              color: context.iqroColors.sand,
            ),
          ],
        ),
      ),
    );
  }
}
