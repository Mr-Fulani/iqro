import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/auth/auth_session.dart';
import 'announcement_logic.dart';
import 'announcement_repository.dart';

final announcementRepositoryProvider = Provider<AnnouncementRepository>(
  (ref) => AnnouncementRepository(
    api: ref.watch(apiClientProvider),
    database: ref.watch(localDatabaseProvider),
  ),
);

/// One store for the bubble, the window and the feed, so a mark set in one
/// place is seen in the others at once.
final announcementsProvider =
    StateNotifierProvider<AnnouncementsController, AnnouncementsState>(
      (ref) => AnnouncementsController(
        // Read lazily: screens without the network stack still build.
        repository: () => ref.read(announcementRepositoryProvider),
        session: () => ref.read(sessionProvider).valueOrNull,
      ),
    );

/// The audience rule of the site: guests and signed-in people may get
/// different announcements.
bool announcementSignedIn(AuthSession? session) =>
    session?.userStatus == 'active';

class AnnouncementsState {
  const AnnouncementsState({
    required this.openedAt,
    this.active = const <Announcement>[],
    this.local = const AnnouncementLocalState(),
    this.shownThisSession = const <String>{},
    this.loaded = false,
  });

  /// When this visit began: the bubble's frequency is judged once per visit.
  final DateTime openedAt;
  final List<Announcement> active;
  final AnnouncementLocalState local;
  final Set<String> shownThisSession;
  final bool loaded;

  AnnouncementsState copyWith({
    DateTime? openedAt,
    List<Announcement>? active,
    AnnouncementLocalState? local,
    Set<String>? shownThisSession,
    bool? loaded,
  }) => AnnouncementsState(
    openedAt: openedAt ?? this.openedAt,
    active: active ?? this.active,
    local: local ?? this.local,
    shownThisSession: shownThisSession ?? this.shownThisSession,
    loaded: loaded ?? this.loaded,
  );

  List<Announcement> bubble({required bool signedIn}) => bubbleAnnouncements(
    forAudience(active, signedIn),
    local,
    openedAt,
    shownThisSession,
  );

  int unread({required bool signedIn}) => forAudience(
    active,
    signedIn,
  ).where((item) => !isFinished(item, local)).length;
}

class AnnouncementsController extends StateNotifier<AnnouncementsState> {
  AnnouncementsController({
    required AnnouncementRepository Function() repository,
    required AuthSession? Function() session,
    DateTime Function() clock = DateTime.now,
  }) : _repository = repository,
       _session = session,
       _clock = clock,
       super(AnnouncementsState(openedAt: clock()));

  /// Coming back after this long counts as a new visit, like reopening the
  /// site in a new tab.
  static const newVisitAfter = Duration(minutes: 30);

  final AnnouncementRepository Function() _repository;
  final AuthSession? Function() _session;
  final DateTime Function() _clock;
  Future<void>? _localLoad;
  String? _syncedUser;
  String? _locale;
  DateTime? _leftAt;

  Future<void> _ensureLocal() => _localLoad ??= _readLocal();

  Future<void> _readLocal() async {
    try {
      final stored = await _repository().loadState();
      if (mounted) state = state.copyWith(local: stored);
    } on Object {
      // Without storage the marks live until the app closes.
    }
  }

  void _update(
    AnnouncementLocalState Function(AnnouncementLocalState value) change,
  ) {
    final next = change(state.local);
    if (identical(next, state.local) || !mounted) return;
    state = state.copyWith(local: next);
    unawaited(
      // Started at once, so writes reach the database in the order made.
      Future<void>.sync(
        () => _repository().saveState(next),
      ).catchError((Object _) {}),
    );
  }

  void _track(Announcement item, String surface, String event) {
    try {
      _repository().track(item.id, surface, event, item.wave);
    } on Object {
      // Counters are best effort.
    }
  }

  /// Active announcements for this language; the last copy without the
  /// network.
  Future<void> load(String locale, {bool refresh = false}) async {
    final changed = _locale != locale;
    _locale = locale;
    await _ensureLocal();
    try {
      final result = await _repository().active(
        locale: locale,
        refresh: refresh || changed,
      );
      if (mounted && _locale == locale) {
        state = state.copyWith(active: result.items, loaded: true);
      }
    } on Object {
      if (mounted) state = state.copyWith(loaded: true);
    }
    await syncReceipts();
  }

  /// Marks of a signed-in person follow them between devices.
  Future<void> syncReceipts() async {
    final session = _session();
    if (session == null ||
        session.userId.isEmpty ||
        _syncedUser == session.userId) {
      return;
    }
    _syncedUser = session.userId;
    try {
      final receipts = await _repository().receipts();
      await _ensureLocal();
      _update((value) => mergeReceipts(value, receipts));
    } on Object {
      _syncedUser = null;
    }
  }

  void _sendReceipt(
    Announcement item, {
    bool read = false,
    bool dismissed = false,
  }) {
    if (_session() == null) return;
    try {
      unawaited(
        _repository()
            .sendReceipt(
              item.id,
              read: read,
              dismissed: dismissed,
              wave: item.wave,
            )
            .catchError((Object _) {}),
      );
    } on Object {
      // The outbox could not be reached; the mark stays on this device.
    }
  }

  /// The bubble came up with these: count the visit for the new ones.
  void recordShown(List<Announcement> items) {
    final session = state.shownThisSession;
    final fresh = items
        .where((item) => !session.contains(item.id))
        .toList(growable: false);
    if (fresh.isEmpty) return;
    final now = _clock();
    _update((value) => recordBubbleShown(value, fresh, now, session));
    state = state.copyWith(
      shownThisSession: <String>{...session, ...fresh.map((item) => item.id)},
    );
    for (final item in fresh) {
      countImpression(item, 'bubble');
    }
  }

  void countImpression(Announcement item, String surface) {
    final result = takeImpression(
      state.local,
      item.id,
      surface,
      _clock(),
      item.wave,
    );
    if (!result.fresh) return;
    _update((_) => result.state);
    _track(item, surface, 'impression');
  }

  Future<void> read(
    Announcement item,
    String surface, {
    bool opened = false,
  }) async {
    if (opened) _track(item, surface, 'open');
    await _ensureLocal();
    if (state.local.read[item.id] != null && isFinished(item, state.local)) {
      return;
    }
    _update((value) => markRead(value, item.id, _clock(), item.wave));
    _sendReceipt(item, read: true);
  }

  Future<void> click(Announcement item, String surface) {
    _track(item, surface, 'click');
    return read(item, surface);
  }

  Future<void> dismiss(Announcement item, String surface) async {
    _track(item, surface, 'dismiss');
    await _ensureLocal();
    _update((value) => markDismissed(value, item.id, _clock(), item.wave));
    _sendReceipt(item, dismissed: true);
  }

  /// The app went to the background: send the counters now.
  void left() {
    _leftAt = _clock();
    try {
      unawaited(_repository().flushEvents());
    } on Object {
      // Counters are best effort.
    }
  }

  /// The app is back. Returns true when this is a new visit: the bubble's
  /// frequency is judged again and the list should be refreshed.
  bool returned() {
    final leftAt = _leftAt;
    _leftAt = null;
    if (leftAt == null || _clock().difference(leftAt) < newVisitAfter) {
      return false;
    }
    state = state.copyWith(
      openedAt: _clock(),
      shownThisSession: const <String>{},
    );
    return true;
  }
}
