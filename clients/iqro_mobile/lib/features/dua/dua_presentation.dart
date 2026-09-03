import 'package:flutter/foundation.dart';

import 'dua_repository.dart';

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

String duaShareText(
  DuaEntry entry, {
  required String translationLabel,
  required String repetitionLabel,
  required String sourceLabel,
}) {
  final blocks = <String>[
    '${entry.categoryTitle} · #${entry.sourceNumber}',
    entry.arabicText.trim(),
  ];
  if (entry.transliteration.trim().isNotEmpty) {
    blocks.add(entry.transliteration.trim());
  }
  if (entry.meaning.trim().isNotEmpty) {
    blocks.add('$translationLabel:\n${entry.meaning.trim()}');
  }
  final repetition = entry.repetitionLabel.trim().isNotEmpty
      ? entry.repetitionLabel.trim()
      : entry.repetitions > 1
      ? entry.repetitions.toString()
      : '';
  if (repetition.isNotEmpty) {
    blocks.add('$repetitionLabel: $repetition');
  }

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
  if (provenance.isNotEmpty) {
    blocks.add('$sourceLabel: ${provenance.join(' · ')}');
  }
  return blocks.where((block) => block.isNotEmpty).join('\n\n');
}

String duaAudioPlaybackId(DuaEntry entry, DuaAudioAsset asset, int assetIndex) {
  final assetId = asset.id.trim();
  return assetId.isNotEmpty
      ? 'dua:$assetId'
      : '${entry.favoriteKey}:audio:$assetIndex';
}
