import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/audio/audio_repository.dart';
import 'package:iqro_mobile/features/names/names_sound.dart';

import 'names_test_data.dart';

void main() {
  test('a recorded name sounds from the app itself, at once', () async {
    final clips = _Clips();
    final voice = NamesVoice(
      audio: () => throw StateError('the shared player is not needed'),
      repository: _NoRepository(),
      recorded: Future.value(<String>{'al-jamil'}),
      clips: clips,
    );
    await Future<void>.delayed(Duration.zero);
    final names = namesDocument().names;
    final recorded = names.firstWhere((name) => name.slug == 'al-jamil');
    final twoWords = names.firstWhere((name) => name.slug == 'malik-al-mulk');

    // A name from the Sunnah has no word of the Quran, but has a recording.
    expect(recorded.hasVoice, isFalse);
    expect(voice.canSay(recorded), isTrue);
    expect(voice.canSay(twoWords), isFalse);
    // A name with a word of the Quran is said by a reciter when not recorded.
    expect(voice.canSay(names.first), isTrue);

    await voice.play(recorded, album: 'IQRO');
    expect(clips.played, <String>['assets/names_audio/al-jamil.mp3']);
    expect(voice.playing, isNull);
    expect(voice.missing, isNull);

    await voice.play(twoWords, album: 'IQRO');
    expect(clips.played, hasLength(1));
    voice.dispose();
  });

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
    final recorded = <String>{
      for (final file in Directory('assets/names_audio').listSync())
        file.uri.pathSegments.last.replaceAll('.mp3', ''),
    };
    expect(recorded, isNotEmpty);
    expect(recorded.difference(slugs), isEmpty);
    // The site serves the same recordings.
    final site = <String>{
      for (final file in Directory(
        '../../services/web/public/names-audio',
      ).listSync())
        file.uri.pathSegments.last.replaceAll('.mp3', ''),
    };
    expect(site, recorded);
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
