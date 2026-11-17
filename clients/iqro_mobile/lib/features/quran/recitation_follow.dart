import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// What the trial shows under the text while it listens.
typedef RecitationEar = ({bool onDevice, String heard, String? error});

/// The phone's speech recognition, listening for Arabic until stopped: a
/// recogniser ends a listen after a pause, so each one is followed by the
/// next. It tries the phone's own model first and, where the phone has none
/// for Arabic, goes on through the network.
class RecitationListener {
  RecitationListener({required this.onHeard});

  /// Gets the words of the current listen so far, as they grow.
  final ValueChanged<String> onHeard;

  final ear = ValueNotifier<RecitationEar>((
    onDevice: true,
    heard: '',
    error: null,
  ));

  final _speech = SpeechToText();
  var _active = false;
  var _onDevice = true;
  var _heardOnDevice = false;
  String? _locale;
  Timer? _again;

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
    await _listen();
    return true;
  }

  Future<void> stop() async {
    _active = false;
    _again?.cancel();
    await _speech.stop();
  }

  void dispose() {
    _active = false;
    _again?.cancel();
    unawaited(_speech.cancel());
    ear.dispose();
  }

  Future<void> _listen() async {
    if (!_active || _speech.isListening) return;
    _show(error: null);
    await _speech.listen(
      onResult: (result) {
        if (!_active) return;
        if (_onDevice) _heardOnDevice = true;
        _show(heard: result.recognizedWords, error: null);
        onHeard(result.recognizedWords);
      },
      listenOptions: SpeechListenOptions(
        localeId: _locale,
        onDevice: _onDevice,
        partialResults: true,
        listenMode: ListenMode.dictation,
        listenFor: const Duration(minutes: 10),
        pauseFor: const Duration(seconds: 8),
      ),
    );
  }

  void _onStatus(String status) {
    if (status == SpeechToText.doneStatus ||
        status == SpeechToText.notListeningStatus) {
      _listenAgain();
    }
  }

  void _onError(SpeechRecognitionError error) {
    if (!_active) return;
    // Silence is not a fault: the next listen starts.
    final silence =
        error.errorMsg == 'error_no_match' ||
        error.errorMsg == 'error_speech_timeout';
    if (!silence) {
      _show(error: error.errorMsg);
      // No Arabic model on the phone: through the network from here on.
      if (_onDevice && !_heardOnDevice) _onDevice = false;
    }
    _listenAgain();
  }

  void _listenAgain() {
    if (!_active) return;
    _again?.cancel();
    _again = Timer(const Duration(milliseconds: 300), _listen);
  }

  void _show({String? heard, required String? error}) {
    ear.value = (
      onDevice: _onDevice,
      heard: heard ?? ear.value.heard,
      error: error,
    );
  }
}

/// The trial's pointer: a lens over the word being read, which glides to
/// the next one.
class RecitationLens extends StatelessWidget {
  const RecitationLens({required this.word, required this.glide, super.key});

  /// The word's box, in the stack the lens is put in.
  final Rect word;

  /// False while the text scrolls under the lens: it then keeps to its word.
  final bool glide;

  @override
  Widget build(BuildContext context) {
    final box = word.inflate(8);
    return AnimatedPositioned.fromRect(
      key: const ValueKey('recitation-lens'),
      rect: box,
      duration: glide ? const Duration(milliseconds: 220) : Duration.zero,
      curve: Curves.easeOutCubic,
      child: IgnorePointer(
        child: RawMagnifier(
          size: box.size,
          magnificationScale: 1.25,
          decoration: const MagnifierDecoration(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(14)),
              side: BorderSide(color: Color(0xFFC49647), width: 2),
            ),
            shadows: <BoxShadow>[
              BoxShadow(
                color: Color(0x40000000),
                blurRadius: 12,
                offset: Offset(0, 3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
