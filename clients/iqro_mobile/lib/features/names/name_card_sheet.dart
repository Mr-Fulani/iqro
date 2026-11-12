import 'dart:async';
import 'dart:math' as math;

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
  late final NamesVoice _voice = ref.read(namesVoiceProvider);

  @override
  void initState() {
    super.initState();
    // «Слушать» follows the recording as it starts and ends.
    _voice.addListener(_voiceChanged);
  }

  @override
  void dispose() {
    _voice.removeListener(_voiceChanged);
    super.dispose();
  }

  void _voiceChanged() {
    if (mounted) setState(() {});
  }

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
    final voice = _voice;
    final learned =
        ref
            .watch(namesProgressProvider(_document.slug))
            .valueOrNull
            ?.isDone(name.slug) ??
        false;
    final canSay = voice.canSay(name);
    final reciting = ref.watch(
      audioControllerProvider.select((state) {
        final clip = state.standalone;
        return clip != null &&
            clip.mediaItem.id == NamesVoice.clipId(name) &&
            (clip.playing || clip.loading);
      }),
    );
    final sounding = reciting || voice.playing == name.slug;
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

    final iqro = context.iqroColors;
    // Gold on the dark panel, the same in both themes.
    const ivory = Color(0xFFF5EBD3);
    const gold = Color(0xFFE2B665);

    return SingleChildScrollView(
      key: const ValueKey('names-card'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // The name in calligraphy on a dark panel with a star ornament.
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[iqro.inkSoft, iqro.ink],
                ),
                // Keeps the panel apart from a dark sheet.
                border: Border.all(color: gold.withValues(alpha: .3)),
                borderRadius: BorderRadius.circular(24),
              ),
              child: CustomPaint(
                painter: const _StarOrnament(gold),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                  child: Column(
                    children: <Widget>[
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: gold.withValues(alpha: .55),
                            ),
                          ),
                          child: Text(
                            l10n.namesCardNumber(name.position, count),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: gold,
                              letterSpacing: .6,
                            ),
                          ),
                        ),
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 150),
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              name.arabic,
                              textDirection: TextDirection.rtl,
                              style: const TextStyle(
                                fontFamily: IqroTheme.arabicFontFamily,
                                fontSize: 60,
                                height: 1.7,
                                color: ivory,
                                shadows: <Shadow>[
                                  Shadow(
                                    color: Color(0x66000000),
                                    blurRadius: 12,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Text(
                        name.label,
                        key: const ValueKey('names-card-title'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const _Divider(gold),
                      const SizedBox(height: 8),
                      Text(
                        name.meaning,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: gold,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: <Widget>[
              if (canSay)
                FilledButton.icon(
                  key: const ValueKey('names-listen'),
                  onPressed: sounding
                      ? voice.stop
                      : () => voice.play(
                          name,
                          album: widget.album,
                          language: Localizations.localeOf(
                            context,
                          ).languageCode,
                        ),
                  icon: Icon(
                    sounding ? Icons.stop_rounded : Icons.volume_up_rounded,
                  ),
                  label: Text(sounding ? l10n.namesStop : l10n.namesListen),
                ),
              if (learned)
                FilledButton.tonalIcon(
                  key: const ValueKey('names-learned'),
                  onPressed: () => unawaited(_setLearned(name, false)),
                  icon: const Icon(Icons.check_circle_rounded),
                  label: Text(l10n.namesLearned),
                )
              else
                OutlinedButton.icon(
                  key: const ValueKey('names-learned'),
                  onPressed: () => unawaited(_setLearned(name, true)),
                  icon: const Icon(Icons.radio_button_unchecked_rounded),
                  label: Text(l10n.namesMarkLearned),
                ),
            ],
          ),
          if (canSay)
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
          const SizedBox(height: 20),
          // The explanation reads as a quotation from its book.
          Container(
            decoration: BoxDecoration(
              color: iqro.panelSoft,
              borderRadius: BorderRadius.circular(20),
            ),
            clipBehavior: Clip.antiAlias,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Container(width: 4, color: iqro.gold),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Icon(
                                Icons.menu_book_rounded,
                                size: 18,
                                color: iqro.gold,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                l10n.namesTafsir.toUpperCase(),
                                style: heading,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            name.tafsir,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              height: 1.55,
                            ),
                          ),
                          if (source.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 10),
                            Text(
                              l10n.namesSource(source),
                              style: muted?.copyWith(
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (ayah != null) ...<Widget>[
            const SizedBox(height: 12),
            Semantics(
              button: true,
              child: IqroCard(
                key: const ValueKey('names-ayah'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                onTap: () {
                  final router = GoRouter.of(context);
                  Navigator.of(context).pop();
                  unawaited(
                    router.push('/reader/${ayah.surah}?ayah=${ayah.ayah}'),
                  );
                },
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.auto_stories_rounded,
                        size: 20,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(l10n.namesInQuran.toUpperCase(), style: heading),
                          const SizedBox(height: 2),
                          Text(
                            l10n.tajweedCourseAyahReference(
                              ayah.surah,
                              ayah.ayah,
                            ),
                            style: theme.textTheme.titleSmall,
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_document.listSource.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              l10n.namesListSource(_document.listSource),
              textAlign: TextAlign.center,
              style: muted,
            ),
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

/// The eight-pointed star behind the name: two squares and two rings.
class _StarOrnament extends CustomPainter {
  const _StarOrnament(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height * .42);
    final side = math.min(size.width, size.height) * .62;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color.withValues(alpha: .22);
    final square = Rect.fromCenter(center: centre, width: side, height: side);
    canvas.drawRect(square, line);
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(math.pi / 4);
    canvas.translate(-centre.dx, -centre.dy);
    canvas.drawRect(square, line);
    canvas.restore();
    canvas.drawCircle(centre, side * .78, line);
    canvas.drawCircle(
      centre,
      side * .36,
      line..color = color.withValues(alpha: .14),
    );
  }

  @override
  bool shouldRepaint(_StarOrnament oldDelegate) => oldDelegate.color != color;
}

/// A thin rule with a diamond in the middle.
class _Divider extends StatelessWidget {
  const _Divider(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) {
    final line = Expanded(
      child: Container(height: 1, color: color.withValues(alpha: .35)),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Row(
        children: <Widget>[
          line,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Transform.rotate(
              angle: math.pi / 4,
              child: Container(width: 7, height: 7, color: color),
            ),
          ),
          line,
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
