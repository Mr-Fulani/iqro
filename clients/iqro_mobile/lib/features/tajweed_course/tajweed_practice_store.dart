import '../../core/auth/account_scope.dart';
import '../../core/auth/auth_session.dart';
import '../../core/network/api_exception.dart';
import '../../core/storage/local_database.dart';
import 'tajweed_course_repository.dart';
import 'tajweed_practice.dart';

/// Keeps the practice in `app_state` under `tajweed.practice.<course>`:
/// `{"state": {...}, "pending": [...]}`.
class TajweedPracticeStore {
  TajweedPracticeStore(this._database);

  final LocalDatabase _database;

  // Writes are read-modify-write; a queue keeps a finished session and a
  // sync answer in order.
  Future<void> _queue = Future<void>.value();

  static String stateKey(String course) => 'tajweed.practice.$course';

  Future<TajweedPracticeLocal> read(
    String course, {
    AccountScopeSnapshot? accountScope,
  }) async => TajweedPracticeLocal.fromJson(
    await _database.readState(stateKey(course), accountScope: accountScope),
  );

  /// Counts a finished session and keeps it until the account takes it.
  Future<TajweedPracticeLocal> record(
    String course,
    TajweedPracticeSession session,
  ) => _update(course, (current) => current.record(session));

  /// The account has taken session [id]: its [state] (null when the session
  /// was refused) replaces the local one, with the sessions still waiting
  /// counted on top.
  Future<TajweedPracticeLocal> settle(
    String course,
    String id,
    TajweedPracticeState? state, {
    AccountScopeSnapshot? accountScope,
  }) => _update(course, (current) {
    final waiting = [
      for (final session in current.pending)
        if (session.id != id) session,
    ];
    return TajweedPracticeLocal(
      state: state == null ? current.state : _counted(state, waiting),
      pending: waiting,
    );
  }, accountScope: accountScope);

  /// The account's state, which other devices may have moved on; sessions
  /// finished while it was on its way are counted on top.
  Future<TajweedPracticeLocal> replaceState(
    String course,
    TajweedPracticeState state, {
    AccountScopeSnapshot? accountScope,
  }) => _update(
    course,
    (current) => TajweedPracticeLocal(
      state: _counted(state, current.pending),
      pending: current.pending,
    ),
    accountScope: accountScope,
  );

  static TajweedPracticeState _counted(
    TajweedPracticeState state,
    List<TajweedPracticeSession> sessions,
  ) => sessions.fold(state, (state, session) => state.apply(session));

  Future<TajweedPracticeLocal> _update(
    String course,
    TajweedPracticeLocal Function(TajweedPracticeLocal current) change, {
    AccountScopeSnapshot? accountScope,
  }) {
    final result = _queue.then((_) async {
      final scope = accountScope ?? await _database.captureAccount();
      final next = change(await read(course, accountScope: scope));
      await _database.writeState(
        stateKey(course),
        next.toJson(),
        accountScope: scope,
      );
      return next;
    });
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}

/// Sends unsent sessions to the account one by one, oldest first, and keeps
/// the account's state from the answer; with nothing to send, takes the
/// account's state.
///
/// Only with a session (a guest has one too) that is not pending deletion.
/// Failures are silent: offline the sessions wait for the next time.
class TajweedPracticeSync {
  TajweedPracticeSync({
    required TajweedCourseRemoteGateway remote,
    required TajweedPracticeStore store,
    required LocalDatabase database,
    required AuthSession? Function() session,
    void Function(String course)? onChanged,
  }) : _remote = remote,
       _store = store,
       _database = database,
       _session = session,
       _onChanged = onChanged;

  final TajweedCourseRemoteGateway _remote;
  final TajweedPracticeStore _store;
  final LocalDatabase _database;
  final AuthSession? Function() _session;

  /// Lets the screens that show the practice read it again.
  final void Function(String course)? _onChanged;

  /// The local copy after the sync, or null when nothing was synchronized.
  Future<TajweedPracticeLocal?> sync(String course) async {
    final session = _session();
    if (session == null || session.isPendingDeletion) return null;
    try {
      final scope = await _database.captureAccount();
      if (scope.userId != session.userId) return null;
      final local = await _store.read(course, accountScope: scope);
      if (local.pending.isEmpty) {
        final state = TajweedPracticeState.tryParse(
          await _remote.practiceState(course, accountScope: scope),
        );
        if (state == null) return null;
        final result = await _store.replaceState(
          course,
          state,
          accountScope: scope,
        );
        _onChanged?.call(course);
        return result;
      }
      TajweedPracticeLocal? result;
      for (final sent in local.pending) {
        TajweedPracticeState? state;
        try {
          state = TajweedPracticeState.tryParse(
            await _remote.savePracticeSession(
              sent.toJson(),
              accountScope: scope,
            ),
          );
        } on ApiException catch (error) {
          // The account holds this session with other answers: it cannot
          // be sent again.
          if (error.statusCode != 409) rethrow;
        }
        result = await _store.settle(
          course,
          sent.id,
          state,
          accountScope: scope,
        );
        _onChanged?.call(course);
      }
      return result;
    } on Object {
      return null;
    }
  }
}
