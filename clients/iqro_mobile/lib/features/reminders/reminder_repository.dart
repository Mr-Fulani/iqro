import 'package:uuid/uuid.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/storage/local_database.dart';
import '../../core/utils/json_helpers.dart';
import 'reminder_models.dart';

class ReminderRepository {
  ReminderRepository({required ApiClient api, required LocalDatabase database})
    : _api = api,
      _database = database;

  final ApiClient _api;
  final LocalDatabase _database;
  final Uuid _uuid = const Uuid();

  Future<List<ReminderRule>> localRules() async =>
      (await _database.readReminders())
          .map(ReminderRule.fromJson)
          .where((rule) => rule.active)
          .toList(growable: false);

  Future<({List<ReminderRule> rules, bool offline})> refresh() async {
    try {
      final snapshot = jsonMap(await _api.get('/me/reminders'));
      final rawRules =
          (snapshot['reminders'] as List?)
              ?.whereType<Map>()
              .map((item) => Map<String, Object?>.from(item))
              .toList(growable: false) ??
          const <Map<String, Object?>>[];
      await _database.replaceReminderSnapshot(rawRules);
      return (
        rules: rawRules
            .map(ReminderRule.fromJson)
            .where((rule) => rule.active)
            .toList(growable: false),
        offline: false,
      );
    } on ApiException catch (error) {
      if (!error.isOffline) rethrow;
      return (rules: await localRules(), offline: true);
    }
  }

  Future<ReminderRule> create({
    required ReminderType type,
    required ReminderSchedule schedule,
    required int weekdaysMask,
    required ReminderSignal signal,
    required ReminderTimezoneMode timezoneMode,
    String? timezoneName,
    ReminderReviewTarget? reviewTarget,
    bool isEnabled = true,
  }) async {
    final now = DateTime.now().toUtc();
    final local = ReminderRule(
      id: _uuid.v7(),
      type: type,
      schedule: schedule,
      reviewTarget: reviewTarget,
      weekdaysMask: weekdaysMask,
      timezoneMode: timezoneMode,
      timezoneName: timezoneName,
      signal: signal,
      isEnabled: isEnabled,
      revision: 0,
      clientUpdatedAt: now,
    );
    try {
      final result = ReminderRule.fromJson(
        jsonMap(
          await _api.post(
            '/me/reminders',
            data: <String, Object?>{
              'id': local.id,
              'base_revision': 0,
              'client_updated_at': now.toIso8601String(),
              ...local.functionalJson,
            },
          ),
        ),
      );
      await _database.upsertReminder(result.toLocalJson());
      return result;
    } on ApiException catch (error) {
      if (!error.isOffline) rethrow;
      await _storeOffline(local, action: 'upsert');
      return local;
    }
  }

  Future<ReminderRule> update(ReminderRule rule) async {
    final now = DateTime.now().toUtc();
    final local = rule.copyWith(clientUpdatedAt: now);
    try {
      final result = ReminderRule.fromJson(
        jsonMap(
          await _api.patch(
            '/me/reminders/${rule.id}',
            data: <String, Object?>{
              'base_revision': rule.revision,
              'client_updated_at': now.toIso8601String(),
              ...local.functionalJson,
            },
          ),
        ),
      );
      await _database.upsertReminder(result.toLocalJson());
      return result;
    } on ApiException catch (error) {
      if (!error.isOffline) rethrow;
      await _storeOffline(local, action: 'upsert');
      return local;
    }
  }

  Future<void> deleteRule(ReminderRule rule) async {
    if (rule.revision == 0) {
      await _database.discardLocalReminder(rule.id);
      return;
    }
    final now = DateTime.now().toUtc();
    try {
      final result = jsonMap(
        await _api.delete(
          '/me/reminders/${rule.id}',
          data: <String, Object?>{
            'base_revision': rule.revision,
            'client_updated_at': now.toIso8601String(),
          },
        ),
      );
      await _database.upsertReminder(result);
    } on ApiException catch (error) {
      if (!error.isOffline) rethrow;
      final tombstone = rule.copyWith(
        isEnabled: false,
        clientUpdatedAt: now,
        deletedAt: now,
      );
      await _storeOffline(tombstone, action: 'delete');
    }
  }

  Future<void> _storeOffline(
    ReminderRule rule, {
    required String action,
  }) async {
    await _database.upsertReminder(rule.toLocalJson());
    final operationId = _uuid.v4();
    await _database.replaceOutboxOperation(
      operationId: operationId,
      entityType: 'reminder',
      entityId: rule.id,
      payload: <String, Object?>{
        'operation_id': operationId,
        'entity_type': 'reminder',
        'entity_id': rule.id,
        'action': action,
        'base_revision': rule.revision,
        'client_updated_at': rule.clientUpdatedAt.toIso8601String(),
        'payload': action == 'delete'
            ? const <String, Object?>{}
            : rule.functionalJson,
      },
    );
  }
}
