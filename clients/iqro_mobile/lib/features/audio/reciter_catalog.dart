import 'audio_models.dart';

const defaultRecitationStyle = 'murattal';
const recitationStyleOrder = <String>[
  defaultRecitationStyle,
  'mujawwad',
  'muallim',
];

const _canonicalReciterSlugs = <String, String>{
  'qf-1-abdulbaset-abdulsamad-mujawwad': 'qf-2-abdul-baset-abdul-samad',
  'qf-12-mahmoud-khaleel-al-husary': 'qf-6-mahmoud-khaleel-al-husary',
};

String reciterPersonKey(Reciter reciter) =>
    _canonicalReciterSlugs[reciter.slug] ?? reciter.slug;

class ReciterPerson {
  const ReciterPerson({
    required this.key,
    required this.primary,
    required this.sources,
  });

  final String key;
  final Reciter primary;
  final List<Reciter> sources;

  bool containsReciter(String? reciterId) =>
      reciterId != null && sources.any((item) => item.id == reciterId);

  Reciter get portraitSource {
    if (primary.portraitUrl?.trim().isNotEmpty == true) return primary;
    for (final source in sources) {
      if (source.portraitUrl?.trim().isNotEmpty == true) return source;
    }
    return primary;
  }
}

Reciter reciterPortraitSourceFor(Reciter reciter, Iterable<Reciter> reciters) {
  final personKey = reciterPersonKey(reciter);
  for (final person in groupRecitersByPerson(
    reciters.toList(growable: false),
  )) {
    if (person.key == personKey) return person.portraitSource;
  }
  return reciter;
}

List<ReciterPerson> groupRecitersByPerson(List<Reciter> reciters) {
  final grouped = <String, List<Reciter>>{};
  for (final reciter in reciters) {
    grouped
        .putIfAbsent(reciterPersonKey(reciter), () => <Reciter>[])
        .add(reciter);
  }
  return grouped.entries
      .map((entry) {
        final sources = List<Reciter>.unmodifiable(entry.value);
        final primary = sources.firstWhere(
          (item) => item.slug == entry.key,
          orElse: () => sources.first,
        );
        return ReciterPerson(
          key: entry.key,
          primary: primary,
          sources: sources,
        );
      })
      .toList(growable: false);
}

/// The catalog's teaching reciter, as the site's `teachingRecitation`.
Recitation? teachingRecitation(Iterable<Recitation> recitations) {
  for (final recitation in recitations) {
    if (recitation.teachingDefault) return recitation;
  }
  return null;
}

/// The fixed voice of the tajweed course: al-Husary's Muallim
/// (Quran.Foundation recitation 12), whatever is picked in the players.
/// Without it in [recitations] the teaching reciter, then Mishary al-Afasy,
/// then the first one. Same choice as `tajweedCourseRecitation` on the site.
Recitation? tajweedCourseRecitation(List<Recitation> recitations) {
  Recitation? byPrefix(String prefix) {
    Recitation? best;
    for (final recitation in recitations) {
      if (!recitation.code.startsWith(prefix)) continue;
      if (best == null || recitation.surahCount > best.surahCount) {
        best = recitation;
      }
    }
    return best;
  }

  return byPrefix('qf-12-') ??
      teachingRecitation(recitations) ??
      byPrefix('qf-7-') ??
      (recitations.isEmpty ? null : recitations.first);
}

/// The recitation to play for [role]: [preferredId] when it is offered, else
/// the catalog's teaching reciter for the Mushaf and Memorization roles, else
/// the first murattal. Listening keeps the first murattal as its default.
Recitation? preferredRecitation(
  List<Recitation> recitations, {
  String? preferredId,
  AudioRecitationRole role = AudioRecitationRole.listening,
}) {
  final supported = recitations
      .where((item) => item.supports(role))
      .toList(growable: false);
  if (supported.isEmpty) return null;
  if (preferredId != null) {
    for (final recitation in supported) {
      if (recitation.id == preferredId) return recitation;
    }
  }
  if (role != AudioRecitationRole.listening) {
    final teaching = teachingRecitation(supported);
    if (teaching != null) return teaching;
  }
  final candidates = supported;
  for (final recitation in candidates) {
    if (recitation.style == 'murattal') return recitation;
  }
  return candidates.first;
}

List<Recitation> recitationsForPerson(
  ReciterPerson person,
  Iterable<Recitation> recitations,
) {
  return recitations
      .where((item) => person.containsReciter(item.reciter.id))
      .toList(growable: false);
}

List<String> orderedRecitationStyles(Iterable<Recitation> recitations) {
  final available = recitations.map((item) => item.style).toSet();
  return <String>[
    for (final style in recitationStyleOrder)
      if (available.remove(style)) style,
    ...available.toList()..sort(),
  ];
}

Recitation? recitationForPersonStyle(
  ReciterPerson person,
  Iterable<Recitation> recitations,
  String style, {
  String? preferredId,
  AudioRecitationRole role = AudioRecitationRole.listening,
}) {
  return preferredRecitation(
    recitationsForPerson(
      person,
      recitations,
    ).where((item) => item.style == style).toList(growable: false),
    preferredId: preferredId,
    role: role,
  );
}

const _nameLetters = <String, String>{
  'ё': 'е',
  'й': 'и',
  'â': 'a',
  'á': 'a',
  'ç': 'c',
  'é': 'e',
  'ğ': 'g',
  'ı': 'i',
  'î': 'i',
  'ö': 'o',
  'ş': 's',
  'û': 'u',
  'ü': 'u',
  'أ': 'ا',
  'إ': 'ا',
  'آ': 'ا',
  'ؤ': 'و',
  'ئ': 'ي',
  'ة': 'ه',
  'ى': 'ي',
};

String _normalizedName(String value) => value
    .toLowerCase()
    .replaceAll(RegExp('[\u064b-\u0655\u0640]'), '')
    .replaceAllMapped(
      RegExp('[${_nameLetters.keys.join()}]'),
      (match) => _nameLetters[match[0]]!,
    )
    .replaceAll(RegExp("[-‘’'ʼ]"), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

const _cyrillicLetters = <String, String>{
  'а': 'a',
  'б': 'b',
  'в': 'v',
  'г': 'g',
  'д': 'd',
  'е': 'e',
  'ж': 'j',
  'з': 'z',
  'и': 'i',
  'к': 'k',
  'л': 'l',
  'м': 'm',
  'н': 'n',
  'о': 'o',
  'п': 'p',
  'р': 'r',
  'с': 's',
  'т': 't',
  'у': 'u',
  'ф': 'f',
  'х': 'h',
  'ц': 's',
  'ч': 'ch',
  'ш': 'sh',
  'щ': 'sh',
  'ъ': '',
  'ы': 'i',
  'ь': '',
  'э': 'e',
  'ю': 'u',
  'я': 'a',
};

/// What a word sounds like, whatever alphabet or spelling it came in: its
/// consonants, with the letters that transcribe one Arabic sound merged.
/// Родзия, Радия and Rodziah all read "rd"; the site holds the same rules.
String _nameSound(String word) => word
    .replaceAllMapped(
      RegExp('[а-я]'),
      (match) => _cyrillicLetters[match[0]] ?? match[0]!,
    )
    .replaceAll(RegExp('dzh|dj'), 'j')
    .replaceAll('dz', 'd')
    .replaceAll('kh', 'h')
    .replaceAll('gh', 'g')
    .replaceAll(RegExp('sh|ch'), 'x')
    .replaceAll('th', 's')
    .replaceAll('dh', 'z')
    .replaceAll(RegExp('[qc]'), 'k')
    .replaceAll('p', 'b')
    .replaceAll('w', 'v')
    .replaceAll(RegExp('[aeiouy]'), '')
    .replaceAll(RegExp(r'h$'), '')
    .replaceAllMapped(RegExp(r'(.)\1+'), (match) => match[1]!);

/// The catalog's search: any word order, in any of the reciter's four names.
/// Only when nothing is spelled as asked does it look for names that sound the
/// same. The names are prepared once, so typing stays quick in a long catalog.
class ReciterSearch {
  ReciterSearch(this.people)
    : _entries = people.map(_ReciterSearchEntry.new).toList(growable: false);

  final List<ReciterPerson> people;
  final List<_ReciterSearchEntry> _entries;

  List<ReciterPerson> find(String query) {
    final words = _normalizedName(
      query,
    ).split(' ').where((word) => word.isNotEmpty).toList(growable: false);
    if (words.isEmpty) return people;
    final spelled = _entries
        .where((entry) => words.every(entry.text.contains))
        .map((entry) => entry.person)
        .toList(growable: false);
    if (spelled.isNotEmpty) return spelled;
    final sounds = words.map(_nameSound).toList(growable: false);
    if (sounds.any((sound) => sound.length < 2)) {
      return const <ReciterPerson>[];
    }
    return _entries
        .where(
          (entry) => sounds.every(
            (sound) => entry.sounds.any((name) => name.startsWith(sound)),
          ),
        )
        .map((entry) => entry.person)
        .toList(growable: false);
  }
}

class _ReciterSearchEntry {
  factory _ReciterSearchEntry(ReciterPerson person) {
    final names = person.sources
        .expand(
          (item) => <String>[
            item.nameAr,
            item.nameEn,
            item.nameRu,
            item.nameTr,
          ],
        )
        .map(_normalizedName)
        .toList(growable: false);
    // Each word with those after it, so "абдульбасит" meets "Абдуль-Басит".
    final sounds = <String>[
      for (final name in names)
        ...() {
          final words = name.split(' ').map(_nameSound).toList(growable: false);
          return <String>[
            for (var index = 0; index < words.length; index += 1)
              words.skip(index).join(),
          ];
        }(),
    ];
    return _ReciterSearchEntry._(person, names.join(' '), sounds);
  }

  const _ReciterSearchEntry._(this.person, this.text, this.sounds);

  final ReciterPerson person;
  final String text;
  final List<String> sounds;
}
