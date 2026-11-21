// ignore_for_file: avoid_print
// Runs the trial follower on recorded recitations (make_cases.py) on a computer, with the same Dart code the app
// runs, and reports how late the lens is and what it calls a mistake.
//
//   dart run tool/recitation_model/harness.dart <libonnxruntime.dylib> <model-int8.onnx> assets/recitation_model <cases folder> [name filter] [-v]
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:iqro_mobile/features/quran/recitation_model/follow_core.dart';
import 'package:iqro_mobile/features/quran/recitation_model/model_session.dart';
import 'package:iqro_mobile/features/quran/recitation_model/pipeline.dart';

/// [ayah] with [remove] sounds taken out at [at] and [insert] put there.
ExpectedAyah _spliced(ExpectedAyah ayah, int at, int remove, List<int> insert) {
  final by = insert.length - remove;
  int start(int i) => i > at ? i + by : i;
  int end(int i) => i > at ? math.max(at, i + by) : i;
  return ExpectedAyah(
    Uint8List.fromList(<int>[
      ...ayah.sounds.sublist(0, at),
      ...insert,
      ...ayah.sounds.sublist(at + remove),
    ]),
    <(int, int)>[for (final (s, e) in ayah.spans) (start(s), end(e))],
    <(int, int, int, int, int)>[
      for (final (kind, s, e, word, golden) in ayah.units)
        (kind, start(s), end(e), word, golden),
    ],
    <int>{
      for (final i in ayah.loose)
        if (i < at || i >= at + remove) start(i),
    },
    <int>{
      for (final i in ayah.added)
        if (i < at || i >= at + remove) start(i),
    },
  );
}

double pct(List<double> v, double q) {
  if (v.isEmpty) return double.nan;
  final s = [...v]..sort();
  return s[((s.length - 1) * q).round()];
}

void main(List<String> args) {
  final verbose = args.contains('-v');
  RecitationFollowCore.strictLetters = args.contains('--strict-letters');
  RecitationFollowCore.checkOmitted = !args.contains('--no-omitted');
  RecitationFollowCore.checkAdded = !args.contains('--no-added');
  final mutate = args
      .where((a) => a.startsWith('--mutate='))
      .map((a) => a.substring(9))
      .firstOrNull;
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
  final filter = args.length > 4 && !args[4].startsWith('-') ? args[4] : '';
  final stats = <String, Map<String, num>>{};
  final delays = <String, List<double>>{};
  final heldCounts = <String, int>{};
  final names =
      Directory(args[3])
          .listSync()
          .map((f) => f.path)
          .where((p) => p.endsWith('.json') && p.contains(filter))
          .toList()
        ..sort();
  for (final name in names) {
    final meta = jsonDecode(File(name).readAsStringSync()) as Map;
    if (verbose) print('# $name');
    final kind = meta['kind'] as String;
    final wav = File(name.replaceAll('.json', '.wav')).readAsBytesSync();
    // A second of silence after the recording, as a microphone left on
    // gives: the last word is final only once nothing follows it.
    final recorded = wav.buffer.asInt16List(44, (wav.length - 44) ~/ 2);
    final pcm = Int16List(recorded.length + 16000)..setAll(0, recorded);
    final surah = (table['surahs'] as Map)['${meta['surah']}'] as List;
    final ayahs = <ExpectedAyah>[
      for (final a in (meta['ayahs'] as List).cast<int>())
        ExpectedAyah.fromJson(surah[a - 1], symbols)!,
    ];
    // --mutate=haraka|letter|ending: one sound of the text is changed to another,
    // so a right recitation differs from it by that sound, as a reader's
    // slip would.
    int? changedWord;
    if (mutate != null && ayahs.length == 1 && ayahs.first.spans.length >= 2) {
      final ayah = ayahs.first;
      final sounds = Uint8List.fromList(ayah.sounds);
      const long = <int, int>{32: 29, 34: 30, 33: 31};
      // A sound that reading on always has (one a stop changes is not
      // asked for after a stop). With "ending": the last short vowel of a
      // word that another word follows, which only a stop leaves unsaid.
      search:
      for (var w = ayah.spans.length ~/ 2; w < ayah.spans.length; w++) {
        final (start, end) = ayah.spans[w];
        if (mutate == 'ikhfa') {
          // A nun said clearly before another letter, as the recording
          // has it, is written as one to be hidden: a reader's clear nun
          // where the text has ikhfa.
          for (var i = start + 1; i + 1 < end; i++) {
            if (ayah.loose.contains(i) || ayah.loose.contains(i + 1)) continue;
            if (sounds[i] != 25 || sounds[i - 1] == 25 || sounds[i + 1] == 25) {
              continue;
            }
            if (sounds[i + 1] < 1 || sounds[i + 1] > 28) continue;
            sounds[i] = 39;
            changedWord = w;
            break search;
          }
          continue;
        }
        if (mutate == 'ending') {
          if (w + 1 >= ayah.spans.length) continue;
          for (var i = end - 1; i > start; i--) {
            if (ayah.added.contains(i)) continue;
            final c = sounds[i];
            if (c < 32 || c > 34) break;
            sounds[i] = const <int, int>{32: 34, 34: 33, 33: 32}[c]!;
            changedWord = w;
            break search;
          }
          continue;
        }
        for (var i = start + 1; i < end; i++) {
          if (ayah.loose.contains(i)) continue;
          final c = sounds[i];
          final fits = mutate == 'haraka'
              ? c >= 32 && c <= 34 && (i + 1 >= end || sounds[i + 1] != long[c])
              : c >= 1 && c <= 28;
          if (!fits) continue;
          final to = mutate == 'haraka'
              ? const <int, int>{32: 34, 34: 33, 33: 32}[c]!
              : (c + 9) % 28 + 1;
          for (var k = i; k < end && ayah.sounds[k] == c; k++) {
            sounds[k] = to;
          }
          changedWord = w;
          break search;
        }
      }
      ayahs[0] = ExpectedAyah(
        sounds,
        ayah.spans,
        ayah.units,
        ayah.loose,
        ayah.added,
      );
      if (const <String>{'omit', 'omit1', 'add', 'addend'}.contains(mutate)) {
        // Sounds written that the recording does not have: a reader who
        // leaves a syllable ("omit") or a letter ("omit1") out of a word.
        // Sounds of the recording taken out of the text: a reader who
        // puts a syllable in, inside a word ("add") or at its end
        // ("addend"). In a word of six sounds or more.
        changedWord = null;
        ayahs[0] = ayah;
        bool letter(int c) => c >= 1 && c <= 28;
        bool short(int c) => c >= 32 && c <= 34;
        bool free(int from, int to) {
          for (var k = from; k < to; k++) {
            if (ayah.loose.contains(k)) return false;
          }
          return !ayah.units.any((unit) => unit.$2 < to && unit.$3 > from);
        }

        search:
        for (var w = ayah.spans.length ~/ 2; w < ayah.spans.length; w++) {
          final (start, end) = ayah.spans[w];
          if (end - start < 6) continue;
          final s = ayah.sounds;
          if (mutate == 'addend') {
            if (w + 1 >= ayah.spans.length) continue;
            var last = end;
            while (last > start && ayah.loose.contains(last - 1)) {
              last -= 1;
            }
            if (last - start < 6 || !free(last - 2, last)) continue;
            ayahs[0] = _spliced(ayah, last - 2, 2, const <int>[]);
            changedWord = w;
            break search;
          }
          for (var i = start + 2; i + 3 < end; i++) {
            if (mutate == 'add') {
              if (!(letter(s[i]) && short(s[i + 1]) && letter(s[i + 2]))) {
                continue;
              }
              if (!short(s[i - 1]) || s[i - 2] == s[i] || !free(i - 1, i + 3)) {
                continue;
              }
              ayahs[0] = _spliced(ayah, i, 2, const <int>[]);
            } else {
              if (!(short(s[i]) && letter(s[i + 1]) && free(i - 1, i + 2))) {
                continue;
              }
              var c = (s[i + 1] + 9) % 28 + 1;
              if (c == s[i - 1] || c == 24 || c == 25) c = c % 28 + 1;
              ayahs[0] = _spliced(
                ayah,
                i + 1,
                0,
                mutate == 'omit' ? <int>[c, 32] : <int>[c],
              );
            }
            changedWord = w;
            break search;
          }
        }
      }
      if (mutate == 'shadda') {
        // A letter said once, as the recording has it, is written as one
        // with a shaddah: a reader who does not double a letter.
        changedWord = null;
        ayahs[0] = ayah;
        search:
        for (var w = ayah.spans.length ~/ 2; w < ayah.spans.length; w++) {
          final (start, end) = ayah.spans[w];
          for (var i = start + 1; i + 1 < end; i++) {
            final c = ayah.sounds[i];
            if (c < 1 || c > 28 || c == 24 || c == 25) continue;
            if (ayah.sounds[i - 1] == c || ayah.sounds[i + 1] == c) continue;
            if (ayah.loose.contains(i)) continue;
            ayahs[0] = ExpectedAyah(
              ayah.sounds,
              ayah.spans,
              <(int, int, int, int, int)>[...ayah.units, (3, i, i + 1, w, 2)],
              ayah.loose,
              ayah.added,
            );
            changedWord = w;
            break search;
          }
        }
      }
      if (mutate == 'qalqala') {
        // A qalqalah is written where the recording has none: after a
        // letter with no vowel that is not one of "qutb jad", inside a
        // word. A reader who leaves a qalqalah out.
        const bounce = <int>{21, 16, 2, 5, 8};
        changedWord = null;
        ayahs[0] = ayah;
        search:
        for (var w = ayah.spans.length ~/ 2; w < ayah.spans.length; w++) {
          final (start, end) = ayah.spans[w];
          for (var i = start + 1; i + 1 < end; i++) {
            final c = ayah.sounds[i];
            final next = ayah.sounds[i + 1];
            if (c < 1 || c > 28 || next < 1 || next > 28 || c == next) continue;
            if (bounce.contains(c) || ayah.sounds[i - 1] == c) continue;
            if (ayah.loose.contains(i) || ayah.loose.contains(i + 1)) continue;
            int moved(int at) => at > i ? at + 1 : at;
            ayahs[0] = ExpectedAyah(
              Uint8List.fromList(<int>[
                ...ayah.sounds.sublist(0, i + 1),
                38,
                ...ayah.sounds.sublist(i + 1),
              ]),
              <(int, int)>[
                for (final (s, e) in ayah.spans) (moved(s), e > i ? e + 1 : e),
              ],
              <(int, int, int, int, int)>[
                for (final (kind, s, e, word, golden) in ayah.units)
                  (kind, moved(s), e > i ? e + 1 : e, word, golden),
              ],
              ayah.loose.map(moved).toSet(),
              ayah.added.map(moved).toSet(),
            );
            changedWord = w;
            break search;
          }
        }
      }
    }
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
      final events = pipeline.step();
      if (pipeline.lastHeld case final held?) {
        final key =
            '${held.place.kind}: ${held.counts} of ${held.place.golden}';
        heldCounts[key] = (heldCounts[key] ?? 0) + 1;
        pipeline.lastHeld = null;
      }
      for (final event in events) {
        switch (event) {
          case ModelPlace(:final word, wrong: false):
            reached.putIfAbsent(word, () => now);
            if (verbose) print('  ${now.toStringAsFixed(2)} on $word');
          case ModelPlace(:final word, wrong: true):
            misses.add((word, now));
            if (verbose) print('  ${now.toStringAsFixed(2)} MISS $word');
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
    if (changedWord != null) {
      count('sound changed');
      final stopped = misses.where((m) => m.$1 == changedWord).isNotEmpty;
      if (stopped) {
        count('red stop on the word');
      } else if (!reached.containsKey(changedWord)) {
        count('word not reached');
      } else {
        count('not noticed');
        if (verbose) print('$name: change at $changedWord not noticed');
      }
      count(
        'red stops on other words',
        misses.where((m) => m.$1 != changedWord).length,
      );
    } else if (kind == 'cut' || kind == 'whole') {
      // Tajweed: a place cut short should be remarked on, a whole ayah not.
      count('words', words);
      count('false stops', misses.length);
      count('words reached', reached.length);
      if (kind == 'cut') {
        final rule = meta['rule'] as int;
        final word = meta['word'] as int;
        final stopped = misses.any((m) => (m.$1 - word).abs() <= 1);
        count('rule $rule: cut');
        if (stopped) count('rule $rule: red stop');
        count('red stops elsewhere', misses.length - (stopped ? 1 : 0));
        if (!stopped && verbose) print('$name: not stopped, got $misses');
      } else {
        count('places of the three rules', (meta['places'] as List).length);
        if (misses.isNotEmpty && verbose) print('$name: $misses');
      }
    } else if (miss == null) {
      count('words', words);
      count('words reached', reached.length);
      count('false mistakes', misses.length);
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
  print('counts heard, by rule: $heldCounts');
  session.close();
}
