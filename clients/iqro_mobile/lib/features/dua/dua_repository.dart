import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/local_database.dart';
import '../../core/utils/json_helpers.dart';

class DuaCategory {
  const DuaCategory({
    required this.id,
    required this.slug,
    required this.title,
    required this.entryCount,
  });

  factory DuaCategory.fromJson(Map<String, Object?> json) => DuaCategory(
    id: json['id']?.toString() ?? '',
    slug: json['slug']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    entryCount: (json['entry_count'] as num?)?.toInt() ?? 0,
  );

  final String id;
  final String slug;
  final String title;
  final int entryCount;
}

class DuaEntry {
  const DuaEntry({
    required this.id,
    required this.sourceNumber,
    required this.collection,
    required this.categoryTitle,
    required this.arabicText,
    required this.meaning,
    required this.transliteration,
    required this.repetitions,
    required this.sourceLabel,
  });

  factory DuaEntry.fromJson(Map<String, Object?> json) {
    final category = json['category'] is Map
        ? Map<String, Object?>.from(json['category']! as Map)
        : const <String, Object?>{};
    final translation = json['translation'] is Map
        ? Map<String, Object?>.from(json['translation']! as Map)
        : const <String, Object?>{};
    final source = json['source'] is Map
        ? Map<String, Object?>.from(json['source']! as Map)
        : const <String, Object?>{};
    return DuaEntry(
      id: json['id']?.toString() ?? '',
      sourceNumber: (json['source_number'] as num?)?.toInt() ?? 0,
      collection: json['collection']?.toString() ?? 'hisn-al-muslim',
      categoryTitle: category['title']?.toString() ?? '',
      arabicText: json['arabic_text']?.toString() ?? '',
      meaning: translation['meaning_text']?.toString() ?? '',
      transliteration: translation['transliteration']?.toString() ?? '',
      repetitions: (json['repetitions'] as num?)?.toInt() ?? 1,
      sourceLabel:
          source['title']?.toString() ?? source['provider']?.toString() ?? '',
    );
  }

  final String id;
  final int sourceNumber;
  final String collection;
  final String categoryTitle;
  final String arabicText;
  final String meaning;
  final String transliteration;
  final int repetitions;
  final String sourceLabel;

  String get favoriteKey => 'dua:$collection:$sourceNumber';

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'source_number': sourceNumber,
    'collection': collection,
    'category_title': categoryTitle,
    'arabic_text': arabicText,
    'meaning': meaning,
    'transliteration': transliteration,
    'repetitions': repetitions,
    'source_label': sourceLabel,
  };

  factory DuaEntry.fromFavorite(Map<String, Object?> json) => DuaEntry(
    id: json['id']?.toString() ?? '',
    sourceNumber: (json['source_number'] as num?)?.toInt() ?? 0,
    collection: json['collection']?.toString() ?? 'hisn-al-muslim',
    categoryTitle: json['category_title']?.toString() ?? '',
    arabicText: json['arabic_text']?.toString() ?? '',
    meaning: json['meaning']?.toString() ?? '',
    transliteration: json['transliteration']?.toString() ?? '',
    repetitions: (json['repetitions'] as num?)?.toInt() ?? 1,
    sourceLabel: json['source_label']?.toString() ?? '',
  );
}

class DuaRepository {
  DuaRepository({
    required ApiClient api,
    required LocalDatabase database,
    Uuid? uuid,
  }) : _api = api,
       _database = database,
       _uuid = uuid ?? const Uuid();

  final ApiClient _api;
  final LocalDatabase _database;
  final Uuid _uuid;

  Future<List<DuaCategory>> categories(String locale) async {
    final key = 'dua:categories:$locale';
    final cached = await _database.readCache(key);
    try {
      if (cached?.isFresh == true) return _parseCategories(cached!.value);
      final payload = await _api.get(
        '/dua/categories',
        query: <String, Object?>{'language': locale},
        public: true,
      );
      await _database.writeCache(key, payload, maxAge: const Duration(days: 7));
      return _parseCategories(payload);
    } on Object {
      if (cached != null) return _parseCategories(cached.value);
      rethrow;
    }
  }

  Future<List<DuaEntry>> entries(String locale, {String? category}) async {
    final key = 'dua:entries:$locale:${category ?? 'all'}';
    final cached = await _database.readCache(key);
    try {
      if (cached?.isFresh == true) return _parseEntries(cached!.value);
      final payload = await _api.get(
        '/dua/entries',
        query: <String, Object?>{'language': locale, 'category': ?category},
        public: true,
      );
      await _database.writeCache(key, payload, maxAge: const Duration(days: 7));
      return _parseEntries(payload);
    } on Object {
      if (cached != null) return _parseEntries(cached.value);
      rethrow;
    }
  }

  Future<bool> isFavorite(DuaEntry entry) async {
    final rows = await _database.database.query(
      'favorites',
      columns: const <String>['item_key'],
      where: 'item_key = ?',
      whereArgs: <Object?>[entry.favoriteKey],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<bool> toggleFavorite(DuaEntry entry) async {
    final active = await isFavorite(entry);
    final operationId = _uuid.v7();
    final payload = <String, Object?>{
      'collection': entry.collection,
      'source_number': entry.sourceNumber,
      'is_favorite': !active,
    };
    if (active) {
      await _database.database.delete(
        'favorites',
        where: 'item_key = ?',
        whereArgs: <Object?>[entry.favoriteKey],
      );
    } else {
      await _database.database.insert('favorites', <String, Object?>{
        'item_key': entry.favoriteKey,
        'kind': 'dua',
        'payload': jsonEncode(entry.toJson()),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    }
    await _database.enqueue(
      operationId: operationId,
      entityType: 'dua_favorite',
      entityId: entry.favoriteKey,
      payload: payload,
    );
    try {
      await _api.put(
        '/me/dua-favorites/${entry.collection}/${entry.sourceNumber}',
        data: <String, Object?>{'is_favorite': !active},
      );
      await _database.acknowledgeOutbox(operationId);
    } on Object catch (error) {
      await _database.markOutboxFailure(operationId, error.toString());
    }
    return !active;
  }

  Future<List<DuaEntry>> favorites() async {
    final rows = await _database.database.query(
      'favorites',
      where: 'kind = ?',
      whereArgs: const <Object?>['dua'],
      orderBy: 'updated_at DESC',
    );
    return rows
        .map((row) {
          final payload = jsonDecode(row['payload']! as String);
          return DuaEntry.fromFavorite(
            Map<String, Object?>.from(payload as Map),
          );
        })
        .toList(growable: false);
  }

  List<DuaCategory> _parseCategories(Object? payload) => jsonResults(payload)
      .whereType<Map>()
      .map((item) => DuaCategory.fromJson(Map<String, Object?>.from(item)))
      .toList(growable: false);

  List<DuaEntry> _parseEntries(Object? payload) => jsonResults(payload)
      .whereType<Map>()
      .map((item) => DuaEntry.fromJson(Map<String, Object?>.from(item)))
      .where((entry) => entry.arabicText.isNotEmpty)
      .toList(growable: false);
}
