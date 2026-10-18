import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/app/audio_navigation_boundary.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/audio/audio_controller.dart';

void main() {
  testWidgets('only audio-specific route entry applies an audio pause policy', (
    tester,
  ) async {
    final audio = _RecordingAudioController();
    var section = AudioNavigationSection.other;
    late StateSetter updateSection;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [audioControllerProvider.overrideWith((ref) => audio)],
        child: MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              updateSection = setState;
              return AudioNavigationBoundary(
                section: section,
                child: const Text('route'),
              );
            },
          ),
        ),
      ),
    );
    expect(audio.quranPauseRequests, 0);
    expect(audio.duaPauseRequests, 0);
    expect(audio.memorizationPauseRequests, 0);

    updateSection(() => section = AudioNavigationSection.quran);
    await tester.pumpAndSettle();
    expect(audio.quranPauseRequests, 1);
    expect(audio.duaPauseRequests, 0);

    updateSection(() => section = AudioNavigationSection.other);
    await tester.pumpAndSettle();
    expect(audio.quranPauseRequests, 1);
    expect(audio.duaPauseRequests, 0);

    updateSection(() => section = AudioNavigationSection.dua);
    await tester.pumpAndSettle();
    expect(audio.quranPauseRequests, 1);
    expect(audio.duaPauseRequests, 1);
    expect(audio.memorizationPauseRequests, 0);

    updateSection(() => section = AudioNavigationSection.dua);
    await tester.pumpAndSettle();
    expect(audio.quranPauseRequests, 1);
    expect(audio.duaPauseRequests, 1);

    updateSection(() => section = AudioNavigationSection.memorization);
    await tester.pumpAndSettle();
    expect(audio.memorizationPauseRequests, 1);

    updateSection(() => section = AudioNavigationSection.salah);
    await tester.pumpAndSettle();
    expect(audio.salahPauseRequests, 1);
    expect(audio.memorizationPauseRequests, 1);
  });

  test('prayer lessons are their own audio section', () {
    expect(
      audioSectionForUri(Uri.parse('/salah')),
      AudioNavigationSection.salah,
    );
    expect(
      audioSectionForUri(Uri.parse('/salah/lesson/fajr/step/fajr.r1.ruku')),
      AudioNavigationSection.salah,
    );
    expect(
      audioSectionForUri(Uri.parse('/prayer')),
      AudioNavigationSection.other,
    );
    expect(
      exitsAudioSection(Uri.parse('/salah/lesson/fajr'), Uri.parse('/salah')),
      isFalse,
    );
    expect(
      exitsAudioSection(Uri.parse('/salah'), Uri.parse('/app?tab=4')),
      isTrue,
    );
  });

  testWidgets('direct entry into Quran applies its pause policy', (
    tester,
  ) async {
    final audio = _RecordingAudioController();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [audioControllerProvider.overrideWith((ref) => audio)],
        child: const MaterialApp(
          home: AudioNavigationBoundary(
            section: AudioNavigationSection.quran,
            child: Text('Quran'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(audio.quranPauseRequests, 1);
    expect(audio.duaPauseRequests, 0);
  });
}

class _RecordingAudioController extends StateNotifier<IqroAudioState>
    implements AudioController {
  _RecordingAudioController() : super(const IqroAudioState());

  var quranPauseRequests = 0;
  var duaPauseRequests = 0;
  var memorizationPauseRequests = 0;
  var salahPauseRequests = 0;

  @override
  Future<void> pauseForQuranEntry() async {
    quranPauseRequests += 1;
  }

  @override
  Future<void> pauseForDuaEntry() async {
    duaPauseRequests += 1;
  }

  @override
  Future<void> pauseForMemorizationEntry() async {
    memorizationPauseRequests += 1;
  }

  @override
  Future<void> pauseForSalahEntry() async {
    salahPauseRequests += 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
