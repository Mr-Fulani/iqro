import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/account_scope.dart';
import '../../core/network/api_exception.dart';
import '../../core/notifications/notification_gateway.dart';
import '../../core/storage/local_database.dart';
import '../prayer/prayer_repository.dart';
import 'reminder_models.dart';
import 'reminder_repository.dart';

class ReminderController extends StateNotifier<ReminderState> {
  ReminderController({
    required ReminderRepository repository,
    required NotificationGateway notifications,
    required PrayerRepository prayerRepository,
    required LocalDatabase database,
    required AccountScopeSnapshot? accountScope,
    required String Function() locale,
  }) : _repository = repository,
       _notifications = notifications,
       _prayerRepository = prayerRepository,
       _database = database,
       _accountScope = accountScope,
       _locale = locale,
       super(const ReminderState()) {
    if (accountScope != null) unawaited(reload());
  }

  final ReminderRepository _repository;
  final NotificationGateway _notifications;
  final PrayerRepository _prayerRepository;
  final LocalDatabase _database;
  final AccountScopeSnapshot? _accountScope;
  final String Function() _locale;

  Future<void> reload() async {
    final scope = _accountScope;
    if (scope == null) return;
    try {
      final local = await _repository.localRules(accountScope: scope);
      final permission = await _notifications.permissionStatus();
      _database.ensureCurrent(scope);
      state = state.copyWith(
        rules: local,
        permission: permission,
        loading: local.isEmpty,
        clearError: true,
      );
      final result = await _repository.refresh(accountScope: scope);
      _database.ensureCurrent(scope);
      state = state.copyWith(
        rules: result.rules,
        permission: permission,
        loading: false,
        offline: result.offline,
        clearError: true,
      );
      await replan();
    } on AccountScopeChanged {
      // This controller belongs to the disposed account generation.
    } on Object catch (error) {
      if (_database.accountScope.isCurrent(scope)) {
        state = state.copyWith(loading: false, error: error);
      }
    }
  }

  Future<void> requestPermission() async {
    final scope = _requireScope();
    try {
      final permission = await _notifications.requestPermission();
      _database.ensureCurrent(scope);
      if (!mounted) return;
      state = state.copyWith(permission: permission, clearError: true);
      if (permission == ReminderPermission.granted) await replan();
    } on AccountScopeChanged {
      // The permission sheet may outlive the account-bound controller.
    } on Object catch (error) {
      if (mounted && _database.accountScope.isCurrent(scope)) {
        state = state.copyWith(error: error);
      }
    }
  }

  Future<void> replan() async {
    final scope = _requireScope();
    try {
      final result = await _notifications.reschedule(
        rules: state.rules,
        prayerRepository: _prayerRepository,
        locale: _locale(),
        accountScope: scope,
      );
      _database.ensureCurrent(scope);
      state = state.copyWith(
        permission: result.permission,
        exactScheduling: result.exact,
      );
    } on ApiException catch (error) {
      if (!error.isOffline && _database.accountScope.isCurrent(scope)) {
        state = state.copyWith(error: error);
      }
    } on AccountScopeChanged {
      // A new provider instance owns the active account.
    } on Object catch (error) {
      if (_database.accountScope.isCurrent(scope)) {
        state = state.copyWith(error: error);
      }
    }
  }

  Future<void> create({
    required ReminderType type,
    required ReminderSchedule schedule,
    required int weekdaysMask,
    required ReminderSignal signal,
    required ReminderTimezoneMode timezoneMode,
    String? timezoneName,
    ReminderReviewTarget? reviewTarget,
  }) async {
    await _mutate((scope) async {
      final rule = await _repository.create(
        type: type,
        schedule: schedule,
        weekdaysMask: weekdaysMask,
        signal: signal,
        timezoneMode: timezoneMode,
        timezoneName: timezoneName,
        reviewTarget: reviewTarget,
        accountScope: scope,
      );
      return <ReminderRule>[...state.rules, rule];
    });
  }

  Future<void> update(ReminderRule rule) async {
    await _mutate((scope) async {
      final result = await _repository.update(rule, accountScope: scope);
      return state.rules
          .map((item) => item.id == result.id ? result : item)
          .toList(growable: false);
    });
  }

  Future<void> toggle(ReminderRule rule, bool enabled) =>
      update(rule.copyWith(isEnabled: enabled));

  Future<void> delete(ReminderRule rule) async {
    await _mutate((scope) async {
      await _repository.deleteRule(rule, accountScope: scope);
      return state.rules
          .where((item) => item.id != rule.id)
          .toList(growable: false);
    });
  }

  Future<void> togglePrayer(String event, bool enabled) async {
    final existing = state.rules
        .where(
          (item) =>
              item.type == ReminderType.prayer &&
              item.schedule.prayerEvent == event,
        )
        .firstOrNull;
    if (existing != null) return toggle(existing, enabled);
    if (!enabled) return;
    await create(
      type: ReminderType.prayer,
      schedule: ReminderSchedule.prayer(prayerEvent: event),
      weekdaysMask: 127,
      signal: ReminderSignal.sound,
      timezoneMode: ReminderTimezoneMode.deviceLocal,
    );
  }

  Future<void> _mutate(
    Future<List<ReminderRule>> Function(AccountScopeSnapshot) operation,
  ) async {
    final scope = _requireScope();
    state = state.copyWith(saving: true, clearError: true);
    try {
      final rules = await operation(scope);
      _database.ensureCurrent(scope);
      state = state.copyWith(rules: rules, saving: false);
      await replan();
    } on AccountScopeChanged {
      // Never publish or re-plan work started by the previous account.
    } on Object catch (error) {
      if (_database.accountScope.isCurrent(scope)) {
        state = state.copyWith(saving: false, error: error);
      }
      rethrow;
    }
  }

  AccountScopeSnapshot _requireScope() =>
      _accountScope ?? (throw const AccountScopeChanged());
}
