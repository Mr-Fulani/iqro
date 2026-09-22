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
}) {
  return preferredRecitation(
    recitationsForPerson(
      person,
      recitations,
    ).where((item) => item.style == style).toList(growable: false),
    preferredId: preferredId,
  );
}
