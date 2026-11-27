import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/quran/recitation_follow.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart';

void main() {
  final speech = _Speech();
  setUpAll(() => SpeechToTextPlatform.instance = speech);
  setUp(() {
    speech.reset();
    // A recogniser of its own for each listener: the app's one keeps the
    // callbacks of its first start, and no test is to depend on another.
    RecitationListener.recogniser = SpeechToText.withMethodChannel;
  });
  tearDown(RecitationListener.resetForTesting);

  Future<RecitationListener> listening(
    WidgetTester tester, {
    bool onDevice = false,
    List<String>? heard,
  }) async {
    RecitationListener.canAskOnDevice = () async => onDevice;
    final listener = RecitationListener(onHeard: (words) => heard?.add(words));
    expect(await listener.start(), isTrue);
    await tester.pump();
    return listener;
  }

  Future<void> off(WidgetTester tester, RecitationListener listener) async {
    listener.dispose();
    await tester.pump();
  }

  testWidgets('on iOS a phone without Arabic of its own listens through the '
      'network, and the line does not say that recognition is unavailable', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      speech.refuseOnDevice = true;
      final heard = <String>[];
      final listener = await listening(tester, onDevice: true, heard: heard);
      // The first listen asked for the phone's own recognition; the
      // package refused it and listened all the same.
      expect(speech.options.single.onDevice, isTrue);
      expect(listener.ear.value.trouble, isNull);
      speech.hear('بسم الله');
      await tester.pump();
      expect(heard.last, 'بسم الله');
      expect(listener.ear.value.heard, 'بسم الله');

      // The next listen goes through the network, at once.
      speech.onStatus!('notListening');
      await tester.pump(const Duration(milliseconds: 200));
      expect(speech.listens, 2);
      expect(speech.options.last.onDevice, isFalse);
      expect(listener.ear.value.trouble, isNull);
      // The buzz of a word read wrongly is let through while it records.
      expect(
        speech.options.every((options) => options.enableHapticFeedback == true),
        isTrue,
      );
      await off(tester, listener);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('on iOS a refusal at the system\'s questions is told, for the '
      'way to the settings', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      speech
        ..ready = false
        ..allowed = false;
      final listener = RecitationListener(onHeard: (_) {});
      expect(await listener.start(), isFalse);
      expect(listener.ear.value.trouble, RecitationTrouble.denied);
      expect(speech.listens, 0);
      await off(tester, listener);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('on iOS a microphone not allowed yet is asked for by the first '
      'listen (speech recognition came first); refused, its silence is told '
      'for what it is', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      speech.allowed = false;
      final listener = await listening(tester);
      // The listen runs: iOS puts its own question as the microphone opens.
      expect(speech.listens, 1);
      expect(listener.ear.value.trouble, isNull);
      await tester.pump(recitationDeafAfter + const Duration(seconds: 2));
      expect(listener.ear.value.deaf, isTrue);
      expect(listener.ear.value.trouble, RecitationTrouble.denied);
      await off(tester, listener);

      // Allowed at the question: silence is only silence.
      speech.allowed = true;
      final allowed = await listening(tester);
      await tester.pump(recitationDeafAfter + const Duration(seconds: 2));
      expect(allowed.ear.value.deaf, isTrue);
      expect(allowed.ear.value.trouble, isNull);
      await off(tester, allowed);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('on iOS a first error before any word on the phone sends the '
      'next listen through the network', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final listener = await listening(tester, onDevice: true);
      expect(speech.options.single.onDevice, isTrue);
      speech.fail('error_assets_not_installed');
      await tester.pump(const Duration(milliseconds: 200));
      expect(speech.listens, 2);
      expect(speech.options.last.onDevice, isFalse);
      // Switched quietly: nothing said about Arabic.
      expect(listener.ear.value.trouble, isNull);
      await off(tester, listener);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('a listen that says it began after the microphone was turned '
      'off is ended', (tester) async {
    final listener = await listening(tester);
    await off(tester, listener);
    final cancels = speech.cancels;
    speech.onStatus!(SpeechToText.listeningStatus);
    await tester.pump();
    expect(speech.cancels, cancels + 1);
  });

  testWidgets('on Android the system asks for the microphone itself: the '
      'listener does not look again', (tester) async {
    speech.allowed = false;
    final listener = await listening(tester);
    expect(speech.listens, 1);
    expect(listener.ear.value.trouble, isNull);
    await off(tester, listener);
  });

  testWidgets('the errors of iOS are said in words', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final listener = await listening(tester);
      Future<RecitationTrouble?> after(String code) async {
        speech.fail(code);
        // Past the longest pause before the next listen.
        await tester.pump(const Duration(seconds: 25));
        return listener.ear.value.trouble;
      }

      expect(
        await after('error_speech_recognizer_disabled'),
        RecitationTrouble.dictation,
      );
      expect(
        await after('error_speech_recognizer_request_not_authorized'),
        RecitationTrouble.denied,
      );
      expect(
        await after('error_assets_not_installed'),
        RecitationTrouble.language,
      );
      expect(await after('error_unknown (-1009)'), RecitationTrouble.network);
      expect(await after('error_listen_failed'), RecitationTrouble.microphone);
      // Apple's recogniser can no longer be reached.
      speech.hear('بسم');
      await tester.pump();
      expect(listener.ear.value.trouble, isNull);
      speech.onStatus!('unavailable');
      await tester.pump();
      expect(listener.ear.value.trouble, RecitationTrouble.network);
      await off(tester, listener);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('after errors in a row the next listen waits longer each time; '
      'on iOS three in a row are taken for the network, and a word heard sets '
      'it all back', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final listener = await listening(tester);
      expect(speech.listens, 1);
      Future<void> waits(Duration pause) async {
        final listens = speech.listens;
        speech.fail('error_retry');
        await tester.pump(pause - const Duration(milliseconds: 20));
        expect(speech.listens, listens, reason: 'not before $pause');
        await tester.pump(const Duration(milliseconds: 40));
        expect(speech.listens, listens + 1, reason: 'after $pause');
      }

      await waits(const Duration(milliseconds: 150));
      await waits(const Duration(seconds: 1));
      expect(listener.ear.value.trouble, isNull);
      await waits(const Duration(seconds: 3));
      expect(listener.ear.value.trouble, RecitationTrouble.network);
      await waits(const Duration(seconds: 8));
      await waits(const Duration(seconds: 20));
      await waits(const Duration(seconds: 20));

      speech.hear('بسم');
      await tester.pump();
      expect(listener.ear.value.trouble, isNull);
      await waits(const Duration(milliseconds: 150));
      expect(listener.ear.value.trouble, isNull);
      await off(tester, listener);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('silence is no error: the next listen starts at once, again and '
      'again', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final listener = await listening(tester);
      for (var time = 0; time < 5; time++) {
        final listens = speech.listens;
        speech.fail('error_no_match');
        await tester.pump(const Duration(milliseconds: 170));
        expect(speech.listens, listens + 1);
      }
      expect(listener.ear.value.trouble, isNull);
      // After errors too: a recogniser that heard silence works.
      for (var time = 0; time < 3; time++) {
        speech.fail('error_retry');
        await tester.pump(const Duration(seconds: 25));
      }
      final listens = speech.listens;
      speech.fail('error_no_match');
      await tester.pump(const Duration(milliseconds: 170));
      expect(speech.listens, listens + 1);
      await off(tester, listener);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('on Android the codes say what is wrong as before, and errors '
      'that say nothing are not taken for the network', (tester) async {
    final listener = await listening(tester);
    for (var time = 0; time < 4; time++) {
      speech.fail('error_client');
      await tester.pump(const Duration(seconds: 25));
    }
    expect(speech.listens, 5);
    expect(listener.ear.value.trouble, isNull);
    speech.fail('error_network');
    await tester.pump(const Duration(seconds: 25));
    expect(listener.ear.value.trouble, RecitationTrouble.network);
    speech.fail('error_language_not_supported');
    await tester.pump(const Duration(seconds: 25));
    expect(listener.ear.value.trouble, RecitationTrouble.language);
    await off(tester, listener);
  });
}

/// A phone's speech recognition the test speaks for.
class _Speech extends SpeechToTextPlatform {
  /// Both the microphone and speech recognition are allowed.
  var allowed = true;

  /// The package's start answers yes: no question refused.
  var ready = true;

  var cancels = 0;

  /// The phone has no Arabic of its own: a listen on the phone is refused
  /// the way speech_to_text 7.4.0 refuses it on iOS, and goes on anyway.
  var refuseOnDevice = false;

  /// What each listen was asked for.
  final options = <SpeechListenOptions>[];

  int get listens => options.length;

  void reset() {
    allowed = true;
    ready = true;
    refuseOnDevice = false;
    options.clear();
    cancels = 0;
  }

  void hear(String words) => onTextRecognition!(
    jsonEncode(<String, Object>{
      'alternates': [
        <String, Object>{'recognizedWords': words, 'confidence': .9},
      ],
      'resultType': 0,
    }),
  );

  void fail(String code) => onError!(
    jsonEncode(<String, Object>{'errorMsg': code, 'permanent': true}),
  );

  @override
  Future<bool> hasPermission() async => allowed;

  @override
  Future<bool> initialize({
    debugLogging = false,
    List<SpeechConfigOption>? options,
  }) async => ready;

  @override
  Future<List<dynamic>> locales() async => <String>['ar_SA:Arabic'];

  @override
  Future<bool> listen({
    String? localeId,
    partialResults = true,
    onDevice = false,
    int listenMode = 0,
    sampleRate = 0,
    SpeechListenOptions? options,
  }) async {
    this.options.add(options!);
    if (refuseOnDevice && options.onDevice == true) {
      throw PlatformException(
        code: 'onDeviceError',
        message: 'on device recognition is not supported on this device',
      );
    }
    return true;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async => cancels++;
}
