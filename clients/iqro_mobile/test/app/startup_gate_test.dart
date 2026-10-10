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
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    expect(find.text('ready app'), findsOneWidget);
    expect(attempts, 2);
    expect(tester.takeException(), isNull);
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
