import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

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
  }) async {
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
      final session = _auth.current;
      if (experience.referralEnabled && session?.isVerified == true) {
        try {
          final referral = jsonMap(
            await _api.post(
              '/me/referrals/links',
              data: <String, Object?>{'campaign_key': experience.campaignKey},
            ),
          );
          final code = referral['code']?.toString();
          final shortUrl = referral['short_url']?.toString();
          if (code != null && shortUrl != null) {
            experience = experience.withReferral(
              code: code,
              shortUrl: shortUrl,
            );
          }
        } on Object {
          // Personalization must never block the ordinary share flow.
        }
      }
      return experience;
    } on Object {
      return fallback;
    }
  }

  Future<ReferralSummary?> summary(String? campaignKey) async {
    if (_auth.current?.isVerified != true) return null;
    try {
      return ReferralSummary.fromJson(
        jsonMap(
          await _api.get(
            '/me/referrals/summary',
            query: campaignKey == null
                ? null
                : <String, Object?>{'campaign': campaignKey},
          ),
        ),
      );
    } on Object {
      return null;
    }
  }

  Future<ShareResult> openShareSheet(
    ShareExperience experience, {
    required String sourceScreen,
  }) async {
    final result = await SharePlus.instance.share(
      ShareParams(
        subject: experience.title,
        text: '${experience.message}\n\n${experience.url}',
        title: experience.ctaLabel,
      ),
    );
    if (experience.campaignKey != null) {
      await _enqueueEvent(
        experience: experience,
        action: 'open-system-share',
        result: switch (result.status) {
          ShareResultStatus.success => 'shared',
          ShareResultStatus.dismissed => 'dismissed',
          ShareResultStatus.unavailable => 'unavailable',
        },
        sourceScreen: sourceScreen,
      );
    }
    return result;
  }

  Future<void> trackCopy(
    ShareExperience experience, {
    required String sourceScreen,
  }) async {
    if (experience.campaignKey == null) return;
    await _enqueueEvent(
      experience: experience,
      action: 'copy-link',
      result: 'copied',
      sourceScreen: sourceScreen,
    );
  }

  Future<void> _enqueueEvent({
    required ShareExperience experience,
    required String action,
    required String result,
    required String sourceScreen,
  }) async {
    final package = await PackageInfo.fromPlatform();
    final android = await DeviceInfoPlugin().androidInfo;
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
        'platform': 'android',
        'os_major': android.version.release.split('.').first,
        'source_screen': sourceScreen,
      },
    };
    await _database.enqueue(
      operationId: id,
      entityType: 'share_event',
      payload: payload,
    );
    try {
      await _api.post('/share/events', data: payload);
      await _database.acknowledgeOutbox(id);
    } on Object catch (error) {
      await _database.markOutboxFailure(id, error.toString());
    }
  }

  Map<String, Object?> decodeOutboxPayload(String encoded) {
    return Map<String, Object?>.from(jsonDecode(encoded) as Map);
  }
}
