import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../app/providers.dart';
import '../../core/auth/account_scope.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/iqro_theme.dart';
import 'prayer_repository.dart';

class PrayerScreen extends ConsumerStatefulWidget {
  const PrayerScreen({super.key});

  @override
  ConsumerState<PrayerScreen> createState() => _PrayerScreenState();
}

class _PrayerScreenState extends ConsumerState<PrayerScreen>
    with WidgetsBindingObserver {
  PrayerSchedule? _schedule;
  PrayerPreferences? _preferences;
  Object? _error;
  String? _selectedMethodCode;
  String? _ownerId;
  String? _profileOwnerId;
  var _loading = false;
  var _profileLoading = false;
  var _savingSettings = false;
  var _profileOffline = false;
  var _retryLocationOnResume = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ownerId = ref.read(sessionProvider).valueOrNull?.userId;
    if (_ownerId != null) _loadAccountState(_ownerId!);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_retryLocationOnResume) return;
    _retryLocationOnResume = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_loading) _calculate();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ownerId = ref.watch(sessionProvider).valueOrNull?.userId;
    if (ownerId != _ownerId) {
      _ownerId = ownerId;
      _schedule = null;
      _preferences = null;
      _selectedMethodCode = null;
      _error = null;
      _profileOwnerId = null;
      _profileLoading = false;
      _profileOffline = false;
      if (ownerId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _ownerId == ownerId) _loadAccountState(ownerId);
        });
      }
    }
    final methods = ref.watch(prayerMethodsProvider);
    final methodItems = methods.valueOrNull ?? const <PrayerMethod>[];
    final selectedMethod = methodItems
        .where((method) => method.code == _selectedMethodCode)
        .firstOrNull;
    final locale = Localizations.localeOf(context).languageCode;
    if (ownerId != null &&
        methodItems.isNotEmpty &&
        _profileOwnerId != ownerId &&
        !_profileLoading) {
      _profileLoading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _ownerId == ownerId) {
          _loadProfile(ownerId, methodItems);
        }
      });
    }
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
            if (_error != null) ...<Widget>[
              const SizedBox(height: 10),
              _PrayerErrorBanner(
                error: _error!,
                onRetry: _calculate,
                onOpenLocationSettings: () =>
                    _openSettings(locationServices: true),
                onOpenAppSettings: () => _openSettings(locationServices: false),
              ),
            ],
            if (methods.hasError) ...<Widget>[
              const SizedBox(height: 10),
              IqroStatusBanner(
                icon: Icons.cloud_off_outlined,
                title: context.l10n.networkError,
                actionLabel: context.l10n.retry,
                onAction: () => ref.invalidate(prayerMethodsProvider),
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
                        final scope = ref
                            .read(localDatabaseProvider)
                            .accountScope
                            .current;
                        if (scope == null || scope.userId != _ownerId) return;
                        final method = methodItems
                            .where((item) => item.code == code)
                            .firstOrNull;
                        if (method == null) return;
                        final preferences =
                            (_preferences ??
                                    PrayerPreferences.defaultsFor(method))
                                .forMethod(method);
                        setState(() {
                          _selectedMethodCode = code;
                          _preferences = preferences;
                        });
                        await _savePreferences(
                          method,
                          preferences,
                          scope: scope,
                        );
                      },
              ),
            ),
            const SizedBox(height: 10),
            IqroCard(
              onTap: selectedMethod == null || _savingSettings
                  ? null
                  : () => _openCalculationSettings(selectedMethod),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.tune),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          context.l10n.prayerCalculationSettings,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _preferencesSummary(context),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (_savingSettings)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(Icons.arrow_forward_ios, size: 16),
                ],
              ),
            ),
            if (_profileOffline) ...<Widget>[
              const SizedBox(height: 10),
              IqroStatusBanner(
                icon: Icons.cloud_off_outlined,
                title: context.l10n.savedOnDevice,
                message: context.l10n.prayerSettingsSyncPending,
              ),
            ],
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
            const SizedBox(height: 18),
            IqroCard(
              onTap: () => context.push('/reminders'),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.notifications_active_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          context.l10n.prayerReminders,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          context.l10n.remindersSubtitle,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, size: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadAccountState(String expectedOwnerId) async {
    final repository = ref.read(prayerRepositoryProvider);
    final scope = ref.read(localDatabaseProvider).accountScope.current;
    if (scope == null || scope.userId != expectedOwnerId) return;
    late final (PrayerSchedule?, String?) values;
    try {
      values = await (
        repository.cachedToday(accountScope: scope),
        repository.selectedMethodCode(accountScope: scope),
      ).wait;
      ref.read(localDatabaseProvider).ensureCurrent(scope);
    } on AccountScopeChanged {
      // Scoped reads are expected to abort during an account transition.
      return;
    } on Object catch (error) {
      if (mounted &&
          ref.read(sessionProvider).valueOrNull?.userId == expectedOwnerId) {
        setState(() => _error = error);
      }
      return;
    }
    if (!mounted ||
        ref.read(sessionProvider).valueOrNull?.userId != expectedOwnerId) {
      return;
    }
    setState(() {
      _schedule = values.$1;
      _selectedMethodCode = values.$2;
    });
  }

  Future<void> _loadProfile(
    String expectedOwnerId,
    List<PrayerMethod> methods,
  ) async {
    final database = ref.read(localDatabaseProvider);
    final scope = database.accountScope.current;
    if (scope == null || scope.userId != expectedOwnerId) return;
    try {
      final profile = await ref
          .read(prayerRepositoryProvider)
          .loadProfile(methods: methods, accountScope: scope);
      database.ensureCurrent(scope);
      if (!mounted || _ownerId != expectedOwnerId) return;
      setState(() {
        _selectedMethodCode = profile.method.code;
        _preferences = profile.preferences;
        _profileOffline = profile.offline;
        _profileOwnerId = expectedOwnerId;
        _profileLoading = false;
      });
      final schedule = await ref
          .read(prayerRepositoryProvider)
          .calculateForStoredLocation(
            method: profile.method,
            accountScope: scope,
          );
      database.ensureCurrent(scope);
      if (!mounted || _ownerId != expectedOwnerId || schedule == null) return;
      setState(() => _schedule = schedule);
      ref.invalidate(prayerScheduleProvider(accountScopeKey(scope)));
    } on AccountScopeChanged {
      // A fresh screen instance loads the new account profile.
    } on Object catch (error) {
      if (!mounted || _ownerId != expectedOwnerId) return;
      setState(() {
        _profileLoading = false;
        _profileOwnerId = expectedOwnerId;
        _error = error;
      });
    }
  }

  Future<void> _openCalculationSettings(PrayerMethod method) async {
    final current = _preferences ?? PrayerPreferences.defaultsFor(method);
    final result = await showModalBottomSheet<PrayerPreferences>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) =>
          _PrayerSettingsSheet(method: method, initial: current),
    );
    if (result == null || !mounted) return;
    final scope = ref.read(localDatabaseProvider).accountScope.current;
    if (scope == null || scope.userId != _ownerId) return;
    setState(() => _preferences = result);
    await _savePreferences(method, result, scope: scope);
  }

  Future<void> _savePreferences(
    PrayerMethod method,
    PrayerPreferences preferences, {
    required AccountScopeSnapshot scope,
  }) async {
    if (_savingSettings) return;
    setState(() {
      _savingSettings = true;
      _error = null;
    });
    final database = ref.read(localDatabaseProvider);
    try {
      final saved = await ref
          .read(prayerRepositoryProvider)
          .saveProfile(
            method: method,
            preferences: preferences,
            accountScope: scope,
          );
      database.ensureCurrent(scope);
      if (!mounted || _ownerId != scope.userId) return;
      setState(() {
        _selectedMethodCode = saved.method.code;
        _preferences = saved.preferences;
        _profileOffline = saved.offline;
      });
      final schedule = await ref
          .read(prayerRepositoryProvider)
          .calculateForStoredLocation(method: method, accountScope: scope);
      database.ensureCurrent(scope);
      if (mounted && _ownerId == scope.userId && schedule != null) {
        setState(() => _schedule = schedule);
        ref.invalidate(prayerScheduleProvider(accountScopeKey(scope)));
        await ref.read(reminderProvider.notifier).replan();
      }
    } on AccountScopeChanged {
      // The next screen instance owns the active account profile.
    } on Object catch (error) {
      if (mounted && database.accountScope.isCurrent(scope)) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted && database.accountScope.isCurrent(scope)) {
        setState(() => _savingSettings = false);
      }
    }
  }

  Future<void> _calculate() async {
    final expectedOwnerId = _ownerId;
    final database = ref.read(localDatabaseProvider);
    final scope = database.accountScope.current;
    if (expectedOwnerId == null ||
        scope == null ||
        scope.userId != expectedOwnerId) {
      return;
    }
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
          .calculateForCurrentLocation(method: method, accountScope: scope);
      database.ensureCurrent(scope);
      if (!mounted || _ownerId != expectedOwnerId) return;
      setState(() => _schedule = value);
      ref.invalidate(prayerScheduleProvider(accountScopeKey(scope)));
      await ref.read(reminderProvider.notifier).replan();
    } on AccountScopeChanged {
      // Ignore a completed location/calculation request from the old account.
    } on Object catch (error) {
      if (mounted &&
          _ownerId == expectedOwnerId &&
          database.accountScope.isCurrent(scope)) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted &&
          _ownerId == expectedOwnerId &&
          database.accountScope.isCurrent(scope)) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openSettings({required bool locationServices}) async {
    _retryLocationOnResume = true;
    final opened = locationServices
        ? await Geolocator.openLocationSettings()
        : await Geolocator.openAppSettings();
    if (!opened) _retryLocationOnResume = false;
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

  String _preferencesSummary(BuildContext context) {
    final preferences = _preferences;
    if (preferences == null) return context.l10n.prayerSettingsDefault;
    final adjusted = preferences.adjustments.values
        .where((value) => value != 0)
        .length;
    final asr = preferences.hanafiAsr
        ? context.l10n.asrHanafi
        : context.l10n.asrStandard;
    return adjusted == 0
        ? asr
        : '$asr · $adjusted ${context.l10n.prayerAdjustedTimes}';
  }
}

class _PrayerSettingsSheet extends StatefulWidget {
  const _PrayerSettingsSheet({required this.method, required this.initial});

  final PrayerMethod method;
  final PrayerPreferences initial;

  @override
  State<_PrayerSettingsSheet> createState() => _PrayerSettingsSheetState();
}

class _PrayerSettingsSheetState extends State<_PrayerSettingsSheet> {
  late String _asrMethod = widget.initial.asrMethod;
  late String _highLatitudeRule = widget.initial.highLatitudeRule;
  late String _polarResolution = widget.initial.polarResolution;
  late Map<String, int> _adjustments = Map<String, int>.from(
    widget.initial.adjustments,
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      12,
      20,
      20 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            context.l10n.prayerCalculationSettings,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 20),
          IqroSectionHeader(title: context.l10n.asrCalculation),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: <ButtonSegment<String>>[
              ButtonSegment<String>(
                value: 'standard',
                label: Text(context.l10n.asrStandard),
              ),
              ButtonSegment<String>(
                value: 'hanafi',
                label: Text(context.l10n.asrHanafi),
              ),
            ],
            selected: <String>{_asrMethod},
            onSelectionChanged: (values) {
              setState(() => _asrMethod = values.single);
            },
          ),
          const SizedBox(height: 8),
          Text(
            _asrMethod == 'hanafi'
                ? context.l10n.asrHanafiHint
                : context.l10n.asrStandardHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          IqroSectionHeader(title: context.l10n.manualPrayerAdjustments),
          const SizedBox(height: 4),
          Text(
            context.l10n.manualPrayerAdjustmentsHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          for (final code in _adjustmentCodes)
            _AdjustmentRow(
              label: _prayerName(context, code),
              value: _adjustments[code] ?? 0,
              onChanged: (value) => setState(() {
                _adjustments = <String, int>{
                  ..._adjustments,
                  code: value.clamp(-120, 120),
                };
              }),
            ),
          const SizedBox(height: 20),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            title: Text(context.l10n.advancedCalculationRules),
            children: <Widget>[
              DropdownButtonFormField<String>(
                initialValue: _highLatitudeRule,
                decoration: InputDecoration(
                  labelText: context.l10n.highLatitudeRule,
                ),
                items: widget.method.supportedHighLatitudeRules
                    .map(
                      (value) => DropdownMenuItem<String>(
                        value: value,
                        child: Text(_highLatitudeName(context, value)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _highLatitudeRule = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _polarResolution,
                decoration: InputDecoration(
                  labelText: context.l10n.polarResolution,
                ),
                items: widget.method.supportedPolarResolutions
                    .map(
                      (value) => DropdownMenuItem<String>(
                        value: value,
                        child: Text(_polarName(context, value)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _polarResolution = value);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(
                widget.initial.copyWith(
                  asrMethod: _asrMethod,
                  highLatitudeRule: _highLatitudeRule,
                  polarResolution: _polarResolution,
                  adjustments: _adjustments,
                ),
              ),
              child: Text(context.l10n.save),
            ),
          ),
        ],
      ),
    ),
  );
}

class _AdjustmentRow extends StatelessWidget {
  const _AdjustmentRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          tooltip: context.l10n.decrease,
          onPressed: value <= -120 ? null : () => onChanged(value - 1),
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 76,
          child: Text(
            '${value > 0 ? '+' : ''}$value ${context.l10n.minutes}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        IconButton(
          tooltip: context.l10n.increase,
          onPressed: value >= 120 ? null : () => onChanged(value + 1),
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    ),
  );
}

String _prayerName(BuildContext context, String code) => switch (code) {
  'fajr' => context.l10n.fajr,
  'sunrise' => context.l10n.sunrise,
  'dhuhr' => context.l10n.dhuhr,
  'asr' => context.l10n.asr,
  'maghrib' => context.l10n.maghrib,
  _ => context.l10n.isha,
};

String _highLatitudeName(BuildContext context, String value) => switch (value) {
  'seventh_of_night' => context.l10n.seventhOfNight,
  'twilight_angle' => context.l10n.twilightAngle,
  _ => context.l10n.middleOfNight,
};

String _polarName(BuildContext context, String value) => switch (value) {
  'aqrab_balad' => context.l10n.nearestLatitude,
  'aqrab_yaum' => context.l10n.nearestDay,
  _ => context.l10n.noPolarSubstitution,
};

const _adjustmentCodes = <String>[
  'fajr',
  'sunrise',
  'dhuhr',
  'asr',
  'maghrib',
  'isha',
];

class _PrayerErrorBanner extends StatelessWidget {
  const _PrayerErrorBanner({
    required this.error,
    required this.onRetry,
    required this.onOpenLocationSettings,
    required this.onOpenAppSettings,
  });

  final Object error;
  final VoidCallback onRetry;
  final VoidCallback onOpenLocationSettings;
  final VoidCallback onOpenAppSettings;

  @override
  Widget build(BuildContext context) {
    final apiError = error is ApiException ? error as ApiException : null;
    return switch (apiError?.code) {
      'location_disabled' => IqroStatusBanner(
        icon: Icons.location_off_outlined,
        title: context.l10n.locationServicesDisabled,
        message: context.l10n.locationServicesDisabledBody,
        actionLabel: context.l10n.settings,
        onAction: onOpenLocationSettings,
      ),
      'location_denied' => IqroStatusBanner(
        icon: Icons.location_disabled_outlined,
        title: context.l10n.locationPermissionRequired,
        message: context.l10n.locationPermissionRequiredBody,
        actionLabel: context.l10n.retry,
        onAction: onRetry,
      ),
      'location_denied_forever' => IqroStatusBanner(
        icon: Icons.location_disabled_outlined,
        title: context.l10n.locationPermissionRequired,
        message: context.l10n.locationDenied,
        actionLabel: context.l10n.settings,
        onAction: onOpenAppSettings,
      ),
      'location_timeout' || 'location_unavailable' => IqroStatusBanner(
        icon: Icons.location_searching_outlined,
        title: context.l10n.locationUnavailable,
        message: context.l10n.prayerCalculationFailed,
        actionLabel: context.l10n.retry,
        onAction: onRetry,
      ),
      _ => IqroStatusBanner(
        icon: Icons.error_outline,
        title: apiError?.isOffline == true
            ? context.l10n.networkError
            : context.l10n.prayerCalculationFailed,
        actionLabel: context.l10n.retry,
        onAction: onRetry,
      ),
    };
  }
}
