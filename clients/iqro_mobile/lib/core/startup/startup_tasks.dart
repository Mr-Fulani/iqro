Future<T> initializeCriticalStartup<T extends Object>({
  required Future<T> Function() initializeDependencies,
  required Future<void> Function() initializeAudioPlatform,
}) async {
  final dependencies = initializeDependencies();
  final audioPlatform = initializeAudioPlatform();
  final results = await Future.wait<Object?>(<Future<Object?>>[
    dependencies,
    audioPlatform,
  ]);
  return results.first as T;
}
