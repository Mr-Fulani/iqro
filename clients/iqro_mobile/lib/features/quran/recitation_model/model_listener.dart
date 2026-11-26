import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, IOSink, Platform;
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

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

/// A build for finding a fault (--dart-define=RECITATION_KEEP_SOUND=true)
/// keeps what the microphone gave since it was last turned on, and what
/// the follower made of it, in the app's own folder on the phone
/// (recitation.pcm, recitation.txt). No other build writes sound anywhere.
const _keepSound = bool.fromEnvironment('RECITATION_KEEP_SOUND');

void _log(String message) {
  // No word the reader says is written, only that the listener went on
  // or off and why it could not.
  if (kDebugMode) debugPrint('IQRO recitation model $message');
}

/// Listens with a model on the phone instead of the phone's speech
/// recognition (Android): the sound stays on the phone and no network is
/// needed. The same line under the text as [RecitationListener], but it
/// says where the place is itself. The model and its memory live only
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

  /// The place is this word of [words]; red when it was left out or
  /// read wrongly.
  final void Function(int word, bool wrong) onPlace;

  /// Why the word waited on in red is waited on; null while none is.
  final hint = ValueNotifier<RecitationWhy?>(null);

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
  IOSink? _keptSound;
  IOSink? _keptNotes;

  /// Sounds the model heard in the last seconds, whatever they were.
  var _sounds = 0;
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
        case (int word, bool wrong, int why, String expected, String heard):
          if (_disposed) return;
          hint.value = wrong
              ? (why: FollowWhy.values[why], expected: expected, heard: heard)
              : null;
          _lastPlace = _clock.elapsedMilliseconds;
          _keptNotes?.writeln(
            '$_lastPlace ms: word $word${wrong ? ' wrong, '
                      '${FollowWhy.values[why].name}, written "$expected", '
                      'heard "$heard"' : ''}',
          );
          ear.value = (heard: words[word], deaf: false, trouble: null);
          onPlace(word, wrong);
        case int sounds:
          _sounds = sounds;
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
    if (_keepSound) {
      final folder = await getExternalStorageDirectory();
      if (folder != null) {
        _keptSound = File('${folder.path}/recitation.pcm').openWrite();
        _keptNotes = File('${folder.path}/recitation.txt').openWrite()
          ..writeln(
            'surah $surah, ayahs ${ayahs.first.$1}-${ayahs.last.$1}, '
            'from word $from; 16000 Hz, 16 bit, mono',
          );
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
        _keptSound?.add(chunk);
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
      final now = modelEar(
        heard: ear.value.heard,
        sinceMs: _clock.elapsedMilliseconds - _lastPlace,
        sounds: _sounds,
      );
      if (now != ear.value) ear.value = now;
    });
    return true;
  }

  /// Reading starts from this word.
  void moveTo(int word) {
    hint.value = null;
    _keptNotes?.writeln(
      '${_clock.elapsedMilliseconds} ms: moved to word $word',
    );
    _toWorker?.send(word);
  }

  /// Turns the microphone off and lets the model's memory go.
  @override
  Future<void> stop() async {
    _log('off');
    _watch?.cancel();
    await _sound?.cancel();
    _sound = null;
    await _keptSound?.close();
    await _keptNotes?.close();
    _keptSound = null;
    _keptNotes = null;
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
    hint.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Why a word is waited on in red, for the line under the text: with
/// [FollowWhy.another], the sound written and the sound heard, as the
/// model writes them (a letter, or a short vowel's mark).
typedef RecitationWhy = ({FollowWhy why, String expected, String heard});

/// Sounds in eight seconds that are a reader reading: fewer are a room's
/// noise or a word now and then.
const recitationSpokenSounds = 8;

/// The line under the text when the model listens. With no word taken for
/// [recitationDeafAfter]: the reader is not heard, if the model hears
/// next to no sounds; else the reader is heard and what is said is not
/// the word waited on, which is not to be called a quiet voice.
RecitationEar modelEar({
  required String heard,
  required int sinceMs,
  required int sounds,
}) {
  final stalled = sinceMs > recitationDeafAfter.inMilliseconds;
  final spoken = sounds >= recitationSpokenSounds;
  return (
    heard: heard,
    deaf: stalled && !spoken,
    trouble: stalled && spoken ? RecitationTrouble.unrecognised : null,
  );
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
  var steps = 0;
  var placed = 0;
  void step() {
    scheduled = false;
    if (!pipeline.due) return;
    for (final event in pipeline.step()) {
      String symbol(int sound) => sound > 0 ? symbols[sound - 1] : '';
      out.send((
        event.word,
        event.wrong,
        event.why.index,
        symbol(event.expected),
        symbol(event.heard),
      ));
      placed = pipeline.frames;
    }
    // Twice a second: whether the reader is heard since the last word
    // taken. (One who has read to the end and is silent is not told that
    // a word was not recognised.)
    steps += 1;
    if (steps % 5 == 0) out.send(pipeline.soundsSince(placed));
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
