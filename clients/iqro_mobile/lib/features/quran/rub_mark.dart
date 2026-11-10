import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/design_system/iqro_widgets.dart';
import '../../l10n/generated/app_localizations.dart';
import 'quran_models.dart';

/// How long the reader shows that a quarter of a hizb begins.
const rubMarkDuration = Duration(milliseconds: 2500);

/// The quarter of a hizb that begins at one of [ayahs], if any. No Mushaf
/// page holds the start of two quarters.
QuranDivision? rubStartingIn(
  Iterable<QuranAyahReference> ayahs,
  List<QuranDivision> rubs,
) {
  final shown = ayahs.toSet();
  if (shown.isEmpty) return null;
  return rubs.where((rub) => shown.contains(rub.startAyah)).firstOrNull;
}

/// The quarter of [surah] whose first ayah is fairly in view in the list
/// under [viewportKey]: half of it, or enough of a long one to read its
/// first lines. [ayahKeys] holds the key of each built ayah by its number.
QuranDivision? rubVisibleIn({
  required int surah,
  required List<QuranDivision> rubs,
  required GlobalKey viewportKey,
  required Map<int, GlobalKey> ayahKeys,
}) {
  final viewportBox = viewportKey.currentContext?.findRenderObject();
  if (viewportBox is! RenderBox || !viewportBox.hasSize) return null;
  final viewportTop = viewportBox.localToGlobal(Offset.zero).dy;
  final viewportBottom = viewportTop + viewportBox.size.height;
  for (final rub in rubs) {
    if (rub.startAyah.surah != surah) continue;
    final box = ayahKeys[rub.startAyah.ayah]?.currentContext
        ?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) continue;
    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = top + box.size.height;
    final visible =
        bottom.clamp(viewportTop, viewportBottom) -
        top.clamp(viewportTop, viewportBottom);
    if (visible >= (box.size.height * .5).clamp(36, 160)) return rub;
  }
  return null;
}

/// «Джуз 5» where a juz begins, «Хизб 9» at the start of a hizb, then
/// «¼ / ½ / ¾ Хизб 9» for its quarters, as printed Mushafs mark them.
String rubMarkLabel(AppLocalizations l10n, QuranDivision rub) {
  final hizb = rub.hizbNumber ?? (rub.number - 1) ~/ 4 + 1;
  final quarter = rub.quarterNumber ?? (rub.number - 1) % 4 + 1;
  return switch (quarter) {
    1 when hizb.isOdd => l10n.rubMarkJuz('${(hizb + 1) ~/ 2}'),
    1 => l10n.rubMarkHizb('$hizb'),
    2 => l10n.rubMarkQuarter('$hizb'),
    3 => l10n.rubMarkHalf('$hizb'),
    _ => l10n.rubMarkThreeQuarters('$hizb'),
  };
}

/// The quarter a reader has just reached, for [rubMarkDuration]. It is
/// announced again each time the reader comes back to it, but not while it
/// stays in view.
class RubMarkController extends ChangeNotifier {
  QuranDivision? _mark;
  int? _lastShown;
  Timer? _timer;

  /// The quarter being announced, or null.
  QuranDivision? get mark => _mark;

  /// The quarter now in view, or null once the reader has left it.
  void reached(QuranDivision? rub) {
    if (rub == null) {
      _lastShown = null;
      return;
    }
    if (rub.number == _lastShown) return;
    _lastShown = rub.number;
    _mark = rub;
    _timer?.cancel();
    _timer = Timer(rubMarkDuration, () {
      _mark = null;
      notifyListeners();
    });
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// A dark pill with the IQRO seal and the quarter's name, which fades in and
/// out over the lower part of the reader's Stack. It never takes a touch.
class RubMarkToast extends StatefulWidget {
  const RubMarkToast({required this.controller, super.key});

  final RubMarkController controller;

  @override
  State<RubMarkToast> createState() => _RubMarkToastState();
}

class _RubMarkToastState extends State<RubMarkToast> {
  // The last label stays while the pill fades out.
  String? _label;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final mark = widget.controller.mark;
        if (mark != null) _label = rubMarkLabel(context.l10n, mark);
        final label = _label;
        return PositionedDirectional(
          start: 24,
          end: 24,
          // Clear of the page's foot; over the text, which it leaves soon.
          bottom: MediaQuery.sizeOf(context).height * .2,
          child: Center(child: _pill(context, mark != null, label)),
        );
      },
    );
  }

  Widget _pill(BuildContext context, bool shown, String? label) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: shown ? 1 : 0,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 220),
        child: label == null
            ? const SizedBox.shrink()
            : Semantics(
                liveRegion: true,
                child: DecoratedBox(
                  key: const ValueKey('rub-mark-toast'),
                  decoration: BoxDecoration(
                    color: const Color(0xE6262A2E),
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 22, 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Image.asset(
                          'assets/brand/iqro-logo.png',
                          width: 34,
                          height: 34,
                          excludeFromSemantics: true,
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
