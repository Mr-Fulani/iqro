import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../recitation_follow.dart';
import 'follow_core.dart';
import 'model_session.dart';
import 'pipeline.dart';

/// The trial of following a reader with a model on the phone
/// (docs/recitation-on-device-spike): only in a build made with
/// `--dart-define=RECITATION_MODEL=true`, which also carries the model.
const recitationModelBuild = bool.fromEnvironment('RECITATION_MODEL');

const _assets = 'assets/recitation_model';
const _mic = EventChannel('forum.iqro.app/recitation_mic');

void _log(String message) {
  // The trial build's measurements are read from the phone's log; no
  // word the reader says is written, only places and times.
  // ignore: avoid_print
  print('IQRO model $message');
}

/// What the trial says of a word read: [kind] 0 ghunnah, 1 idgham with
/// ghunnah, 2 madd muttasil held too short; 3 a sound that was not the
/// text's, the model's class [heard] (0: nothing) for [expected].
typedef ModelNote = ({int word, int kind, int expected, int heard});

/// Listens with the model instead of the phone's speech recognition: the
/// same switch and line under the text as [RecitationListener], but it
/// says where the lens goes itself.
class ModelRecitationListener implements RecitationListener {
  ModelRecitationListener({
    required this.surah,
    required this.ayahs,
    required this.words,
    required this.start_,
    required this.onPlace,
    required this.onNote,
    this.dump = false,
  });

  final int surah;

  /// The ayahs on screen and how many words the screen has in each.
  final List<(int number, int words)> ayahs;

  /// Their words, for the line under the text.
  final List<String> words;
  final int start_;

  /// The lens goes to this word of [words]; red when it was left out.
  final void Function(int word, bool wrong) onPlace;
  final ValueChanged<ModelNote> onNote;

  /// Keeps the microphone's sound in a file of the app, for measuring.
  final bool dump;

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
  StreamSubscription<Object?>? _sound;
  IOSink? _dump;
  final _clock = Stopwatch();
  final _arrived = <(int samples, int ms)>[];
  var _samples = 0;
  Timer? _watch;
  var _lastPlace = 0;

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
      _log('no model in this build: $error');
      return false;
    }
    final ready = Completer<bool>();
    _fromWorker.listen((message) {
      switch (message) {
        case SendPort port:
          _toWorker = port;
        case bool ok:
          if (!ready.isCompleted) ready.complete(ok);
        case (int word, bool wrong, double heard):
          _lastPlace = _clock.elapsedMilliseconds;
          _log(
            'place word=$word wrong=$wrong heard=${heard.toStringAsFixed(2)} '
            'after=${_since(heard)}ms',
          );
          ear.value = (heard: words[word], deaf: false, trouble: null);
          onPlace(word, wrong);
        case (int word, int kind, int expected, int heard):
          _log('note word=$word kind=$kind expected=$expected heard=$heard');
          onNote((word: word, kind: kind, expected: expected, heard: heard));
        case (double heard, int modelMs, int restMs):
          _log(
            'step heard=${heard.toStringAsFixed(2)} model=${modelMs}ms '
            'rest=${restMs}ms done=${_since(heard)}ms',
          );
        case String note:
          _log(note);
      }
    });
    _worker = await Isolate.spawn(_work, (
      _fromWorker.sendPort,
      TransferableTypedData.fromList(<Uint8List>[model.buffer.asUint8List()]),
      TransferableTypedData.fromList(<Uint8List>[filters.buffer.asUint8List()]),
      table,
      surah,
      ayahs,
      start_,
    ));
    if (!await ready.future) {
      _log('the model or this surah\'s table did not load');
      await stop();
      return false;
    }
    if (dump) {
      final folder = await getExternalStorageDirectory();
      if (folder != null) {
        _dump = File('${folder.path}/recitation.pcm').openWrite();
        _log('sound kept in ${folder.path}/recitation.pcm');
      }
    }
    final heard = Completer<bool>();
    _clock
      ..reset()
      ..start();
    _sound = _mic.receiveBroadcastStream().listen(
      (chunk) {
        if (chunk is! Uint8List) return;
        if (!heard.isCompleted) heard.complete(true);
        _samples += chunk.length ~/ 2;
        _arrived.add((_samples, _clock.elapsedMilliseconds));
        if (_arrived.length > 400) _arrived.removeRange(0, 200);
        _dump?.add(chunk);
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
    _log('on: surah $surah, ${words.length} words, from $start_');
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

  /// Milliseconds since the sound at [heard] seconds came from the
  /// microphone.
  int _since(double heard) {
    final samples = (heard * 16000).round();
    for (final (count, ms) in _arrived) {
      if (count >= samples) return _clock.elapsedMilliseconds - ms;
    }
    return 0;
  }

  /// Reading starts from this word.
  void moveTo(int word) => _toWorker?.send(word);

  @override
  Future<void> stop() async {
    _log('off');
    _watch?.cancel();
    await _sound?.cancel();
    _sound = null;
    await _dump?.close();
    _dump = null;
    _worker?.kill(priority: Isolate.immediate);
    _worker = null;
    _fromWorker.close();
  }

  @override
  void dispose() {
    _watch?.cancel();
    unawaited(_sound?.cancel());
    _worker?.kill(priority: Isolate.immediate);
    _fromWorker.close();
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
        ..send(
          'ayah $surah:$number: ${ayah?.spans.length} words in the table, '
          '$words on screen',
        )
        ..send(false);
      return;
    }
    expected.add(ayah);
  }
  final session = RecitationModelSession.open(
    model.materialize().asUint8List(),
    threads: const int.fromEnvironment('RECITATION_THREADS', defaultValue: 4),
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
    final events = pipeline.step();
    final timing = pipeline.lastTiming;
    if (timing == null) return;
    for (final event in events) {
      switch (event) {
        case ModelPlace(:final word, :final wrong):
          out.send((word, wrong, timing.heard));
        case ModelRemark(:final word, :final kind):
          out.send((word, kind, 0, 0));
        case ModelOtherwise(:final word, :final expected, :final heard):
          out.send((word, 3, expected, heard));
      }
    }
    out.send((timing.heard, timing.modelMs, timing.restMs));
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
    }
  });
  out
    ..send(port.sendPort)
    ..send(true);
}
