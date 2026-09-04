import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'app/app.dart';
import 'app/app_dependencies.dart';
import 'core/startup/startup_tasks.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _IqroBootstrap());
}

Future<AppDependencies> _initialize() async {
  return initializeCriticalStartup<AppDependencies>(
    initializeDependencies: AppDependencies.initialize,
    initializeAudioPlatform: _initializeAudioPlatform,
  );
}

Future<void> _initializeAudioPlatform() async {
  await JustAudioBackground.init(
    androidNotificationChannelId: 'forum.iqro.app.audio',
    androidNotificationChannelName: 'IQRO Quran audio',
    androidNotificationOngoing: true,
  );
  final audioSession = await AudioSession.instance;
  await audioSession.configure(const AudioSessionConfiguration.speech());
}

class _IqroBootstrap extends StatefulWidget {
  const _IqroBootstrap();

  @override
  State<_IqroBootstrap> createState() => _IqroBootstrapState();
}

class _IqroBootstrapState extends State<_IqroBootstrap> {
  late Future<AppDependencies> _dependencies = _initialize();

  void _retry() {
    setState(() => _dependencies = _initialize());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppDependencies>(
      future: _dependencies,
      builder: (context, snapshot) {
        final dependencies = snapshot.data;
        if (dependencies != null) {
          return ProviderScope(
            overrides: dependencies.overrides,
            child: const IqroApp(),
          );
        }
        return _StartupScreen(hasError: snapshot.hasError, onRetry: _retry);
      },
    );
  }
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen({required this.hasError, required this.onRetry});

  final bool hasError;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF01251F);
    const accent = Color(0xFF8FDCCB);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
        ),
      ),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 82,
                  height: 82,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF073E34),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Text(
                    'اق',
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'IQRO',
                  style: TextStyle(
                    color: accent,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 5,
                  ),
                ),
                const SizedBox(height: 28),
                if (!hasError)
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      color: accent,
                      strokeWidth: 3,
                    ),
                  )
                else ...<Widget>[
                  Text(
                    _startupMessage(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: onRetry,
                    child: Text(_retryLabel()),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _startupMessage() =>
      switch (WidgetsBinding.instance.platformDispatcher.locale.languageCode) {
        'ru' => 'Не удалось запустить приложение',
        'ar' => 'تعذر تشغيل التطبيق',
        'tr' => 'Uygulama başlatılamadı',
        _ => 'The app could not start',
      };

  String _retryLabel() =>
      switch (WidgetsBinding.instance.platformDispatcher.locale.languageCode) {
        'ru' => 'Повторить',
        'ar' => 'إعادة المحاولة',
        'tr' => 'Tekrar dene',
        _ => 'Try again',
      };
}
