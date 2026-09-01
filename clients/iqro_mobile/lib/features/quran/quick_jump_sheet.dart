import 'package:flutter/material.dart';

import '../../core/design_system/iqro_widgets.dart';
import 'quran_models.dart';

enum QuranQuickJumpMode { ayah, juz, page }

class QuranQuickJumpSelection {
  const QuranQuickJumpSelection({
    required this.mode,
    required this.surah,
    required this.ayah,
    required this.page,
  });

  final QuranQuickJumpMode mode;
  final int surah;
  final int ayah;
  final int page;
}

class QuranQuickJumpSheet extends StatefulWidget {
  const QuranQuickJumpSheet({
    required this.surahs,
    required this.juz,
    this.initialMode = QuranQuickJumpMode.ayah,
    this.initialSurah = 1,
    this.initialAyah = 1,
    this.initialPage = 1,
    super.key,
  });

  final List<Surah> surahs;
  final List<QuranDivision> juz;
  final QuranQuickJumpMode initialMode;
  final int initialSurah;
  final int initialAyah;
  final int initialPage;

  @override
  State<QuranQuickJumpSheet> createState() => _QuranQuickJumpSheetState();
}

class _QuranQuickJumpSheetState extends State<QuranQuickJumpSheet> {
  late var _mode = widget.initialMode;
  late var _surah = widget.initialSurah.clamp(1, 114);
  late var _ayah = widget.initialAyah.clamp(1, 286);
  late var _number = widget.initialPage.clamp(1, 604);
  late var _juz = _initialJuz();

  int _initialJuz() {
    for (final division in widget.juz) {
      if (widget.initialPage >= division.startPage &&
          widget.initialPage <= division.endPage) {
        return division.number;
      }
    }
    return widget.juz.firstOrNull?.number ?? 1;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        20,
        12,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 18),
          IqroEyebrow(context.l10n.navigation),
          Text(
            context.l10n.quickJump,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 18),
          SegmentedButton<QuranQuickJumpMode>(
            segments: <ButtonSegment<QuranQuickJumpMode>>[
              ButtonSegment(
                value: QuranQuickJumpMode.ayah,
                label: Text(context.l10n.ayah),
              ),
              ButtonSegment(
                value: QuranQuickJumpMode.juz,
                label: Text(context.l10n.juz),
              ),
              ButtonSegment(
                value: QuranQuickJumpMode.page,
                label: Text(context.l10n.page),
              ),
            ],
            selected: <QuranQuickJumpMode>{_mode},
            onSelectionChanged: (value) => setState(() => _mode = value.first),
            showSelectedIcon: false,
          ),
          const SizedBox(height: 18),
          if (_mode == QuranQuickJumpMode.ayah)
            Row(
              children: <Widget>[
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<int>(
                    initialValue: _surah,
                    decoration: InputDecoration(labelText: context.l10n.surah),
                    items: widget.surahs
                        .map(
                          (surah) => DropdownMenuItem(
                            value: surah.number,
                            child: Text(
                              '${surah.number}. '
                              '${surah.nameFor(Localizations.localeOf(context).languageCode)}',
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) => setState(() {
                      _surah = value ?? 1;
                      final surah = _selectedSurah;
                      _ayah = _ayah.clamp(1, surah?.ayahCount ?? 286);
                    }),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    initialValue: '$_ayah',
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: context.l10n.ayah),
                    onChanged: (value) => _ayah = int.tryParse(value) ?? 1,
                  ),
                ),
              ],
            )
          else if (_mode == QuranQuickJumpMode.juz)
            DropdownButtonFormField<int>(
              initialValue: _juz,
              decoration: InputDecoration(labelText: context.l10n.juz),
              items: widget.juz
                  .map(
                    (division) => DropdownMenuItem<int>(
                      value: division.number,
                      child: Text(
                        '${context.l10n.juz} ${division.number} · '
                        '${context.l10n.page} ${division.startPage}',
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) => setState(() => _juz = value ?? 1),
            )
          else
            TextFormField(
              initialValue: '$_number',
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: context.l10n.page),
              onChanged: (value) => _number = int.tryParse(value) ?? 1,
            ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => Navigator.pop(context, _selection()),
              icon: const Icon(Icons.arrow_forward),
              label: Text(context.l10n.open),
            ),
          ),
        ],
      ),
    );
  }

  Surah? get _selectedSurah =>
      widget.surahs.where((item) => item.number == _surah).firstOrNull;

  QuranQuickJumpSelection _selection() {
    if (_mode == QuranQuickJumpMode.page) {
      return QuranQuickJumpSelection(
        mode: _mode,
        surah: 1,
        ayah: 1,
        page: _number.clamp(1, 604),
      );
    }
    if (_mode == QuranQuickJumpMode.juz) {
      final division = widget.juz
          .where((item) => item.number == _juz)
          .firstOrNull;
      return QuranQuickJumpSelection(
        mode: _mode,
        surah: division?.startAyah.surah ?? 1,
        ayah: division?.startAyah.ayah ?? 1,
        page: division?.startPage ?? 1,
      );
    }
    final surah = _selectedSurah;
    return QuranQuickJumpSelection(
      mode: _mode,
      surah: surah?.number ?? 1,
      ayah: _ayah.clamp(1, surah?.ayahCount ?? 286),
      page: surah?.firstPage ?? 1,
    );
  }
}
