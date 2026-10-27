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
