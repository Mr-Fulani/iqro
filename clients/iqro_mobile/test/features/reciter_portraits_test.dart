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
      resolveReciterPortraitUrl(
        reciter,
        apiBaseUrl: 'https://staging.iqro.forum',
      ),
      'https://cdn.example.test/managed.webp',
    );
  });

  test('curated portrait is resolved against the active environment', () {
    final reciter = _reciter(slug: 'qf-2-abdul-baset-abdul-samad');

    expect(
      resolveReciterPortraitUrl(
        reciter,
        apiBaseUrl: 'https://staging.iqro.forum',
      ),
      'https://staging.iqro.forum/reciters/abdul-baset-abdul-samad.webp',
    );
  });

  test('unknown reciter without a managed portrait uses initials', () {
    expect(
      resolveReciterPortraitUrl(
        _reciter(slug: 'unknown'),
        apiBaseUrl: 'https://staging.iqro.forum',
      ),
      isNull,
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
