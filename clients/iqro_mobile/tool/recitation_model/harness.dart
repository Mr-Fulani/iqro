// ignore_for_file: avoid_print
// Runs the trial follower on recorded recitations (make_cases.py) on a computer, with the same Dart code the app
// runs, and reports how late the lens is and what it calls a mistake.
//
//   dart run tool/recitation_model/harness.dart <libiqro_recite.dylib> <model-int8.onnx> assets/recitation_model <cases folder> [name filter] [-v]
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:iqro_mobile/features/quran/recitation_model/follow_core.dart';
import 'package:iqro_mobile/features/quran/recitation_model/model_session.dart';
import 'package:iqro_mobile/features/quran/recitation_model/pipeline.dart';

double pct(List<double> v, double q) {
  if (v.isEmpty) return double.nan;
  final s = [...v]..sort();
  return s[((s.length - 1) * q).round()];
}

void main(List<String> args) {
  final verbose = args.contains('-v');
  final session = RecitationModelSession.open(
    File(args[1]).readAsBytesSync(),
    threads: 4,
    library: args[0],
  )!;
  final table =
      jsonDecode(File('${args[2]}/expected.json').readAsStringSync()) as Map;
  final symbols = (table['symbols'] as List).cast<String>();
  final filters = File(
    '${args[2]}/mel_filters.bin',
  ).readAsBytesSync().buffer.asFloat32List();
  final filter = args.length > 4 && args[4] != '-v' ? args[4] : '';
  final stats = <String, Map<String, num>>{};
  final delays = <String, List<double>>{};
  final names =
      Directory(args[3])
          .listSync()
          .map((f) => f.path)
          .where((p) => p.endsWith('.json') && p.contains(filter))
          .toList()
        ..sort();
  for (final name in names) {
    final meta = jsonDecode(File(name).readAsStringSync()) as Map;
    final kind = meta['kind'] as String;
    final wav = File(name.replaceAll('.json', '.wav')).readAsBytesSync();
    final pcm = wav.buffer.asInt16List(44, (wav.length - 44) ~/ 2);
    final surah = (table['surahs'] as Map)['${meta['surah']}'] as List;
    final ayahs = <ExpectedAyah>[
      for (final a in (meta['ayahs'] as List).cast<int>())
        ExpectedAyah.fromJson(surah[a - 1], symbols)!,
    ];
    final pipeline = RecitationPipeline(
      session: session,
      melFilters: filters,
      ayahs: ayahs,
    );
    final starts = (meta['starts'] as List).cast<num>();
    if (args.contains('-vv')) {
      pipeline.core.trace = (line) => print('    $line');
    }
    final reached = <int, double>{};
    final misses = <(int, double)>[];
    final remarks = <(int, int)>[];
    for (var at = 0; at < pcm.length; at += 800) {
      pipeline.add(
        Int16List.sublistView(
          pcm,
          at,
          at + 800 > pcm.length ? pcm.length : at + 800,
        ),
      );
      if (!pipeline.due) continue;
      final now = (at + 800) / 16000;
      final before = pipeline.core.debugState;
      for (final event in pipeline.step()) {
        switch (event) {
          case ModelPlace(:final word, wrong: false):
            reached.putIfAbsent(word, () => now);
            if (verbose) print('  ${now.toStringAsFixed(2)} on $word');
          case ModelPlace(:final word, wrong: true):
            misses.add((word, now));
            if (verbose) print('  ${now.toStringAsFixed(2)} MISS $word');
          case ModelRemarks(remarks: final found):
            remarks.addAll(found);
            if (verbose) print('  ${now.toStringAsFixed(2)} tajweed $found');
        }
      }
      if (verbose && pipeline.core.debugState != before) {
        print('  ${now.toStringAsFixed(2)} ${pipeline.core.debugState}');
      }
    }
    final s = stats.putIfAbsent(kind, () => <String, num>{});
    void count(String key, [num by = 1]) => s[key] = (s[key] ?? 0) + by;
    count('recitations');
    final miss = meta['miss'] as int?;
    final words = pipeline.core.passage.words;
    if (miss == null) {
      count('words', words);
      count('words reached', reached.length);
      count('false mistakes', misses.length);
      count('remarks', remarks.length);
      for (final entry in reached.entries) {
        final d = entry.value - starts[entry.key];
        (delays['$kind: word begins → lens on it'] ??= []).add(d);
        if (d < -.1) count('lens before the word began');
      }
      if (misses.isNotEmpty || reached.length < words) {
        print('$name: misses $misses, reached ${reached.length} of $words');
      }
    } else {
      // An ayah left out: the lens may wait on any of its first words.
      final right = misses
          .where((m) => m.$1 >= miss && m.$1 < miss + (kind == 'ayah' ? 4 : 1))
          .toList();
      final early = misses.where((m) => m.$2 < (meta['resume'] as num) - .05);
      if (right.isNotEmpty && early.isEmpty) {
        count('noticed on the right word');
        (delays['$kind: next word begins → red lens'] ??= []).add(
          right.first.$2 - (meta['resume'] as num),
        );
      } else {
        print('$name: expected a miss at $miss, got $misses');
      }
      if (early.isNotEmpty) count('false mistake before it');
      if (misses.length > 1) count('more than one mistake');
      if (reached.entries.any(
        (e) => e.key >= miss && e.value > (meta['resume'] as num),
      )) {
        count('lens went on past the word left out');
      }
    }
  }
  for (final entry in stats.entries) {
    print('${entry.key}: ${entry.value}');
  }
  for (final entry in delays.entries) {
    final v = entry.value;
    print(
      '${entry.key}: median ${pct(v, .5).toStringAsFixed(2)} s, '
      '90 % ${pct(v, .9).toStringAsFixed(2)} s, worst ${pct(v, 1).toStringAsFixed(2)} s (${v.length})',
    );
  }
  session.close();
}
