import 'package:flutter/material.dart';

import 'startup_video.dart';

typedef StartupIntroBuilder = Widget Function(VoidCallback onFinished);

/// Readiness and the intro run concurrently; both finish before the app opens.
class StartupGate<T extends Object> extends StatefulWidget {
  const StartupGate({
    required this.initialize,
    required this.readyBuilder,
    this.introBuilder,
    this.shouldPlayIntro,
    this.onIntroFinished,
    super.key,
  });

  final Future<T> Function() initialize;
  final Widget Function(T dependencies) readyBuilder;
  final StartupIntroBuilder? introBuilder;

  /// Decides whether the intro plays; without it the intro always plays.
  /// A failed decision skips the intro rather than delaying startup.
  final Future<bool> Function()? shouldPlayIntro;

  /// Called once after the intro has played or the user skipped it.
  final VoidCallback? onIntroFinished;

  @override
  State<StartupGate<T>> createState() => _StartupGateState<T>();
}

class _StartupGateState<T extends Object> extends State<StartupGate<T>> {
  late Future<T> _dependencies = widget.initialize();
  late bool? _playIntro = widget.shouldPlayIntro == null ? true : null;
  var _introFinished = false;

  @override
  void initState() {
    super.initState();
    final shouldPlayIntro = widget.shouldPlayIntro;
    if (shouldPlayIntro == null) return;
    shouldPlayIntro().then(
      _decideIntro,
      onError: (Object _) => _decideIntro(false),
    );
  }

  void _decideIntro(bool play) {
    if (!mounted) return;
    setState(() {
      _playIntro = play;
      if (!play) _introFinished = true;
    });
  }

  void _finishIntro() {
    if (!mounted || _introFinished) return;
    setState(() => _introFinished = true);
    widget.onIntroFinished?.call();
  }

  void _retry() {
    setState(() {
      _introFinished = true;
      _dependencies = widget.initialize();
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: _dependencies,
    builder: (context, snapshot) {
      final dependencies = snapshot.data;
      if (dependencies != null && _introFinished) {
        return widget.readyBuilder(dependencies);
      }
      return _StartupScreen(
        hasError: snapshot.hasError,
        onRetry: _retry,
        intro: _introFinished || snapshot.hasError
            ? null
            // Undecided for a few milliseconds: keep the splash without a
            // spinner flash.
            : _playIntro == null
            ? const SizedBox.shrink()
            : widget.introBuilder?.call(_finishIntro) ??
                  StartupVideo(onFinished: _finishIntro),
      );
    },
  );
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen({
    required this.hasError,
    required this.onRetry,
    this.intro,
  });

  final bool hasError;
  final VoidCallback onRetry;
  final Widget? intro;

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFFE6D8BF);
    const accent = Color(0xFF073E34);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.fromSeed(seedColor: accent),
      ),
      home: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (hasError || intro == null)
              SafeArea(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
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
                          style: const TextStyle(color: accent),
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
            ?intro,
          ],
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
