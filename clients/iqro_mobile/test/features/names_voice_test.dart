import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/audio/audio_repository.dart';
import 'package:iqro_mobile/features/names/names_models.dart';
import 'package:iqro_mobile/features/names/names_sound.dart';

import 'names_test_data.dart';

void main() {
  test(
    'a recorded name sounds from the app itself, in the asked language',
    () async {
      final clips = _Clips();
      final voice = NamesVoice(
        audio: () => throw StateError('the shared player is not needed'),
        repository: _NoRepository(),
        recorded: Future.value(<String>{
          'ru/al-jamil',
          'ar/al-jamil',
          'ar/ar-rahim',
        }),
        clips: clips,
      );
      await Future<void>.delayed(Duration.zero);
      final names = namesDocument().names;
      DivineName named(String slug) =>
          names.firstWhere((name) => name.slug == slug);

      // A name from the Sunnah has no word of the Quran, but has a recording.
      expect(named('al-jamil').hasVoice, isFalse);
      expect(voice.canSay(named('al-jamil')), isTrue);
      expect(voice.canSay(named('malik-al-mulk')), isFalse);
      // A name with a word of the Quran is said by a reciter when not recorded.
      expect(voice.canSay(names.first), isTrue);

      // The card: the name with its meaning in the interface language.
      await voice.play(named('al-jamil'), album: 'IQRO', language: 'ru');
      // The wheel and the Arabic interface: the name alone.
      await voice.play(named('al-jamil'), album: 'IQRO', language: 'ar');
      // No recording in this language yet: the name alone.
      await voice.play(named('ar-rahim'), album: 'IQRO', language: 'tr');
      expect(clips.played, <String>[
        'assets/names_audio/ru/al-jamil.mp3',
        'assets/names_audio/ar/al-jamil.mp3',
        'assets/names_audio/ar/ar-rahim.mp3',
      ]);
      expect(voice.playing, isNull);
      expect(voice.missing, isNull);

      await voice.play(named('malik-al-mulk'), album: 'IQRO', language: 'ru');
      expect(clips.played, hasLength(3));
      voice.dispose();
    },
  );

  test('every recording belongs to a name of the list', () {
    final data =
        jsonDecode(
              File(
                '../../services/backend/src/quran_backend/modules/names/data/asma-al-husna.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final slugs = <String>{
      for (final name in data['names']! as List<Object?>)
        (name! as Map<String, Object?>)['slug']! as String,
    };
    Set<String> folder(String path) => <String>{
      for (final file in Directory(path).listSync())
        file.uri.pathSegments.last.replaceAll('.mp3', ''),
    };
    // Every name is recorded in every language, and alone for the wheel; the
    // site serves the same recordings.
    for (final language in <String>['ar', 'ru', 'en', 'tr']) {
      expect(folder('assets/names_audio/$language'), slugs, reason: language);
      expect(
        folder('../../services/web/public/names-audio/$language'),
        slugs,
        reason: 'site $language',
      );
    }
  });
}

class _Clips implements NamesClipPlayer {
  final played = <String>[];

  @override
  Future<void> play(String asset) async => played.add(asset);

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

class _NoRepository implements AudioRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
