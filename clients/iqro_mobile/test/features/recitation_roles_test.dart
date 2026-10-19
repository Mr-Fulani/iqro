import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/audio/audio_models.dart';

void main() {
  Recitation parse({
    Map<String, Object?>? timings,
    Map<String, Object?>? capabilities,
  }) => Recitation.fromJson(<String, Object?>{
    'id': 'recitation',
    'code': 'code',
    'style': 'murattal',
    'reciter': <String, Object?>{'id': 'reciter', 'slug': 'reciter'},
    'rights': <String, Object?>{'stream': true},
    'coverage': <String, Object?>{'surah_count': 114},
    'timings': ?timings,
    'capabilities': ?capabilities,
  });

  const ayahRoles = <AudioRecitationRole>[
    AudioRecitationRole.ayahPlayback,
    AudioRecitationRole.memorization,
  ];

  test('server capabilities keep listening-only audio out of ayah roles', () {
    // A listening-only recording may still carry complete timings.
    final recitation = parse(
      timings: <String, Object?>{'available': true, 'complete': true},
      capabilities: <String, Object?>{
        'listen': true,
        'ayah_playback': false,
        'memorization': false,
        'offline': false,
      },
    );

    expect(recitation.supports(AudioRecitationRole.listening), isTrue);
    for (final role in ayahRoles) {
      expect(recitation.supports(role), isFalse, reason: role.name);
    }
  });

  test('a catalog without capabilities needs complete timings', () {
    final partial = parse(
      timings: <String, Object?>{'available': true, 'complete': false},
    );
    final unknown = parse(timings: <String, Object?>{'available': true});
    final complete = parse(
      timings: <String, Object?>{'available': true, 'complete': true},
    );

    for (final role in ayahRoles) {
      expect(partial.supports(role), isFalse, reason: role.name);
      expect(unknown.supports(role), isFalse, reason: role.name);
      expect(complete.supports(role), isTrue, reason: role.name);
    }
    expect(partial.supports(AudioRecitationRole.listening), isTrue);
    expect(partial.timingsComplete, isFalse);
    expect(complete.timingsComplete, isTrue);
  });

  test('a recitation built without capabilities needs complete timings', () {
    const reciter = Reciter(
      id: 'reciter',
      slug: 'reciter',
      nameAr: '',
      nameEn: 'Reciter',
      nameRu: '',
      nameTr: '',
      biographyAr: '',
      biographyEn: '',
      biographyRu: '',
      biographyTr: '',
    );
    const partial = Recitation(
      id: 'partial',
      code: 'partial',
      reciter: reciter,
      style: 'murattal',
      timingsAvailable: true,
      surahCount: 114,
      streamAllowed: true,
      offlineDownloadAllowed: false,
    );
    const complete = Recitation(
      id: 'complete',
      code: 'complete',
      reciter: reciter,
      style: 'murattal',
      timingsAvailable: true,
      timingsComplete: true,
      surahCount: 114,
      streamAllowed: true,
      offlineDownloadAllowed: false,
    );

    for (final role in ayahRoles) {
      expect(partial.supports(role), isFalse, reason: role.name);
      expect(complete.supports(role), isTrue, reason: role.name);
    }
    expect(partial.supports(AudioRecitationRole.listening), isTrue);
  });
}
