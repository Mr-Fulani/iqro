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

/// The quarter a reader has just reached, for [rubMarkDuration]. The same
/// quarter is announced once until another one is: turning back and forth
/// over its page does not repeat it.
class RubMarkController extends ChangeNotifier {
  QuranDivision? _mark;
  int? _lastShown;
  Timer? _timer;

  /// The quarter being announced, or null.
  QuranDivision? get mark => _mark;

  void reached(QuranDivision? rub) {
    if (rub == null || rub.number == _lastShown) return;
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
/// out above the bottom of the reader. It never takes a touch.
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
        return IgnorePointer(
          child: AnimatedOpacity(
            opacity: mark == null ? 0 : 1,
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
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          10,
                          8,
                          22,
                          8,
                        ),
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
      },
    );
  }
}
