import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/startup/startup_gate.dart';
import 'package:iqro_mobile/core/startup/startup_video.dart';

void main() {
  testWidgets('ready app waits for the intro and initializes only once', (
    tester,
  ) async {
    final ready = Completer<String>();
    late VoidCallback finishIntro;
    var initializations = 0;
    await tester.pumpWidget(
      StartupGate<String>(
        initialize: () {
          initializations++;
          return ready.future;
        },
        readyBuilder: (value) => MaterialApp(home: Text(value)),
        introBuilder: (finish) {
          finishIntro = finish;
          return const Text('intro');
        },
      ),
    );
    ready.complete('ready app');
    await tester.pump();
    expect(find.text('intro'), findsOneWidget);
    expect(find.text('IQRO'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('ready app'), findsNothing);
    finishIntro();
    await tester.pumpAndSettle();
    expect(find.text('ready app'), findsOneWidget);
    expect(initializations, 1);
  });

  testWidgets('finished or failed video still waits for app readiness', (
    tester,
  ) async {
    final ready = Completer<String>();
    late VoidCallback finishIntro;
    await tester.pumpWidget(
      StartupGate<String>(
        initialize: () => ready.future,
        readyBuilder: (value) => MaterialApp(home: Text(value)),
        introBuilder: (finish) {
          finishIntro = finish;
          return const Text('intro');
        },
      ),
    );
    finishIntro();
    await tester.pump();
    expect(find.text('intro'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    ready.complete('ready app');
    await tester.pumpAndSettle();
    expect(find.text('ready app'), findsOneWidget);
  });

  testWidgets('startup error can retry without replaying the intro', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      StartupGate<String>(
        initialize: () async {
          if (++attempts == 1) throw StateError('startup failed');
          return 'ready app';
        },
        readyBuilder: (value) => MaterialApp(home: Text(value)),
        introBuilder: (_) => const Text('intro'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('intro'), findsNothing);
    expect(find.byKey(const ValueKey('startup-seal')), findsNothing);
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    expect(find.text('ready app'), findsOneWidget);
    expect(attempts, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a seen intro opens the app as soon as it is ready', (
    tester,
  ) async {
    final decision = Completer<bool>();
    var introBuilds = 0;
    var introFinishes = 0;
    await tester.pumpWidget(
      StartupGate<String>(
        initialize: () async => 'ready app',
        readyBuilder: (value) => MaterialApp(home: Text(value)),
        introBuilder: (_) {
          introBuilds++;
          return const Text('intro');
        },
        shouldPlayIntro: () => decision.future,
        onIntroFinished: () => introFinishes++,
      ),
    );
    await tester.pump();
    // Still deciding: no intro yet and no spinner flash.
    expect(find.text('ready app'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    decision.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('ready app'), findsOneWidget);
    expect(introBuilds, 0);
    expect(introFinishes, 0);
  });

  testWidgets('the IQRO seal holds the launch screen until the app opens', (
    tester,
  ) async {
    final ready = Completer<String>();
    final decision = Completer<bool>();
    await tester.pumpWidget(
      StartupGate<String>(
        initialize: () => ready.future,
        readyBuilder: (value) => MaterialApp(home: Text(value)),
        introBuilder: (_) => const Text('intro'),
        shouldPlayIntro: () => decision.future,
      ),
    );
    await tester.pump();
    final seal = find.byKey(const ValueKey('startup-seal'));
    // Where the native launch screen draws it: the centre of the screen.
    expect(seal, findsOneWidget);
    expect(tester.getCenter(seal), tester.getCenter(find.byType(Scaffold)));

    decision.complete(false);
    await tester.pump();
    await tester.pump();
    expect(seal, findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    ready.complete('ready app');
    await tester.pumpAndSettle();
    expect(seal, findsNothing);
    expect(find.text('ready app'), findsOneWidget);
  });

  testWidgets('first launch plays the intro and reports it once', (
    tester,
  ) async {
    late VoidCallback finishIntro;
    var introFinishes = 0;
    await tester.pumpWidget(
      StartupGate<String>(
        initialize: () async => 'ready app',
        readyBuilder: (value) => MaterialApp(home: Text(value)),
        introBuilder: (finish) {
          finishIntro = finish;
          return const Text('intro');
        },
        shouldPlayIntro: () async => true,
        onIntroFinished: () => introFinishes++,
      ),
    );
    await tester.pump();
    expect(find.text('intro'), findsOneWidget);
    finishIntro();
    finishIntro();
    await tester.pumpAndSettle();
    expect(find.text('ready app'), findsOneWidget);
    expect(introFinishes, 1);
  });

  testWidgets('a failed intro decision does not block startup', (tester) async {
    await tester.pumpWidget(
      StartupGate<String>(
        initialize: () async => 'ready app',
        readyBuilder: (value) => MaterialApp(home: Text(value)),
        introBuilder: (_) => const Text('intro'),
        shouldPlayIntro: () async => throw StateError('preferences failed'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('intro'), findsNothing);
    expect(find.text('ready app'), findsOneWidget);
  });

  testWidgets('reduced motion skips video without initializing a decoder', (
    tester,
  ) async {
    var completions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: StartupVideo(onFinished: () => completions++),
        ),
      ),
    );
    await tester.pump();
    expect(completions, 1);
    expect(tester.takeException(), isNull);
  });
}
