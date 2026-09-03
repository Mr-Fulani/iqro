import 'dart:async';

/// Immutable identity used to bind local reads, writes and remote requests to
/// the account that started them.
class AccountScopeSnapshot {
  const AccountScopeSnapshot({required this.userId, required this.epoch});

  final String userId;
  final int epoch;
}

class AccountScopeChanged implements Exception {
  const AccountScopeChanged();

  @override
  String toString() => 'The active account changed while the operation ran';
}

typedef AccountScopeLoader = Future<void> Function();
typedef AccountDataTransfer =
    Future<void> Function(String sourceOwnerId, String targetOwnerId);

/// Process-wide account boundary.
///
/// The monotonically increasing epoch prevents an asynchronous response that
/// started under account A from being applied after a switch to account B.
class AccountScope {
  AccountScope();

  factory AccountScope.forTesting([String userId = 'test-owner']) {
    final scope = AccountScope();
    scope.activate(userId);
    return scope;
  }

  String? _userId;
  int _epoch = 0;
  AccountScopeLoader? _loader;
  AccountDataTransfer? _transfer;
  AccountDataTransfer? _finalizeTransfer;
  Future<void>? _loadFlight;
  Completer<void>? _transition;
  final StreamController<AccountScopeSnapshot?> _changes =
      StreamController<AccountScopeSnapshot?>.broadcast(sync: true);

  AccountScopeSnapshot? get current {
    final userId = _userId;
    return userId == null
        ? null
        : AccountScopeSnapshot(userId: userId, epoch: _epoch);
  }

  int get epoch => _epoch;
  Stream<AccountScopeSnapshot?> get changes => _changes.stream;

  void configure({
    AccountScopeLoader? loader,
    AccountDataTransfer? transfer,
    AccountDataTransfer? finalizeTransfer,
  }) {
    _loader = loader ?? _loader;
    _transfer = transfer ?? _transfer;
    _finalizeTransfer = finalizeTransfer ?? _finalizeTransfer;
  }

  Future<AccountScopeSnapshot> capture() async {
    final transition = _transition;
    if (transition != null) await transition.future;
    final ready = current;
    if (ready != null) return ready;
    final loader = _loader;
    if (loader == null) {
      throw const AccountScopeChanged();
    }
    final activeFlight = _loadFlight;
    if (activeFlight != null) {
      await activeFlight;
    } else {
      late final Future<void> flight;
      flight = loader().whenComplete(() {
        if (identical(_loadFlight, flight)) _loadFlight = null;
      });
      _loadFlight = flight;
      await flight;
    }
    return current ?? (throw const AccountScopeChanged());
  }

  bool isCurrent(AccountScopeSnapshot snapshot) =>
      snapshot.userId == _userId && snapshot.epoch == _epoch;

  void ensureCurrent(AccountScopeSnapshot snapshot) {
    if (!isCurrent(snapshot)) throw const AccountScopeChanged();
  }

  void activate(String userId) {
    final normalized = userId.trim();
    if (normalized.isEmpty) throw const FormatException('User ID is empty');
    if (_userId == normalized) return;
    _userId = normalized;
    _epoch++;
    _changes.add(current);
  }

  AccountScopeTransition beginTransition(AccountScopeSnapshot expected) {
    ensureCurrent(expected);
    if (_transition != null) throw StateError('Account transition is active');
    final transition = Completer<void>();
    _transition = transition;
    _userId = null;
    _epoch++;
    _changes.add(null);
    return AccountScopeTransition._(
      sourceUserId: expected.userId,
      transition: transition,
    );
  }

  void completeTransition(
    AccountScopeTransition token, {
    required String targetUserId,
  }) {
    if (!identical(_transition, token._transition)) {
      throw StateError('Account transition token is stale');
    }
    final normalized = targetUserId.trim();
    if (normalized.isEmpty) throw const FormatException('User ID is empty');
    _userId = normalized;
    _epoch++;
    _transition = null;
    _changes.add(current);
    token._transition.complete();
  }

  void rollbackTransition(AccountScopeTransition token) {
    if (!identical(_transition, token._transition)) return;
    _userId = token.sourceUserId;
    _epoch++;
    _transition = null;
    _changes.add(current);
    token._transition.complete();
  }

  void deactivate() {
    if (_userId == null) {
      // Still invalidate operations captured before a repeated logout.
      _epoch++;
      _changes.add(null);
      return;
    }
    _userId = null;
    _epoch++;
    _changes.add(null);
  }

  Future<void> transferConfirmedData(
    String sourceOwnerId,
    String targetOwnerId,
  ) async {
    final transfer = _transfer;
    if (transfer == null) {
      throw StateError('Account transfer storage is not configured');
    }
    await transfer(sourceOwnerId, targetOwnerId);
  }

  Future<void> finalizeConfirmedDataTransfer(
    String sourceOwnerId,
    String targetOwnerId,
  ) async {
    final finalize = _finalizeTransfer;
    if (finalize == null) {
      throw StateError('Account transfer finalizer is not configured');
    }
    await finalize(sourceOwnerId, targetOwnerId);
  }
}

class AccountScopeTransition {
  const AccountScopeTransition._({
    required this.sourceUserId,
    required Completer<void> transition,
  }) : _transition = transition;

  final String sourceUserId;
  final Completer<void> _transition;
}
