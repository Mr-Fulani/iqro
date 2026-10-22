import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/audio/audio_controller.dart';
import '../../core/design_system/iqro_step_flow.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import '../audio/audio_models.dart';
import '../quran/foundation_mushaf_page.dart';
import '../quran/mushaf_edition.dart';
import 'tajweed_models.dart';
import 'tajweed_sheet.dart';

/// A word of an ayah in its QF Mushaf 19 page font.
typedef TajweedGlyph = ({
  Map<String, Object?> word,
  String fontFamily,

  /// `position_in_verse`; null for the ayah-end marker.
  int? position,
});

/// The glyphs of one ayah on its QF Mushaf 19 page, in reading order.
final tajweedAyahGlyphsProvider = FutureProvider.autoDispose
    .family<List<TajweedGlyph>, ({int page, String verseKey})>((
      ref,
      key,
    ) async {
      final repository = ref.watch(
        mushafRepositoryProvider(MushafIdentity.defaultEdition),
      );
      final page = (await repository.mushafPage(key.page)).foundation;
      if (page == null ||
          page.sourceId != tajweedMushafId ||
          page.rendering['mode'] == 'word-images') {
        throw const FormatException('The page has no tajweed font');
      }
      final resources = await loadFoundationPageResources(
        page,
        repository.foundationAsset,
      );
      final family = resources.fontFamily;
      resources.dispose();
      if (family == null) throw const FormatException('No page font');
      return [
        for (final word in page.words)
          if (word['verse_key'] == key.verseKey)
            (
              word: word,
              fontFamily: family,
              position: word['char_type_name'] == 'word'
                  ? (word['position_in_verse'] as num?)?.toInt()
                  : null,
            ),
      ];
    });

/// Opens the step-by-step tajweed breakdown of [ayah].
Future<void> showTajweedBreakdown(
  BuildContext context, {
  required TajweedReference reference,
  required TajweedAyah ayah,
  TajweedRecitation? recitation,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .9,
    child: TajweedBreakdownSheet(
      reference: reference,
      ayah: ayah,
      recitation: recitation,
    ),
  ),
);

/// The tajweed of one ayah, rule by rule in reading order, on the steps of
/// a Salah lesson: the rule's place lit in the ayah, why it applies and how
/// to read it, its sound; then a summary of the rules met, each with its card.
class TajweedBreakdownSheet extends ConsumerStatefulWidget {
  const TajweedBreakdownSheet({
    required this.reference,
    required this.ayah,
    this.recitation,
    super.key,
  });

  final TajweedReference reference;
  final TajweedAyah ayah;

  /// Null hides the listen buttons.
  final TajweedRecitation? recitation;

  @override
  ConsumerState<TajweedBreakdownSheet> createState() =>
      _TajweedBreakdownSheetState();
}

typedef _AyahAudio = ({String recitationId, AyahPlayback playback});

class _TajweedBreakdownSheetState extends ConsumerState<TajweedBreakdownSheet> {
  late final List<TajweedStep> _steps = tajweedSteps(
    widget.ayah,
    widget.reference,
  );
  late final _summary = tajweedStepRules(_steps);

  // The pages are the steps and, after them, the summary.
  final _pager = IqroStepController();
  // Kept for dispose, when ref can no longer be read.
  late final AudioController _audio;

  // The breakdown owns its clips in the shared player: a step change stops
  // them, as in a Salah lesson, and they start over on the next play.
  final _owner = Object();
  late final Future<_AyahAudio?> _ayahAudio = _loadAudio();
  String? _rule;
  var _slow = false;
  var _audioFailed = false;

  int get _pageCount => _steps.length + 1;

  @override
  void initState() {
    super.initState();
    _audio = ref.read(audioControllerProvider.notifier);
  }

  @override
  void dispose() {
    unawaited(_audio.stopStandaloneOf(_owner));
    _pager.dispose();
    super.dispose();
  }

  Future<_AyahAudio?> _loadAudio() async {
    try {
      final recitationId = await widget.recitation?.call();
      if (recitationId == null) return null;
      final playback = await ref
          .read(audioRepositoryProvider)
          .ayahPlayback(
            recitationId: recitationId,
            surah: widget.ayah.surah,
            ayah: widget.ayah.ayah,
          );
      return (recitationId: recitationId, playback: playback);
    } on Object {
      // Without timings the breakdown simply has nothing to play.
      return null;
    }
  }

  void _onPageChanged(int index) {
    unawaited(_audio.stopStandaloneOf(_owner));
    setState(() => _audioFailed = false);
  }

  void _goTo(int index) => _pager.goTo(context, index, _pageCount);

  void _next() {
    final index = _pager.index.value;
    if (index >= _pageCount - 1) {
      unawaited(Navigator.maybePop(context));
    } else {
      _goTo(index + 1);
    }
  }

  void _previous() => _goTo(_pager.index.value - 1);

  String _clipId(_AyahAudio audio, String part) =>
      'tajweed:${audio.recitationId}:${widget.ayah.verseKey}:$part';

  Future<void> _play(
    _AyahAudio audio,
    String id,
    ({Duration start, Duration end}) clip,
  ) async {
    setState(() => _audioFailed = false);
    try {
      await _audio.loadStandalone(
        id: id,
        url: audio.playback.track.url,
        title: widget.ayah.verseKey,
        album: 'IQRO · ${context.l10n.tajweedBreakdown}',
        contentType: 'tajweed',
        owner: _owner,
        speed: _slow ? .75 : 1,
        clipStart: clip.start,
        clipEnd: clip.end,
      );
    } on Object {
      if (mounted) setState(() => _audioFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clip = ref.watch(
      audioControllerProvider.select((state) {
        final standalone = state.standalone;
        return standalone == null
            ? null
            : (
                id: standalone.mediaItem.id,
                active: standalone.playing || standalone.loading,
                failed: standalone.error != null,
                position: standalone.position,
              );
      }),
    );
    final theme = Theme.of(context);
    return FutureBuilder<_AyahAudio?>(
      future: _ayahAudio,
      builder: (context, snapshot) {
        final audio = snapshot.data;
        final ayahId = audio == null ? null : _clipId(audio, 'ayah');
        final ayahClip = audio?.playback.start == null
            ? null
            : (start: audio!.playback.start!, end: audio.playback.end!);
        final readingAyah = clip != null && clip.id == ayahId && clip.active;
        final reading = readingAyah && ayahClip != null
            ? tajweedTimedPosition(
                audio!.playback.words,
                ayahClip.start + clip.position,
              )
            : null;
        final failed =
            _audioFailed ||
            (clip != null &&
                clip.failed &&
                audio != null &&
                clip.id.startsWith(_clipId(audio, '')));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 4, 0),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text.rich(
                        TextSpan(
                          text: context.l10n.tajweedBreakdown,
                          children: <InlineSpan>[
                            TextSpan(
                              text: '  ${widget.ayah.verseKey}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.tajweedClose,
                    onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ValueListenableBuilder<int>(
                valueListenable: _pager.index,
                builder: (context, index, _) => _AyahLine(
                  ayah: widget.ayah,
                  reference: widget.reference,
                  step: _rule == null && index < _steps.length
                      ? _steps[index]
                      : null,
                  reading: reading,
                ),
              ),
            ),
            if (audio != null && ayahClip != null)
              Center(
                child: TextButton.icon(
                  key: const ValueKey('tajweed-play-ayah'),
                  onPressed: readingAyah
                      ? () => _audio.stopStandalone(ayahId!, owner: _owner)
                      : () => _play(audio, ayahId!, ayahClip),
                  icon: Icon(
                    readingAyah ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  ),
                  label: Text(
                    readingAyah
                        ? context.l10n.tajweedStop
                        : context.l10n.tajweedPlayAyah,
                  ),
                ),
              ),
            if (failed)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    context.l10n.tajweedAudioError,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ),
            if (_rule == null)
              ValueListenableBuilder<int>(
                valueListenable: _pager.index,
                builder: (context, index, _) => _Progress(
                  label: index < _steps.length
                      ? context.l10n.tajweedStepOf(index + 1, _steps.length)
                      : context.l10n.tajweedSummary,
                  spoken: index < _steps.length
                      ? tajweedText(
                          widget.reference.rule(_steps[index].code)!.name,
                          Localizations.localeOf(context).languageCode,
                        )
                      : null,
                  value: (index + 1) / _pageCount,
                ),
              ),
            Expanded(
              child: Stack(
                children: <Widget>[
                  // The pager stays attached behind a rule card, so the
                  // summary is where the card was opened from.
                  Visibility(
                    visible: _rule == null,
                    maintainState: true,
                    maintainAnimation: true,
                    child: IqroStepPager(
                      controller: _pager,
                      keyPrefix: 'tajweed',
                      itemCount: _pageCount,
                      nextLabel: context.l10n.tajweedNextStep,
                      previousLabel: context.l10n.tajweedPreviousStep,
                      onNext: _next,
                      onPrevious: _previous,
                      onPageChanged: _onPageChanged,
                      itemBuilder: (context, index) => index < _steps.length
                          ? _StepPage(
                              key: ValueKey('tajweed-step-$index'),
                              reference: widget.reference,
                              step: _steps[index],
                              listen: _listenRow(context, audio, clip, index),
                            )
                          : _SummaryPage(
                              key: const ValueKey('tajweed-summary'),
                              reference: widget.reference,
                              rules: _summary,
                              onRule: (code) => setState(() => _rule = code),
                              onRestart: () => _goTo(0),
                            ),
                    ),
                  ),
                  if (_rule case final code?)
                    _RuleCard(
                      reference: widget.reference,
                      code: code,
                      steps: [
                        for (final rule in _summary)
                          if (rule.code == code) ...rule.steps,
                      ],
                      allSteps: _steps,
                      onBack: () => setState(() => _rule = null),
                      onStep: (index) {
                        setState(() => _rule = null);
                        _pager.pages.jumpToPage(index);
                      },
                    ),
                ],
              ),
            ),
            if (_rule == null)
              ValueListenableBuilder<int>(
                valueListenable: _pager.index,
                builder: (context, index, _) => IqroStepButtons(
                  keyPrefix: 'tajweed',
                  isFirst: index == 0,
                  isLast: index == _pageCount - 1,
                  onBack: _previous,
                  onNext: _next,
                  backLabel: context.l10n.tajweedPrevious,
                  nextLabel: index == _steps.length - 1
                      ? context.l10n.tajweedToSummary
                      : context.l10n.tajweedNext,
                  finishLabel: context.l10n.tajweedDone,
                ),
              ),
            if (widget.reference.pendingReview)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  context.l10n.tajweedReviewNote,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// «Listen» and «0.75×» for a step, when its words are timed.
  Widget? _listenRow(
    BuildContext context,
    _AyahAudio? audio,
    ({String id, bool active, bool failed, Duration position})? clip,
    int index,
  ) {
    final timing = audio == null
        ? null
        : tajweedStepTiming(audio.playback.words, _steps[index]);
    if (audio == null || timing == null) return null;
    final id = _clipId(audio, 'step$index');
    final playing = clip?.id == id && clip!.active;
    return Row(
      children: <Widget>[
        Expanded(
          child: FilledButton.tonalIcon(
            key: const ValueKey('tajweed-listen'),
            onPressed: playing
                ? () => _audio.stopStandalone(id, owner: _owner)
                : () => _play(audio, id, timing),
            icon: Icon(playing ? Icons.stop_rounded : Icons.play_arrow_rounded),
            label: Text(
              playing ? context.l10n.tajweedStop : context.l10n.tajweedListen,
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilterChip(
          key: const ValueKey('tajweed-slow'),
          label: Text(context.l10n.tajweedSlow),
          tooltip: context.l10n.tajweedSlowLabel,
          selected: _slow,
          onSelected: (value) {
            setState(() => _slow = value);
            final current = clip?.id;
            if (clip != null && clip.active && current != null) {
              unawaited(
                _audio.setStandaloneSpeed(
                  current,
                  value ? .75 : 1,
                  owner: _owner,
                ),
              );
            }
          },
        ),
      ],
    );
  }
}

/// The ayah in its Mushaf glyphs with the step's words lit, and the word the
/// reciter is on while the whole ayah plays.
class _AyahLine extends ConsumerWidget {
  const _AyahLine({
    required this.ayah,
    required this.reference,
    required this.step,
    required this.reading,
  });

  final TajweedAyah ayah;
  final TajweedReference reference;
  final TajweedStep? step;
  final int? reading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final glyphs = ref
        .watch(
          tajweedAyahGlyphsProvider((page: ayah.page, verseKey: ayah.verseKey)),
        )
        .valueOrNull;
    if (glyphs == null || glyphs.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final lit = {...?step?.parts.map((part) => part.word.position)};
    final color = step == null ? null : reference.rule(step!.code)?.color;
    final style = TextStyle(
      fontSize: 26,
      height: 1.8,
      color: IqroTheme.arabicInk(context),
    );
    return ExcludeSemantics(
      child: Container(
        key: const ValueKey('tajweed-ayah-line'),
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Wrap(
          textDirection: TextDirection.rtl,
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 2,
          children: <Widget>[
            for (final glyph in glyphs)
              AnimatedContainer(
                key: glyph.position == null
                    ? null
                    : ValueKey('tajweed-glyph-${glyph.position}'),
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: glyph.position != null && glyph.position == reading
                      ? scheme.primaryContainer
                      : lit.contains(glyph.position) && color != null
                      ? color.withValues(alpha: .18)
                      : null,
                  border: lit.contains(glyph.position) && color != null
                      ? Border(bottom: BorderSide(color: color, width: 2))
                      : null,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text.rich(
                  foundationWordSpan(
                    glyph.word,
                    style.copyWith(fontFamily: glyph.fontFamily),
                  ),
                  textDirection: TextDirection.rtl,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// «3 of 7» over a progress bar; screen readers hear the step's rule too.
class _Progress extends StatelessWidget {
  const _Progress({
    required this.label,
    required this.spoken,
    required this.value,
  });

  final String label;
  final String? spoken;
  final double value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Semantics(
        liveRegion: true,
        label: spoken == null ? label : '$label: $spoken',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              key: const ValueKey('tajweed-step-label'),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: value,
              minHeight: 4,
              borderRadius: BorderRadius.circular(4),
              backgroundColor: context.iqroColors.line,
            ),
          ],
        ),
      ),
    );
  }
}

class _StepPage extends StatelessWidget {
  const _StepPage({
    required this.reference,
    required this.step,
    required this.listen,
    super.key,
  });

  final TajweedReference reference;
  final TajweedStep step;
  final Widget? listen;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final rule = reference.rule(step.code)!;
    final texts = rule.variant(step.variant) ?? rule;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TajweedRuleHeading(
            reference: reference,
            code: step.code,
            variant: step.variant,
          ),
          const SizedBox(height: 8),
          Text.rich(
            tajweedPartsSpan(reference, step.parts),
            key: const ValueKey('tajweed-step-word'),
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            style: tajweedArabicStyle(context, 36),
          ),
          const SizedBox(height: 8),
          tajweedLabel(context, context.l10n.tajweedWhyHere),
          Text(
            tajweedText(texts.why, locale),
            style: tajweedBodyStyle(context),
          ),
          const SizedBox(height: 14),
          tajweedLabel(context, context.l10n.tajweedHowToRead),
          Text(
            tajweedText(texts.how, locale),
            style: tajweedBodyStyle(context),
          ),
          if (listen case final row?) ...<Widget>[
            const SizedBox(height: 20),
            row,
          ],
        ],
      ),
    );
  }
}

class _SummaryPage extends StatelessWidget {
  const _SummaryPage({
    required this.reference,
    required this.rules,
    required this.onRule,
    required this.onRestart,
    super.key,
  });

  final TajweedReference reference;
  final List<({String code, List<int> steps})> rules;
  final ValueChanged<String> onRule;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(
              context.l10n.tajweedSummaryTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final item in rules)
                if (reference.rule(item.code) case final rule?)
                  ActionChip(
                    key: ValueKey('tajweed-summary-${item.code}'),
                    avatar: TajweedRuleDot(rule.color),
                    label: Text(tajweedText(rule.name, locale)),
                    onPressed: () => onRule(item.code),
                  ),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const ValueKey('tajweed-restart'),
            onPressed: onRestart,
            icon: const Icon(Icons.replay_rounded),
            label: Text(context.l10n.tajweedRestart),
          ),
        ],
      ),
    );
  }
}

/// A rule's card from the summary; its places in the ayah lead to their steps.
class _RuleCard extends StatelessWidget {
  const _RuleCard({
    required this.reference,
    required this.code,
    required this.steps,
    required this.allSteps,
    required this.onBack,
    required this.onStep,
  });

  final TajweedReference reference;
  final String code;
  final List<int> steps;
  final List<TajweedStep> allSteps;
  final VoidCallback onBack;
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final rule = reference.rule(code)!;
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SingleChildScrollView(
        key: const ValueKey('tajweed-rule-card'),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('tajweed-back-to-summary'),
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
                label: Text(context.l10n.tajweedBackToSummary),
              ),
            ),
            TajweedRuleHeading(reference: reference, code: code),
            const SizedBox(height: 14),
            tajweedLabel(context, context.l10n.tajweedWhenApplies),
            Text(
              tajweedText(rule.why, locale),
              style: tajweedBodyStyle(context),
            ),
            const SizedBox(height: 14),
            tajweedLabel(context, context.l10n.tajweedHowToRead),
            Text(
              tajweedText(rule.how, locale),
              style: tajweedBodyStyle(context),
            ),
            const SizedBox(height: 14),
            tajweedLabel(context, context.l10n.tajweedOccurrencesAyah),
            for (final index in steps)
              ListTile(
                key: ValueKey('tajweed-occurrence-$index'),
                contentPadding: EdgeInsets.zero,
                title: Text.rich(
                  tajweedPartsSpan(reference, allSteps[index].parts),
                  textDirection: TextDirection.rtl,
                  style: tajweedArabicStyle(context, 28),
                ),
                trailing: Text(context.l10n.tajweedStepNumber(index + 1)),
                onTap: () => onStep(index),
              ),
          ],
        ),
      ),
    );
  }
}
