import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/analytics/analytics.dart';

/// Reports «surah_open» once per surah while the reader is open, after the
/// surah has stayed the current one for three seconds, as the site does: the
/// restored reading position and paging past a surah do not count. Takes no
/// room on the screen.
class SurahOpenReporter extends ConsumerStatefulWidget {
  const SurahOpenReporter({required this.surah, super.key});

  final int? surah;

  @override
  ConsumerState<SurahOpenReporter> createState() => _SurahOpenReporterState();
}

class _SurahOpenReporterState extends ConsumerState<SurahOpenReporter> {
  static const _delay = Duration(seconds: 3);
  final _reported = <int>{};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant SurahOpenReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.surah != widget.surah) _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _schedule() {
    _timer?.cancel();
    final surah = widget.surah;
    if (surah == null || _reported.contains(surah)) return;
    _timer = Timer(_delay, () {
      _reported.add(surah);
      ref.read(analyticsProvider.notifier).track(AnalyticsEvent.surahOpen, {
        'surah': surah,
      });
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
