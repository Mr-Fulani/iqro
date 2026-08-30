import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../auth/auth_repository.dart';
import '../config/app_config.dart';
import 'api_exception.dart';

class ApiClient {
  ApiClient({
    required AppConfig config,
    required AuthRepository authRepository,
    required String Function() locale,
  }) : _authRepository = authRepository,
       _locale = locale,
       dio = Dio(
         BaseOptions(
           baseUrl: config.apiV1,
           connectTimeout: const Duration(seconds: 12),
           receiveTimeout: const Duration(seconds: 25),
           sendTimeout: const Duration(seconds: 12),
           headers: const <String, Object>{'Accept': 'application/json'},
         ),
       ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (options.extra['public'] != true) {
            final token = await _authRepository.validAccessToken(
              locale: _locale(),
            );
            options.headers['Authorization'] = 'Bearer $token';
          }
          options.headers['Accept-Language'] = _locale();
          handler.next(options);
        },
        onError: (error, handler) async {
          final request = error.requestOptions;
          if (error.response?.statusCode == 401 &&
              request.extra['public'] != true &&
              request.extra['refreshed'] != true) {
            try {
              final session = await _authRepository.refresh();
              request.extra['refreshed'] = true;
              request.headers['Authorization'] =
                  'Bearer ${session.accessToken}';
              final response = await dio.fetch<Object?>(request);
              handler.resolve(response);
              return;
            } on Object {
              // Preserve the original response for predictable error mapping.
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  final AuthRepository _authRepository;
  final String Function() _locale;
  final Dio dio;

  Future<Object?> get(
    String path, {
    Map<String, Object?>? query,
    bool public = false,
    String? etag,
  }) async {
    try {
      final response = await dio.get<Object?>(
        path,
        queryParameters: query,
        options: Options(
          extra: <String, Object?>{'public': public},
          headers: etag == null
              ? null
              : <String, Object?>{'If-None-Match': etag},
        ),
      );
      return response.data;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<Uint8List> getPublicBytes(
    Uri uri, {
    required Set<String> allowedHosts,
    int maxBytes = 8 * 1024 * 1024,
  }) async {
    if (uri.scheme != 'https' || !allowedHosts.contains(uri.host)) {
      throw ArgumentError.value(uri, 'uri', 'Unapproved public asset origin');
    }
    try {
      final response = await dio.getUri<List<int>>(
        uri,
        options: Options(
          responseType: ResponseType.bytes,
          extra: <String, Object?>{'public': true},
          followRedirects: false,
        ),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty || bytes.length > maxBytes) {
        throw const FormatException('Public asset size is invalid');
      }
      return Uint8List.fromList(bytes);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<Object?> post(String path, {Object? data, bool public = false}) async {
    try {
      final response = await dio.post<Object?>(
        path,
        data: data,
        options: Options(extra: <String, Object?>{'public': public}),
      );
      return response.data;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<Object?> put(String path, {Object? data}) async {
    try {
      return (await dio.put<Object?>(path, data: data)).data;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<Object?> patch(String path, {Object? data}) async {
    try {
      return (await dio.patch<Object?>(path, data: data)).data;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> delete(String path, {Object? data}) async {
    try {
      await dio.delete<Object?>(path, data: data);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}
