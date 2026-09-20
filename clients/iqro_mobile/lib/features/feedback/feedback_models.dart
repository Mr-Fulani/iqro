import '../../core/utils/json_helpers.dart';

class FeedbackTicket {
  const FeedbackTicket({
    required this.publicId,
    required this.category,
    required this.subject,
    required this.status,
    required this.priority,
    required this.locale,
    required this.channel,
    required this.slaResponseDueAt,
    required this.firstResponseAt,
    required this.createdAt,
    required this.updatedAt,
    this.clientRequestId,
    this.contactEmail,
    this.team,
    this.resolvedAt,
    this.closedAt,
    this.reopenedAt,
    this.reopenCount = 0,
    this.context,
    this.messages = const <FeedbackMessage>[],
  });

  factory FeedbackTicket.fromJson(Map<String, Object?> json) {
    final publicId = json['public_id']?.toString().trim() ?? '';
    final subject = json['subject']?.toString() ?? '';
    if (publicId.isEmpty || subject.isEmpty) {
      throw const FormatException('Malformed feedback ticket');
    }
    final rawMessages = json['messages'];
    return FeedbackTicket(
      publicId: publicId,
      category: json['category']?.toString() ?? 'other',
      subject: subject,
      status: json['status']?.toString() ?? 'new',
      priority: json['priority']?.toString() ?? 'normal',
      locale: json['locale']?.toString() ?? 'en',
      channel: json['channel']?.toString() ?? 'android',
      slaResponseDueAt: _optionalDate(json['sla_response_due_at']),
      firstResponseAt: _optionalDate(json['first_response_at']),
      createdAt: _requiredDate(json['created_at'], 'created_at'),
      updatedAt: _requiredDate(json['updated_at'], 'updated_at'),
      clientRequestId: json['client_request_id']?.toString(),
      contactEmail: json['contact_email']?.toString(),
      team: json['team']?.toString(),
      resolvedAt: _optionalDate(json['resolved_at']),
      closedAt: _optionalDate(json['closed_at']),
      reopenedAt: _optionalDate(json['reopened_at']),
      reopenCount: (json['reopen_count'] as num?)?.toInt() ?? 0,
      context: json['context'] is Map
          ? FeedbackContext.fromJson(jsonMap(json['context']))
          : null,
      messages: rawMessages is List
          ? rawMessages
                .whereType<Map>()
                .map(
                  (message) => FeedbackMessage.fromJson(
                    Map<String, Object?>.from(message),
                  ),
                )
                .toList(growable: false)
          : const <FeedbackMessage>[],
    );
  }

  final String publicId;
  final String category;
  final String subject;
  final String status;
  final String priority;
  final String locale;
  final String channel;
  final DateTime? slaResponseDueAt;
  final DateTime? firstResponseAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? clientRequestId;
  final String? contactEmail;
  final String? team;
  final DateTime? resolvedAt;
  final DateTime? closedAt;
  final DateTime? reopenedAt;
  final int reopenCount;
  final FeedbackContext? context;
  final List<FeedbackMessage> messages;

  bool get isTerminal => status == 'rejected' || status == 'duplicate';
  bool get canReply => !isTerminal;
  bool get canReopen => status == 'closed' || status == 'resolved';
}

class FeedbackMessage {
  const FeedbackMessage({
    required this.id,
    required this.clientMessageId,
    required this.authorType,
    required this.body,
    required this.createdAt,
  });

  factory FeedbackMessage.fromJson(Map<String, Object?> json) {
    final id = json['id']?.toString().trim() ?? '';
    if (id.isEmpty) throw const FormatException('Malformed feedback message');
    return FeedbackMessage(
      id: id,
      clientMessageId: json['client_message_id']?.toString() ?? '',
      authorType: json['author_type']?.toString() ?? 'system',
      body: json['body']?.toString() ?? '',
      createdAt: _requiredDate(json['created_at'], 'created_at'),
    );
  }

  final String id;
  final String clientMessageId;
  final String authorType;
  final String body;
  final DateTime createdAt;
}

class FeedbackContext {
  const FeedbackContext({
    this.editionCode = '',
    this.contentVersion = '',
    this.surahNumber,
    this.ayahNumber,
    this.pageNumber,
    this.reciterId = '',
    this.recitationId = '',
    this.audioTrackId = '',
    this.playbackMs,
    this.adCampaignId = '',
    this.adCreativeId = '',
    this.route = '',
    this.appVersion = '',
    this.appBuild = '',
    this.clientPlatform = '',
    this.osVersion = '',
  });

  factory FeedbackContext.fromJson(Map<String, Object?> json) {
    return FeedbackContext(
      editionCode: json['edition_code']?.toString() ?? '',
      contentVersion: json['content_version']?.toString() ?? '',
      surahNumber: (json['surah_number'] as num?)?.toInt(),
      ayahNumber: (json['ayah_number'] as num?)?.toInt(),
      pageNumber: (json['page_number'] as num?)?.toInt(),
      reciterId: json['reciter_id']?.toString() ?? '',
      recitationId: json['recitation_id']?.toString() ?? '',
      audioTrackId: json['audio_track_id']?.toString() ?? '',
      playbackMs: (json['playback_ms'] as num?)?.toInt(),
      adCampaignId: json['ad_campaign_id']?.toString() ?? '',
      adCreativeId: json['ad_creative_id']?.toString() ?? '',
      route: json['route']?.toString() ?? '',
      appVersion: json['app_version']?.toString() ?? '',
      appBuild: json['app_build']?.toString() ?? '',
      clientPlatform: json['client_platform']?.toString() ?? '',
      osVersion: json['os_version']?.toString() ?? '',
    );
  }

  final String editionCode;
  final String contentVersion;
  final int? surahNumber;
  final int? ayahNumber;
  final int? pageNumber;
  final String reciterId;
  final String recitationId;
  final String audioTrackId;
  final int? playbackMs;
  final String adCampaignId;
  final String adCreativeId;
  final String route;
  final String appVersion;
  final String appBuild;
  final String clientPlatform;
  final String osVersion;
}

DateTime _requiredDate(Object? value, String field) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  if (date == null) throw FormatException('Malformed feedback $field');
  return date;
}

DateTime? _optionalDate(Object? value) {
  final raw = value?.toString();
  return raw == null ? null : DateTime.tryParse(raw);
}
