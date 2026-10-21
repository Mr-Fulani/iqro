import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/audio/playback_speed.dart';
import '../../core/design_system/iqro_repetition_counter.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import '../dua/dua_arabic.dart';
import 'salah_display.dart';
import 'salah_models.dart';

/// Media id of a formula in the shared player. One formula sounds the same
/// on every step, so its steps share the id.
String salahFormulaAudioId(SalahFormula formula) => 'salah:${formula.id}';

/// A formula of a step: Arabic text, transliteration, translation, a counter
/// of its repetitions and its recording in the shared player.
class SalahFormulaCard extends ConsumerStatefulWidget {
  const SalahFormulaCard({
    required this.formula,
    required this.display,
    required this.audioTitle,
    super.key,
  });

  final SalahFormula formula;
  final SalahDisplay display;

  /// Title of the recording on the lock screen and in the mini player.
  final String audioTitle;

  @override
  ConsumerState<SalahFormulaCard> createState() => _SalahFormulaCardState();
}

class _SalahFormulaCardState extends ConsumerState<SalahFormulaCard> {
  var _completed = 0;

  @override
  Widget build(BuildContext context) {
    final formula = widget.formula;
    final display = widget.display;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fontSize = ref.watch(
      appPreferencesProvider.select((value) => value.readerArabicFontSize),
    );
    final arabicStyle = theme.textTheme.headlineMedium?.copyWith(
      color: IqroTheme.arabicInk(context),
      fontFamily: IqroTheme.arabicFontFamily,
      fontWeight: FontWeight.normal,
      fontSize: fontSize,
      height: 1.9,
    );
    final transliteration = formula.transliteration;
    return IqroCard(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (display.arabicVisible && formula.arabic.isNotEmpty)
            for (final (index, part) in splitDuaArabic(
              formula.arabic,
            ).indexed) ...<Widget>[
              if (index > 0) SizedBox(height: part.opening ? 14 : 4),
              Text(
                part.text,
                key: index == 0 ? ValueKey('salah-arabic-${formula.id}') : null,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.center,
                style: part.opening
                    ? arabicStyle?.copyWith(
                        fontSize: fontSize * .78,
                        color: scheme.primary,
                      )
                    : arabicStyle,
              ),
            ],
          if (display.transliterationVisible &&
              transliteration != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              transliteration,
              key: ValueKey('salah-transliteration-${formula.id}'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
                height: 1.5,
              ),
            ),
          ],
          if (display.translationVisible &&
              formula.translation.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              formula.translation,
              key: ValueKey('salah-translation-${formula.id}'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: scheme.primary,
                height: 1.55,
              ),
            ),
          ],
          if (formula.repetitions > 1) ...<Widget>[
            const SizedBox(height: 16),
            Center(
              child: IqroRepetitionCounter(
                key: ValueKey('salah-counter-${formula.id}'),
                total: formula.repetitions,
                completed: _completed,
                onTap: () => setState(
                  () => _completed = advanceRepetitionCount(
                    _completed,
                    formula.repetitions,
                  ),
                ),
              ),
            ),
          ],
          if (formula.audio case final audio?) ...<Widget>[
            const SizedBox(height: 14),
            _FormulaAudioBar(
              formula: formula,
              audio: audio,
              title: widget.audioTitle,
            ),
          ],
        ],
      ),
    );
  }
}

/// The step's own voice-over, in the same bar as a formula's recording.
class SalahStepAudioBar extends StatelessWidget {
  const SalahStepAudioBar({
    required this.step,
    required this.audio,
    required this.title,
    super.key,
  });

  final SalahStep step;
  final SalahFormulaAudio audio;

  /// Title of the recording on the lock screen and in the mini player.
  final String title;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Text(
        context.l10n.salahStepAudio,
        style: Theme.of(context).textTheme.labelLarge,
      ),
      const SizedBox(height: 6),
      _FormulaAudioBar(
        // The media id `salah:step:<slug>` never meets a formula's.
        formula: SalahFormula(
          id: 'step:${step.slug}',
          arabic: '',
          translation: '',
          source: const SalahFormulaSource(kind: 'step'),
          audio: audio,
        ),
        audio: audio,
        title: title,
      ),
    ],
  );
}

typedef _AudioView = ({bool playing, bool loading, double speed});

/// Play and speed of one formula. Only this bar listens to the player, and
/// only to play, loading and speed, so position ticks rebuild nothing.
class _FormulaAudioBar extends ConsumerStatefulWidget {
  const _FormulaAudioBar({
    required this.formula,
    required this.audio,
    required this.title,
  });

  final SalahFormula formula;
  final SalahFormulaAudio audio;
  final String title;

  @override
  ConsumerState<_FormulaAudioBar> createState() => _FormulaAudioBarState();
}

class _FormulaAudioBarState extends ConsumerState<_FormulaAudioBar> {
  // Identifies this card's requests in the shared player.
  final Object _owner = Object();
  var _owned = false;
  var _failed = false;
  var _stopping = false;

  String get _id => salahFormulaAudioId(widget.formula);

  @override
  Widget build(BuildContext context) {
    final id = _id;
    final view = ref.watch(
      audioControllerProvider.select<_AudioView?>((state) {
        final standalone = state.standalone;
        if (standalone == null || standalone.mediaItem.id != id) return null;
        return (
          playing: standalone.playing,
          loading: standalone.loading,
          speed: standalone.speed,
        );
      }),
    );
    final endMs = widget.audio.endMs;
    if (endMs != null) {
      // A formula cut from a longer recording stops at its end.
      ref.listen<Duration?>(
        audioControllerProvider.select((state) {
          final standalone = state.standalone;
          return standalone != null &&
                  standalone.mediaItem.id == id &&
                  standalone.playing
              ? standalone.position
              : null;
        }),
        (previous, position) {
          if (_owned && position != null && position.inMilliseconds >= endMs) {
            unawaited(_stopAtEnd());
          }
        },
      );
    }
    final owned = _owned && view != null;
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: .7),
        borderRadius: BorderRadius.circular(22),
      ),
      child: IconButtonTheme(
        data: IconButtonThemeData(
          style: IconButton.styleFrom(foregroundColor: scheme.primary),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: _failed
                  ? IconButton(
                      tooltip: context.l10n.retry,
                      onPressed: () => unawaited(_play(reload: true)),
                      icon: Icon(Icons.refresh, color: scheme.error),
                    )
                  : view?.loading == true
                  ? const Center(
                      child: SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      key: ValueKey('salah-play-${widget.formula.id}'),
                      tooltip: view?.playing == true
                          ? context.l10n.pause
                          : context.l10n.play,
                      onPressed: () => unawaited(_play(reload: false)),
                      icon: Icon(
                        view?.playing == true ? Icons.pause : Icons.play_arrow,
                      ),
                    ),
            ),
            Expanded(
              child: TextButton(
                onPressed: owned
                    ? () => unawaited(
                        ref
                            .read(audioControllerProvider.notifier)
                            .setStandaloneSpeed(
                              id,
                              nextPlaybackSpeed(view.speed),
                              owner: _owner,
                            ),
                      )
                    : null,
                child: Text(
                  '${playbackSpeedLabel(owned ? view.speed : 1)}×',
                  semanticsLabel: context.l10n.speed,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _play({required bool reload}) async {
    final controller = ref.read(audioControllerProvider.notifier);
    final id = _id;
    final current = ref.read(audioControllerProvider).standalone;
    final album = 'IQRO · ${context.l10n.salahTitle}';
    try {
      if (!reload && _owned && current?.mediaItem.id == id) {
        await controller.toggleStandalone(id, owner: _owner);
        return;
      }
      _owned = true;
      if (_failed) setState(() => _failed = false);
      final startMs = widget.audio.startMs ?? 0;
      await controller.loadStandalone(
        id: id,
        url: widget.audio.url,
        title: widget.title,
        album: album,
        contentType: 'salah',
        extras: <String, dynamic>{'formula': widget.formula.id},
        autoplay: startMs <= 0,
        owner: _owner,
      );
      if (startMs > 0) {
        await controller.seekStandalone(
          id,
          Duration(milliseconds: startMs),
          owner: _owner,
        );
        await controller.toggleStandalone(id, owner: _owner);
      }
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _stopAtEnd() async {
    // Ticks keep coming until the pause lands; one stop is enough.
    if (_stopping) return;
    _stopping = true;
    try {
      final controller = ref.read(audioControllerProvider.notifier);
      await controller.toggleStandalone(_id, owner: _owner);
      await controller.seekStandalone(
        _id,
        Duration(milliseconds: widget.audio.startMs ?? 0),
        owner: _owner,
      );
    } finally {
      _stopping = false;
    }
  }
}
