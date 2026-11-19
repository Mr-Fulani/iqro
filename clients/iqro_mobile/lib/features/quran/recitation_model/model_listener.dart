import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../recitation_follow.dart';
import 'follow_core.dart';
import 'model_session.dart';
import 'pipeline.dart';

const _assets = 'assets/recitation_model';
const _mic = EventChannel('forum.iqro.app/recitation_mic');

/// Whether the recitation check listens with the model on the phone: on
/// Android. Elsewhere, and where the model cannot, the phone's speech
/// recognition does.
bool get recitationByModel => Platform.isAndroid;

/// The threads the model works on: a step is in time on a phone's four
/// fast cores (docs/recitation-on-device-spike).
const _threads = 4;

void _log(String message) {
  // No word the reader says is written, only that the listener went on
  // or off and why it could not.
  if (kDebugMode) debugPrint('IQRO recitation model $message');
}

/// Listens with a model on the phone instead of the phone's speech
/// recognition (Android): the sound stays on the phone and no network is
/// needed. The same line under the text as [RecitationListener], but it
/// says where the lens goes itself. The model and its memory live only
/// between [start] and [stop].
class ModelRecitationListener implements RecitationListener {
  ModelRecitationListener({
    required this.surah,
    required this.ayahs,
    required this.words,
    required this.from,
    required this.onPlace,
  });

  final int surah;

  /// The ayahs on screen and how many words the screen has in each.
  final List<(int number, int words)> ayahs;

  /// Their words, for the line under the text.
  final List<String> words;

  /// The word reading starts from.
  final int from;

  /// The lens goes to this word of [words]; red when it was left out or
  /// read wrongly.
  final void Function(int word, bool wrong) onPlace;

  @override
  ValueChanged<String> get onHeard => (_) {};

  @override
  final ear = ValueNotifier<RecitationEar>((
    heard: '',
    deaf: false,
    trouble: null,
  ));

  Isolate? _worker;
  SendPort? _toWorker;
  final _fromWorker = ReceivePort();
  final _closed = Completer<void>();
  StreamSubscription<Object?>? _sound;
  final _clock = Stopwatch();
  Timer? _watch;
  var _lastPlace = 0;
  var _disposed = false;

  /// False when this build has no model, the model does not load, the
  /// table of expected sounds does not have this surah's words as the
  /// screen has them, or the microphone gives no sound: the caller then
  /// listens with the phone's speech recognition.
  @override
  Future<bool> start() async {
    final ByteData model;
    final ByteData filters;
    final String table;
    try {
      model = await rootBundle.load('$_assets/model-int8.onnx');
      filters = await rootBundle.load('$_assets/mel_filters.bin');
      table = await rootBundle.loadString('$_assets/expected.json');
    } on Object catch (error) {
      _log('has no model: $error');
      return false;
    }
    final ready = Completer<bool>();
    _fromWorker.listen((message) {
      switch (message) {
        case SendPort port:
          _toWorker = port;
        case bool ok:
          if (!ready.isCompleted) ready.complete(ok);
        case (int word, bool wrong):
          if (_disposed) return;
          _lastPlace = _clock.elapsedMilliseconds;
          ear.value = (heard: words[word], deaf: false, trouble: null);
          onPlace(word, wrong);
        case String note:
          _log(note);
        case null:
          if (!_closed.isCompleted) _closed.complete();
      }
    });
    _worker = await Isolate.spawn(_work, (
      _fromWorker.sendPort,
      TransferableTypedData.fromList(<Uint8List>[model.buffer.asUint8List()]),
      TransferableTypedData.fromList(<Uint8List>[filters.buffer.asUint8List()]),
      table,
      surah,
      ayahs,
      from,
    ));
    if (!await ready.future) {
      _log('did not load, or the table differs from the screen');
      await stop();
      return false;
    }
    final heard = Completer<bool>();
    _clock
      ..reset()
      ..start();
    _sound = _mic.receiveBroadcastStream().listen(
      (chunk) {
        if (chunk is! Uint8List) return;
        if (!heard.isCompleted) heard.complete(true);
        _toWorker?.send(chunk);
      },
      onError: (Object error) {
        _log('microphone: $error');
        if (!heard.isCompleted) heard.complete(false);
      },
    );
    final on = await heard.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () => false,
    );
    if (!on) {
      await stop();
      return false;
    }
    _log('on');
    _lastPlace = 0;
    _watch = Timer.periodic(const Duration(seconds: 2), (_) {
      final deaf =
          _clock.elapsedMilliseconds - _lastPlace >
          recitationDeafAfter.inMilliseconds;
      if (deaf != ear.value.deaf) {
        ear.value = (heard: ear.value.heard, deaf: deaf, trouble: null);
      }
    });
    return true;
  }

  /// Reading starts from this word.
  void moveTo(int word) => _toWorker?.send(word);

  /// Turns the microphone off and lets the model's memory go.
  @override
  Future<void> stop() async {
    _log('off');
    _watch?.cancel();
    await _sound?.cancel();
    _sound = null;
    final worker = _worker;
    _worker = null;
    if (worker != null) {
      // The worker frees the model itself (its memory is not Dart's);
      // one that does not answer is stopped all the same.
      if (_toWorker case final port?) {
        port.send(null);
        await _closed.future.timeout(
          const Duration(seconds: 2),
          onTimeout: () {},
        );
      }
      worker.kill(priority: Isolate.immediate);
    }
    _fromWorker.close();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    ear.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The worker: the model and the follower, off the screen's thread.
void _work(
  (
    SendPort,
    TransferableTypedData,
    TransferableTypedData,
    String,
    int,
    List<(int, int)>,
    int,
  )
  job,
) {
  final (out, model, filters, tableText, surah, ayahs, start) = job;
  final table = jsonDecode(tableText) as Map<String, Object?>;
  final symbols = (table['symbols']! as List).cast<String>();
  final entries = (table['surahs']! as Map)['$surah'] as List?;
  final expected = <ExpectedAyah>[];
  for (final (number, words) in ayahs) {
    final ayah = entries == null || number > entries.length
        ? null
        : ExpectedAyah.fromJson(entries[number - 1], symbols);
    if (ayah == null || ayah.spans.length != words) {
      out
        ..send('ayah $surah:$number is not in the table as on screen')
        ..send(false);
      return;
    }
    expected.add(ayah);
  }
  final session = RecitationModelSession.open(
    model.materialize().asUint8List(),
    threads: _threads,
  );
  if (session == null) {
    out.send(false);
    return;
  }
  final pipeline = RecitationPipeline(
    session: session,
    melFilters: filters.materialize().asFloat32List(),
    ayahs: expected,
  )..moveTo(start);
  final port = ReceivePort();
  var scheduled = false;
  void step() {
    scheduled = false;
    if (!pipeline.due) return;
    for (final event in pipeline.step()) {
      out.send((event.word, event.wrong));
    }
  }

  port.listen((message) {
    switch (message) {
      case Uint8List chunk:
        // The channel's bytes may begin at an odd place in their buffer.
        pipeline.add(Uint8List.fromList(chunk).buffer.asInt16List());
        // After the chunks already waiting: a step takes all of them.
        if (!scheduled) {
          scheduled = true;
          Timer.run(step);
        }
      case int word:
        pipeline.moveTo(word);
      case null:
        // Turned off: the model's memory goes, then the worker.
        session.close();
        port.close();
        out.send(null);
    }
  });
  out
    ..send(port.sendPort)
    ..send(true);
}
