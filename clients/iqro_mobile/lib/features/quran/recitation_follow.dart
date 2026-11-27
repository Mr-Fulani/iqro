import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

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

  /// iOS: the microphone or speech recognition is not allowed to the app
  /// in the system's settings.
  denied,

  /// iOS: dictation is off, and Apple's recognition with it.
  dictation,

  /// iOS: the microphone gives no sound to listen to: another app or a
  /// call has it, or it is not there.
  microphone,

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
/// the rest go through the network. After an error the next listen waits
/// longer each time: a recogniser that fails at once (no network, Apple's
/// limit of requests) is not asked again and again.
class RecitationListener {
  RecitationListener({required this.onHeard});

  /// Gets the words of the current listen so far, as they grow.
  final ValueChanged<String> onHeard;

  final ear = ValueNotifier<RecitationEar>((
    heard: '',
    deaf: false,
    trouble: null,
  ));

  final _speech = recogniser();
  static RecitationListener? _current;

  /// The package's recogniser: one for the app. A test gives each listener
  /// a fresh one, so no test depends on another's start.
  @visibleForTesting
  static SpeechToText Function() recogniser = SpeechToText.new;

  /// The phone's own recognition is asked for, until it fails before it
  /// has heard a word; for as long as the app runs.
  static var _onDevice = false;
  static var _onDeviceHeard = false;

  /// Whether the phone can recognise speech by itself; a test answers for
  /// the phone.
  @visibleForTesting
  static Future<bool> Function() canAskOnDevice = _canAskOnDevice;

  /// As at a fresh start of the app, for the next test.
  @visibleForTesting
  static void resetForTesting() {
    _onDevice = false;
    _onDeviceHeard = false;
    canAskOnDevice = _canAskOnDevice;
    recogniser = SpeechToText.new;
  }

  static bool get _apple => defaultTargetPlatform == TargetPlatform.iOS;

  /// Errors in a row since the last word heard: the pause before the next
  /// listen grows with them.
  var _failures = 0;

  /// So many errors in a row on iOS are taken for the network: Apple's
  /// codes do not say that it is down.
  static const _failuresTold = 3;

  /// The pause before the next listen, by the errors in a row.
  static const _againAfter = <Duration>[
    Duration(milliseconds: 150),
    Duration(milliseconds: 150),
    Duration(seconds: 1),
    Duration(seconds: 3),
    Duration(seconds: 8),
    Duration(seconds: 20),
  ];

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
        onStatus: _routeStatus,
        onError: (error) => _current?._onError(error),
      );
    } on Object catch (error) {
      _log('failed to start: $error');
      return false;
    }
    if (!identical(_current, this)) return false;
    if (!ready) {
      // iOS: speech recognition or the microphone refused, at the system's
      // questions or since in its settings, which the reader is sent to.
      if (_apple && !await _allowed() && identical(_current, this)) {
        _trouble(RecitationTrouble.denied);
      }
      return false;
    }
    final locales = await _speech.locales();
    final arabic = locales
        .map((locale) => locale.localeId)
        .where((id) => id.toLowerCase().startsWith('ar'))
        .toList();
    _locale =
        arabic.where((id) => id.toUpperCase().endsWith('SA')).firstOrNull ??
        arabic.firstOrNull ??
        'ar-SA';
    if (!_onDeviceHeard) _onDevice = await canAskOnDevice();
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
                _failures = 0;
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
              // iOS keeps the phone still while it records unless told:
              // the buzz of a word read wrongly is to be felt.
              enableHapticFeedback: true,
            ),
          )
          .timeout(patience);
      _log('listen started');
      _listening = true;
      _lastSign = DateTime.now();
    } on ListenFailedException catch (error) {
      if (_onDevice && !_onDeviceHeard && _noArabicOnPhone(error)) {
        // iOS with no Arabic of the phone's own: speech_to_text 7.4.0 says
        // so, then listens all the same, through Apple's server (a request
        // keeps to the phone only where the phone can). This listen runs;
        // the next ones are asked of the network.
        _log('no Arabic on the phone: through the network');
        _onDevice = false;
        _listening = true;
        _lastSign = DateTime.now();
      } else {
        _listenFailed(error);
      }
    } on Object catch (error) {
      _listenFailed(error);
    } finally {
      _starting = false;
    }
  }

  static bool _noArabicOnPhone(ListenFailedException error) =>
      error.message?.contains('on device recognition is not supported') ??
      false;

  void _listenFailed(Object error) {
    _log('listen failed: $error');
    if (!_active) return;
    _trouble(RecitationTrouble.unavailable);
    _failures += 1;
    _listenAgain();
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
      // iOS asks for the microphone at the first listen, after speech
      // recognition; refused there or since in the settings, it gives
      // silence, which is said for what it is.
      if (deaf && _apple) unawaited(_tellIfDenied());
    }
    if (_again?.isActive ?? false) return;
    if (_listening && now.difference(_lastSign) < const Duration(seconds: 70)) {
      return;
    }
    _listening = false;
    unawaited(_listen());
  }

  /// The package's statuses go to the listener of the moment. A listen that
  /// says it has begun after the microphone was turned off (the app going
  /// to the background as it started) is ended.
  void _routeStatus(String status) {
    final current = _current;
    if (current != null) return current._onStatus(status);
    if (status == SpeechToText.listeningStatus) {
      _log('a listen begun after the microphone was off: ended');
      unawaited(_speech.cancel());
    }
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
    // iOS: Apple's recogniser can no longer be reached; without Arabic on
    // the phone it is reached over the network.
    if (status == 'unavailable') {
      _failures += 1;
      if (!_onDevice) _trouble(RecitationTrouble.network);
    }
    _listening = false;
    _listenAgain();
  }

  void _onError(SpeechRecognitionError error) {
    if (!_active || _starting) return;
    final code = error.errorMsg;
    _log('error: $code');
    // Silence is not a fault, nor a listen the app itself ended: the next
    // listen starts.
    final silence =
        code == 'error_no_match' ||
        code == 'error_speech_timeout' ||
        code == 'error_request_cancelled';
    // A recogniser that heard silence works: the pause starts over.
    _failures = silence ? 0 : _failures + 1;
    final trouble = _troubleOf(code);
    if (!silence &&
        _onDevice &&
        !_onDeviceHeard &&
        trouble != RecitationTrouble.denied &&
        trouble != RecitationTrouble.dictation) {
      // No model for Arabic on the phone: through the network from here.
      _onDevice = false;
    } else if (trouble != null) {
      _trouble(trouble);
    } else if (_apple && _failures >= _failuresTold) {
      _trouble(RecitationTrouble.network);
    }
    _listening = false;
    _listenAgain();
  }

  /// What an error of the recogniser says, in Android's codes and iOS's
  /// (speech_to_text 7.4.0 names Apple's numbers).
  static RecitationTrouble? _troubleOf(String code) => switch (code) {
    // 201: Siri and dictation are off.
    'error_speech_recognizer_disabled' => RecitationTrouble.dictation,
    // 1700: the request is not allowed.
    'error_speech_recognizer_request_not_authorized' =>
      RecitationTrouble.denied,
    // 102: the phone's own Arabic is not installed.
    'error_assets_not_installed' => RecitationTrouble.language,
    // The microphone gave no sound to listen to.
    'error_listen_failed' => RecitationTrouble.microphone,
    // The internet's own errors, by their negative numbers.
    _ when code.startsWith('error_unknown (-1') => RecitationTrouble.network,
    _ when code.contains('network') || code.contains('server') =>
      RecitationTrouble.network,
    _ when code.contains('language') => RecitationTrouble.language,
    _
        when code.contains('permission') ||
            code.contains('audio') ||
            code.contains('not_available') =>
      RecitationTrouble.unavailable,
    _ => null,
  };

  void _trouble(RecitationTrouble trouble) {
    ear.value = (
      heard: ear.value.heard,
      deaf: ear.value.deaf,
      trouble: trouble,
    );
  }

  Future<void> _tellIfDenied() async {
    if (await _allowed() || !_active) return;
    _trouble(RecitationTrouble.denied);
  }

  /// The microphone and speech recognition are both allowed (iOS).
  Future<bool> _allowed() async {
    try {
      return await _speech.hasPermission;
    } on Object catch (error) {
      // Not known: the listen will tell.
      _log('permission unknown: $error');
      return true;
    }
  }

  void _listenAgain() {
    if (!_active) return;
    _again?.cancel();
    _again = Timer(
      _againAfter[math.min(_failures, _againAfter.length - 1)],
      _listen,
    );
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
