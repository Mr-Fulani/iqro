import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../core/auth/account_scope.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/local_database.dart';
import '../../core/utils/json_helpers.dart';

class ShareExperience {
  const ShareExperience({
    required this.title,
    required this.message,
    required this.ctaLabel,
    required this.url,
    required this.remote,
    this.campaignKey,
    this.configVersion,
    this.referralEnabled = false,
    this.referralCode,
  });

  final String title;
  final String message;
  final String ctaLabel;
  final String url;
  final bool remote;
  final String? campaignKey;
  final String? configVersion;
  final bool referralEnabled;
  final String? referralCode;

  ShareExperience withReferral({
    required String code,
    required String shortUrl,
  }) {
    return ShareExperience(
      title: title,
      message: message,
      ctaLabel: ctaLabel,
      url: shortUrl,
      remote: remote,
      campaignKey: campaignKey,
      configVersion: configVersion,
      referralEnabled: referralEnabled,
      referralCode: code,
    );
  }
}

class ReferralSummary {
  const ReferralSummary({
    required this.invited,
    required this.qualified,
    required this.rewardBalance,
    required this.pendingReward,
  });

  factory ReferralSummary.fromJson(Map<String, Object?> json) {
    return ReferralSummary(
      invited: (json['invited'] as num?)?.toInt() ?? 0,
      qualified: (json['qualified'] as num?)?.toInt() ?? 0,
      rewardBalance: (json['reward_balance'] as num?)?.toInt() ?? 0,
      pendingReward: (json['pending_reward'] as num?)?.toInt() ?? 0,
    );
  }

  final int invited;
  final int qualified;
  final int rewardBalance;
  final int pendingReward;
}

class ShareClientMetadata {
  const ShareClientMetadata({required this.platform, required this.osMajor});

  final String platform;
  final String osMajor;
}

String shareOsMajor(String version) {
  final match = RegExp(r'\d+').firstMatch(version);
  return match?.group(0) ?? 'unknown';
}

class ShareRepository {
  ShareRepository({
    required ApiClient api,
    required AppConfig config,
    required LocalDatabase database,
    required AuthRepository auth,
    Uuid? uuid,
  }) : _api = api,
       _config = config,
       _database = database,
       _auth = auth,
       _uuid = uuid ?? const Uuid();

  final ApiClient _api;
  final AppConfig _config;
  final LocalDatabase _database;
  final AuthRepository _auth;
  final Uuid _uuid;

  Future<ShareExperience> experience({
    required String locale,
    required String fallbackTitle,
    required String fallbackMessage,
    required String fallbackCta,
    AccountScopeSnapshot? accountScope,
  }) async {
    // Capture the private-account boundary before the public config request.
    // Otherwise a response started by A could resume after a handoff and
    // create a personalized referral link for B.
    final scope = accountScope ?? await _database.captureAccount();
    _database.ensureCurrent(scope);
    final initialSession = _auth.current;
    final referralEligible =
        initialSession?.userId == scope.userId &&
        initialSession?.isVerified == true;
    final fallback = ShareExperience(
      title: fallbackTitle,
      message: fallbackMessage,
      ctaLabel: fallbackCta,
      url: _config.fallbackDownloadUrl,
      remote: false,
    );
    try {
      final response = jsonMap(
        await _api.get(
          '/share/config',
          query: <String, Object?>{'locale': locale},
          public: true,
        ),
      );
      _database.ensureCurrent(scope);
      if (response['available'] != true || response['campaign'] is! Map) {
        return fallback;
      }
      final campaign = Map<String, Object?>.from(response['campaign']! as Map);
      var experience = ShareExperience(
        title: campaign['title']?.toString() ?? fallbackTitle,
        message: campaign['message']?.toString() ?? fallbackMessage,
        ctaLabel: campaign['cta_label']?.toString() ?? fallbackCta,
        url: campaign['canonical_download_url']?.toString() ?? fallback.url,
        remote: true,
        campaignKey: campaign['key']?.toString(),
        configVersion: campaign['config_version']?.toString(),
        referralEnabled: campaign['referral_enabled'] == true,
      );
      if (experience.referralEnabled && referralEligible) {
        try {
          _database.ensureCurrent(scope);
          final session = _auth.current;
          if (session?.userId != scope.userId || session?.isVerified != true) {
            return experience;
          }
          final referral = jsonMap(
            await _api.post(
              '/me/referrals/links',
              data: <String, Object?>{'campaign_key': experience.campaignKey},
              accountScope: scope,
            ),
          );
          _database.ensureCurrent(scope);
          final code = referral['code']?.toString();
          final shortUrl = referral['short_url']?.toString();
          if (code != null && shortUrl != null) {
            experience = experience.withReferral(
              code: code,
              shortUrl: shortUrl,
            );
          }
        } on AccountScopeChanged {
          rethrow;
        } on Object {
          // Personalization must never block the ordinary share flow.
        }
      }
      return experience;
    } on AccountScopeChanged {
      rethrow;
    } on Object {
      return fallback;
    }
  }

  Future<ReferralSummary?> summary(
    String? campaignKey, {
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    try {
      _database.ensureCurrent(scope);
      final session = _auth.current;
      if (session?.userId != scope.userId || session?.isVerified != true) {
        return null;
      }
      final summary = ReferralSummary.fromJson(
        jsonMap(
          await _api.get(
            '/me/referrals/summary',
            query: campaignKey == null
                ? null
                : <String, Object?>{'campaign': campaignKey},
            accountScope: scope,
          ),
        ),
      );
      _database.ensureCurrent(scope);
      return summary;
    } on AccountScopeChanged {
      rethrow;
    } on Object {
      return null;
    }
  }

  Future<ShareResult> openShareSheet(
    ShareExperience experience, {
    required String sourceScreen,
    Rect? sharePositionOrigin,
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = experience.campaignKey == null
        ? null
        : accountScope ?? await _database.captureAccount();
    if (scope != null) _database.ensureCurrent(scope);
    final result = await SharePlus.instance.share(
      ShareParams(
        subject: experience.title,
        text: '${experience.message}\n\n${experience.url}',
        title: experience.ctaLabel,
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
    if (scope != null) {
      await _enqueueEvent(
        experience: experience,
        action: 'open-system-share',
        result: switch (result.status) {
          ShareResultStatus.success => 'shared',
          ShareResultStatus.dismissed => 'dismissed',
          ShareResultStatus.unavailable => 'unavailable',
        },
        sourceScreen: sourceScreen,
        accountScope: scope,
      );
    }
    return result;
  }

  Future<void> trackCopy(
    ShareExperience experience, {
    required String sourceScreen,
    AccountScopeSnapshot? accountScope,
  }) async {
    if (experience.campaignKey == null) return;
    final scope = accountScope ?? await _database.captureAccount();
    _database.ensureCurrent(scope);
    await _enqueueEvent(
      experience: experience,
      action: 'copy-link',
      result: 'copied',
      sourceScreen: sourceScreen,
      accountScope: scope,
    );
  }

  Future<void> _enqueueEvent({
    required ShareExperience experience,
    required String action,
    required String result,
    required String sourceScreen,
    required AccountScopeSnapshot accountScope,
  }) async {
    try {
      final package = await _packageMetadata();
      final client = await _clientMetadata();
      _database.ensureCurrent(accountScope);
      final id = _uuid.v7();
      final payload = <String, Object?>{
        'client_event_id': id,
        'campaign_key': experience.campaignKey,
        if (experience.referralCode != null)
          'referral_code': experience.referralCode,
        'action': action,
        'result': result,
        'channel': action == 'copy-link' ? 'copy' : 'system',
        'occurred_at': DateTime.now().toUtc().toIso8601String(),
        'metadata': <String, Object?>{
          'app_version': package.version,
          'app_build': package.buildNumber,
          'platform': client.platform,
          'os_major': client.osMajor,
          'source_screen': sourceScreen,
        },
      };
      await _database.enqueue(
        operationId: id,
        entityType: 'share_event',
        payload: payload,
        accountScope: accountScope,
      );
      unawaited(_deliverEvent(id, payload, accountScope));
    } on Object {
      // Analytics must never make sharing or copying appear to fail.
    }
  }

  Future<({String version, String buildNumber})> _packageMetadata() async {
    try {
      final package = await PackageInfo.fromPlatform();
      return (version: package.version, buildNumber: package.buildNumber);
    } on Object {
      return (version: 'unknown', buildNumber: 'unknown');
    }
  }

  Future<ShareClientMetadata> _clientMetadata() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isIOS) {
        final ios = await deviceInfo.iosInfo;
        return ShareClientMetadata(
          platform: 'ios',
          osMajor: shareOsMajor(ios.systemVersion),
        );
      }
      if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        return ShareClientMetadata(
          platform: 'android',
          osMajor: shareOsMajor(android.version.release),
        );
      }
    } on Object {
      // Keep privacy-safe coarse metadata even when the plugin is unavailable.
    }
    return ShareClientMetadata(
      platform: Platform.operatingSystem,
      osMajor: 'unknown',
    );
  }

  Future<void> _deliverEvent(
    String id,
    Map<String, Object?> payload,
    AccountScopeSnapshot scope,
  ) async {
    try {
      await _api.post('/share/events', data: payload, accountScope: scope);
      _database.ensureCurrent(scope);
      await _database.acknowledgeOutbox(id, accountScope: scope);
    } on Object catch (error) {
      try {
        await _database.markOutboxFailure(
          id,
          error.toString(),
          accountScope: scope,
        );
      } on Object {
        // The durable outbox will be retried by the background sync worker.
      }
    }
  }

  Map<String, Object?> decodeOutboxPayload(String encoded) {
    return Map<String, Object?>.from(jsonDecode(encoded) as Map);
  }
}
