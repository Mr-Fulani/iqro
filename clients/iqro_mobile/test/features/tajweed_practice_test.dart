import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/auth/auth_session.dart';
import 'package:iqro_mobile/core/network/api_exception.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/features/tajweed_course/tajweed_course_repository.dart';
import 'package:iqro_mobile/features/tajweed_course/tajweed_practice.dart';
import 'package:iqro_mobile/features/tajweed_course/tajweed_practice_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'tajweed_practice_test_data.dart';

const _key = 'find~112:4~izhar';

TajweedPracticeAnswer _answer(String key, bool correct, String at) {
  final [type, _, target] = key.split('~');
  return TajweedPracticeAnswer(
    key: key,
    target: target,
    type: TajweedPracticeTaskType.tryParse(type)!,
    correct: correct,
    at: at,
  );
}

TajweedPracticeSession _session(
  String id,
  String day,
  List<TajweedPracticeAnswer> answers, {
  String? finished,
}) => TajweedPracticeSession(
  id: id,
  course: 'tajweed',
  localDate: day,
  finishedAt: finished ?? '${day}T12:00:00.000Z',
  answers: answers,
);

void main() {
  // The same cases as the backend's tests/test_tajweed_practice.py and the
  // site's lib/tajweed-practice.test.ts: one algorithm in three places.
  group('state', () {
    test('score counts right answers and the streak counts days in a row', () {
      var state = const TajweedPracticeState()
          .apply(
            _session('a', '2026-10-20', [
              _answer(_key, true, '2026-10-20T10:00:00Z'),
            ]),
          )
          .apply(
            _session('b', '2026-10-20', [
              _answer(_key, false, '2026-10-20T11:00:00Z'),
            ]),
          )
          .apply(_session('c', '2026-10-21', []));
      expect(
        [state.answers, state.correct, state.streak, state.bestStreak],
        [2, 1, 2, 2],
      );
      state = state.apply(_session('d', '2026-10-25', []));
      expect((state.streak, state.bestStreak), (1, 2));
      expect(state.score, 1);
      expect(state.sessions, 4);
      expect(state.toJson()['streak'], <String, Object?>{
        'current': 1,
        'best': 2,
        'last_date': '2026-10-25',
      });
    });

    test('a mistake comes back after one then three days until learned', () {
      var state = const TajweedPracticeState().apply(
        _session('a', '2026-10-20', [
          _answer(_key, false, '2026-10-20T10:00:00Z'),
        ]),
      );
      expect(
        [for (final item in state.review) item.toJson()],
        [
          <String, Object?>{
            'key': _key,
            'target': 'izhar',
            'type': 'find',
            'box': 1,
            'due_at': '2026-10-20T10:00:00.000Z',
          },
        ],
      );
      state = state.apply(
        _session('b', '2026-10-20', [
          _answer(_key, true, '2026-10-20T11:00:00Z'),
        ]),
      );
      expect(
        (state.review.single.box, state.review.single.dueAt),
        (2, '2026-10-21T11:00:00.000Z'),
      );
      state = state.apply(
        _session('c', '2026-10-21', [
          // Another time zone is the same moment.
          _answer(_key, true, '2026-10-21T14:00:00+03:00'),
        ]),
      );
      expect(
        (state.review.single.box, state.review.single.dueAt),
        (3, '2026-10-24T11:00:00.000Z'),
      );
      state = state.apply(
        _session('d', '2026-10-24', [
          _answer(_key, true, '2026-10-24T11:00:00Z'),
        ]),
      );
      expect(state.review, isEmpty);
      // A right answer to a task that was never missed changes nothing.
      state = state.apply(
        _session('e', '2026-10-24', [
          _answer(_key, true, '2026-10-24T12:00:00Z'),
        ]),
      );
      expect(state.review, isEmpty);
    });

    test('the state does not depend on the order sessions arrive in', () {
      // The backend applies the stored sessions by finished_at, then id.
      TajweedPracticeState from(List<TajweedPracticeSession> sessions) =>
          ([...sessions]..sort(
                (a, b) => a.finishedAt == b.finishedAt
                    ? a.id.compareTo(b.id)
                    : a.finishedAt.compareTo(b.finishedAt),
              ))
              .fold(
                const TajweedPracticeState(),
                (state, session) => state.apply(session),
              );
      final sessions = [
        _session('b', '2026-10-21', [
          _answer(_key, true, '2026-10-21T10:00:00Z'),
        ]),
        _session('a', '2026-10-20', [
          _answer(_key, false, '2026-10-20T10:00:00Z'),
        ]),
      ];
      expect(
        from(sessions).toJson(),
        from(sessions.reversed.toList()).toJson(),
      );
      expect(from(sessions).review.single.box, 2);
    });

    test('task keys', () {
      expect(
        tajweedPracticeKey(
          TajweedPracticeTaskType.listen,
          '1:7',
          'izhar_shafawi',
        ),
        'listen~1:7~izhar_shafawi',
      );
      expect(TajweedPracticeTaskType.tryParse('guess'), isNull);
    });

    test('due review keys come oldest first; the streak breaks after a '
        'missed day', () {
      final state = const TajweedPracticeState().apply(
        _session('a', '2026-10-20', [
          _answer(
            'identify~2:2~idgham_wo_ghunnah',
            false,
            '2026-10-20T10:05:00Z',
          ),
          _answer(_key, false, '2026-10-20T10:01:00Z'),
        ]),
      );
      expect(state.dueReviewKeys(DateTime.utc(2026, 10, 20, 10, 3)), [_key]);
      expect(state.dueReviewKeys(DateTime.utc(2026, 10, 21)), [
        _key,
        'identify~2:2~idgham_wo_ghunnah',
      ]);
      expect(state.dueReviewKeys(DateTime.utc(2026, 10, 21), limit: 1), [_key]);
      expect(state.shownStreak('2026-10-20'), 1);
      expect(state.shownStreak('2026-10-21'), 1);
      expect(state.shownStreak('2026-10-22'), 0);
      expect(const TajweedPracticeState().shownStreak('2026-10-22'), 0);
      expect(tajweedLocalDate(DateTime(2026, 10, 5, 23, 30)), '2026-10-05');
      // Across a month and a year.
      expect(
        const TajweedPracticeState()
            .apply(_session('a', '2025-12-31', []))
            .apply(_session('b', '2026-01-01', []))
            .streak,
        2,
      );
    });

    test('a finished session counts at once and waits to be sent', () {
      final first = const TajweedPracticeLocal().record(
        _session('a', '2026-10-20', [
          _answer(_key, true, '2026-10-20T10:00:00Z'),
        ]),
      );
      expect(first.state.score, 1);
      expect(first.pending.map((session) => session.id), ['a']);
      final stored = TajweedPracticeLocal.fromJson(first.toJson());
      expect(stored.toJson(), first.toJson());
      var local = stored;
      for (var index = 0; index < tajweedPracticePending + 5; index++) {
        local = local.record(_session('s$index', '2026-10-21', []));
      }
      expect(local.pending, hasLength(tajweedPracticePending));
      expect(local.pending.first.id, 's5');
      expect(
        TajweedPracticeLocal.fromJson(null).toJson(),
        const TajweedPracticeLocal().toJson(),
      );
      expect(
        TajweedPracticeState.tryParse(<String, Object?>{'score': 1}),
        isNull,
      );
      // A session with an answer that does not fit is dropped.
      final broken = TajweedPracticeLocal.fromJson(<String, Object?>{
        'state': first.state.toJson(),
        'pending': [
          first.pending.single.toJson(),
          <String, Object?>{
            ...first.pending.single.toJson(),
            'answers': [
              <String, Object?>{'key': _key},
            ],
          },
        ],
      });
      expect(broken.pending, hasLength(1));
      expect(broken.state.score, 1);
    });

    test('tasks that do not fit the contract are dropped', () {
      final example = tajweedPracticeTaskJson(
        'find',
        'izhar',
        '80:18',
        'izhar',
      )['example'];
      final tasks = parseTajweedPracticeTasks(<String, Object?>{
        'seed': 1,
        'tasks': [
          <String, Object?>{
            'key': 'find~80:18~izhar',
            'type': 'find',
            'target': 'izhar',
            'review': true,
            'example': example,
            'focus': 0,
          },
          <String, Object?>{
            'key': 'identify~80:18~izhar',
            'type': 'identify',
            'target': 'izhar',
            'review': false,
            'example': example,
            'focus': 1,
            'options': ['idgham_ghunnah', 'izhar', 7],
          },
          // The right target is not among the options.
          <String, Object?>{
            'key': 'identify~80:18~izhar',
            'type': 'identify',
            'target': 'izhar',
            'example': example,
            'focus': 0,
            'options': ['idgham_ghunnah'],
          },
          // There is no third place.
          <String, Object?>{
            'key': 'listen~80:18~izhar',
            'type': 'listen',
            'target': 'izhar',
            'example': example,
            'focus': 2,
            'options': ['izhar'],
          },
          <String, Object?>{
            'key': 'guess~80:18~izhar',
            'type': 'guess',
            'target': 'izhar',
            'example': example,
            'focus': 0,
          },
          'not a task',
        ],
      });
      expect(
        [
          for (final task in tasks)
            (task.type, task.review, task.focus, task.options.join(',')),
        ],
        [
          (TajweedPracticeTaskType.find, true, 0, ''),
          (TajweedPracticeTaskType.identify, false, 1, 'idgham_ghunnah,izhar'),
        ],
      );
      expect(tasks[1].focusOccurrence.positions, [3, 4]);
      expect(parseTajweedPracticeTasks(null), isEmpty);
    });
  });

  group('store, repository and sync', () {
    late Database sqlDatabase;
    late LocalDatabase database;
    late TajweedPracticeStore store;
    late _FakeRemote remote;

    setUpAll(sqfliteFfiInit);

    setUp(() async {
      sqlDatabase = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await sqlDatabase.execute('''
        CREATE TABLE app_state (
          owner_id TEXT NOT NULL,
          state_key TEXT NOT NULL,
          payload TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          PRIMARY KEY (owner_id, state_key)
        )
      ''');
      database = LocalDatabase.forTesting(sqlDatabase);
      store = TajweedPracticeStore(database);
      remote = _FakeRemote();
    });

    tearDown(() => sqlDatabase.close());

    TajweedPracticeSync sync([AuthSession? Function()? session]) =>
        TajweedPracticeSync(
          remote: remote,
          store: store,
          database: database,
          session: session ?? () => _authSession('test-owner'),
        );

    test('keeps the state and the unsent sessions in app_state', () async {
      final session = _session('a', '2026-10-22', [
        _answer(_key, false, '2026-10-22T10:01:00.000Z'),
      ]);
      await store.record('tajweed', session);
      expect(await database.readState('tajweed.practice.tajweed'), {
        'state': {
          'sessions': 1,
          'answers': 1,
          'correct': 0,
          'score': 0,
          'streak': {'current': 1, 'best': 1, 'last_date': '2026-10-22'},
          'review': [
            {
              'key': _key,
              'target': 'izhar',
              'type': 'find',
              'box': 1,
              'due_at': '2026-10-22T10:01:00.000Z',
            },
          ],
        },
        'pending': [session.toJson()],
      });
      expect((await store.read('other')).pending, isEmpty);
    });

    test('asks for tasks of the passed lessons with the review keys', () async {
      final repository = TajweedCourseRepository(
        remote: remote,
        database: database,
      );
      final tasks = await repository.practice(
        'tajweed',
        lessons: ['izhar', 'idgham-ghunnah'],
        seed: 42,
        review: ['find~80:18~izhar'],
      );
      expect(remote.requests, [
        'practice tajweed izhar,idgham-ghunnah 8 42 find~80:18~izhar',
      ]);
      expect(tasks.map((task) => task.key), [
        'find~80:18~izhar',
        'identify~80:13~idgham_ghunnah',
        'listen~96:14~ikhafa_shafawi',
      ]);
      expect(tasks.first.review, isTrue);
    });

    test('sends unsent sessions oldest first and keeps the answer', () async {
      // Another device already sent a session to the account.
      remote.stored['other'] = _session('other', '2026-10-21', [
        _answer(_key, true, '2026-10-21T09:00:00.000Z'),
      ], finished: '2026-10-21T09:05:00.000Z');
      final first = _session('a', '2026-10-22', [
        _answer(_key, false, '2026-10-22T10:01:00.000Z'),
      ], finished: '2026-10-22T10:05:00.000Z');
      final second = _session('b', '2026-10-22', [
        _answer(_key, true, '2026-10-22T11:01:00.000Z'),
      ], finished: '2026-10-22T11:05:00.000Z');
      await store.record('tajweed', first);
      await store.record('tajweed', second);
      final changed = <String>[];
      final result = await TajweedPracticeSync(
        remote: remote,
        store: store,
        database: database,
        session: () => _authSession('test-owner'),
        onChanged: changed.add,
      ).sync('tajweed');

      expect(remote.requests, ['save a', 'save b']);
      expect(remote.scopes.toSet().single?.userId, 'test-owner');
      expect(result?.pending, isEmpty);
      final local = await store.read('tajweed');
      expect(local.pending, isEmpty);
      // The account's state counts the other device's session too.
      expect(local.state.toJson(), remote.state().toJson());
      expect(local.state.sessions, 3);
      expect((local.state.streak, local.state.score), (2, 2));
      expect(local.state.review.single.box, 2);
      expect(changed, ['tajweed', 'tajweed']);
    });

    test('a conflict drops the session; offline the rest waits', () async {
      final conflicting = _session('a', '2026-10-22', [
        _answer(_key, false, '2026-10-22T10:01:00.000Z'),
      ]);
      remote.stored['a'] = _session('a', '2026-10-22', [
        _answer(_key, true, '2026-10-22T10:01:00.000Z'),
      ]);
      await store.record('tajweed', conflicting);
      await store.record('tajweed', _session('b', '2026-10-23', []));
      remote.offlineAfter = 1;
      expect(await sync().sync('tajweed'), isNull);
      expect(remote.requests, ['save a', 'save b']);
      var local = await store.read('tajweed');
      expect(local.pending.map((session) => session.id), ['b']);
      // The refused session still counts locally until the account's state
      // comes.
      expect(local.state.sessions, 2);

      remote.offlineAfter = null;
      await sync().sync('tajweed');
      local = await store.read('tajweed');
      expect(local.pending, isEmpty);
      expect(local.state.toJson(), remote.state().toJson());
      expect(local.state.score, 1);
    });

    test(
      'with nothing to send the account state replaces the local one',
      () async {
        remote.stored['x'] = _session('x', '2026-10-21', [
          _answer(_key, false, '2026-10-21T09:00:00.000Z'),
        ]);
        final result = await sync().sync('tajweed');
        expect(remote.requests, ['state tajweed']);
        expect(result?.state.toJson(), remote.state().toJson());
        expect((await store.read('tajweed')).state.review.single.key, _key);
      },
    );

    test('only with a session that is not pending deletion', () async {
      await store.record('tajweed', _session('a', '2026-10-22', []));
      AuthSession? session;
      final guarded = sync(() => session);
      expect(await guarded.sync('tajweed'), isNull);
      session = _authSession('test-owner', status: 'pending_deletion');
      expect(await guarded.sync('tajweed'), isNull);
      session = _authSession('someone-else');
      expect(await guarded.sync('tajweed'), isNull);
      expect(remote.requests, isEmpty);
      // A guest has a session too.
      session = _authSession('test-owner', status: 'guest');
      expect(await guarded.sync('tajweed'), isNotNull);
      expect(remote.requests, ['save a']);
    });
  });
}

AuthSession _authSession(String userId, {String status = 'active'}) =>
    AuthSession(
      accessToken: 'a',
      refreshToken: 'r',
      accessExpiresAt: DateTime.utc(2030),
      refreshExpiresAt: DateTime.utc(2030),
      bootstrapGeneration: 1,
      userId: userId,
      userStatus: status,
      deviceId: 'device',
      email: status == 'guest' ? null : 'learner@example.com',
    );

/// The backend's practice endpoints: sessions stored once by id, the state
/// recomputed from all of them by `finished_at`, then id.
class _FakeRemote implements TajweedCourseRemoteGateway {
  final requests = <String>[];
  final scopes = <AccountScopeSnapshot?>[];
  final stored = <String, TajweedPracticeSession>{};

  /// Requests that pass before the network goes away.
  int? offlineAfter;

  void _check() {
    final left = offlineAfter;
    if (left == null) return;
    if (left <= 0) throw const ApiException(message: 'offline');
    offlineAfter = left - 1;
  }

  TajweedPracticeState state() =>
      (stored.values.toList()..sort(
            (a, b) => a.finishedAt == b.finishedAt
                ? a.id.compareTo(b.id)
                : a.finishedAt.compareTo(b.finishedAt),
          ))
          .fold(
            const TajweedPracticeState(),
            (state, session) => state.apply(session),
          );

  Map<String, Object?> _answer() => <String, Object?>{
    'course': 'tajweed',
    ...state().toJson(),
  };

  @override
  Future<Object?> practice(
    String slug, {
    required List<String> lessons,
    required int count,
    required int seed,
    required List<String> review,
  }) async {
    requests.add(
      'practice $slug ${lessons.join(',')} $count $seed ${review.join(',')}',
    );
    return tajweedPracticeTasksJson();
  }

  @override
  Future<Object?> savePracticeSession(
    Map<String, Object?> body, {
    AccountScopeSnapshot? accountScope,
  }) async {
    requests.add('save ${body['id']}');
    scopes.add(accountScope);
    _check();
    final session = TajweedPracticeSession.tryParse(body)!;
    final existing = stored[session.id];
    if (existing != null && existing.toJson().toString() != body.toString()) {
      throw const ApiException(message: 'conflict', statusCode: 409);
    }
    stored[session.id] = session;
    return _answer();
  }

  @override
  Future<Object?> practiceState(
    String course, {
    AccountScopeSnapshot? accountScope,
  }) async {
    requests.add('state $course');
    scopes.add(accountScope);
    _check();
    return _answer();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
