import 'package:uuid/uuid.dart';

import '../../core/auth/account_scope.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/storage/local_database.dart';
import '../../core/sync/sync_store.dart';
import '../../core/utils/json_helpers.dart';
import 'reminder_models.dart';

class ReminderRepository {
  ReminderRepository({required ApiClient api, required LocalDatabase database})
    : _api = api,
      _database = database;

  final ApiClient _api;
  final LocalDatabase _database;
  final Uuid _uuid = const Uuid();

  Future<List<ReminderRule>> localRules({
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    return _localRulesFor(scope);
  }

  Future<List<ReminderRule>> _localRulesFor(AccountScopeSnapshot scope) async =>
      (await _database.readReminders(accountScope: scope))
          .map(ReminderRule.fromJson)
          .where((rule) => rule.active)
          .toList(growable: false);

  Future<({List<ReminderRule> rules, bool offline})> refresh({
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    try {
      final snapshot = jsonMap(
        await _api.get('/me/reminders', accountScope: scope),
      );
      _database.ensureCurrent(scope);
      final rawRules =
          (snapshot['reminders'] as List?)
              ?.whereType<Map>()
              .map((item) => Map<String, Object?>.from(item))
              .toList(growable: false) ??
          const <Map<String, Object?>>[];
      await SqliteSyncStore(
        _database.database,
        ownerId: scope.userId,
        guard: () => _database.ensureCurrent(scope),
      ).replaceAuthoritativeReminderSnapshot(rawRules);
      return (rules: await _localRulesFor(scope), offline: false);
    } on ApiException catch (error) {
      if (error.code == 'account_scope_changed') rethrow;
      if (!error.isOffline) rethrow;
      return (rules: await _localRulesFor(scope), offline: true);
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
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
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
            accountScope: scope,
          ),
        ),
      );
      _database.ensureCurrent(scope);
      await _database.upsertReminder(result.toLocalJson(), accountScope: scope);
      return result;
    } on ApiException catch (error) {
      if (!shouldPersistReminderMutation(error)) rethrow;
      await _storeOffline(local, action: 'upsert', accountScope: scope);
      return local;
    }
  }

  Future<ReminderRule> update(
    ReminderRule rule, {
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
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
            accountScope: scope,
          ),
        ),
      );
      _database.ensureCurrent(scope);
      await _database.upsertReminder(result.toLocalJson(), accountScope: scope);
      return result;
    } on ApiException catch (error) {
      if (!shouldPersistReminderMutation(error)) rethrow;
      await _storeOffline(local, action: 'upsert', accountScope: scope);
      return local;
    }
  }

  Future<void> deleteRule(
    ReminderRule rule, {
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    if (rule.revision == 0) {
      await _database.discardLocalReminder(rule.id, accountScope: scope);
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
          accountScope: scope,
        ),
      );
      _database.ensureCurrent(scope);
      await _database.upsertReminder(result, accountScope: scope);
    } on ApiException catch (error) {
      if (!shouldPersistReminderMutation(error)) rethrow;
      final tombstone = rule.copyWith(
        isEnabled: false,
        clientUpdatedAt: now,
        deletedAt: now,
      );
      await _storeOffline(tombstone, action: 'delete', accountScope: scope);
    }
  }

  Future<void> _storeOffline(
    ReminderRule rule, {
    required String action,
    required AccountScopeSnapshot accountScope,
  }) async {
    final operationId = _uuid.v4();
    await _database.upsertReminderWithOutbox(
      reminder: rule.toLocalJson(),
      operationId: operationId,
      operation: <String, Object?>{
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
      accountScope: accountScope,
    );
  }
}

bool shouldPersistReminderMutation(ApiException error) {
  if (error.code == 'account_scope_changed') return false;
  final status = error.statusCode;
  return error.isOffline ||
      status == 408 ||
      status == 425 ||
      status == 429 ||
      (status != null && status >= 500 && status <= 599);
}
