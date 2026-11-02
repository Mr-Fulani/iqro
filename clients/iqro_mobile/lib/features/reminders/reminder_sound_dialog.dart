import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../onboarding/onboarding_services.dart';

/// People who installed the app before the adhan never saw the onboarding step,
/// so whoever expects a sounding reminder is checked once on opening the app.
/// Reminders turned on later are caught on a later launch.
Future<void> checkReminderSoundOnce(BuildContext context, WidgetRef ref) async {
  if (await _soundMutedAtFirstCheck(ref) && context.mounted) {
    await showDialog<void>(
      context: context,
      builder: (_) => const ReminderSoundDialog(),
    );
  }
}

Future<bool> _soundMutedAtFirstCheck(WidgetRef ref) async {
  try {
    if (ref.read(appPreferencesProvider).reminderSoundChecked) return false;
    final services = ref.read(onboardingServicesProvider);
    if (!await services.soundingPrayerReminders()) return false;
    final allowed = await services.reminderSoundAllowed();
    await ref.read(appPreferencesProvider.notifier).markReminderSoundChecked();
    return !allowed;
  } on Object {
    // A courtesy check: it never gets in the way of opening the app.
    return false;
  }
}

class ReminderSoundDialog extends ConsumerStatefulWidget {
  const ReminderSoundDialog({super.key});

  @override
  ConsumerState<ReminderSoundDialog> createState() =>
      _ReminderSoundDialogState();
}

class _ReminderSoundDialogState extends ConsumerState<ReminderSoundDialog>
    with WidgetsBindingObserver {
  var _on = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // The switch itself lives in the system settings; read it on the way back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_read());
  }

  Future<void> _read() async {
    final allowed = await ref
        .read(onboardingServicesProvider)
        .reminderSoundAllowed();
    if (mounted) setState(() => _on = allowed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      constraints: const BoxConstraints(maxWidth: 420),
      icon: const Icon(Icons.volume_up_outlined),
      title: Text(l10n.onboardingSoundTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            _on ? l10n.onboardingSoundOn : l10n.onboardingSoundBody,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            key: const Key('reminder-sound-switch'),
            contentPadding: EdgeInsets.zero,
            value: _on,
            onChanged: (_) =>
                ref.read(onboardingServicesProvider).openNotificationSettings(),
            title: Text(l10n.onboardingSoundSwitch),
          ),
        ],
      ),
      actions: <Widget>[
        FilledButton(
          key: const Key('reminder-sound-close'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.continueLabel),
        ),
      ],
    );
  }
}
