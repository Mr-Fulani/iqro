import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_system/iqro_widgets.dart';
import '../../core/text/arabic_digits.dart';
import '../../core/theme/iqro_theme.dart';
import 'mushaf_paper.dart';
import 'quran_models.dart';

/// How far past the end of a surah a finger pulls to open the next one.
const nextSurahPullDistance = 120.0;

/// The last surah: after it the reader shows the end of the Quran.
const lastSurah = 114;

/// A pull past the end of a surah. Fed the list's scroll notifications, it
/// fills [progress] as the finger pulls on at the end, and calls [onNext]
/// when the finger lets go with it full. A pull back, or letting go early,
/// starts over.
class NextSurahPull {
  NextSurahPull({required this.onNext});

  final VoidCallback onNext;
  final progress = ValueNotifier<double>(0);
  var _pulled = 0.0;

  void _set(double pulled) {
    _pulled = math.max(0, pulled);
    final value = (_pulled / nextSurahPullDistance).clamp(0.0, 1.0);
    if (value >= 1 && progress.value < 1) {
      unawaited(HapticFeedback.mediumImpact());
    }
    progress.value = value;
  }

  /// Whether a pull may count; false while words are selected, say.
  void handle(ScrollNotification notification, {required bool enabled}) {
    if (!enabled) {
      if (_pulled != 0) _set(0);
      return;
    }
    final metrics = notification.metrics;
    switch (notification) {
      case OverscrollNotification(:final overscroll, :final dragDetails)
          when dragDetails != null && overscroll > 0:
        // A clamping list stays at its end: the finger's travel past it.
        _set(_pulled + overscroll);
      case ScrollUpdateNotification(:final dragDetails, :final scrollDelta)
          when dragDetails != null:
        if (metrics.pixels > metrics.maxScrollExtent) {
          // A bouncing list goes past its end.
          _set(metrics.pixels - metrics.maxScrollExtent);
        } else if ((scrollDelta ?? 0) < 0) {
          _set(0);
        }
      case ScrollEndNotification():
        final full = progress.value >= 1;
        _set(0);
        if (full) onNext();
      default:
        break;
    }
  }

  void dispose() => progress.dispose();
}

/// The card after the last ayah: the next surah, opened by a tap or a pull.
class NextSurahCard extends StatelessWidget {
  const NextSurahCard({
    required this.number,
    required this.surah,
    required this.progress,
    required this.onTap,
    this.paper = false,
    super.key,
  });

  final int number;

  /// The next surah from the catalog, when it has loaded.
  final Surah? surah;
  final ValueListenable<double> progress;
  final VoidCallback? onTap;

  /// On the plain text's paper rather than in the app's colours.
  final bool paper;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).languageCode;
    final ink = paper ? mushafInkColor : scheme.onSurface;
    final soft = paper ? mushafAccentColor : scheme.onSurfaceVariant;
    final accent = paper ? nextSurahGold : scheme.primary;
    final surah = this.surah;
    return ValueListenableBuilder<double>(
      valueListenable: progress,
      builder: (context, value, _) {
        final ready = value >= 1;
        return Material(
          color: paper
              ? const Color(0xFFFBF4E6)
              : ready
              ? scheme.primaryContainer
              : scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: paper ? const Color(0xFFC49647) : accent,
              width: ready ? 2 : 1.5,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('next-surah-card'),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    paper
                        ? '${context.l10n.nextSurah} · ${arabicIndicDigits(number)}'
                        : context.l10n.nextSurah,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: soft,
                      letterSpacing: .6,
                    ),
                  ),
                  if (!paper)
                    Text(
                      '$number. ${surah?.nameFor(locale) ?? ''}',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (surah != null) ...<Widget>[
                    Text(
                      'سُورَةُ ${surah.nameAr}',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontFamily: IqroTheme.arabicFontFamily,
                        fontSize: paper ? 28 : 22,
                        height: 1.7,
                        color: ink,
                      ),
                    ),
                    Text(
                      paper
                          ? '${surah.nameFor(locale)} · ${surah.ayahCount} ${context.l10n.ayahs}'
                          : '${surah.ayahCount} ${context.l10n.ayahs} · ${surah.revelationType == 'meccan' ? context.l10n.meccan : context.l10n.medinan}',
                      style: theme.textTheme.bodySmall?.copyWith(color: soft),
                    ),
                  ],
                  const SizedBox(height: 10),
                  SizedBox.square(
                    dimension: 52,
                    child: Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        SizedBox.square(
                          dimension: 50,
                          child: CircularProgressIndicator(
                            key: const ValueKey('next-surah-progress'),
                            value: value,
                            strokeWidth: 3.5,
                            color: accent,
                            backgroundColor: accent.withValues(alpha: .2),
                          ),
                        ),
                        Icon(
                          ready ? Icons.check_rounded : Icons.arrow_upward,
                          color: accent,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ready
                        ? context.l10n.nextSurahRelease('$number')
                        : context.l10n.nextSurahHint,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The app's gold on the plain text's paper.
const nextSurahGold = Color(0xFF9A6D22);

/// After an-Nas: no next surah, and plainly so.
class QuranEndCard extends StatelessWidget {
  const QuranEndCard({required this.surah, this.paper = false, super.key});

  final Surah? surah;
  final bool paper;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).languageCode;
    final ink = paper ? mushafInkColor : scheme.onSurface;
    final soft = paper ? mushafAccentColor : scheme.onSurfaceVariant;
    return Container(
      key: const ValueKey('quran-end'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      decoration: BoxDecoration(
        color: paper ? null : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: paper
            ? const Border.symmetric(
                horizontal: BorderSide(color: Color(0xFFE6D7B7)),
              )
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            '۞',
            style: TextStyle(
              fontFamily: IqroTheme.arabicFontFamily,
              fontSize: 40,
              height: 1,
              color: Color(0xFFC49647),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            context.l10n.quranEnd,
            style: theme.textTheme.titleLarge?.copyWith(
              color: ink,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.quranEndNote(
              '$lastSurah. ${surah?.nameFor(locale) ?? ''}'.trim(),
            ),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: soft),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            key: const ValueKey('quran-end-surah-list'),
            onPressed: () => context.go('/app?tab=1'),
            style: OutlinedButton.styleFrom(
              foregroundColor: paper ? nextSurahGold : scheme.primary,
              side: BorderSide(
                color: paper ? const Color(0xFFC49647) : scheme.primary,
              ),
            ),
            child: Text(context.l10n.toSurahList),
          ),
        ],
      ),
    );
  }
}

/// The page a next surah opens with: it rises from below over the last one.
class NextSurahTransition extends StatelessWidget {
  const NextSurahTransition({
    required this.animation,
    required this.child,
    super.key,
  });

  /// What a route opened by the end of a surah carries, so it rises in.
  static const routeExtra = 'next-surah';

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return FadeTransition(opacity: animation, child: child);
    }
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(curved),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          boxShadow: <BoxShadow>[
            BoxShadow(color: Color(0x59000000), blurRadius: 30),
          ],
        ),
        child: child,
      ),
    );
  }
}
