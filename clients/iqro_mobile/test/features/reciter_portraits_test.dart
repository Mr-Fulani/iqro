import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/audio/audio_models.dart';
import 'package:iqro_mobile/features/audio/reciter_portraits.dart';

void main() {
  test('managed backend portrait has priority', () {
    final reciter = _reciter(
      slug: 'qf-2-abdul-baset-abdul-samad',
      portraitUrl: 'https://cdn.example.test/managed.webp',
    );

    expect(
      resolveReciterPortraitUrl(reciter, apiBaseUrl: 'https://iqro.forum'),
      'https://cdn.example.test/managed.webp',
    );
  });

  test('curated portrait is resolved against the active environment', () {
    final reciter = _reciter(slug: 'qf-2-abdul-baset-abdul-samad');

    expect(
      resolveReciterPortraitUrl(reciter, apiBaseUrl: 'https://iqro.forum'),
      'https://iqro.forum/reciters/abdul-baset-abdul-samad.webp',
    );
  });

  test('unknown reciter without a managed portrait uses initials', () {
    expect(
      resolveReciterPortraitUrl(
        _reciter(slug: 'unknown'),
        apiBaseUrl: 'https://iqro.forum',
      ),
      isNull,
    );
  });

  test('player variants use the canonical person portrait', () {
    final mujawwad = _reciter(
      slug: 'qf-1-abdulbaset-abdulsamad-mujawwad',
      portraitUrl: 'https://cdn.example.test/variant.webp',
    );
    final murattal = _reciter(
      slug: 'qf-2-abdul-baset-abdul-samad',
      portraitUrl: 'https://cdn.example.test/person.webp',
    );

    expect(
      resolveReciterPortraitUrl(
        mujawwad,
        apiBaseUrl: 'https://iqro.forum',
        reciters: <Reciter>[mujawwad, murattal],
      ),
      'https://cdn.example.test/person.webp',
    );
    expect(
      reciterWithPersonPortrait(
        mujawwad,
        apiBaseUrl: 'https://iqro.forum',
        reciters: <Reciter>[mujawwad, murattal],
      ),
      isA<Reciter>()
          .having((item) => item.id, 'id', mujawwad.id)
          .having((item) => item.slug, 'slug', mujawwad.slug)
          .having(
            (item) => item.portraitUrl,
            'portraitUrl',
            'https://cdn.example.test/person.webp',
          ),
    );
  });
}

Reciter _reciter({required String slug, String? portraitUrl}) => Reciter(
  id: 'reciter-id',
  slug: slug,
  nameAr: 'قارئ',
  nameEn: 'Test Reciter',
  nameRu: 'Тестовый чтец',
  nameTr: 'Test kâri',
  biographyAr: '',
  biographyEn: '',
  biographyRu: '',
  biographyTr: '',
  portraitUrl: portraitUrl,
);
