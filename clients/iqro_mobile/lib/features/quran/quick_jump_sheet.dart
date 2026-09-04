import 'package:flutter/material.dart';

import '../../core/design_system/iqro_widgets.dart';
import 'quran_models.dart';

enum QuranQuickJumpMode { ayah, juz, hizb, rubElHizb, page }

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
    required this.hizb,
    required this.rubElHizb,
    this.initialMode = QuranQuickJumpMode.ayah,
    this.initialSurah = 1,
    this.initialAyah = 1,
    this.initialPage = 1,
    super.key,
  });

  final List<Surah> surahs;
  final List<QuranDivision> juz;
  final List<QuranDivision> hizb;
  final List<QuranDivision> rubElHizb;
  final QuranQuickJumpMode initialMode;
  final int initialSurah;
  final int initialAyah;
  final int initialPage;

  @override
  State<QuranQuickJumpSheet> createState() => _QuranQuickJumpSheetState();
}

class _QuranQuickJumpSheetState extends State<QuranQuickJumpSheet> {
  late var _mode = _modeAvailable(widget.initialMode)
      ? widget.initialMode
      : QuranQuickJumpMode.page;
  late var _surah = widget.initialSurah.clamp(1, 114);
  late var _ayah = widget.initialAyah.clamp(1, 286);
  late var _number = widget.initialPage.clamp(1, 604);
  late var _juz = _initialDivision(widget.juz);
  late var _hizb = _initialDivision(widget.hizb);
  late var _rubElHizb = _initialDivision(widget.rubElHizb);

  int _initialDivision(List<QuranDivision> divisions) {
    for (final division in divisions) {
      if (widget.initialPage >= division.startPage &&
          widget.initialPage <= division.endPage) {
        return division.number;
      }
    }
    return divisions.firstOrNull?.number ?? 1;
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final mode in QuranQuickJumpMode.values)
                ChoiceChip(
                  label: Text(_modeLabel(context, mode)),
                  selected: _mode == mode,
                  onSelected: _modeAvailable(mode)
                      ? (_) => setState(() => _mode = mode)
                      : null,
                ),
            ],
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
          else if (_mode != QuranQuickJumpMode.page)
            _divisionPicker(context)
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
              onPressed: _modeAvailable(_mode)
                  ? () => Navigator.pop(context, _selection())
                  : null,
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

  List<QuranDivision> _divisionsFor(QuranQuickJumpMode mode) => switch (mode) {
    QuranQuickJumpMode.juz => widget.juz,
    QuranQuickJumpMode.hizb => widget.hizb,
    QuranQuickJumpMode.rubElHizb => widget.rubElHizb,
    _ => const <QuranDivision>[],
  };

  int _divisionNumberFor(QuranQuickJumpMode mode) => switch (mode) {
    QuranQuickJumpMode.juz => _juz,
    QuranQuickJumpMode.hizb => _hizb,
    QuranQuickJumpMode.rubElHizb => _rubElHizb,
    _ => 1,
  };

  void _setDivisionNumber(QuranQuickJumpMode mode, int number) {
    switch (mode) {
      case QuranQuickJumpMode.juz:
        _juz = number;
      case QuranQuickJumpMode.hizb:
        _hizb = number;
      case QuranQuickJumpMode.rubElHizb:
        _rubElHizb = number;
      case QuranQuickJumpMode.ayah:
      case QuranQuickJumpMode.page:
        break;
    }
  }

  bool _modeAvailable(QuranQuickJumpMode mode) => switch (mode) {
    QuranQuickJumpMode.ayah => widget.surahs.isNotEmpty,
    QuranQuickJumpMode.page => true,
    _ => _divisionsFor(mode).isNotEmpty,
  };

  String _modeLabel(BuildContext context, QuranQuickJumpMode mode) =>
      switch (mode) {
        QuranQuickJumpMode.ayah => context.l10n.ayah,
        QuranQuickJumpMode.juz => context.l10n.juz,
        QuranQuickJumpMode.hizb => context.l10n.hizb,
        QuranQuickJumpMode.rubElHizb => context.l10n.rubElHizb,
        QuranQuickJumpMode.page => context.l10n.page,
      };

  Widget _divisionPicker(BuildContext context) {
    final divisions = _divisionsFor(_mode);
    final selectedNumber = _divisionNumberFor(_mode);
    final selected = divisions.any((item) => item.number == selectedNumber)
        ? selectedNumber
        : null;
    return DropdownButtonFormField<int>(
      key: ValueKey<QuranQuickJumpMode>(_mode),
      initialValue: selected,
      isExpanded: true,
      decoration: InputDecoration(labelText: _modeLabel(context, _mode)),
      items: divisions
          .map(
            (division) => DropdownMenuItem<int>(
              value: division.number,
              child: Text(
                _divisionLabel(context, division),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(growable: false),
      onChanged: (value) {
        if (value == null) return;
        setState(() => _setDivisionNumber(_mode, value));
      },
    );
  }

  String _divisionLabel(BuildContext context, QuranDivision division) {
    final page = '${context.l10n.page} ${division.startPage}';
    final reference = '${division.startAyah.surah}:${division.startAyah.ayah}';
    if (_mode == QuranQuickJumpMode.rubElHizb) {
      return '${division.number}. ${context.l10n.hizb} '
          '${division.hizbNumber ?? '—'} · ¼ ${division.quarterNumber ?? '—'} '
          '· $reference · $page';
    }
    return '${_modeLabel(context, _mode)} ${division.number} '
        '· $reference · $page';
  }

  QuranQuickJumpSelection _selection() {
    if (_mode == QuranQuickJumpMode.page) {
      return QuranQuickJumpSelection(
        mode: _mode,
        surah: 1,
        ayah: 1,
        page: _number.clamp(1, 604),
      );
    }
    if (_mode != QuranQuickJumpMode.ayah) {
      final division = _divisionsFor(
        _mode,
      ).where((item) => item.number == _divisionNumberFor(_mode)).firstOrNull;
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
