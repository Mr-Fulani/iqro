import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

enum AudioNavigationSection { other, quran, dua, memorization, salah }

AudioNavigationSection audioSectionForUri(Uri uri) {
  final path = uri.path;
  if (path == '/mushaf' ||
      path.startsWith('/reader/') ||
      (path == '/app' && uri.queryParameters['tab'] == '1')) {
    return AudioNavigationSection.quran;
  }
  if (path == '/dua' || path.startsWith('/dua/')) {
    return AudioNavigationSection.dua;
  }
  if (path == '/memorization') return AudioNavigationSection.memorization;
  if (path == '/salah' || path.startsWith('/salah/')) {
    return AudioNavigationSection.salah;
  }
  return AudioNavigationSection.other;
}

bool exitsAudioSection(Uri previous, Uri next) {
  final before = audioSectionForUri(previous);
  final after = audioSectionForUri(next);
  if (before == AudioNavigationSection.other) return false;
  if (before != after) return true;
  // Leaving a reader also ends its local playback when the Quran tab remains
  // underneath it in the navigation stack.
  return before == AudioNavigationSection.quran &&
      (previous.path == '/mushaf' || previous.path.startsWith('/reader/')) &&
      previous.path != next.path;
}

class AudioNavigationBoundary extends ConsumerStatefulWidget {
  const AudioNavigationBoundary({
    required this.section,
    required this.child,
    super.key,
  });

  final AudioNavigationSection section;
  final Widget child;

  @override
  ConsumerState<AudioNavigationBoundary> createState() =>
      _AudioNavigationBoundaryState();
}

class _AudioNavigationBoundaryState
    extends ConsumerState<AudioNavigationBoundary> {
  @override
  void initState() {
    super.initState();
    _applyEntryPolicy(widget.section);
  }

  @override
  void didUpdateWidget(covariant AudioNavigationBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section) {
      _applyEntryPolicy(widget.section);
    }
  }

  void _applyEntryPolicy(AudioNavigationSection section) {
    if (section == AudioNavigationSection.other) return;
    unawaited(_applyEntryPolicyAsync(section));
  }

  Future<void> _applyEntryPolicyAsync(AudioNavigationSection section) async {
    try {
      final audio = ref.read(audioControllerProvider.notifier);
      switch (section) {
        case AudioNavigationSection.other:
          return;
        case AudioNavigationSection.quran:
          await audio.pauseForQuranEntry();
          return;
        case AudioNavigationSection.dua:
          await audio.pauseForDuaEntry();
          return;
        case AudioNavigationSection.memorization:
          await audio.pauseForMemorizationEntry();
          return;
        case AudioNavigationSection.salah:
          await audio.pauseForSalahEntry();
          return;
      }
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'IQRO audio pause on ${section.name} entry',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
