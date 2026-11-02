import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/audio/audio_models.dart';
import 'package:iqro_mobile/features/audio/reciter_catalog.dart';
import 'package:iqro_mobile/features/audio/reciter_portraits.dart';

void main() {
  test('the search reads every name in any word order', () {
    final person = _person(
      'ناصر القطامي',
      'Nasser Alqatami',
      'Насер Аль Катами',
    );
    final search = ReciterSearch(<ReciterPerson>[person]);

    expect(search.find('катами'), <ReciterPerson>[person]);
    expect(search.find('Катами насер'), <ReciterPerson>[person]);
    expect(search.find('QATAMI'), <ReciterPerson>[person]);
    expect(search.find('القطامي'), <ReciterPerson>[person]);
    expect(search.find('  '), <ReciterPerson>[person]);
    expect(search.find('афаси'), isEmpty);
  });

  test('the search forgives Arabic letter forms', () {
    final person = _person('أبو بكر الشاطري', 'Abu Bakr', 'Абу Бакр');
    final hamza = _person('حمزة', 'Hamza', 'Хамза');

    expect(
      ReciterSearch(<ReciterPerson>[person]).find('ابو بكر'),
      hasLength(1),
    );
    expect(ReciterSearch(<ReciterPerson>[hamza]).find('حمزه'), hasLength(1));
  });

  test('the search finds a name spelled another way', () {
    final radia = _person(
      'رضية عبدالرحمن',
      'Rodziah Abdulrahman',
      'Радия Абдуррахман',
      'Radiye Abdurrahman',
    );
    final rukaya = _person(
      'رقية سولونق',
      'Rogayah Sulong',
      'Рукайя Сулонг',
      'Rukiye Sulong',
    );
    final sapina = _person('سابينة مامات', 'Sapinah Mamat', 'Сапина Мамат');
    final basit = _person(
      'عبد الباسط',
      'Abdul Baset',
      'Абдуль-Басит Абдус-Самад',
    );
    final shuraym = _person(
      'سعود الشريم',
      'Saud ash-Shuraym',
      'Сауд аш-Шурайм',
    );
    final search = ReciterSearch(<ReciterPerson>[
      radia,
      rukaya,
      sapina,
      basit,
      shuraym,
    ]);

    for (final query in <String>['Родзия', 'Радзия', 'Rodzia', 'Радиях']) {
      expect(search.find(query), <ReciterPerson>[radia], reason: query);
    }
    for (final query in <String>['Рогая', 'Рукия', 'Рукайа', 'Ruqayya']) {
      expect(search.find(query), <ReciterPerson>[rukaya], reason: query);
    }
    expect(search.find('сапинах'), <ReciterPerson>[sapina]);
    expect(search.find('сабина мамат'), <ReciterPerson>[sapina]);
    expect(search.find('абдульбасит'), <ReciterPerson>[basit]);
    expect(search.find('Шурейм'), <ReciterPerson>[shuraym]);
    expect(search.find('Шурайм'), <ReciterPerson>[shuraym]);
    expect(search.find('Зульфия'), isEmpty);
  });

  test('a name spelled as asked hides the ones that only sound like it', () {
    final rashid = _person('راشد', 'Rashid', 'Рашид');
    final rushd = _person('رشدي', 'Roshdi', 'Рошди');

    expect(
      ReciterSearch(<ReciterPerson>[rashid, rushd]).find('рашид'),
      <ReciterPerson>[rashid],
    );
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

  test('people with a portrait open the list in their own order', () {
    ReciterPerson person(String slug, [String? portraitUrl]) =>
        groupRecitersByPerson(<Reciter>[
          Reciter.fromJson(<String, dynamic>{
            'id': slug,
            'slug': slug,
            'name_ar': slug,
            'name_en': slug,
            'name_ru': slug,
            'portrait_url': portraitUrl,
          }),
        ]).single;

    final plain = person('plain');
    final uploaded = person('uploaded', 'https://cdn/a.webp');
    final curated = person('qf-3-abdur-rahman-as-sudais');

    expect(
      peopleWithPortraitsFirst(<ReciterPerson>[plain, uploaded, curated]),
      <ReciterPerson>[uploaded, curated, plain],
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

ReciterPerson _person(
  String nameAr,
  String nameEn,
  String nameRu, [
  String nameTr = '',
]) {
  return groupRecitersByPerson(<Reciter>[
    Reciter.fromJson(<String, dynamic>{
      'id': nameEn,
      'slug': nameEn.toLowerCase().replaceAll(' ', '-'),
      'name_ar': nameAr,
      'name_en': nameEn,
      'name_ru': nameRu,
      'name_tr': nameTr,
    }),
  ]).single;
}
