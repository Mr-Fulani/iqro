import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/theme/iqro_theme.dart';
import '../l10n/generated/app_localizations.dart';
import 'providers.dart';
import 'router.dart';

class IqroApp extends ConsumerStatefulWidget {
  const IqroApp({super.key});

  @override
  ConsumerState<IqroApp> createState() => _IqroAppState();
}

class _IqroAppState extends ConsumerState<IqroApp> {
  late final _router = createRouter(
    onboardingComplete: ref.read(appPreferencesProvider).onboardingComplete,
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(appPreferencesProvider);
    ref.watch(sessionProvider);
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
}
