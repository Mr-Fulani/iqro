import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/notifications/notification_gateway.dart';
import '../prayer/prayer_repository.dart';
import 'reminder_models.dart';
import 'reminder_repository.dart';

class ReminderController extends StateNotifier<ReminderState> {
  ReminderController({
    required ReminderRepository repository,
    required NotificationGateway notifications,
    required PrayerRepository prayerRepository,
    required String Function() locale,
  }) : _repository = repository,
       _notifications = notifications,
       _prayerRepository = prayerRepository,
       _locale = locale,
       super(const ReminderState()) {
    unawaited(reload());
  }

  final ReminderRepository _repository;
  final NotificationGateway _notifications;
  final PrayerRepository _prayerRepository;
  final String Function() _locale;

  Future<void> reload() async {
    final local = await _repository.localRules();
    final permission = await _notifications.permissionStatus();
    state = state.copyWith(
      rules: local,
      permission: permission,
      loading: local.isEmpty,
      clearError: true,
    );
    try {
      final result = await _repository.refresh();
      state = state.copyWith(
        rules: result.rules,
        permission: permission,
        loading: false,
        offline: result.offline,
        clearError: true,
      );
      await replan();
    } on Object catch (error) {
      state = state.copyWith(loading: false, error: error);
    }
  }

  Future<void> requestPermission() async {
    final permission = await _notifications.requestPermission();
    state = state.copyWith(permission: permission, clearError: true);
    if (permission == ReminderPermission.granted) await replan();
  }

  Future<void> replan() async {
    try {
      final result = await _notifications.reschedule(
        rules: state.rules,
        prayerRepository: _prayerRepository,
        locale: _locale(),
      );
      state = state.copyWith(
        permission: result.permission,
        exactScheduling: result.exact,
      );
    } on ApiException catch (error) {
      if (!error.isOffline) state = state.copyWith(error: error);
    } on Object catch (error) {
      state = state.copyWith(error: error);
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
    await _mutate(() async {
      final rule = await _repository.create(
        type: type,
        schedule: schedule,
        weekdaysMask: weekdaysMask,
        signal: signal,
        timezoneMode: timezoneMode,
        timezoneName: timezoneName,
        reviewTarget: reviewTarget,
      );
      return <ReminderRule>[...state.rules, rule];
    });
  }

  Future<void> update(ReminderRule rule) async {
    await _mutate(() async {
      final result = await _repository.update(rule);
      return state.rules
          .map((item) => item.id == result.id ? result : item)
          .toList(growable: false);
    });
  }

  Future<void> toggle(ReminderRule rule, bool enabled) =>
      update(rule.copyWith(isEnabled: enabled));

  Future<void> delete(ReminderRule rule) async {
    await _mutate(() async {
      await _repository.deleteRule(rule);
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

  Future<void> _mutate(Future<List<ReminderRule>> Function() operation) async {
    state = state.copyWith(saving: true, clearError: true);
    try {
      final rules = await operation();
      state = state.copyWith(rules: rules, saving: false);
      await replan();
    } on Object catch (error) {
      state = state.copyWith(saving: false, error: error);
      rethrow;
    }
  }
}
