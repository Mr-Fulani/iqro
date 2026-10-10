import 'dua_repository.dart';

part 'dua_topic_catalog.g.dart';

class DuaTopic {
  const DuaTopic({
    required this.id,
    required this.collection,
    required this.chapterNumbers,
    required this.titles,
    required this.descriptions,
    this.entryNumbers,
  });

  final String id;
  final String collection;
  final List<int> chapterNumbers;
  final Map<String, String> titles;
  final Map<String, String> descriptions;
  final List<int>? entryNumbers;

  String title(String locale) => titles[locale] ?? titles['en']!;
  String description(String locale) =>
      descriptions[locale] ?? descriptions['en']!;

  bool includesCategory(DuaCategory category) =>
      category.collection == collection &&
      (chapterNumbers.isEmpty ||
          chapterNumbers.contains(category.sourceNumber));

  bool includesEntry(DuaEntry entry) =>
      entry.collection == collection &&
      (entryNumbers == null || entryNumbers!.contains(entry.sourceNumber));

  int entryCount(List<DuaCategory> categories) {
    final count = categories
        .where(includesCategory)
        .fold<int>(0, (total, category) => total + category.entryCount);
    return entryNumbers != null && count == 24 ? entryNumbers!.length : count;
  }
}
