import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_session/audio_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/app_dependencies.dart';
import 'core/startup/startup_tasks.dart';
import 'core/startup/startup_gate.dart';
import 'core/audio/listening_media_service.dart';

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

// The brand intro plays on the first launch only; later cold starts open as
// soon as dependencies are ready.
const _startupIntroSeenKey = 'startup_intro_seen_v1';

Future<bool> _shouldPlayIntro() async {
  final preferences = await SharedPreferences.getInstance();
  return preferences.getBool(_startupIntroSeenKey) != true;
}

void _markIntroSeen() {
  unawaited(
    SharedPreferences.getInstance()
        .then((preferences) => preferences.setBool(_startupIntroSeenKey, true))
        .catchError((Object _) => false),
  );
}

Future<void> _initializeAudioPlatform() async {
  await ListeningMediaService.initialize();
  final audioSession = await AudioSession.instance;
  await audioSession.configure(const AudioSessionConfiguration.speech());
}

class _IqroBootstrap extends StatelessWidget {
  const _IqroBootstrap();

  @override
  Widget build(BuildContext context) => StartupGate<AppDependencies>(
    initialize: _initialize,
    shouldPlayIntro: _shouldPlayIntro,
    onIntroFinished: _markIntroSeen,
    readyBuilder: (dependencies) => ProviderScope(
      overrides: dependencies.overrides,
      child: const IqroApp(),
    ),
  );
}
