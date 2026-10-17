import 'dua_repository.dart';

/// Well-known names of du'a that the translated chapter titles do not use —
/// «истихара» is «молитва испрашивания помощи» in the Russian Hisn
/// al-Muslim — mapped to its chapters. Stems, so «истихару» and «istikharah»
/// match too.
const _hisnAliases = <(List<int>, List<String>)>[
  ([26], <String>['истихар', 'istikhar', 'istihar', 'استخار']),
  (
    [27, 28],
    <String>[
      'аятулькурси',
      'аятелькурси',
      'аятальк',
      'аяткурси',
      'ayatalkursi',
      'ayatulkursi',
      'ayetelkursi',
      'ayetelkürsi',
      'آيةالكرسي',
    ],
  ),
  ([32], <String>['кунут', 'qunut', 'kunut', 'قنوت']),
  ([16], <String>['истифтах', 'istiftah', 'iftitah', 'استفتاح']),
  ([22], <String>['ташаххуд', 'ташахуд', 'tashahhud', 'teşehhüd', 'تشهد']),
  ([23, 107], <String>['салават', 'salawat', 'salavat', 'صلاةعلىالنبي']),
  ([55, 56], <String>['джаназ', 'жаназ', 'janaz', 'cenaze', 'جناز']),
  ([129], <String>['истигфар', 'istighfar', 'istiğfar', 'توب', 'استغفار']),
  ([68], <String>['ифтар', 'iftar', 'إفطار']),
  ([115], <String>['тальби', 'talbiy', 'telbiye', 'تلبي']),
  ([63], <String>['истиск', 'istisq', 'istiska', 'استسقاء']),
  ([88], <String>['даджал', 'даджжал', 'dajjal', 'deccal', 'دجال']),
  ([85], <String>['каффара', 'kaffara', 'keffaret', 'كفارةالمجلس']),
];

// Letters only: apostrophes, hyphens and spaces are written every which way.
String _letters(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^\p{L}]', unicode: true), '');

/// Chapters a search should offer before individual du'a: those whose title
/// contains the query, and those a well-known name points to.
List<DuaCategory> duaChaptersMatching(
  String query,
  List<DuaCategory> categories, {
  int limit = 8,
}) {
  final needle = query.trim().toLowerCase();
  final letters = _letters(needle);
  if (letters.length < 3) return const <DuaCategory>[];
  final numbers = <int>{
    for (final (chapters, names) in _hisnAliases)
      if (names.any(
        (name) =>
            letters.contains(name) ||
            (letters.length >= 4 && name.startsWith(letters)),
      ))
        ...chapters,
  };
  final matches = <DuaCategory>[
    for (final category in categories)
      if (category.collection == 'hisn-al-muslim' &&
          numbers.contains(category.sourceNumber))
        category,
  ];
  for (final category in categories) {
    if (matches.length >= limit) break;
    if (!matches.contains(category) &&
        category.title.toLowerCase().contains(needle)) {
      matches.add(category);
    }
  }
  return matches.take(limit).toList(growable: false);
}
