abstract interface class SyncRemote {
  Future<Object?> get(String path, {Map<String, Object?>? query});

  Future<Object?> post(String path, {Object? data});

  Future<Object?> put(String path, {Object? data});
}
