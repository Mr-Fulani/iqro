import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_session/audio_session.dart';

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
    readyBuilder: (dependencies) => ProviderScope(
      overrides: dependencies.overrides,
      child: const IqroApp(),
    ),
  );
}
