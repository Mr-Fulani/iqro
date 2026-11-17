import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// What the trial shows under the text while it listens.
typedef RecitationEar = ({String heard, String? error});

/// The phone's speech recognition, listening for Arabic until stopped: a
/// recogniser ends a listen after a pause or an error, so each one is
/// followed by the next. The phone chooses between its own model for Arabic,
/// where it has one, and the network.
class RecitationListener {
  RecitationListener({required this.onHeard});

  /// Gets the words of the current listen so far, as they grow.
  final ValueChanged<String> onHeard;

  final ear = ValueNotifier<RecitationEar>((heard: '', error: null));

  final _speech = SpeechToText();
  var _active = false;
  String? _locale;
  Timer? _again;

  /// Starts a listen whenever none runs: a recogniser does not always say
  /// that it has stopped.
  Timer? _watch;

  /// False when the phone has no speech recognition, or the reader refused
  /// the microphone.
  Future<bool> start() async {
    final ready = await _speech.initialize(
      onStatus: _onStatus,
      onError: _onError,
    );
    if (!ready) return false;
    final locales = await _speech.locales();
    final arabic = locales
        .map((locale) => locale.localeId)
        .where((id) => id.toLowerCase().startsWith('ar'))
        .toList();
    _locale =
        arabic.where((id) => id.toUpperCase().endsWith('SA')).firstOrNull ??
        arabic.firstOrNull ??
        'ar-SA';
    _active = true;
    debugPrint('IQRO recitation locale: $_locale of ${arabic.length} Arabic');
    _watch = Timer.periodic(const Duration(seconds: 2), (_) => _check());
    await _listen();
    return true;
  }

  Future<void> stop() async {
    _active = false;
    _again?.cancel();
    _watch?.cancel();
    await _speech.stop();
  }

  void dispose() {
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

  Future<void> _listen() async {
    if (!_active || _starting) return;
    _starting = true;
    try {
      // Ends a listen the package still counts as running.
      if (_speech.isListening) await _speech.cancel();
      if (!_active) return;
      await _speech.listen(
        onResult: (result) {
          if (!_active) return;
          _lastSign = DateTime.now();
          debugPrint('IQRO recitation heard: ${result.recognizedWords}');
          _show(heard: result.recognizedWords, error: null);
          onHeard(result.recognizedWords);
        },
        listenOptions: SpeechListenOptions(
          localeId: _locale,
          partialResults: true,
          listenMode: ListenMode.dictation,
          // No limit of the package's own: the listen it stops on a timer
          // does not start again. The phone ends a listen after a silence.
        ),
      );
      debugPrint('IQRO recitation listen started');
      _listening = true;
      _lastSign = DateTime.now();
    } on Object catch (error) {
      debugPrint('IQRO recitation listen failed: $error');
      if (_active) _show(error: '$error');
    } finally {
      _starting = false;
    }
  }

  /// Starts a listen when none runs, or when the one that should has been
  /// silent longer than a pause may last.
  void _check() {
    if (_again?.isActive ?? false) return;
    if (_listening &&
        DateTime.now().difference(_lastSign) < const Duration(seconds: 15)) {
      return;
    }
    _listening = false;
    unawaited(_listen());
  }

  void _onStatus(String status) {
    debugPrint('IQRO recitation status: $status');
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
    debugPrint('IQRO recitation error: ${error.errorMsg}');
    // Silence is not a fault: the next listen starts.
    final silence =
        error.errorMsg == 'error_no_match' ||
        error.errorMsg == 'error_speech_timeout';
    if (!silence) _show(error: error.errorMsg);
    _listening = false;
    _listenAgain();
  }

  void _listenAgain() {
    if (!_active) return;
    _again?.cancel();
    _again = Timer(const Duration(milliseconds: 300), _listen);
  }

  void _show({String? heard, required String? error}) {
    ear.value = (heard: heard ?? ear.value.heard, error: error);
  }
}

/// The trial's pointer: a round lens over the word to read now, which
/// glides to the next one.
class RecitationLens extends StatelessWidget {
  const RecitationLens({required this.word, required this.glide, super.key});

  /// The word's box, in the stack the lens is put in.
  final Rect word;

  /// False while the text scrolls under the lens: it then keeps to its word.
  final bool glide;

  @override
  Widget build(BuildContext context) {
    // As wide as the word, within what a line and its neighbours leave.
    final size =
        word.width.clamp(word.height * .9, word.height * 1.5).toDouble() + 12;
    return AnimatedPositioned.fromRect(
      key: const ValueKey('recitation-lens'),
      rect: Rect.fromCircle(center: word.center, radius: size / 2),
      duration: glide ? const Duration(milliseconds: 120) : Duration.zero,
      curve: Curves.easeOut,
      child: IgnorePointer(
        child: RawMagnifier(
          size: Size.square(size),
          magnificationScale: 1.2,
          decoration: const MagnifierDecoration(
            shape: CircleBorder(
              side: BorderSide(color: Color(0xFFC49647), width: 2.5),
            ),
          ),
        ),
      ),
    );
  }
}
