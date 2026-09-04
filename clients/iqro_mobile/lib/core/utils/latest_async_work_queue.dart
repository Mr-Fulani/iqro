typedef AsyncWork<T> = Future<void> Function(T value);
typedef AsyncWorkErrorHandler =
    void Function(Object error, StackTrace stackTrace);

/// Runs at most one asynchronous operation at a time and retains only the
/// newest value submitted while that operation is in flight.
///
/// This is useful for durable UI state such as a reading position: intermediate
/// values may be superseded, while the final value must still be processed.
class LatestAsyncWorkQueue<T> {
  LatestAsyncWorkQueue(this._worker, {AsyncWorkErrorHandler? onError})
    : _onError = onError;

  final AsyncWork<T> _worker;
  final AsyncWorkErrorHandler? _onError;

  T? _pending;
  bool _hasPending = false;
  bool _running = false;
  bool _accepting = true;
  Future<void> _idle = Future<void>.value();

  Future<void> get idle => _idle;

  void add(T value) {
    if (!_accepting) return;
    _pending = value;
    _hasPending = true;
    if (_running) return;
    _running = true;
    _idle = _drain();
  }

  void clearPending() {
    _pending = null;
    _hasPending = false;
  }

  void close({bool discardPending = true}) {
    _accepting = false;
    if (discardPending) clearPending();
  }

  Future<void> _drain() async {
    try {
      while (_hasPending) {
        final value = _pending as T;
        _pending = null;
        _hasPending = false;
        try {
          await _worker(value);
        } on Object catch (error, stackTrace) {
          _onError?.call(error, stackTrace);
        }
      }
    } finally {
      _running = false;
      if (_hasPending) {
        _running = true;
        _idle = _drain();
      }
    }
  }
}
