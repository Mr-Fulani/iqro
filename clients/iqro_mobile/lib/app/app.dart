import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/background/background_maintenance_service.dart';
import '../core/background/background_work.dart';
import '../core/theme/iqro_theme.dart';
import '../core/widgets/home_widget_routes.dart';
import '../features/app_update/app_update_controller.dart';
import '../features/plan/plan_repository.dart';
import '../l10n/generated/app_localizations.dart';
import 'account_scoped_maintenance.dart';
import 'audio_navigation_boundary.dart';
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
  StreamSubscription<String>? _widgetRoutes;
  final _maintenance = AccountScopedMaintenanceCoordinator();
  // Built once: fresh ThemeData on every root build forces an app-wide
  // theme transition and rebuild.
  final _lightTheme = IqroTheme.light();
  final _darkTheme = IqroTheme.dark();
  late Uri _previousAudioUri;
  var _backgroundWorkRequested = false;
  Timer? _cacheMaintenance;

  @override
  void initState() {
    super.initState();
    _previousAudioUri = _router.routeInformationProvider.value.uri;
    _router.routerDelegate.addListener(_handleAudioNavigation);
    WidgetsBinding.instance.addObserver(this);
    _clearPlanWidget();
    final notifications = ref.read(notificationGatewayProvider);
    _notificationRoutes = notifications.routeRequests.listen(_router.go);
    _widgetRoutes = homeWidgetRoutes().listen(
      _router.go,
      onError: (Object error, StackTrace stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'IQRO home widget routing',
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
      _checkForAppUpdate();
      _scheduleCacheMaintenance();
    });
  }

  // Delayed past the first screens: the sweep reads large cache rows and
  // walks file trees, which should not compete with opening the app.
  void _scheduleCacheMaintenance() {
    _cacheMaintenance = Timer(const Duration(seconds: 20), () {
      unawaited(
        ref
            .read(cacheMaintenanceProvider)
            .run()
            .then<void>(
              (_) {},
              onError: (Object error, StackTrace stackTrace) {
                FlutterError.reportError(
                  FlutterErrorDetails(
                    exception: error,
                    stack: stackTrace,
                    library: 'IQRO cache maintenance',
                  ),
                );
              },
            ),
      );
    });
  }

  void _handleAudioNavigation() {
    final configuration = _router.routerDelegate.currentConfiguration;
    if (configuration.isEmpty) return;
    // RouteMatchList.uri stays on the base route for GoRouter.push. The top
    // state resolves the actual visible URI, including imperative routes.
    final next = _router.routerDelegate.state.uri;
    final previous = _previousAudioUri;
    if (next == previous) return;
    _previousAudioUri = next;
    if (!exitsAudioSection(previous, next)) return;
    final audio = ref.read(audioControllerProvider.notifier);
    final pause = switch (audioSectionForUri(previous)) {
      AudioNavigationSection.quran => audio.pauseForQuranExit(),
      AudioNavigationSection.dua => audio.pauseForDuaExit(),
      AudioNavigationSection.memorization => audio.pauseForMemorizationExit(),
      AudioNavigationSection.salah => audio.pauseForSalahExit(),
      AudioNavigationSection.other => Future<void>.value(),
    };
    unawaited(
      pause.catchError((Object error, StackTrace stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'IQRO audio pause on route exit',
          ),
        );
      }),
    );
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

  // Google Play is asked at most once a day; outside Play nothing happens.
  void _checkForAppUpdate() {
    unawaited(
      ref.read(appUpdateProvider.notifier).checkIfDue().catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'IQRO app update check',
          ),
        );
      }),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _requestMaintenance();
      _checkForAppUpdate();
      unawaited(ref.read(planProvider.notifier).reload());
    }
  }

  @override
  void dispose() {
    _cacheMaintenance?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _router.routerDelegate.removeListener(_handleAudioNavigation);
    _notificationRoutes?.cancel();
    _widgetRoutes?.cancel();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (themeMode, locale) = ref.watch(
      appPreferencesProvider.select((value) => (value.themeMode, value.locale)),
    );
    // Keep session and reminders alive without rebuilding the whole app on
    // every token refresh or reminder state change.
    ref.listen(sessionProvider, (_, _) {});
    ref.listen(reminderProvider, (_, _) {});
    ref.listen<AccountScopeKey?>(activeAccountScopeKeyProvider, (
      previous,
      next,
    ) {
      if (next != previous) _clearPlanWidget();
      if (next != null && next != previous) _requestMaintenance();
    });
    ref.listen<AsyncValue<DailyPlan>>(planProvider, (_, next) {
      final plan = next.asData?.value;
      if (plan != null) _publishPlanWidget(plan);
    });
    ref.listen<String>(appPreferencesProvider.select((value) => value.locale), (
      previous,
      next,
    ) {
      if (previous != null && previous != next) {
        unawaited(ref.read(reminderProvider.notifier).replan());
        _requestPrayerWidgetUpdate(next);
        final plan = ref.read(planProvider).asData?.value;
        if (plan != null) _publishPlanWidget(plan);
      }
    });
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      theme: _lightTheme,
      darkTheme: _darkTheme,
      themeMode: themeMode,
      locale: Locale(locale),
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

  void _clearPlanWidget() {
    _reportPlanWidget(
      ref
          .read(planWidgetServiceProvider)
          .clear(locale: ref.read(appPreferencesProvider).locale),
    );
  }

  void _publishPlanWidget(DailyPlan plan) {
    final scope = ref.read(localDatabaseProvider).accountScope.current;
    if (scope == null) return;
    _reportPlanWidget(
      ref
          .read(planWidgetServiceProvider)
          .update(
            plan: plan,
            locale: ref.read(appPreferencesProvider).locale,
            accountScope: scope,
          ),
    );
  }

  void _reportPlanWidget(Future<void> update) {
    unawaited(
      update.catchError((Object error, StackTrace stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'IQRO plan widget',
          ),
        );
      }),
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
