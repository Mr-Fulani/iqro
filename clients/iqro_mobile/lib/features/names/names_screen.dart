import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import '../courses/course_progress_store.dart';
import 'name_card_sheet.dart';
import 'names_models.dart';
import 'names_repository.dart';
import 'names_sound.dart';
import 'names_wheel.dart';

/// «Имена Аллаха»: the wheel, the name under it and the card of each name.
class NamesScreen extends ConsumerWidget {
  const NamesScreen({this.collection = namesDefaultCollection, super.key});

  final String collection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final names = ref.watch(namesProvider(collection));
    final document = names.valueOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.namesOfAllah)),
      body: document != null
          ? _Wheel(document: document)
          : names.error is NamesUnavailable
          ? _Soon()
          : names.hasError
          ? IqroAsyncError(
              title: context.l10n.networkError,
              onRetry: () => ref.invalidate(namesProvider(collection)),
            )
          : const IqroLoading(),
    );
  }
}

/// Nothing is published yet.
class _Soon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: const ValueKey('names-soon'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              context.l10n.namesSoonTitle,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.namesSoonText,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Wheel extends ConsumerStatefulWidget {
  const _Wheel({required this.document});

  final NamesDocument document;

  @override
  ConsumerState<_Wheel> createState() => _WheelState();
}

class _WheelState extends ConsumerState<_Wheel> {
  final _wheel = GlobalKey<NamesWheelState>();
  var _current = 0;
  var _arabicChosen = false;
  var _soundOn = true;
  DateTime _lastClick = DateTime.fromMillisecondsSinceEpoch(0);

  NamesDocument get _document => widget.document;

  String get _album => 'IQRO · ${context.l10n.namesOfAllah}';

  void _tick() {
    namesHaptic();
    if (!_soundOn) return;
    // The players cannot restart faster than this; a fast spin skips clicks.
    final now = DateTime.now();
    if (now.difference(_lastClick) < const Duration(milliseconds: 45)) return;
    _lastClick = now;
    ref.read(namesClickProvider).play();
  }

  /// The needle has stopped on a name: it counts as seen and the reciter
  /// says it.
  Future<void> _settled(int index) async {
    final name = _document.names[index];
    if (_soundOn) {
      unawaited(ref.read(namesVoiceProvider).play(name, album: _album));
    }
    final CourseProgress progress;
    try {
      progress = await ref.read(namesProgressProvider(_document.slug).future);
    } on Object {
      return;
    }
    // A name already seen or learned keeps its mark.
    if (progress.lessons.containsKey(name.slug)) return;
    await ref
        .read(namesProgressStoreProvider)
        .recordOpen(
          course: _document.slug,
          lesson: name.slug,
          contentVersion: _document.version,
        );
    ref.invalidate(namesProgressProvider(_document.slug));
  }

  Future<void> _openCard() => showNameCard(
    context,
    document: _document,
    index: _current,
    album: _album,
    onStep: (index) => _wheel.currentState?.goTo(index),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final names = _document.names;
    final name = names[_current];
    // The Arabic interface has one way to write a name.
    final arabicLocale = Localizations.localeOf(context).languageCode == 'ar';
    final arabicLabels = _arabicChosen || arabicLocale;
    final progress = ref
        .watch(namesProgressProvider(_document.slug))
        .valueOrNull;
    final seen = progress == null
        ? 0
        : names.where((item) => progress.lessons.containsKey(item.slug)).length;

    return LayoutBuilder(
      builder: (context, constraints) {
        // The wheel and the name under it fit one screen where they can.
        final side = (constraints.maxHeight - 330)
            .clamp(240.0, 520.0)
            .clamp(0.0, constraints.maxWidth - 32);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            children: <Widget>[
              // Large text puts the two switches on two lines.
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilterChip(
                      key: const ValueKey('names-sound'),
                      avatar: Icon(
                        _soundOn
                            ? Icons.volume_up_outlined
                            : Icons.volume_off_outlined,
                        size: 18,
                      ),
                      showCheckmark: false,
                      label: Text(l10n.namesSound),
                      selected: _soundOn,
                      onSelected: (value) {
                        if (!value) {
                          unawaited(ref.read(namesVoiceProvider).stop());
                        }
                        setState(() => _soundOn = value);
                      },
                    ),
                    if (!arabicLocale)
                      Semantics(
                        label: l10n.namesLabelsGroup,
                        container: true,
                        child: SegmentedButton<bool>(
                          key: const ValueKey('names-labels'),
                          showSelectedIcon: false,
                          style: const ButtonStyle(
                            visualDensity: VisualDensity.compact,
                          ),
                          segments: <ButtonSegment<bool>>[
                            ButtonSegment<bool>(
                              value: false,
                              label: Text(l10n.namesLabelsLocale),
                            ),
                            const ButtonSegment<bool>(
                              value: true,
                              label: Text('عربي'),
                            ),
                          ],
                          selected: <bool>{_arabicChosen},
                          onSelectionChanged: (value) =>
                              setState(() => _arabicChosen = value.first),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      l10n.namesSeen,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.namesSeenCount(seen, names.length),
                    key: const ValueKey('names-seen'),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ExcludeSemantics(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: seen / names.length,
                    minHeight: 6,
                    backgroundColor: context.iqroColors.panelSoft,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox.square(
                dimension: side,
                child: NamesWheel(
                  key: _wheel,
                  names: names,
                  arabicLabels: arabicLabels,
                  semanticLabel: l10n.namesWheelLabel,
                  nextLabel: l10n.namesNext,
                  onChanged: (index) => setState(() => _current = index),
                  onSettled: _settled,
                  onTick: _tick,
                  centre: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        '${name.position}',
                        key: const ValueKey('names-number'),
                        textScaler: TextScaler.noScaling,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontSize: side * .085,
                          height: 1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        l10n.namesOfTotal(names.length),
                        textScaler: TextScaler.noScaling,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Semantics(
                button: true,
                hint: l10n.namesOpenCard,
                child: IqroCard(
                  key: const ValueKey('names-readout'),
                  onTap: _openCard,
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      children: <Widget>[
                        Text(
                          name.arabic,
                          textDirection: TextDirection.rtl,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: IqroTheme.arabicFontFamily,
                            fontSize: 30,
                            height: 1.6,
                            color: scheme.primary,
                          ),
                        ),
                        // Arabic vowel marks hang below the line.
                        const SizedBox(height: 12),
                        if (name.transliteration.isNotEmpty)
                          Text(
                            name.transliteration,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        const SizedBox(height: 2),
                        Text(
                          name.meaning,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.namesOpenCard,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: scheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.namesHint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
