import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/audio/audio_models.dart';
import 'package:iqro_mobile/features/audio/reciter_catalog.dart';

void main() {
  test('recitation variants are grouped under one reciter person', () {
    final people = groupRecitersByPerson(<Reciter>[
      _reciter('1', 'qf-1-abdulbaset-abdulsamad-mujawwad'),
      _reciter('2', 'qf-2-abdul-baset-abdul-samad'),
      _reciter('6', 'qf-6-mahmoud-khaleel-al-husary'),
      _reciter(
        '12',
        'qf-12-mahmoud-khaleel-al-husary',
        portraitUrl: 'https://media.example.test/husary.png',
      ),
    ]);

    expect(people, hasLength(2));
    expect(people.first.primary.slug, 'qf-2-abdul-baset-abdul-samad');
    expect(people.first.sources, hasLength(2));
    expect(people.last.primary.slug, 'qf-6-mahmoud-khaleel-al-husary');
    expect(people.last.portraitSource.id, '12');
  });

  test('preferred recitation wins and murattal is the safe default', () {
    final reciter = _reciter('2', 'qf-2-abdul-baset-abdul-samad');
    final murattal = _recitation('murattal', reciter);
    final mujawwad = _recitation('mujawwad', reciter);
    final variants = <Recitation>[mujawwad, murattal];

    expect(preferredRecitation(variants)?.style, 'murattal');
    expect(
      preferredRecitation(variants, preferredId: mujawwad.id)?.style,
      'mujawwad',
    );
  });
}

Reciter _reciter(String id, String slug, {String? portraitUrl}) => Reciter(
  id: id,
  slug: slug,
  nameAr: 'قارئ',
  nameEn: 'Reciter',
  nameRu: 'Чтец',
  nameTr: 'Kâri',
  biographyAr: '',
  biographyEn: '',
  biographyRu: '',
  biographyTr: '',
  portraitUrl: portraitUrl,
);

Recitation _recitation(String style, Reciter reciter) => Recitation(
  id: '$style-id',
  code: '$style-code',
  reciter: reciter,
  style: style,
  timingsAvailable: true,
  surahCount: 114,
  streamAllowed: true,
  offlineDownloadAllowed: false,
);
