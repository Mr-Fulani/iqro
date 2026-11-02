import 'package:flutter/material.dart';

import '../../core/design_system/iqro_widgets.dart';
import '../../core/text/arabic_digits.dart';
import 'quran_models.dart';

/// Two dropdowns on the Quran tab: a surah, then one of its ayahs. Picking
/// the ayah opens it; numbers are in Arabic-Indic digits.
class QuranSurahAyahPicker extends StatefulWidget {
  const QuranSurahAyahPicker({
    required this.surahs,
    required this.onOpen,
    super.key,
  });

  final List<Surah> surahs;
  final void Function(Surah surah, int ayah) onOpen;

  @override
  State<QuranSurahAyahPicker> createState() => _QuranSurahAyahPickerState();
}

class _QuranSurahAyahPickerState extends State<QuranSurahAyahPicker> {
  Surah? _surah;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final surah = _surah;
    return Row(
      children: <Widget>[
        Expanded(
          flex: 3,
          child: DropdownButtonFormField<int>(
            key: const ValueKey('quran-surah-picker'),
            initialValue: surah?.number,
            isExpanded: true,
            menuMaxHeight: 420,
            decoration: InputDecoration(labelText: context.l10n.surah),
            items: widget.surahs
                .map(
                  (item) => DropdownMenuItem<int>(
                    value: item.number,
                    child: Text(
                      '${arabicIndicDigits(item.number)} · '
                      '${item.nameFor(locale)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged: widget.surahs.isEmpty
                ? null
                : (value) => setState(
                    () => _surah = widget.surahs
                        .where((item) => item.number == value)
                        .firstOrNull,
                  ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<int>(
            // A new surah starts the ayah list over.
            key: ValueKey('quran-ayah-picker-${surah?.number}'),
            isExpanded: true,
            menuMaxHeight: 420,
            decoration: InputDecoration(labelText: context.l10n.ayah),
            items: <DropdownMenuItem<int>>[
              for (var ayah = 1; ayah <= (surah?.ayahCount ?? 0); ayah++)
                DropdownMenuItem<int>(
                  value: ayah,
                  child: Text(arabicIndicDigits(ayah)),
                ),
            ],
            onChanged: surah == null
                ? null
                : (value) {
                    if (value != null) widget.onOpen(surah, value);
                  },
          ),
        ),
      ],
    );
  }
}
