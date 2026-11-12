import 'package:flutter/foundation.dart';

import '../../core/utils/json_helpers.dart';

/// The only list of the first version.
const namesDefaultCollection = 'asma-al-husna';

final _slug = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');

String _text(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is String) return value;
  throw FormatException('Names document: $field must be a string');
}

int _positive(Object? value, String field) {
  if (value is int && value > 0) return value;
  throw FormatException('Names document: $field must be a positive integer');
}

/// «В Коране»: the ayah of a name, and the word a reciter says.
@immutable
class NameAyah {
  const NameAyah({required this.surah, required this.ayah, this.word});

  factory NameAyah.fromJson(Map<String, Object?> json) => NameAyah(
    surah: _positive(json['surah'], 'ayah.surah'),
    ayah: _positive(json['ayah'], 'ayah.ayah'),
    word: json['word'] == null ? null : _positive(json['word'], 'ayah.word'),
  );

  final int surah;
  final int ayah;

  /// Null when the name is not one word of the ayah: nothing to play then.
  final int? word;
}

@immutable
class DivineName {
  const DivineName({
    required this.slug,
    required this.position,
    required this.arabic,
    required this.transliteration,
    required this.meaning,
    required this.tafsir,
    required this.tafsirSource,
    required this.tafsirRef,
    this.ayah,
  });

  factory DivineName.fromJson(Map<String, Object?> json, int position) {
    final slug = _text(json, 'slug');
    if (slug.length > 64 || !_slug.hasMatch(slug)) {
      throw FormatException('Names document: bad slug "$slug"');
    }
    if (json['position'] != position) {
      throw const FormatException(
        'Names document: positions must run from 1 without gaps',
      );
    }
    final arabic = _text(json, 'arabic');
    if (arabic.isEmpty) {
      throw const FormatException('Names document: arabic is required');
    }
    final ayah = json['ayah'];
    return DivineName(
      slug: slug,
      position: position,
      arabic: arabic,
      transliteration: _text(json, 'transliteration'),
      meaning: _text(json, 'meaning'),
      tafsir: _text(json, 'tafsir'),
      tafsirSource: _text(json, 'tafsir_source'),
      tafsirRef: _text(json, 'tafsir_ref'),
      ayah: ayah == null ? null : NameAyah.fromJson(jsonMap(ayah)),
    );
  }

  /// Stays the same from version to version: the marks are kept by it.
  final String slug;
  final int position;
  final String arabic;

  /// Empty in the Arabic document: the name itself is shown.
  final String transliteration;
  final String meaning;
  final String tafsir;

  /// The book the explanation is from.
  final String tafsirSource;
  final String tafsirRef;
  final NameAyah? ayah;

  /// The name as the interface language writes it.
  String get label => transliteration.isEmpty ? arabic : transliteration;

  /// The word a reciter says, when the name is one word of its ayah.
  bool get hasVoice => ayah?.word != null;
}

/// The published list in one language (docs/names-of-allah/README.md).
@immutable
class NamesDocument {
  const NamesDocument({
    required this.slug,
    required this.version,
    required this.listSource,
    required this.names,
  });

  /// A list that does not fit the contract is an error, not a half-drawn
  /// wheel.
  factory NamesDocument.fromJson(Object? payload) {
    final json = jsonMap(payload);
    final collection = jsonMap(json['collection']);
    final rows = json['names'];
    if (rows is! List || rows.isEmpty) {
      throw const FormatException('Names document: names are required');
    }
    final names = <DivineName>[
      for (final (index, row) in rows.indexed)
        DivineName.fromJson(jsonMap(row), index + 1),
    ];
    if (names.map((name) => name.slug).toSet().length != names.length) {
      throw const FormatException('Names document: slugs must be unique');
    }
    return NamesDocument(
      slug: _text(collection, 'slug'),
      version: _text(collection, 'version'),
      listSource: _text(collection, 'list_source'),
      names: names,
    );
  }

  final String slug;
  final String version;

  /// The book the list and its order come from.
  final String listSource;
  final List<DivineName> names;
}

final _harakat = RegExp('[ً-ْٰـ]');

/// Arabic without vowel marks: small labels on the wheel stay legible.
String stripHarakat(String arabic) => arabic.replaceAll(_harakat, '');

/// The index of the name under the needle for a wheel position that may run
/// past either end.
int wheelIndex(double position, int count) =>
    ((position.round() % count) + count) % count;

/// The nearest wheel position that shows [index], going the short way round.
int wheelTarget(double position, int index, int count) {
  final from = position.round();
  var delta =
      wheelIndex(index.toDouble(), count) - wheelIndex(from.toDouble(), count);
  if (delta > count / 2) delta -= count;
  if (delta < -count / 2) delta += count;
  return from + delta;
}
