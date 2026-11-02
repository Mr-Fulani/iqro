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

  test(
    'unknown reciter without a managed portrait gets the default figure',
    () {
      expect(
        resolveReciterPortraitUrl(
          _reciter(slug: 'unknown'),
          apiBaseUrl: 'https://iqro.forum',
        ),
        isNull,
      );
    },
  );

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

  test('the small copy comes from the same person portrait', () {
    final mujawwad = _reciter(slug: 'qf-1-abdulbaset-abdulsamad-mujawwad');
    final murattal = _reciter(
      slug: 'qf-2-abdul-baset-abdul-samad',
      portraitUrl: 'https://cdn.example.test/person-640.webp',
      portraitThumbnailUrl: 'https://cdn.example.test/person-320.webp',
    );

    expect(
      resolveReciterThumbnailUrl(
        mujawwad,
        apiBaseUrl: 'https://iqro.forum',
        reciters: <Reciter>[mujawwad, murattal],
      ),
      'https://cdn.example.test/person-320.webp',
    );
    expect(
      reciterWithPersonPortrait(
        mujawwad,
        apiBaseUrl: 'https://iqro.forum',
        reciters: <Reciter>[mujawwad, murattal],
      ).portraitThumbnailUrl,
      'https://cdn.example.test/person-320.webp',
    );
    expect(
      resolveReciterThumbnailUrl(
        _reciter(slug: 'qf-2-abdul-baset-abdul-samad'),
        apiBaseUrl: 'https://iqro.forum',
      ),
      isNull,
    );
  });

  test('the small copy survives a round trip through JSON', () {
    final reciter = Reciter.fromJson(<String, Object?>{
      'id': 'reciter-id',
      'slug': 'test',
      'portrait_url': 'https://cdn.example.test/640.webp',
      'portrait_thumbnail_url': 'https://cdn.example.test/320.webp',
    });

    expect(reciter.portraitThumbnailUrl, 'https://cdn.example.test/320.webp');
    expect(
      Reciter.fromJson(reciter.toJson()).portraitThumbnailUrl,
      'https://cdn.example.test/320.webp',
    );
  });
}

Reciter _reciter({
  required String slug,
  String? portraitUrl,
  String? portraitThumbnailUrl,
}) => Reciter(
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
  portraitThumbnailUrl: portraitThumbnailUrl,
);
