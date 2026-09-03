import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/dua/dua_presentation.dart';
import 'package:iqro_mobile/features/dua/dua_repository.dart';

void main() {
  test('builds a multi-stage repetition plan from a trusted label', () {
    expect(duaRepetitionStages('33 · 33 · 34', 33), <int>[33, 33, 34]);
    expect(duaRepetitionStages('3 / 7', 1), <int>[3, 7]);
  });

  test('falls back safely for malformed or excessive repetition labels', () {
    expect(duaRepetitionStages('33 times', 3), <int>[3]);
    expect(duaRepetitionStages('1001 · 2', 4), <int>[4]);
    expect(duaRepetitionStages('', 0), <int>[1]);
  });

  test('tracks current stage and clamps completed practice', () {
    final first = DuaPracticeProgress(stages: const <int>[2, 3], completed: 1);
    final second = DuaPracticeProgress(stages: const <int>[2, 3], completed: 2);
    final complete = DuaPracticeProgress(
      stages: const <int>[2, 3],
      completed: 99,
    );

    expect(
      (first.stageIndex, first.completedInStage, first.stageTarget),
      (0, 1, 2),
    );
    expect((second.stageIndex, second.completedInStage), (1, 0));
    expect(
      (complete.completed, complete.isComplete, complete.fraction),
      (5, true, 1),
    );
  });

  test(
    'share text includes content and provenance without claiming verification',
    () {
      const entry = DuaEntry(
        id: 'entry-1',
        sourceNumber: 7,
        collection: 'hisn-al-muslim',
        categoryTitle: 'Morning',
        arabicText: 'دعاء',
        meaning: 'A meaning',
        transliteration: 'Dua',
        repetitions: 1,
        sourceLabel: 'Hisn al-Muslim',
        evidence: <DuaEvidence>[
          DuaEvidence(
            kind: 'source_note',
            provider: 'provider',
            sourceName: 'Hisn',
            sourceReference: 'Entry 7',
            sourceUrl: '',
            grade: '',
            externalId: '',
            verificationStatus: 'source_only',
          ),
        ],
      );

      final text = duaShareText(
        entry,
        translationLabel: 'Translation',
        repetitionLabel: 'Repetitions',
        sourceLabel: 'Source',
        canonicalUrl: 'https://iqro.forum/dua/hisn-al-muslim/7',
      );

      expect(text, contains('Morning · #7'));
      expect(text, contains('Translation:\nA meaning'));
      expect(text, contains('Source: Hisn al-Muslim · Entry 7'));
      expect(text, endsWith('https://iqro.forum/dua/hisn-al-muslim/7'));
      expect(text.toLowerCase(), isNot(contains('verified')));
    },
  );

  test('share text preserves simple and staged repetition instructions', () {
    const simple = DuaEntry(
      id: 'simple',
      sourceNumber: 1,
      collection: 'hisn',
      categoryTitle: 'Morning',
      arabicText: 'دعاء',
      meaning: '',
      transliteration: '',
      repetitions: 3,
      sourceLabel: '',
    );
    const staged = DuaEntry(
      id: 'staged',
      sourceNumber: 2,
      collection: 'hisn',
      categoryTitle: 'Morning',
      arabicText: 'ذكر',
      meaning: '',
      transliteration: '',
      repetitions: 3,
      repetitionLabel: '33 · 33 · 34',
      sourceLabel: '',
    );

    String share(DuaEntry entry) => duaShareText(
      entry,
      translationLabel: 'Translation',
      repetitionLabel: 'Repetitions',
      sourceLabel: 'Source',
    );

    expect(share(simple), contains('Repetitions: 3'));
    expect(share(staged), contains('Repetitions: 33 · 33 · 34'));
  });
}
