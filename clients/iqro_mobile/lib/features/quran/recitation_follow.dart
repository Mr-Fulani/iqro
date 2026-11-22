import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Why the recitation check cannot hear the reader.
enum RecitationTrouble {
  /// No way to the recognition service: it works over the network here.
  network,

  /// The phone's recognition has no Arabic.
  language,

  /// No recognition service, or the microphone is not allowed.
  unavailable,

  /// The reader is heard, and what is said is not taken for the word
  /// waited on: not a microphone that hears nothing.
  unrecognised,
}

/// What the line under the text shows while the microphone is on: the words
/// heard last; that none have come for a while; what is wrong.
typedef RecitationEar = ({String heard, bool deaf, RecitationTrouble? trouble});

/// How long the microphone may be on with no word heard before the reader
/// is told so.
const recitationDeafAfter = Duration(seconds: 8);

void _log(String message) {
  // What the reader says is not written to the phone's log.
  if (kDebugMode) debugPrint('IQRO recitation $message');
}

/// The phone's speech recognition, listening for Arabic until stopped: a
/// recogniser ends a listen after a pause or an error, so each one is
/// followed by the next. Where the phone can recognise speech by itself
/// (iOS, Android 12 and later) it is asked to, as that answers sooner than
/// the network; if it has no model for Arabic the first listen fails and
/// the rest go through the network.
class RecitationListener {
  RecitationListener({required this.onHeard});

  /// Gets the words of the current listen so far, as they grow.
  final ValueChanged<String> onHeard;

  final ear = ValueNotifier<RecitationEar>((
    heard: '',
    deaf: false,
    trouble: null,
  ));

  final _speech = SpeechToText();
  static RecitationListener? _current;

  /// The phone's own recognition is asked for, until it fails before it
  /// has heard a word; for as long as the app runs.
  static var _onDevice = false;
  static var _onDeviceHeard = false;
  var _active = false;
  String? _locale;
  Timer? _again;

  /// Starts a listen whenever none runs: a recogniser does not always say
  /// that it has stopped.
  Timer? _watch;

  /// False when the phone has no speech recognition, or the reader refused
  /// the microphone.
  Future<bool> start() async {
    // The package keeps the callbacks of its first start only: they pass
    // what it reports on to the listener of the moment.
    _current = this;
    final bool ready;
    try {
      ready = await _speech.initialize(
        onStatus: (status) => _current?._onStatus(status),
        onError: (error) => _current?._onError(error),
      );
    } on Object catch (error) {
      _log('failed to start: $error');
      return false;
    }
    if (!ready || !identical(_current, this)) return false;
    final locales = await _speech.locales();
    final arabic = locales
        .map((locale) => locale.localeId)
        .where((id) => id.toLowerCase().startsWith('ar'))
        .toList();
    _locale =
        arabic.where((id) => id.toUpperCase().endsWith('SA')).firstOrNull ??
        arabic.firstOrNull ??
        'ar-SA';
    if (!_onDeviceHeard) _onDevice = await _canAskOnDevice();
    if (!identical(_current, this)) return false;
    _active = true;
    _log(
      'on: $_locale of ${arabic.length} Arabic, '
      '${_onDevice ? 'on the phone' : 'by the phone\'s choice'}',
    );
    _watch = Timer.periodic(_beat, (_) => _check());
    await _listen();
    return true;
  }

  static Future<bool> _canAskOnDevice() async {
    if (Platform.isIOS) return true;
    if (!Platform.isAndroid) return false;
    return (await DeviceInfoPlugin().androidInfo).version.sdkInt >= 31;
  }

  Future<void> stop() async {
    _log('off');
    if (identical(_current, this)) _current = null;
    _active = false;
    _again?.cancel();
    _watch?.cancel();
    await _speech.stop();
  }

  void dispose() {
    if (identical(_current, this)) _current = null;
    _active = false;
    _again?.cancel();
    _watch?.cancel();
    unawaited(_speech.cancel());
    ear.dispose();
  }

  /// A listen runs, as far as the recogniser has said: the package's own
  /// flag stays set after an error.
  var _listening = false;
  var _starting = false;
  var _lastSign = DateTime.now();

  /// How long no word has been heard, since the last one or since the
  /// microphone was turned on.
  var _quiet = Duration.zero;
  static const _beat = Duration(seconds: 2);

  Future<void> _listen() async {
    if (!_active || _starting) return;
    _starting = true;
    const patience = Duration(seconds: 4);
    try {
      // Ends the listen before: the package keeps a timer of it.
      await _speech.cancel().timeout(patience);
      if (!_active) return;
      await _speech
          .listen(
            onResult: (result) {
              if (!_active) return;
              if (_onDevice) _onDeviceHeard = true;
              _lastSign = DateTime.now();
              final words = result.recognizedWords;
              _log('heard: $words');
              if (words.trim().isNotEmpty) {
                _quiet = Duration.zero;
                ear.value = (heard: words, deaf: false, trouble: null);
              }
              onHeard(words);
            },
            listenOptions: SpeechListenOptions(
              localeId: _locale,
              onDevice: _onDevice,
              partialResults: true,
              listenMode: ListenMode.dictation,
              // A reader stops for breath: the listen goes on through it,
              // or the first words after it are lost.
              pauseFor: const Duration(seconds: 60),
            ),
          )
          .timeout(patience);
      _log('listen started');
      _listening = true;
      _lastSign = DateTime.now();
    } on Object catch (error) {
      _log('listen failed: $error');
      if (_active) _trouble(RecitationTrouble.unavailable);
    } finally {
      _starting = false;
    }
  }

  /// Starts a listen when none runs, or when the one that should has been
  /// silent longer than a pause may last; and tells the reader when no
  /// word has been heard for a while.
  void _check() {
    if (!_active) return;
    final now = DateTime.now();
    _quiet += _beat;
    final deaf = _quiet >= recitationDeafAfter;
    if (deaf != ear.value.deaf) {
      ear.value = (
        heard: ear.value.heard,
        deaf: deaf,
        trouble: ear.value.trouble,
      );
    }
    if (_again?.isActive ?? false) return;
    if (_listening && now.difference(_lastSign) < const Duration(seconds: 70)) {
      return;
    }
    _listening = false;
    unawaited(_listen());
  }

  void _onStatus(String status) {
    if (!_active) return;
    _log('status: $status');
    // What ending the listen before reports.
    if (_starting) return;
    _lastSign = DateTime.now();
    if (status == SpeechToText.listeningStatus) {
      _listening = true;
      return;
    }
    _listening = false;
    _listenAgain();
  }

  void _onError(SpeechRecognitionError error) {
    if (!_active || _starting) return;
    final code = error.errorMsg;
    _log('error: $code');
    // Silence is not a fault: the next listen starts.
    final silence = code == 'error_no_match' || code == 'error_speech_timeout';
    if (!silence && _onDevice && !_onDeviceHeard) {
      // No model for Arabic on the phone: through the network from here.
      _onDevice = false;
    } else if (code.contains('network') || code.contains('server')) {
      _trouble(RecitationTrouble.network);
    } else if (code.contains('language')) {
      _trouble(RecitationTrouble.language);
    } else if (code.contains('permission') ||
        code.contains('audio') ||
        code.contains('not_available')) {
      _trouble(RecitationTrouble.unavailable);
    }
    _listening = false;
    _listenAgain();
  }

  void _trouble(RecitationTrouble trouble) {
    ear.value = (
      heard: ear.value.heard,
      deaf: ear.value.deaf,
      trouble: trouble,
    );
  }

  void _listenAgain() {
    if (!_active) return;
    _again?.cancel();
    _again = Timer(const Duration(milliseconds: 150), _listen);
  }
}

/// The gold of the microphone when its hint is up.
const recitationGold = Color(0xFFC49647);

/// How many words in a row that are not the one expected are a mistake
/// at once, and how long a single one waits for the recogniser's next
/// words to put it right before it is one too.
const recitationMissesAtOnce = 2;
const recitationMissPause = Duration(milliseconds: 1500);

/// The red of a word left out or said as another.
const recitationWrong = Color(0xFFC62828);

/// The plate under the word a reader is on: the app's gold, soft enough
/// for the letters on it to keep their own colours (those of a Mushaf
/// with tajweed too) and plain to see at a glance; and its edge.
const recitationPlate = Color(0x66E0B354);
const recitationPlateEdge = Color(0xFFC49647);

/// The plate under a word left out or said as another, and its edge.
const recitationWrongPlate = Color(0x38E53935);

/// When the hint by the microphone first comes, how long it stays and how
/// long it is away before it comes again.
const recitationHintDelay = Duration(seconds: 2);
const recitationHintTime = Duration(seconds: 5);
const recitationHintPause = Duration(seconds: 40);

/// The hint by the microphone: what it is for.
class RecitationHint extends StatelessWidget {
  const RecitationHint({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xFF392D20),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFFFFFCF7), fontSize: 13),
          ),
        ),
        const SizedBox(width: 6),
        const Icon(
          Icons.arrow_forward_rounded,
          size: 16,
          color: Color(0xFFFFFCF7),
        ),
      ],
    ),
  );
}

/// The microphone while its hint is up or while it listens: breathing,
/// with rings going out from it, so the hint is seen to be about this
/// button and a listening microphone is not taken for one that is off.
class RecitationMicPulse extends StatefulWidget {
  const RecitationMicPulse({
    required this.active,
    required this.color,
    required this.child,
    super.key,
  });

  final bool active;

  /// The colour of the rings.
  final Color color;
  final Widget child;

  @override
  State<RecitationMicPulse> createState() => _RecitationMicPulseState();
}

class _RecitationMicPulseState extends State<RecitationMicPulse>
    with SingleTickerProviderStateMixin {
  late final _beat = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didUpdateWidget(covariant RecitationMicPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    if (widget.active && !MediaQuery.disableAnimationsOf(context)) {
      unawaited(_beat.repeat());
    } else {
      _beat
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _beat,
    child: widget.child,
    builder: (context, child) {
      if (!widget.active) return child!;
      // Larger and back, once a beat.
      final swell = 1 - (2 * _beat.value - 1).abs();
      return CustomPaint(
        painter: _RingsPainter(_beat.value, widget.color),
        child: Transform.scale(scale: 1 + .18 * swell, child: child),
      );
    },
  );
}

class _RingsPainter extends CustomPainter {
  const _RingsPainter(this.beat, this.color);

  final double beat;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    // Two rings, half a beat apart, fading as they grow.
    for (final shift in const <double>[0, .5]) {
      final at = (beat + shift) % 1;
      canvas.drawCircle(
        center,
        14 + 16 * at,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: .8 * (1 - at)),
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter oldDelegate) =>
      oldDelegate.beat != beat || oldDelegate.color != color;
}
