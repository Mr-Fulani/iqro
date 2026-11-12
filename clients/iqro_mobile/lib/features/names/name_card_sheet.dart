import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import '../courses/account_progress_sync.dart';
import 'names_models.dart';
import 'names_sound.dart';

/// The card of one name as a bottom sheet. [onStep] turns the wheel to the
/// name the card moved to.
Future<void> showNameCard(
  BuildContext context, {
  required NamesDocument document,
  required int index,
  required String album,
  required ValueChanged<int> onStep,
}) => showIqroSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (context) => _NameCard(
    document: document,
    initialIndex: index,
    album: album,
    onStep: onStep,
  ),
);

class _NameCard extends ConsumerStatefulWidget {
  const _NameCard({
    required this.document,
    required this.initialIndex,
    required this.album,
    required this.onStep,
  });

  final NamesDocument document;
  final int initialIndex;
  final String album;
  final ValueChanged<int> onStep;

  @override
  ConsumerState<_NameCard> createState() => _NameCardState();
}

class _NameCardState extends ConsumerState<_NameCard> {
  late var _index = widget.initialIndex;

  NamesDocument get _document => widget.document;

  void _step(int delta) {
    final count = _document.names.length;
    setState(() => _index = (_index + delta + count) % count);
    widget.onStep(_index);
  }

  Future<void> _setLearned(DivineName name, bool learned) async {
    final store = ref.read(namesProgressStoreProvider);
    await (learned ? store.markDone : store.unmark)(
      course: _document.slug,
      lesson: name.slug,
      contentVersion: _document.version,
    );
    ref.invalidate(namesProgressProvider(_document.slug));
    unawaited(
      ref
          .read(accountProgressSyncProvider)
          .sync(AccountProgressSync.names, _document.slug),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final names = _document.names;
    final count = names.length;
    final name = names[_index];
    final voice = ref.watch(namesVoiceProvider);
    final learned =
        ref
            .watch(namesProgressProvider(_document.slug))
            .valueOrNull
            ?.isDone(name.slug) ??
        false;
    final sounding = ref.watch(
      audioControllerProvider.select((state) {
        final clip = state.standalone;
        return clip != null &&
            clip.mediaItem.id == NamesVoice.clipId(name) &&
            (clip.playing || clip.loading);
      }),
    );
    final ayah = name.ayah;
    final source = <String>[
      name.tafsirSource,
      name.tafsirRef,
    ].where((part) => part.isNotEmpty).join(', ');
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final heading = theme.textTheme.labelMedium?.copyWith(
      color: scheme.onSurfaceVariant,
      letterSpacing: .8,
    );

    return SingleChildScrollView(
      key: const ValueKey('names-card'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(l10n.namesCardNumber(name.position, count), style: heading),
          const SizedBox(height: 12),
          Container(
            constraints: const BoxConstraints(minHeight: 160),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: context.iqroColors.panelSoft,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.iqroColors.line),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                name.arabic,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontFamily: IqroTheme.arabicFontFamily,
                  fontSize: 54,
                  height: 1.7,
                  color: scheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            name.label,
            key: const ValueKey('names-card-title'),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            name.meaning,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: <Widget>[
              if (name.hasVoice)
                FilledButton.icon(
                  key: const ValueKey('names-listen'),
                  onPressed: sounding
                      ? voice.stop
                      : () => voice.play(name, album: widget.album),
                  icon: Icon(
                    sounding ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  ),
                  label: Text(sounding ? l10n.namesStop : l10n.namesListen),
                ),
              if (learned)
                FilledButton.tonalIcon(
                  key: const ValueKey('names-learned'),
                  onPressed: () => unawaited(_setLearned(name, false)),
                  icon: const Icon(Icons.check_rounded),
                  label: Text(l10n.namesLearned),
                )
              else
                OutlinedButton(
                  key: const ValueKey('names-learned'),
                  onPressed: () => unawaited(_setLearned(name, true)),
                  child: Text(l10n.namesMarkLearned),
                ),
            ],
          ),
          if (name.hasVoice)
            ListenableBuilder(
              listenable: voice,
              builder: (context, _) => voice.missing == name.slug
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          l10n.namesNoRecording,
                          textAlign: TextAlign.center,
                          style: muted,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          const Divider(height: 32),
          Text(l10n.namesTafsir.toUpperCase(), style: heading),
          const SizedBox(height: 6),
          Text(
            name.tafsir,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.55),
          ),
          if (source.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(l10n.namesSource(source), style: muted),
          ],
          if (ayah != null) ...<Widget>[
            const Divider(height: 32),
            Text(l10n.namesInQuran.toUpperCase(), style: heading),
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ActionChip(
                key: const ValueKey('names-ayah'),
                label: Text(
                  l10n.tajweedCourseAyahReference(ayah.surah, ayah.ayah),
                ),
                onPressed: () {
                  final router = GoRouter.of(context);
                  Navigator.of(context).pop();
                  unawaited(
                    router.push('/reader/${ayah.surah}?ayah=${ayah.ayah}'),
                  );
                },
              ),
            ),
          ],
          if (_document.listSource.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Text(l10n.namesListSource(_document.listSource), style: muted),
          ],
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: _Neighbour(
                  key: const ValueKey('names-card-previous'),
                  caption: l10n.namesPrevious,
                  name: names[(_index - 1 + count) % count].label,
                  end: false,
                  onTap: () => _step(-1),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Neighbour(
                  key: const ValueKey('names-card-next'),
                  caption: l10n.namesFollowing,
                  name: names[(_index + 1) % count].label,
                  end: true,
                  onTap: () => _step(1),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Neighbour extends StatelessWidget {
  const _Neighbour({
    required this.caption,
    required this.name,
    required this.end,
    required this.onTap,
    super.key,
  });

  final String caption;
  final String name;
  final bool end;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IqroCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: end
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            caption,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
