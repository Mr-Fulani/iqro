import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/utils/json_helpers.dart';

final accountDevicesProvider = FutureProvider.autoDispose<List<AccountDevice>>((
  ref,
) async {
  final session = ref.watch(sessionProvider).valueOrNull;
  final database = ref.watch(localDatabaseProvider);
  final scope = database.accountScope.current;
  if (session == null ||
      !session.isVerified ||
      scope == null ||
      scope.userId != session.userId) {
    return const <AccountDevice>[];
  }

  final payload = await ref
      .watch(apiClientProvider)
      .get('/me/devices', accountScope: scope);
  return jsonResults(payload)
      .whereType<Map>()
      .map((value) => AccountDevice.fromJson(Map<String, Object?>.from(value)))
      .toList(growable: false);
});

class AccountDevice {
  const AccountDevice({
    required this.id,
    required this.platform,
    required this.locale,
    required this.appVersion,
    required this.isCurrent,
  });

  factory AccountDevice.fromJson(Map<String, Object?> json) {
    final id = json['id']?.toString().trim();
    final platform = json['platform']?.toString().trim();
    if (id == null || id.isEmpty || platform == null || platform.isEmpty) {
      throw const FormatException('Malformed device inventory item');
    }
    return AccountDevice(
      id: id,
      platform: platform,
      locale: json['locale']?.toString().trim() ?? '',
      appVersion: json['app_version']?.toString().trim() ?? '',
      isCurrent: json['is_current'] == true,
    );
  }

  final String id;
  final String platform;
  final String locale;
  final String appVersion;
  final bool isCurrent;

  String get displayPlatform => switch (platform.toLowerCase()) {
    'android' => 'Android',
    'ios' => 'iOS',
    'web' => 'Web',
    _ => platform,
  };

  String get subtitle {
    final details = <String>[
      if (appVersion.isNotEmpty) appVersion,
      if (locale.isNotEmpty) locale.toUpperCase(),
    ];
    return details.join(' · ');
  }

  IconData get icon => switch (platform.toLowerCase()) {
    'android' => Icons.android,
    'ios' => Icons.phone_iphone,
    'web' => Icons.language,
    _ => Icons.devices_outlined,
  };
}

class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(accountDevicesProvider);
    return Scaffold(
      appBar: IqroTopBar(
        title: context.l10n.devices,
        actions: <Widget>[
          IconButton(
            tooltip: context.l10n.refresh,
            onPressed: () => ref.invalidate(accountDevicesProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: devices.when(
        loading: () => const IqroLoading(),
        error: (error, stackTrace) => IqroAsyncError(
          title: context.l10n.networkError,
          onRetry: () => ref.invalidate(accountDevicesProvider),
        ),
        data: (items) => _DevicesContent(devices: items),
      ),
    );
  }
}

class _DevicesContent extends StatelessWidget {
  const _DevicesContent({required this.devices});

  final List<AccountDevice> devices;

  @override
  Widget build(BuildContext context) {
    if (devices.isEmpty) {
      return IqroPage(
        child: IqroCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.devices_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(context.l10n.noDevices)),
            ],
          ),
        ),
      );
    }

    return IqroPage(
      child: IqroCard(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(
          children: <Widget>[
            for (var index = 0; index < devices.length; index++) ...<Widget>[
              IqroListTile(
                icon: devices[index].icon,
                title: devices[index].displayPlatform,
                subtitle: devices[index].subtitle.isEmpty
                    ? null
                    : devices[index].subtitle,
                trailing: devices[index].isCurrent
                    ? Chip(label: Text(context.l10n.currentDevice))
                    : null,
              ),
              if (index < devices.length - 1) const Divider(height: 1),
            ],
          ],
        ),
      ),
    );
  }
}
