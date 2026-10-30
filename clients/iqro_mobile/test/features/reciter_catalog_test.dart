import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/audio/audio_models.dart';
import 'package:iqro_mobile/features/audio/reciter_catalog.dart';

void main() {
  test('the search reads every name in any word order', () {
    final person = groupRecitersByPerson(<Reciter>[
      Reciter.fromJson(<String, dynamic>{
        'id': '7',
        'slug': 'nasser-alqatami',
        'name_ar': 'ناصر القطامي',
        'name_en': 'Nasser Alqatami',
        'name_ru': 'Насер Аль Катами',
        'name_tr': '',
      }),
    ]).single;

    expect(reciterMatchesQuery(person, 'катами'), isTrue);
    expect(reciterMatchesQuery(person, 'Катами насер'), isTrue);
    expect(reciterMatchesQuery(person, 'QATAMI'), isTrue);
    expect(reciterMatchesQuery(person, 'القطامي'), isTrue);
    expect(reciterMatchesQuery(person, '  '), isTrue);
    expect(reciterMatchesQuery(person, 'афаси'), isFalse);
  });

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

  test('Mushaf and Memorization default to the teaching reciter', () {
    final husary = _reciter('6', 'qf-6-mahmoud-khaleel-al-husary');
    final murattal = _timed('qf-6-murattal', 'murattal', husary);
    final teaching = _timed(
      'qf-12-muallim',
      'muallim',
      _reciter('12', 'qf-12-mahmoud-khaleel-al-husary'),
      teachingDefault: true,
    );
    final variants = <Recitation>[murattal, teaching];

    for (final role in <AudioRecitationRole>[
      AudioRecitationRole.ayahPlayback,
      AudioRecitationRole.memorization,
    ]) {
      expect(preferredRecitation(variants, role: role), same(teaching));
      // The user's own choice wins; one that is no longer offered gives way.
      expect(
        preferredRecitation(variants, preferredId: murattal.id, role: role),
        same(murattal),
      );
      expect(
        preferredRecitation(variants, preferredId: 'gone', role: role),
        same(teaching),
      );
    }
    // The Audio tab keeps the first murattal as its default.
    expect(
      preferredRecitation(variants, role: AudioRecitationRole.listening),
      same(murattal),
    );
    expect(teachingRecitation(variants), same(teaching));
    expect(teachingRecitation(<Recitation>[murattal]), isNull);
  });

  test('all recitation variants resolve the same person portrait', () {
    final mujawwad = _reciter(
      '1',
      'qf-1-abdulbaset-abdulsamad-mujawwad',
      portraitUrl: 'https://media.example.test/variant.png',
    );
    final murattal = _reciter(
      '2',
      'qf-2-abdul-baset-abdul-samad',
      portraitUrl: 'https://media.example.test/person.png',
    );
    final catalog = <Reciter>[mujawwad, murattal];

    expect(reciterPortraitSourceFor(mujawwad, catalog), same(murattal));
    expect(reciterPortraitSourceFor(murattal, catalog), same(murattal));
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

Recitation _timed(
  String code,
  String style,
  Reciter reciter, {
  bool teachingDefault = false,
}) => Recitation(
  id: '$code-id',
  code: code,
  reciter: reciter,
  style: style,
  timingsAvailable: true,
  timingsComplete: true,
  surahCount: 114,
  streamAllowed: true,
  offlineDownloadAllowed: false,
  teachingDefault: teachingDefault,
);
