import 'package:flutter/foundation.dart';

import 'dua_repository.dart';
import '../../core/share/content_share.dart';

const int _maxPracticeStage = 1000;
const int _maxPracticeTotal = 10000;

List<int> duaRepetitionStages(String label, int fallback) {
  final safeFallback = fallback.clamp(1, _maxPracticeStage).toInt();
  final normalized = label.trim();
  if (normalized.isEmpty) return <int>[safeFallback];

  final supportedLabel = RegExp(r'^\d{1,4}(?:\s*[·•,;/+]\s*\d{1,4})+$');
  if (!supportedLabel.hasMatch(normalized)) return <int>[safeFallback];

  final stages = RegExp(r'\d+')
      .allMatches(normalized)
      .map((match) => int.parse(match.group(0)!))
      .toList(growable: false);
  if (stages.isEmpty ||
      stages.any((stage) => stage < 1 || stage > _maxPracticeStage) ||
      stages.fold<int>(0, (sum, stage) => sum + stage) > _maxPracticeTotal) {
    return <int>[safeFallback];
  }
  return stages;
}

@immutable
class DuaPracticeProgress {
  DuaPracticeProgress({required List<int> stages, required int completed})
    : stages = List<int>.unmodifiable(stages.isEmpty ? const <int>[1] : stages),
      completed = completed.clamp(
        0,
        stages.isEmpty ? 1 : stages.fold<int>(0, (sum, stage) => sum + stage),
      );

  final List<int> stages;
  final int completed;

  int get total => stages.fold<int>(0, (sum, stage) => sum + stage);
  bool get isComplete => completed >= total;
  double get fraction => total == 0 ? 0 : completed / total;

  int get stageIndex {
    var boundary = 0;
    for (var index = 0; index < stages.length; index += 1) {
      boundary += stages[index];
      if (completed < boundary) return index;
    }
    return stages.length - 1;
  }

  int get completedInStage {
    final preceding = stages
        .take(stageIndex)
        .fold<int>(0, (sum, stage) => sum + stage);
    return (completed - preceding).clamp(0, stages[stageIndex]).toInt();
  }

  int get stageTarget => stages[stageIndex];
}

/// The du'a as shared: its chapter, the Arabic, the meaning, how many times
/// it is said, its sources and a link to it on the site.
ContentShare duaContentShare(
  DuaEntry entry, {
  required String locale,
  required String repetitionLabel,
  required String readInIqro,
}) {
  final repetition = entry.repetitionLabel.trim().isNotEmpty
      ? entry.repetitionLabel.trim()
      : entry.repetitions > 1
      ? entry.repetitions.toString()
      : '';
  final provenance = <String>[];
  if (entry.sourceLabel.trim().isNotEmpty) {
    provenance.add(entry.sourceLabel.trim());
  }
  for (final evidence in entry.evidence) {
    final reference = evidence.sourceReference.trim();
    if (reference.isNotEmpty && !provenance.contains(reference)) {
      provenance.add(reference);
    }
  }
  return ContentShare(
    title: '${duaDisplayTitle(entry.categoryTitle)} · #${entry.sourceNumber}',
    arabic: entry.arabicText,
    translation: entry.meaning,
    note: repetition.isEmpty ? '' : '$repetitionLabel: $repetition',
    reference: provenance.join(' · '),
    url: duaShareUrl(locale, entry.collection, entry.sourceNumber),
    readInIqro: readInIqro,
  );
}

String duaAudioPlaybackId(DuaEntry entry, DuaAudioAsset asset, int assetIndex) {
  final assetId = asset.id.trim();
  return assetId.isNotEmpty
      ? 'dua:$assetId'
      : '${entry.favoriteKey}:audio:$assetIndex';
}

final _caseWords = RegExp(
  r'(^|[\s«"(\[])(аллах|allah|коран|quran|пророк|мухаммад|muhammad|ислам)',
  unicode: true,
);
final _firstLetter = RegExp(r'\p{L}', unicode: true);

/// Titles some sources print in capitals, in sentence case. The names that
/// keep a capital — Allah, the Quran, the Prophet — get it back; titles in
/// ordinary case or in scripts without case stay as they are.
String duaDisplayTitle(String title) {
  // Capitals with a lowercase gloss, «… МОЛИТВЫ (ду'ау-ль-истифтах)», count
  // as capitals too.
  final upper = RegExp(r'\p{Lu}', unicode: true).allMatches(title).length;
  final small = RegExp(r'\p{Ll}', unicode: true).allMatches(title).length;
  if (upper <= small) return title;
  final lower = title.toLowerCase().replaceAllMapped(
    _caseWords,
    (match) =>
        '${match[1]}${match[2]![0].toUpperCase()}${match[2]!.substring(1)}',
  );
  final first = _firstLetter.firstMatch(lower);
  if (first == null) return lower;
  return lower.replaceRange(first.start, first.end, first[0]!.toUpperCase());
}
