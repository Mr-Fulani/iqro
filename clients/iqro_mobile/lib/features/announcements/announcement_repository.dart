import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

import '../../core/auth/account_scope.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/storage/local_database.dart';
import 'announcement_logic.dart';

const announcementReceiptEntity = 'announcement_receipt';

typedef AnnouncementList = ({List<Announcement> items, bool fromCache});
typedef AnnouncementFeed = ({AnnouncementFeedPage page, bool fromCache});

String announcementPlatform() =>
    defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

Future<String?> _installedVersion() async {
  try {
    return (await PackageInfo.fromPlatform()).version;
  } on Object {
    return null;
  }
}

/// The public announcement API, its offline copy, this device's marks and the
/// anonymous counters. Marks of a signed-in person go through the outbox, so
/// the sync worker delivers them when the network returns.
class AnnouncementRepository {
  AnnouncementRepository({
    required ApiClient api,
    required LocalDatabase database,
    String? platform,
    Future<String?> Function() appVersion = _installedVersion,
  }) : _api = api,
       _database = database,
       platform = platform ?? announcementPlatform(),
       _appVersion = appVersion;

  static const _stateKey = 'announcements_v1';
  static const _flushDelay = Duration(seconds: 5);
  static const _maxEventsPerBatch = 50;

  final ApiClient _api;
  final LocalDatabase _database;
  final String platform;
  final Future<String?> Function() _appVersion;
  final _uuid = const Uuid();
  final _events = <Map<String, Object?>>[];
  Timer? _flushTimer;

  Future<Map<String, Object?>> _query(String locale) async {
    final version = await _appVersion();
    return <String, Object?>{
      'platform': platform,
      'locale': locale,
      if (version != null &&
          RegExp(r'^\d{1,4}(\.\d{1,4}){0,2}$').hasMatch(version))
        'app_version': version,
    };
  }

  /// Fundraising is asked for on the site only; the server already leaves it
  /// out for the app, and the app never shows it either.
  static List<Announcement> _forApp(List<Announcement> items) =>
      items.where((item) => item.kind != 'fundraising').toList(growable: false);

  Future<AnnouncementLocalState> loadState() async =>
      parseLocalState(await _database.readDeviceState(_stateKey));

  Future<void> saveState(AnnouncementLocalState state) =>
      _database.writeDeviceState(_stateKey, state.toJson());

  /// What may appear on the home screen now. Without the network the last
  /// copy is used, minus what has run out since.
  Future<AnnouncementList> active({
    required String locale,
    bool refresh = false,
    DateTime? now,
  }) async {
    final key = 'announcements:active:v1:$platform:$locale';
    final cached = await _database.readCache(key);
    if (!refresh && cached != null && cached.isFresh) {
      return (
        items: _forApp(parseAnnouncements(cached.value)),
        fromCache: false,
      );
    }
    try {
      final payload = await _api.get(
        '/announcements/active',
        query: await _query(locale),
        public: true,
      );
      await _database.writeCache(key, payload);
      final enabled = payload is Map && payload['enabled'] != false;
      return (
        items: enabled
            ? _forApp(parseAnnouncements(payload))
            : const <Announcement>[],
        fromCache: false,
      );
    } on Object {
      if (cached == null) rethrow;
      final moment = (now ?? DateTime.now()).toUtc();
      return (
        items: _forApp(
          parseAnnouncements(cached.value),
        ).where((item) => item.endsAt.isAfter(moment)).toList(growable: false),
        fromCache: true,
      );
    }
  }

  /// «What's new», newest first. The first page of each filter is kept for
  /// reading without the network.
  Future<AnnouncementFeed> feed({
    required String locale,
    String? kind,
    String? cursor,
  }) async {
    final key = 'announcements:feed:v1:$platform:$locale:${kind ?? 'all'}';
    try {
      final payload = await _api.get(
        '/announcements',
        query: <String, Object?>{
          ...await _query(locale),
          'kind': ?kind,
          'cursor': ?cursor,
        },
        public: true,
      );
      if (cursor == null) {
        await _database.writeCache(key, payload, maxAge: Duration.zero);
      }
      final page = parseAnnouncementFeed(payload);
      return (
        page: AnnouncementFeedPage(
          nextCursor: page.nextCursor,
          results: _forApp(page.results),
        ),
        fromCache: false,
      );
    } on Object {
      final cached = cursor == null ? await _database.readCache(key) : null;
      if (cached == null) rethrow;
      final page = parseAnnouncementFeed(cached.value);
      return (
        page: AnnouncementFeedPage(
          nextCursor: null,
          results: _forApp(page.results),
        ),
        fromCache: true,
      );
    }
  }

  /// The marks this person made on any of their devices.
  Future<Object?> receipts() async {
    final scope = await _database.captureAccount();
    return _api.get('/me/announcement-receipts', accountScope: scope);
  }

  /// Saves the mark in the outbox and sends it at once; the sync worker
  /// retries what could not be sent.
  Future<void> sendReceipt(
    String id, {
    bool read = false,
    bool dismissed = false,
    required int wave,
  }) async {
    final AccountScopeSnapshot scope;
    final operationId = _uuid.v7();
    final body = <String, Object?>{
      if (read) 'read': true,
      if (dismissed) 'dismissed': true,
      'wave': wave,
    };
    try {
      scope = await _database.captureAccount();
      await _database.enqueue(
        operationId: operationId,
        entityType: announcementReceiptEntity,
        entityId: id,
        payload: <String, Object?>{'announcement_id': id, ...body},
        accountScope: scope,
      );
    } on Object {
      return;
    }
    try {
      await _api.put(
        '/me/announcement-receipts/$id',
        data: body,
        accountScope: scope,
      );
      await _database.acknowledgeOutbox(operationId, accountScope: scope);
    } on ApiException catch (error) {
      try {
        // A withdrawn announcement or a rejected mark will never be accepted.
        if (error.statusCode == 400 || error.statusCode == 404) {
          await _database.acknowledgeOutbox(operationId, accountScope: scope);
        } else {
          await _database.markOutboxFailure(
            operationId,
            error.toString(),
            accountScope: scope,
          );
        }
      } on Object {
        // The account changed meanwhile: its own outbox keeps the mark.
      }
    } on Object catch (error) {
      try {
        await _database.markOutboxFailure(
          operationId,
          error.toString(),
          accountScope: scope,
        );
      } on Object {
        // See above.
      }
    }
  }

  /// Anonymous counters: only daily sums per announcement reach the server.
  void track(String id, String surface, String event, int wave) {
    _events.add(<String, Object?>{
      'id': id,
      'surface': surface,
      'event': event,
      'wave': wave,
    });
    _flushTimer ??= Timer(_flushDelay, () => unawaited(flushEvents()));
  }

  Future<void> flushEvents() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    while (_events.isNotEmpty) {
      final batch = _events.take(_maxEventsPerBatch).toList(growable: false);
      _events.removeRange(0, batch.length);
      try {
        await _api.post(
          '/announcements/events',
          data: <String, Object?>{'platform': platform, 'events': batch},
          public: true,
        );
      } on Object {
        // Counters are best effort and never block the app.
      }
    }
  }

  @visibleForTesting
  int get pendingEvents => _events.length;
}
