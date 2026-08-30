import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'app/app.dart';
import 'app/app_dependencies.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'forum.iqro.app.audio',
    androidNotificationChannelName: 'IQRO Quran audio',
    androidNotificationOngoing: true,
  );
  final dependencies = await AppDependencies.initialize();
  runApp(
    ProviderScope(overrides: dependencies.overrides, child: const IqroApp()),
  );
}
