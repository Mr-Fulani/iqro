import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/background/background_maintenance_service.dart';
import '../core/background/background_work.dart';
import '../core/theme/iqro_theme.dart';
import '../core/widgets/prayer_times.home_widget.dart';
import '../l10n/generated/app_localizations.dart';
import 'account_scoped_maintenance.dart';
import 'providers.dart';
import 'router.dart';

class IqroApp extends ConsumerStatefulWidget {
  const IqroApp({super.key});

  @override
  ConsumerState<IqroApp> createState() => _IqroAppState();
}

class _IqroAppState extends ConsumerState<IqroApp> with WidgetsBindingObserver {
  late final _router = createRouter(
    onboardingComplete: ref.read(appPreferencesProvider).onboardingComplete,
  );
  StreamSubscription<String>? _notificationRoutes;
  StreamSubscription<Uri>? _prayerWidgetRoutes;
  final _maintenance = AccountScopedMaintenanceCoordinator();
  var _backgroundWorkRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final notifications = ref.read(notificationGatewayProvider);
    _notificationRoutes = notifications.routeRequests.listen(_router.go);
    _prayerWidgetRoutes = PrayerTimesHomeWidget.launchedFromWidget().listen(
      (_) => _router.go('/prayer'),
      onError: (Object error, StackTrace stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'IQRO prayer widget routing',
          ),
        );
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = notifications.takeInitialRoute();
      if (route != null) _router.go(route);
      _requestBackgroundWork();
      _requestMaintenance();
    });
  }

  void _requestBackgroundWork() {
    if (_backgroundWorkRequested) return;
    _backgroundWorkRequested = true;
    late final Future<void> initialization;
    try {
      initialization = initializeBackgroundWork();
    } on Object catch (error, stackTrace) {
      _reportBackgroundWorkError(error, stackTrace);
      return;
    }
    unawaited(
      initialization.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          _reportBackgroundWorkError(error, stackTrace);
        },
      ),
    );
  }

  void _reportBackgroundWorkError(Object error, StackTrace stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'IQRO deferred background work',
      ),
    );
  }

  void _requestMaintenance() {
    final key = ref.read(activeAccountScopeKeyProvider);
    late final Future<BackgroundMaintenanceReport> Function() run;
    late final Future<void> Function() restoreAudio;
    try {
      final service = ref.read(backgroundMaintenanceProvider);
      final audio = ref.read(audioControllerProvider.notifier);
      run = () => service.run(renewReminders: true);
      restoreAudio = audio.restoreLatestIfIdle;
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'IQRO background maintenance',
        ),
      );
      return;
    }
    // iOS only keeps a bounded future notification plan. Renew it on launch
    // and every foreground resume; headless account mutation is intentionally
    // disabled until it can be fenced safely across isolates.
    unawaited(
      _maintenance.run(
        key: key,
        maintenance: run,
        isCurrent: (expected) =>
            mounted && ref.read(activeAccountScopeKeyProvider) == expected,
        restoreAudio: restoreAudio,
        reportUnexpected: (error, stackTrace) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'IQRO background maintenance',
            ),
          );
        },
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _requestMaintenance();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationRoutes?.cancel();
    _prayerWidgetRoutes?.cancel();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(appPreferencesProvider);
    ref.watch(sessionProvider);
    ref.watch(reminderProvider);
    ref.listen<AccountScopeKey?>(activeAccountScopeKeyProvider, (
      previous,
      next,
    ) {
      if (next != null && next != previous) _requestMaintenance();
    });
    ref.listen<String>(appPreferencesProvider.select((value) => value.locale), (
      previous,
      next,
    ) {
      if (previous != null && previous != next) {
        unawaited(ref.read(reminderProvider.notifier).replan());
        _requestPrayerWidgetUpdate(next);
      }
    });
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      theme: IqroTheme.light(),
      darkTheme: IqroTheme.dark(),
      themeMode: preferences.themeMode,
      locale: Locale(preferences.locale),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: _router,
    );
  }

  void _requestPrayerWidgetUpdate(String locale) {
    final database = ref.read(localDatabaseProvider);
    final scope = database.accountScope.current;
    if (scope == null) return;
    final update = ref
        .read(prayerWidgetServiceProvider)
        .update(locale: locale, accountScope: scope);
    unawaited(
      update.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'IQRO prayer widget localization',
            ),
          );
        },
      ),
    );
  }
}
