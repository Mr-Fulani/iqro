import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../core/analytics/analytics.dart';
import '../../core/design_system/iqro_animated_logo.dart';
import '../../core/design_system/iqro_icon.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/network/api_exception.dart';
import '../../core/share/content_share.dart';
import '../../core/storage/preferences_store.dart';
import '../../core/theme/iqro_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../account/google_sign_in_button.dart';
import '../prayer/prayer_places.dart';
import '../prayer/prayer_repository.dart';
import '../prayer/prayer_screen.dart' show PrayerCitySheet;
import '../reminders/reminder_models.dart';
import 'onboarding_services.dart';

part 'onboarding_steps.dart';

enum OnboardingStep {
  language,
  tour,
  plan,
  prayer,
  reminders,
  exactReminders,
  analytics,
  done,
}

const _tourSlides = 4;

/// First launch, and a replay from Settings. Every permission has "Later":
/// nothing in the app depends on it, and nothing asks again on its own.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({
    super.key,
    this.replay = false,
    this.initialStep,
    this.initialTourSlide = 0,
  });

  /// From Settings: no plan step (it would reset today's progress) and the
  /// flag is already set.
  final bool replay;

  /// Screenshot tests open a step directly.
  final OnboardingStep? initialStep;
  final int initialTourSlide;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late final List<OnboardingStep> _steps;
  var _index = 0;
  late final _tour = PageController(initialPage: widget.initialTourSlide);
  late var _tourSlide = widget.initialTourSlide;
  var _busy = false;

  var _goal = 'reading';
  var _unit = DailyUnit.pages;
  var _target = 6;

  OnboardingPrayerSetup? _prayer;
  String? _methodCode;
  var _asrMethod = 'standard';
  PrayerLocation? _location;
  var _locating = false;
  Object? _locationError;

  var _remindPrayers = true;
  ReminderPermission? _notifications;
  var _notificationsBlocked = false;
  var _remindersOn = false;

  @override
  void initState() {
    super.initState();
    final analytics = ref.read(analyticsProvider.notifier);
    final preferences = ref.read(appPreferencesProvider);
    _goal = preferences.goal;
    _unit = preferences.dailyUnit;
    _target = preferences.dailyTarget;
    _steps = <OnboardingStep>[
      OnboardingStep.language,
      OnboardingStep.tour,
      if (!widget.replay) OnboardingStep.plan,
      OnboardingStep.prayer,
      OnboardingStep.reminders,
      if (widget.initialStep == OnboardingStep.exactReminders)
        OnboardingStep.exactReminders,
      if (analytics.available &&
          (ref.read(analyticsProvider) == null ||
              widget.initialStep == OnboardingStep.analytics))
        OnboardingStep.analytics,
      OnboardingStep.done,
    ];
    final initial = widget.initialStep;
    if (initial != null && _steps.contains(initial)) {
      _index = _steps.indexOf(initial);
    }
    if (!widget.replay) {
      final locales = WidgetsBinding.instance.platformDispatcher.locales;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(appPreferencesProvider.notifier).adoptDeviceLocale(locales);
        }
      });
    }
    unawaited(_load());
  }

  Future<void> _load() async {
    final services = ref.read(onboardingServicesProvider);
    try {
      final status = await services.reminderStatus();
      if (mounted) {
        setState(() {
          _notifications = status.permission;
          _remindersOn = status.prayerReminders;
        });
      }
    } on Object {
      // Unknown status reads as "not yet": the step still offers the request.
    }
    final OnboardingPrayerSetup setup;
    try {
      setup = await services.loadPrayer();
    } on Object {
      if (mounted) {
        setState(
          () => _prayer = const OnboardingPrayerSetup(
            methods: <PrayerMethod>[],
            methodCode: null,
            asrMethod: 'standard',
            location: null,
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _prayer = setup;
      _methodCode = setup.methodCode;
      _asrMethod = setup.asrMethod;
      _location = setup.location;
    });
  }

  @override
  void dispose() {
    _tour.dispose();
    super.dispose();
  }

  OnboardingStep get _step => _steps[_index];

  PrayerMethod? get _method =>
      _prayer?.methods.where((item) => item.code == _methodCode).firstOrNull;

  Duration _motion(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 280);

  void _advance() {
    if (_index < _steps.length - 1) setState(() => _index++);
  }

  void _back() {
    if (_index > 0) setState(() => _index--);
  }

  Future<void> _run(Future<void> Function() work) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await work();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _nextTourSlide() async {
    if (_tourSlide >= _tourSlides - 1) return _advance();
    final duration = _motion(context);
    if (duration == Duration.zero) {
      _tour.jumpToPage(_tourSlide + 1);
    } else {
      await _tour.nextPage(duration: duration, curve: Curves.easeOutCubic);
    }
  }

  Future<void> _useDeviceLocation() async {
    final method = _method;
    if (method == null || _locating) return;
    setState(() {
      _locating = true;
      _locationError = null;
    });
    try {
      final location = await ref
          .read(onboardingServicesProvider)
          .useDeviceLocation(method);
      if (mounted) setState(() => _location = location);
    } on Object catch (error) {
      if (mounted) setState(() => _locationError = error);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _chooseCity() async {
    final method = _method;
    if (method == null || _locating) return;
    final city = await showModalBottomSheet<PrayerCity>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) =>
          PrayerCitySheet(locale: Localizations.localeOf(context).languageCode),
    );
    if (city == null || !mounted) return;
    setState(() {
      _locating = true;
      _locationError = null;
    });
    try {
      final location = await ref
          .read(onboardingServicesProvider)
          .useCity(city, method);
      if (mounted) setState(() => _location = location);
    } on Object catch (error) {
      if (mounted) setState(() => _locationError = error);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _savePrayer() => _run(() async {
    final method = _method;
    if (method != null) {
      try {
        await ref
            .read(onboardingServicesProvider)
            .savePrayerProfile(
              method: method,
              asrMethod: _asrMethod,
              locale: Localizations.localeOf(context).languageCode,
            );
      } on Object catch (error, stackTrace) {
        // Offline or a server hiccup: the prayer screen can save it later.
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'IQRO onboarding',
          ),
        );
      }
    }
    _advance();
  });

  Future<void> _allowNotifications() => _run(() async {
    final services = ref.read(onboardingServicesProvider);
    final permission = await services.requestNotifications();
    if (!mounted) return;
    setState(() {
      _notifications = permission;
      _notificationsBlocked = permission != ReminderPermission.granted;
    });
    if (permission != ReminderPermission.granted) return;
    if (_remindPrayers) {
      try {
        await services.enablePrayerReminders();
        if (mounted) setState(() => _remindersOn = true);
      } on Object catch (error, stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'IQRO onboarding',
          ),
        );
      }
    }
    final needsExact =
        _remindersOn && await services.needsExactReminderAccess();
    if (!mounted) return;
    if (needsExact && !_steps.contains(OnboardingStep.exactReminders)) {
      _steps.insert(_index + 1, OnboardingStep.exactReminders);
    }
    _advance();
  });

  Future<void> _openExactSettings() => _run(() async {
    await ref.read(onboardingServicesProvider).requestExactReminders();
    if (mounted) _advance();
  });

  Future<void> _answerAnalytics(AnalyticsConsent consent) async {
    await ref.read(analyticsProvider.notifier).setConsent(consent);
    if (mounted) _advance();
  }

  Future<void> _finish() => _run(() async {
    if (!widget.replay) {
      await ref
          .read(appPreferencesProvider.notifier)
          .completeOnboarding(
            locale: ref.read(appPreferencesProvider).locale,
            goal: _goal,
            unit: _unit,
            target: _target,
          );
    }
    if (!mounted) return;
    if (widget.replay && context.canPop()) {
      context.pop();
    } else {
      context.go('/app');
    }
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final step = _step;
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: <Widget>[
              _Header(
                index: _index,
                total: _steps.length,
                onBack: _index == 0 ? null : _back,
                onSkipTour: step == OnboardingStep.tour ? _advance : null,
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: _motion(context),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  // The default centres a short step; steps start at the top.
                  layoutBuilder: (current, previous) => Stack(
                    fit: StackFit.expand,
                    children: <Widget>[...previous, ?current],
                  ),
                  child: KeyedSubtree(
                    key: ValueKey<OnboardingStep>(step),
                    child: _body(step),
                  ),
                ),
              ),
              _Footer(children: _actions(step, l10n)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(OnboardingStep step) => switch (step) {
    OnboardingStep.language => _LanguageStep(
      selected: ref.watch(appPreferencesProvider).locale,
      onSelected: ref.read(appPreferencesProvider.notifier).setLocale,
    ),
    OnboardingStep.tour => _TourStep(
      controller: _tour,
      slide: _tourSlide,
      onSlide: (value) => setState(() => _tourSlide = value),
    ),
    OnboardingStep.plan => _PlanStep(
      goal: _goal,
      unit: _unit,
      target: _target,
      onGoal: (value) => setState(() => _goal = value),
      onUnit: (value) => setState(() {
        _unit = value;
        _target = switch (value) {
          DailyUnit.minutes => 10,
          DailyUnit.pages => 6,
          DailyUnit.ayahs => 10,
        };
      }),
      onTarget: (value) => setState(() => _target = value),
    ),
    OnboardingStep.prayer => _PrayerStep(
      setup: _prayer,
      methodCode: _methodCode,
      asrMethod: _asrMethod,
      location: _location,
      locating: _locating,
      error: _locationError,
      onUseLocation: _useDeviceLocation,
      onChooseCity: _chooseCity,
      onMethod: (value) => setState(() => _methodCode = value),
      onAsr: (value) => setState(() => _asrMethod = value),
      onOpenLocationSettings: () =>
          ref.read(onboardingServicesProvider).openLocationSettings(),
      onOpenAppSettings: () =>
          ref.read(onboardingServicesProvider).openAppSettings(),
    ),
    OnboardingStep.reminders => _RemindersStep(
      remindPrayers: _remindPrayers,
      permission: _notifications,
      blocked: _notificationsBlocked,
      onRemindPrayers: (value) => setState(() => _remindPrayers = value),
    ),
    OnboardingStep.exactReminders => const _ExactRemindersStep(),
    OnboardingStep.analytics => _AnalyticsStep(
      consent: ref.watch(analyticsProvider),
      onPolicy: _openPolicy,
    ),
    OnboardingStep.done => _DoneStep(rows: _summary(context)),
  };

  List<Widget> _actions(OnboardingStep step, AppLocalizations l10n) {
    Widget primary(String label, VoidCallback? onPressed, {Key? key}) =>
        FilledButton(
          key: key,
          onPressed: _busy ? null : onPressed,
          child: Text(label, textAlign: TextAlign.center),
        );
    Widget secondary(String label, VoidCallback? onPressed, {Key? key}) =>
        TextButton(
          key: key,
          onPressed: _busy ? null : onPressed,
          child: Text(label, textAlign: TextAlign.center),
        );
    return switch (step) {
      OnboardingStep.language => <Widget>[
        primary(
          l10n.continueLabel,
          _advance,
          key: const Key('onboarding-next'),
        ),
      ],
      OnboardingStep.tour => <Widget>[
        primary(
          l10n.onboardingNext,
          _nextTourSlide,
          key: const Key('onboarding-next'),
        ),
      ],
      OnboardingStep.plan => <Widget>[
        primary(
          l10n.continueLabel,
          _advance,
          key: const Key('onboarding-next'),
        ),
      ],
      OnboardingStep.prayer => <Widget>[
        primary(
          l10n.continueLabel,
          _prayer == null || _locating ? null : _savePrayer,
          key: const Key('onboarding-next'),
        ),
        secondary(
          l10n.onboardingLater,
          _advance,
          key: const Key('onboarding-later'),
        ),
      ],
      OnboardingStep.reminders => <Widget>[
        primary(
          _notifications == ReminderPermission.granted
              ? l10n.continueLabel
              : l10n.allowNotifications,
          _allowNotifications,
          key: const Key('onboarding-next'),
        ),
        secondary(
          l10n.onboardingLater,
          _advance,
          key: const Key('onboarding-later'),
        ),
      ],
      OnboardingStep.exactReminders => <Widget>[
        primary(
          l10n.onboardingOpenSettings,
          _openExactSettings,
          key: const Key('onboarding-next'),
        ),
        secondary(
          l10n.onboardingKeepApproximate,
          _advance,
          key: const Key('onboarding-later'),
        ),
      ],
      OnboardingStep.analytics => <Widget>[
        primary(
          l10n.analyticsAccept,
          () => _answerAnalytics(AnalyticsConsent.granted),
          key: const Key('onboarding-next'),
        ),
        OutlinedButton(
          key: const Key('onboarding-later'),
          onPressed: _busy
              ? null
              : () => _answerAnalytics(AnalyticsConsent.denied),
          child: Text(l10n.analyticsDecline, textAlign: TextAlign.center),
        ),
      ],
      OnboardingStep.done => <Widget>[
        primary(
          l10n.onboardingStart,
          _finish,
          key: const Key('onboarding-next'),
        ),
      ],
    };
  }

  List<(String, String, bool)> _summary(BuildContext context) {
    final l10n = context.l10n;
    final locale = ref.watch(appPreferencesProvider).locale;
    final analytics = ref.read(analyticsProvider.notifier);
    final consent = ref.watch(analyticsProvider);
    final city = prayerCityById(_location?.cityId);
    final place = _location == null
        ? null
        : city?.nameFor(locale) ?? l10n.currentLocation;
    return <(String, String, bool)>[
      (l10n.language, _languageName(locale), true),
      if (!widget.replay)
        (l10n.onboardingSummaryPlan, _planAmount(l10n, _unit, _target), true),
      (
        l10n.onboardingPrayerTitle,
        place ?? l10n.onboardingLater,
        place != null,
      ),
      (
        l10n.reminders,
        _remindersOn ? l10n.onboardingRemindersOn : l10n.onboardingLater,
        _remindersOn,
      ),
      if (analytics.available)
        (
          l10n.analyticsTitle,
          consent == AnalyticsConsent.granted
              ? l10n.onboardingAnalyticsOn
              : l10n.onboardingAnalyticsOff,
          true,
        ),
    ];
  }

  Future<void> _openPolicy() async {
    final locale = Localizations.localeOf(context).languageCode;
    await launchUrl(
      Uri.parse('$iqroPublicSite/$locale/privacy'),
      mode: LaunchMode.externalApplication,
    );
  }
}

const _languages = <(String, String, String)>[
  ('ru', 'Русский', 'RU'),
  ('en', 'English', 'EN'),
  ('ar', 'العربية', 'عر'),
  ('tr', 'Türkçe', 'TR'),
];

String _languageName(String code) =>
    _languages.where((item) => item.$1 == code).firstOrNull?.$2 ?? code;

String _planAmount(AppLocalizations l10n, DailyUnit unit, int target) =>
    l10n.onboardingPerDay(switch (unit) {
      DailyUnit.minutes => l10n.planMinutes(target),
      DailyUnit.pages => l10n.planPages(target),
      DailyUnit.ayahs => l10n.planAyahs(target),
    });
