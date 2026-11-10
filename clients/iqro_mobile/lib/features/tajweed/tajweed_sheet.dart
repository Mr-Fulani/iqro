import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/audio/audio_controller.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import '../audio/audio_models.dart';
import '../quran/word_range.dart';
import 'tajweed_models.dart';

/// Resolves the reciter whose timings play a word from a tajweed card.
typedef TajweedRecitation = Future<String?> Function();

/// What a tajweed card shows: one tapped word, or one rule from a legend.
sealed class TajweedSelection {
  const TajweedSelection();
}

final class TajweedWordSelection extends TajweedSelection {
  const TajweedWordSelection(this.verseKey, this.position);
  final String verseKey;
  final int position;
}

final class TajweedRuleSelection extends TajweedSelection {
  const TajweedRuleSelection(this.code);
  final String code;
}

/// Opens the card of a word or a rule over a page ([wholePage]) or an ayah.
Future<void> showTajweedSheet(
  BuildContext context, {
  required TajweedReference reference,
  required List<TajweedAyah> ayahs,
  required bool wholePage,
  required TajweedSelection selection,
  TajweedRecitation? recitation,
  ValueChanged<TajweedWordSelection>? onSelectWord,
}) => showIqroSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  // The tapped page stays in sight above a long card.
  builder: (context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .85,
    ),
    child: TajweedSheet(
      reference: reference,
      ayahs: ayahs,
      wholePage: wholePage,
      selection: selection,
      recitation: recitation,
      onSelectWord: onSelectWord,
    ),
  ),
);

/// The rules present on a page or in an ayah, as chips in reference order.
class TajweedLegend extends StatelessWidget {
  const TajweedLegend({
    required this.title,
    required this.rules,
    required this.onSelected,
    this.singleLine = false,
    super.key,
  });

  final String title;
  final List<TajweedRule> rules;
  final ValueChanged<String> onSelected;

  /// One scrolling row, for the little room under a Mushaf page.
  final bool singleLine;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final chips = <Widget>[
      for (final rule in rules)
        ActionChip(
          key: ValueKey('tajweed-chip-${rule.code}'),
          avatar: TajweedRuleDot(rule.color),
          label: Text(tajweedText(rule.name, locale)),
          visualDensity: VisualDensity.compact,
          onPressed: () => onSelected(rule.code),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.labelLarge),
        ),
        const SizedBox(height: 6),
        if (singleLine)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                for (final (index, chip) in chips.indexed) ...<Widget>[
                  if (index > 0) const SizedBox(width: 8),
                  chip,
                ],
              ],
            ),
          )
        else
          Wrap(spacing: 8, runSpacing: 8, children: chips),
      ],
    );
  }
}

class TajweedSheet extends ConsumerStatefulWidget {
  const TajweedSheet({
    required this.reference,
    required this.ayahs,
    required this.wholePage,
    required this.selection,
    this.recitation,
    this.onSelectWord,
    super.key,
  });

  final TajweedReference reference;
  final List<TajweedAyah> ayahs;
  final bool wholePage;
  final TajweedSelection selection;

  /// The chosen reciter of the listen button; without one the voices that
  /// stand in for a reciter play the words.
  final TajweedRecitation? recitation;

  /// Selects words on the page from a word card's word; null hides «Select
  /// from here». The card closes first.
  final ValueChanged<TajweedWordSelection>? onSelectWord;

  @override
  ConsumerState<TajweedSheet> createState() => _TajweedSheetState();
}

/// The voice of a word card: the chosen reciter's, or [standIn] when it has
/// no timing of the word.
typedef _WordAudio = ({
  String recitationId,
  AyahPlayback playback,
  Recitation? standIn,
});

class _TajweedSheetState extends ConsumerState<TajweedSheet> {
  late TajweedSelection _selection = widget.selection;
  late final AudioController _audio = ref.read(
    audioControllerProvider.notifier,
  );
  final _owner = Object();
  final _audioByWord = <String, Future<_WordAudio?>>{};
  late final Future<String?> _recitationId =
      widget.recitation?.call().catchError((Object _) => null) ??
      Future<String?>.value();
  String? _clipId;
  var _slow = false;
  var _audioFailed = false;

  @override
  void dispose() {
    final clip = _clipId;
    if (clip != null) unawaited(_audio.stopStandalone(clip, owner: _owner));
    super.dispose();
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
              );
      }),
    );
    final selection = _selection;
    final title = switch (selection) {
      TajweedWordSelection() => context.l10n.tajweedWordTitle,
      TajweedRuleSelection() => context.l10n.tajweedRuleTitle,
    };
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
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
          ...switch (selection) {
            TajweedWordSelection(:final verseKey, :final position) => _wordCard(
              context,
              verseKey,
              position,
              clip,
            ),
            TajweedRuleSelection(:final code) => _ruleCard(context, code),
          },
          if (widget.reference.pendingReview) ...<Widget>[
            const SizedBox(height: 20),
            Text(
              context.l10n.tajweedReviewNote,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _wordCard(
    BuildContext context,
    String verseKey,
    int position,
    ({String id, bool active, bool failed})? clip,
  ) {
    final ayah = widget.ayahs.where((a) => a.verseKey == verseKey).firstOrNull;
    final word = ayah?.word(position);
    if (ayah == null || word == null) return const <Widget>[];
    final locale = Localizations.localeOf(context).languageCode;
    final sections = <(String, String?)>{
      for (final fragment in word.rules)
        if (widget.reference.rule(fragment.code) != null)
          (fragment.code, fragment.variant),
    };
    return <Widget>[
      const SizedBox(height: 8),
      Text.rich(
        _highlighted(word.text, word.rules),
        textAlign: TextAlign.center,
        textDirection: TextDirection.rtl,
        style: _arabic(context, 44),
      ),
      Text(
        verseKey,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      _wordActions(context, ayah, word, verseKey, position, clip),
      for (final (code, variant) in sections) ...<Widget>[
        const Divider(height: 32),
        _ruleHeading(context, code, variant, locale),
        const SizedBox(height: 14),
        _label(context, context.l10n.tajweedWhyHere),
        Text.rich(
          _parts(
            ayah,
            word,
            word.rules.firstWhere(
              (item) => item.code == code && item.variant == variant,
            ),
          ),
          key: ValueKey('tajweed-why-$code'),
          textDirection: TextDirection.rtl,
          style: _arabic(context, 30),
        ),
        const SizedBox(height: 4),
        Text(
          tajweedText(_texts(code, variant).why, locale),
          style: _body(context),
        ),
        const SizedBox(height: 14),
        _label(context, context.l10n.tajweedHowToRead),
        Text(
          tajweedText(_texts(code, variant).how, locale),
          style: _body(context),
        ),
      ],
    ];
  }

  /// Listen to the word and select words from it: first on the card, so a
  /// long explanation does not push them out of sight. The listen button is
  /// on every card; with no voice for the words it says why instead.
  Widget _wordActions(
    BuildContext context,
    TajweedAyah ayah,
    TajweedWord word,
    String verseKey,
    int position,
    ({String id, bool active, bool failed})? clip,
  ) {
    final span = tajweedWordSpan(ayah, word);
    return FutureBuilder<_WordAudio?>(
      future: _wordAudio(ayah, span),
      builder: (context, snapshot) {
        final checking = snapshot.connectionState != ConnectionState.done;
        final audio = snapshot.data;
        final from = audio?.playback.words[span.first];
        final to = audio?.playback.words[span.last];
        final timing = from == null || to == null
            ? null
            : (start: from.start, end: to.end);
        final selectFrom = widget.onSelectWord;
        final id = audio == null
            ? null
            : 'tajweed:${audio.recitationId}:$verseKey:'
                  '${span.first}-${span.last}';
        final playing = id != null && clip?.id == id && clip!.active;
        final failed =
            id != null &&
            _clipId == id &&
            (_audioFailed || clip?.failed == true);
        final standIn = audio?.standIn;
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      key: const ValueKey('tajweed-listen'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: id == null || timing == null
                          ? null
                          : playing
                          ? () => _audio.stopStandalone(id, owner: _owner)
                          : () => _play(id, word, audio!.playback, timing),
                      icon: checking
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              playing
                                  ? Icons.stop_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                      label: Text(
                        playing
                            ? context.l10n.tajweedStop
                            : context.l10n.tajweedListen,
                      ),
                    ),
                  ),
                  if (selectFrom != null) ...<Widget>[
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const ValueKey('tajweed-select-from'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        onPressed: () {
                          Navigator.maybePop(context);
                          selectFrom(TajweedWordSelection(verseKey, position));
                        },
                        icon: const Icon(Icons.format_list_numbered_rtl),
                        label: Text(context.l10n.tajweedSelectFrom),
                      ),
                    ),
                  ],
                ],
              ),
              if (!checking && timing == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    context.l10n.tajweedAudioUnavailable,
                    key: const ValueKey('tajweed-audio-unavailable'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (timing != null) ...<Widget>[
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    FilterChip(
                      key: const ValueKey('tajweed-slow'),
                      label: Text(context.l10n.tajweedSlow),
                      tooltip: context.l10n.tajweedSlowLabel,
                      selected: _slow,
                      onSelected: (value) {
                        setState(() => _slow = value);
                        if (playing) {
                          unawaited(
                            _audio.setStandaloneSpeed(
                              id,
                              value ? .75 : 1,
                              owner: _owner,
                            ),
                          );
                        }
                      },
                    ),
                    if (standIn != null) ...<Widget>[
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          wordRangeVoiceNote(context, standIn),
                          key: const ValueKey('tajweed-voice'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              if (failed)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      context.l10n.tajweedAudioError,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _ruleCard(BuildContext context, String code) {
    final rule = widget.reference.rule(code);
    if (rule == null) return const <Widget>[];
    final locale = Localizations.localeOf(context).languageCode;
    return <Widget>[
      const SizedBox(height: 8),
      _ruleHeading(context, code, null, locale),
      const SizedBox(height: 14),
      _label(context, context.l10n.tajweedWhenApplies),
      Text(tajweedText(rule.why, locale), style: _body(context)),
      const SizedBox(height: 14),
      _label(context, context.l10n.tajweedHowToRead),
      Text(tajweedText(rule.how, locale), style: _body(context)),
      const SizedBox(height: 14),
      _label(
        context,
        widget.wholePage
            ? context.l10n.tajweedOccurrencesPage
            : context.l10n.tajweedOccurrencesAyah,
      ),
      for (final parts in tajweedOccurrences(widget.ayahs, code))
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text.rich(
            _spans(parts),
            textDirection: TextDirection.rtl,
            style: _arabic(context, 28),
          ),
          trailing: Text(parts.first.ayah.verseKey),
          onTap: () => setState(
            () => _selection = TajweedWordSelection(
              parts.first.ayah.verseKey,
              parts.first.word.position,
            ),
          ),
        ),
    ];
  }

  Widget _ruleHeading(
    BuildContext context,
    String code,
    String? variant,
    String locale,
  ) => TajweedRuleHeading(
    reference: widget.reference,
    code: code,
    variant: variant,
  );

  Widget _label(BuildContext context, String text) =>
      tajweedLabel(context, text);

  TajweedVariant _texts(String code, String? variant) {
    final rule = widget.reference.rule(code)!;
    return rule.variant(variant) ?? rule;
  }

  TextStyle? _body(BuildContext context) => tajweedBodyStyle(context);

  TextStyle _arabic(BuildContext context, double size) =>
      tajweedArabicStyle(context, size);

  TextSpan _highlighted(String text, Iterable<TajweedFragment> fragments) =>
      tajweedHighlighted(widget.reference, text, fragments);

  /// The tapped word with the letters of one of its rules, joined with the
  /// neighbouring word when the rule crosses into it.
  TextSpan _parts(
    TajweedAyah ayah,
    TajweedWord word,
    TajweedFragment fragment,
  ) {
    final own = word.rules.where(
      (item) => item.code == fragment.code && item.variant == fragment.variant,
    );
    return _spans([
      for (final part in tajweedJoinedParts(ayah, word, fragment))
        part.word == word
            ? (ayah: ayah, word: word, fragments: [...own])
            : part,
    ]);
  }

  TextSpan _spans(List<TajweedPart> parts) =>
      tajweedPartsSpan(widget.reference, parts);

  /// The voice of the words of [span]: the chosen reciter, else the voices
  /// that stand in for it in a selection of words. Null when none has the
  /// timings of its first and last words.
  Future<_WordAudio?> _wordAudio(
    TajweedAyah ayah,
    ({int first, int last}) span,
  ) {
    final repository = ref.read(audioRepositoryProvider);
    final key = '${ayah.verseKey}:${span.first}-${span.last}';
    return _audioByWord.putIfAbsent(key, () async {
      final chosen = await _recitationId;
      Future<AyahPlayback?> timed(String recitationId) async {
        try {
          final playback = await repository.ayahPlayback(
            recitationId: recitationId,
            surah: ayah.surah,
            ayah: ayah.ayah,
          );
          final from = playback.words[span.first];
          final to = playback.words[span.last];
          return from == null || to == null || to.end <= from.start
              ? null
              : playback;
        } on Object {
          return null;
        }
      }

      if (chosen != null) {
        final own = await timed(chosen);
        if (own != null) {
          return (recitationId: chosen, playback: own, standIn: null);
        }
      }
      final List<Recitation> recitations;
      try {
        recitations = await repository.recitationsForRole(
          AudioRecitationRole.ayahPlayback,
        );
      } on Object {
        unawaited(Future<void>(() => _audioByWord.remove(key)));
        return null;
      }
      for (final voice in wordTimingFallbackRecitations(recitations)) {
        if (voice.id == chosen) continue;
        final playback = await timed(voice.id);
        if (playback != null) {
          return (recitationId: voice.id, playback: playback, standIn: voice);
        }
      }
      return null;
    });
  }

  /// Plays exactly the word, after stopping whatever else was playing.
  Future<void> _play(
    String id,
    TajweedWord word,
    AyahPlayback playback,
    ({Duration start, Duration end}) timing,
  ) async {
    setState(() {
      _clipId = id;
      _audioFailed = false;
    });
    try {
      await _audio.loadStandalone(
        id: id,
        url: playback.track.url,
        title: word.text,
        album: 'IQRO · ${context.l10n.tajweedWordTitle}',
        contentType: 'tajweed',
        owner: _owner,
        speed: _slow ? .75 : 1,
        clipStart: timing.start,
        clipEnd: timing.end,
      );
    } on Object {
      if (mounted && _clipId == id) setState(() => _audioFailed = true);
    }
  }
}

/// A rule's name with its colour dot (and variant), then its Arabic name.
class TajweedRuleHeading extends StatelessWidget {
  const TajweedRuleHeading({
    required this.reference,
    required this.code,
    this.variant,
    super.key,
  });

  final TajweedReference reference;
  final String code;
  final String? variant;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final rule = reference.rule(code)!;
    final name = tajweedText(rule.name, locale);
    final variantName = rule.variant(variant)?.name;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            TajweedRuleDot(rule.color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                variantName == null
                    ? name
                    : '$name · ${tajweedText(variantName, locale)}',
                style: theme.textTheme.titleMedium,
              ),
            ),
          ],
        ),
        if (locale != 'ar' || rule.arabicName != name)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 22),
            child: Text(
              rule.arabicName,
              textDirection: TextDirection.rtl,
              style: tajweedArabicStyle(context, 20),
            ),
          ),
      ],
    );
  }
}

Widget tajweedLabel(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.only(bottom: 4),
  child: Text(text, style: Theme.of(context).textTheme.titleSmall),
);

/// Explanations quote letters and Uthmani marks such as ۥ.
TextStyle? tajweedBodyStyle(BuildContext context) => Theme.of(context)
    .textTheme
    .bodyMedium
    ?.copyWith(fontFamilyFallback: const [IqroTheme.arabicFontFamily]);

TextStyle tajweedArabicStyle(BuildContext context, double size) => TextStyle(
  fontFamily: IqroTheme.arabicFontFamily,
  fontSize: size,
  height: 1.7,
  color: IqroTheme.arabicInk(context),
);

/// A word with the letters of [fragments] in their rules' colours.
TextSpan tajweedHighlighted(
  TajweedReference reference,
  String text,
  Iterable<TajweedFragment> fragments,
) => TextSpan(
  children: <InlineSpan>[
    for (final run in tajweedRuns(text, fragments))
      TextSpan(
        text: run.text,
        style: run.code == null
            ? null
            : TextStyle(color: reference.rule(run.code!)?.color),
      ),
  ],
);

/// Words in reading order, each with its own rule letters coloured.
TextSpan tajweedPartsSpan(
  TajweedReference reference,
  List<TajweedPart> parts,
) => TextSpan(
  children: <InlineSpan>[
    for (final (index, part) in parts.indexed) ...<InlineSpan>[
      if (index > 0) const TextSpan(text: ' '),
      tajweedHighlighted(reference, part.word.text, part.fragments),
    ],
  ],
);

class TajweedRuleDot extends StatelessWidget {
  const TajweedRuleDot(this.color, {super.key});
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 12,
    child: DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ),
  );
}
