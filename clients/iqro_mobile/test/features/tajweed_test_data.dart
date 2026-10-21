// Tajweed of 112:4 as the backend serves it (docs: tajweed stage 1 contract).

Map<String, Object?> _texts(String ru, String en) => {
  'ru': ru,
  'en': en,
  'ar': ru,
  'tr': en,
};

/// Reference order: ikhafa, idgham_wo_ghunnah, qalaqah, madda_normal.
final tajweedRulesJson = <String, Object?>{
  'version': '2026-10-21',
  'review_status': 'pending_teacher_review',
  'languages': ['ru', 'en', 'ar', 'tr'],
  'rules': [
    {
      'code': 'ikhafa',
      'arabic_name': 'الإخفاء',
      'color': '#09B000',
      'name': _texts('Ихфа', 'Ikhfa'),
      'why': _texts('Нун перед буквой ихфа.', 'Noon before an ikhfa letter.'),
      'how': _texts('Скройте нун.', 'Hide the noon.'),
      'variants': <Object?>[],
    },
    {
      'code': 'idgham_wo_ghunnah',
      'arabic_name': 'الإدغام بغير غنة',
      'color': '#A3A5A5',
      'name': _texts('Идгам без гунны', 'Idgham without ghunnah'),
      'why': _texts(
        'Нун с сукуном или танвин в конце слова перед ل или ر.',
        'A noon with sukun or a tanween at the end of a word before ل or ر.',
      ),
      'how': _texts(
        'Нун не произносится: сразу читайте удвоенную ل или ر.',
        'The noon is not pronounced: go straight to a doubled ل or ر.',
      ),
      'variants': <Object?>[],
    },
    {
      'code': 'qalaqah',
      'arabic_name': 'القلقلة',
      'color': '#2FADFF',
      'name': _texts('Калькаля', 'Qalqalah'),
      'why': _texts('Буква калькали с сукуном.', 'A qalqalah letter.'),
      'how': _texts('Лёгкий отскок.', 'A light bounce.'),
      'variants': [
        {
          'code': 'stop',
          'name': _texts('Калькаля при остановке', 'Qalqalah when stopping'),
          'why': _texts('Буква калькали в конце слова.', 'At a word end.'),
          'how': _texts('При остановке отчётливее.', 'Clearer at a stop.'),
        },
      ],
    },
    {
      'code': 'madda_normal',
      'arabic_name': 'المد الطبيعي',
      'color': '#CE9E00',
      'name': _texts('Мадд табии', 'Natural madd'),
      'why': _texts('Буква мадда без хамзы и сукуна.', 'A madd letter.'),
      'how': _texts('Тяните на 2 хараката.', 'Lengthen for 2 counts.'),
      'variants': [
        {
          'code': 'silah_sughra',
          'name': _texts('Мадд силя сугра', 'Minor silah'),
          'why': _texts(
            'Хаъ местоимения между огласованными буквами.',
            'The pronoun ha between voweled letters.',
          ),
          'how': _texts(
            'При слитном чтении тяните на 2 хараката.',
            'Lengthen for 2 counts when reading on.',
          ),
        },
      ],
    },
  ],
};

final tajweedAyah1124Json = <String, Object?>{
  'verse_key': '112:4',
  'surah_number': 112,
  'ayah_number': 4,
  'page_number': 604,
  'rules': ['idgham_wo_ghunnah', 'qalaqah', 'madda_normal'],
  'words': [
    {
      'position': 2,
      'text': 'يَكُن',
      'rules': [
        {'code': 'idgham_wo_ghunnah', 'start': 3, 'end': 5, 'joins_next': true},
      ],
    },
    {
      'position': 3,
      'text': 'لَّهُۥ',
      'rules': [
        {
          'code': 'idgham_wo_ghunnah',
          'start': 0,
          'end': 1,
          'joins_previous': true,
        },
        {
          'code': 'madda_normal',
          'start': 5,
          'end': 6,
          'variant': 'silah_sughra',
        },
      ],
    },
    {
      'position': 5,
      'text': 'أَحَدُۢ',
      'rules': [
        {'code': 'qalaqah', 'start': 4, 'end': 5, 'variant': 'stop'},
      ],
    },
  ],
};

/// Deliberately not in reference order; ikhafa is absent from the page.
final tajweedPage604Json = <String, Object?>{
  'page_number': 604,
  'rules': ['madda_normal', 'idgham_wo_ghunnah', 'qalaqah'],
  'ayahs': [tajweedAyah1124Json],
  'source': {
    'name': 'Quran.Foundation Content API',
    'url': 'https://api.quran.com',
    'license_name': 'QF',
    'license_url': 'https://quran.foundation',
    'attribution': 'Quran data provided by Quran Foundation.',
    'checksum_sha256': 'c' * 64,
  },
};

/// The words of 112:4 on QF Mushaf 19 page 604 (Unicode text stands in for
/// the V4 glyphs), followed by the ayah-end marker.
final page604Words = <Map<String, Object?>>[
  for (final (index, text) in [
    'وَلَمۡ',
    'يَكُن',
    'لَّهُۥ',
    'كُفُوًا',
    'أَحَدُۢ',
    '٤',
  ].indexed)
    {
      'id': index + 1,
      'verse_key': '112:4',
      'line_number': 1 + index ~/ 3,
      'position_in_verse': index + 1,
      'position_in_page': index + 1,
      'char_type_name': index == 5 ? 'end' : 'word',
      'text': text,
    },
];
