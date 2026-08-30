import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/iqro_theme.dart';
import 'prayer_repository.dart';

class PrayerScreen extends ConsumerStatefulWidget {
  const PrayerScreen({super.key});

  @override
  ConsumerState<PrayerScreen> createState() => _PrayerScreenState();
}

class _PrayerScreenState extends ConsumerState<PrayerScreen> {
  PrayerSchedule? _schedule;
  Object? _error;
  String? _selectedMethodCode;
  var _loading = false;

  @override
  void initState() {
    super.initState();
    _schedule = ref.read(prayerScheduleProvider).valueOrNull;
    ref.read(prayerRepositoryProvider).cachedToday().then((value) {
      if (mounted) setState(() => _schedule = value);
    });
    ref.read(prayerRepositoryProvider).selectedMethodCode().then((value) {
      if (mounted) setState(() => _selectedMethodCode = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final methods = ref.watch(prayerMethodsProvider);
    final methodItems = methods.valueOrNull ?? const <PrayerMethod>[];
    final selectedMethod = methodItems
        .where((method) => method.code == _selectedMethodCode)
        .firstOrNull;
    final locale = Localizations.localeOf(context).languageCode;
    return Scaffold(
      appBar: IqroTopBar(
        title: context.l10n.prayer,
        subtitle: DateFormat.yMMMMd(
          Localizations.localeOf(context).languageCode,
        ).format(DateTime.now()),
      ),
      body: IqroPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            IqroCard(
              color: context.iqroColors.ink,
              borderColor: Colors.transparent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  IqroEyebrow(context.l10n.nextPrayer, light: true),
                  const SizedBox(height: 8),
                  Text(
                    _nextPrayerName(context),
                    style: Theme.of(
                      context,
                    ).textTheme.displaySmall?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _nextPrayerTime(),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .72),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            IqroStatusBanner(
              icon: Icons.privacy_tip_outlined,
              title: context.l10n.privacy,
              message: context.l10n.prayerLocationPrivacy,
              color: context.iqroColors.lavender,
            ),
            if (_error is ApiException &&
                (_error! as ApiException).code ==
                    'location_denied') ...<Widget>[
              const SizedBox(height: 10),
              IqroStatusBanner(
                icon: Icons.location_off_outlined,
                title: context.l10n.locationDenied,
                actionLabel: context.l10n.settings,
                onAction: Geolocator.openAppSettings,
              ),
            ],
            const SizedBox(height: 22),
            IqroCard(
              child: DropdownButtonFormField<String>(
                key: ValueKey(_selectedMethodCode),
                initialValue: selectedMethod?.code,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.l10n.calculationMethod,
                  prefixIcon: const Icon(Icons.calculate_outlined),
                ),
                items: methodItems
                    .map(
                      (method) => DropdownMenuItem<String>(
                        value: method.code,
                        child: Text(
                          method.nameFor(locale),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: methods.isLoading
                    ? null
                    : (code) async {
                        if (code == null) return;
                        setState(() => _selectedMethodCode = code);
                        await ref
                            .read(prayerRepositoryProvider)
                            .selectMethod(code);
                      },
              ),
            ),
            const SizedBox(height: 14),
            if (_schedule == null)
              IqroCard(
                child: Column(
                  children: <Widget>[
                    const Icon(Icons.location_searching, size: 42),
                    const SizedBox(height: 12),
                    Text(
                      context.l10n.prayerUnavailable,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _loading || selectedMethod == null
                            ? null
                            : _calculate,
                        icon: _loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.my_location),
                        label: Text(context.l10n.useMyLocation),
                      ),
                    ),
                  ],
                ),
              )
            else
              IqroCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                child: Column(
                  children: <Widget>[
                    for (final code in const <String>[
                      'fajr',
                      'dhuhr',
                      'asr',
                      'maghrib',
                      'isha',
                    ])
                      ListTile(
                        minTileHeight: 62,
                        leading: Icon(
                          Icons.mosque_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(
                          _name(context, code),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        trailing: Text(
                          _schedule!.times[code] == null
                              ? '—'
                              : DateFormat.Hm().format(_schedule!.times[code]!),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
            if (_schedule != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                '${selectedMethod?.nameFor(locale) ?? _schedule!.methodName} · ${_schedule!.timezone}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _loading || selectedMethod == null
                    ? null
                    : _calculate,
                icon: const Icon(Icons.refresh),
                label: Text(context.l10n.retry),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _calculate() async {
    final methods = ref.read(prayerMethodsProvider).valueOrNull;
    final method = methods
        ?.where((item) => item.code == _selectedMethodCode)
        .firstOrNull;
    if (method == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final value = await ref
          .read(prayerRepositoryProvider)
          .calculateForCurrentLocation(method: method);
      if (mounted) setState(() => _schedule = value);
      ref.invalidate(prayerScheduleProvider);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _nextPrayerName(BuildContext context) {
    if (_schedule == null) return context.l10n.prayerUnavailable;
    final now = DateTime.now();
    for (final code in const <String>[
      'fajr',
      'dhuhr',
      'asr',
      'maghrib',
      'isha',
    ]) {
      if (_schedule!.times[code]?.isAfter(now) == true) {
        return _name(context, code);
      }
    }
    return context.l10n.fajr;
  }

  String _nextPrayerTime() {
    if (_schedule == null) return '';
    final now = DateTime.now();
    for (final code in const <String>[
      'fajr',
      'dhuhr',
      'asr',
      'maghrib',
      'isha',
    ]) {
      final time = _schedule!.times[code];
      if (time?.isAfter(now) == true) return DateFormat.Hm().format(time!);
    }
    return '';
  }

  String _name(BuildContext context, String code) => switch (code) {
    'fajr' => context.l10n.fajr,
    'dhuhr' => context.l10n.dhuhr,
    'asr' => context.l10n.asr,
    'maghrib' => context.l10n.maghrib,
    _ => context.l10n.isha,
  };
}
