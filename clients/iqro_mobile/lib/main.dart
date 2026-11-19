import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/app_dependencies.dart';
import 'core/observability/error_reporting.dart';
import 'core/startup/startup_gate.dart';
import 'core/startup/startup_trace.dart';

void main() {
  StartupTrace.begin();
  WidgetsFlutterBinding.ensureInitialized();
  startErrorReporting();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const <String>[
      'Amiri Quran',
    ], await rootBundle.loadString('assets/fonts/AmiriQuran-OFL.txt'));
    yield LicenseEntryWithLineBreaks(const <String>[
      'three.js',
    ], await rootBundle.loadString('assets/salah3d/LICENSE-three.txt'));
    // The recitation check's model and what runs it.
    yield LicenseEntryWithLineBreaks(
      const <String>['HisnLabs Tajweed v2'],
      'HisnLabs Tajweed v2 (huggingface.co/Hisnlabs/tajweed-v2), '
      'Copyright HisnLabs (HISNLABS CYBER AI - FZCO). Built on '
      'tarteel-ai/whisper-base-ar-quran (Apache-2.0) and the labels of '
      'obadx/muaalem-model-v3_2 (MIT); the expected sounds are written '
      'with quran-transcript (MIT).\n\n'
      '${await rootBundle.loadString('assets/recitation_model/LICENSE-Apache-2.0.txt')}',
    );
    yield LicenseEntryWithLineBreaks(
      const <String>['ONNX Runtime'],
      await rootBundle.loadString(
        'assets/recitation_model/LICENSE-onnxruntime.txt',
      ),
    );
  });
  StartupTrace.mark('runApp');
  runApp(const _IqroBootstrap());
}

// The audio platform is not part of this: the player starts it on first use
// (ListeningMediaService.ensureStarted), after the first screen.
Future<AppDependencies> _initialize() =>
    StartupTrace.step('dependencies', AppDependencies.initialize);

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
