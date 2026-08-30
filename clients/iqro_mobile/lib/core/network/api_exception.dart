import 'package:dio/dio.dart';

class ApiException implements Exception {
  const ApiException({
    required this.message,
    this.code,
    this.statusCode,
    this.fieldErrors = const <String, Object?>{},
    this.retryAfter,
  });

  factory ApiException.fromDio(DioException error) {
    final data = error.response?.data;
    final problem = data is Map ? Map<String, Object?>.from(data) : null;
    final rawFields = problem?['field_errors'];
    return ApiException(
      message:
          (problem?['detail'] ??
                  problem?['title'] ??
                  error.message ??
                  'Network request failed')
              .toString(),
      code: problem?['code']?.toString(),
      statusCode: error.response?.statusCode,
      fieldErrors: rawFields is Map
          ? Map<String, Object?>.from(rawFields)
          : const <String, Object?>{},
      retryAfter: int.tryParse(
        error.response?.headers.value('retry-after') ?? '',
      ),
    );
  }

  final String message;
  final String? code;
  final int? statusCode;
  final Map<String, Object?> fieldErrors;
  final int? retryAfter;

  bool get isOffline => statusCode == null;
  bool get isUnauthorized => statusCode == 401;
  bool get requiresVerifiedAccount =>
      statusCode == 403 && code == 'verified_account_required';

  @override
  String toString() => 'ApiException($statusCode, $code, $message)';
}
