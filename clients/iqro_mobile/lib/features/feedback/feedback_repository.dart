import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

import '../../core/auth/account_scope.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/local_database.dart';
import '../../core/utils/json_helpers.dart';
import 'feedback_models.dart';

class FeedbackRepository {
  FeedbackRepository({
    required ApiClient api,
    required LocalDatabase database,
    required String Function() locale,
    Uuid? uuid,
  }) : _api = api,
       _database = database,
       _locale = locale,
       _uuid = uuid ?? const Uuid();

  final ApiClient _api;
  final LocalDatabase _database;
  final String Function() _locale;
  final Uuid _uuid;

  Future<List<FeedbackTicket>> list({
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    final payload = await _api.get(
      '/feedback/tickets',
      query: const <String, Object?>{'page_size': 25},
      accountScope: scope,
    );
    _database.ensureCurrent(scope);
    return jsonResults(payload)
        .whereType<Map>()
        .map((item) => FeedbackTicket.fromJson(Map<String, Object?>.from(item)))
        .toList(growable: false);
  }

  Future<FeedbackTicket> get(
    String publicId, {
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    final payload = await _api.get(
      '/feedback/tickets/${Uri.encodeComponent(publicId)}',
      accountScope: scope,
    );
    _database.ensureCurrent(scope);
    return FeedbackTicket.fromJson(jsonMap(payload));
  }

  Future<FeedbackTicket> create({
    required String category,
    required String subject,
    required String message,
    String? contactEmail,
    String route = '/feedback',
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    final context = await _clientContext(route);
    final payload = await _api.post(
      '/feedback/tickets',
      data: <String, Object?>{
        'client_request_id': _uuid.v7(),
        'client_message_id': _uuid.v7(),
        'category': category,
        'subject': subject.trim(),
        'message': message.trim(),
        'locale': _backendLocale(_locale()),
        if (contactEmail != null && contactEmail.trim().isNotEmpty)
          'contact_email': contactEmail.trim().toLowerCase(),
        'context': context,
      },
      accountScope: scope,
    );
    _database.ensureCurrent(scope);
    return FeedbackTicket.fromJson(jsonMap(payload));
  }

  Future<FeedbackTicket> sendMessage(
    String publicId,
    String body, {
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    final payload = await _api.post(
      '/feedback/tickets/${Uri.encodeComponent(publicId)}/messages',
      data: <String, Object?>{
        'client_message_id': _uuid.v7(),
        'body': body.trim(),
      },
      accountScope: scope,
    );
    _database.ensureCurrent(scope);
    return FeedbackTicket.fromJson(jsonMap(payload));
  }

  Future<FeedbackTicket> close(
    String publicId, {
    String? reason,
    AccountScopeSnapshot? accountScope,
  }) => _transition(
    publicId,
    action: 'close',
    reason: reason,
    accountScope: accountScope,
  );

  Future<FeedbackTicket> reopen(
    String publicId, {
    String? reason,
    AccountScopeSnapshot? accountScope,
  }) => _transition(
    publicId,
    action: 'reopen',
    reason: reason,
    accountScope: accountScope,
  );

  Future<FeedbackTicket> _transition(
    String publicId, {
    required String action,
    String? reason,
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    final payload = await _api.post(
      '/feedback/tickets/${Uri.encodeComponent(publicId)}/$action',
      data: <String, Object?>{
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
      accountScope: scope,
    );
    _database.ensureCurrent(scope);
    return FeedbackTicket.fromJson(jsonMap(payload));
  }

  Future<Map<String, Object?>> _clientContext(String route) async {
    var appVersion = 'unknown';
    var appBuild = 'unknown';
    try {
      final package = await PackageInfo.fromPlatform();
      appVersion = package.version;
      appBuild = package.buildNumber;
    } on Object {
      // Metadata is helpful for triage but must never block a report.
    }

    final platform = Platform.isIOS ? 'ios' : 'android';
    var osVersion = 'unknown';
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isIOS) {
        osVersion = (await deviceInfo.iosInfo).systemVersion;
      } else if (Platform.isAndroid) {
        osVersion = (await deviceInfo.androidInfo).version.release;
      }
    } on Object {
      // Keep the coarse platform even when device metadata is unavailable.
    }
    return <String, Object?>{
      'route': route,
      'app_version': appVersion,
      'app_build': appBuild,
      'client_platform': platform,
      'os_version': osVersion,
    };
  }

  String _backendLocale(String locale) => switch (locale) {
    'ar' || 'en' || 'ru' => locale,
    _ => 'en',
  };
}
