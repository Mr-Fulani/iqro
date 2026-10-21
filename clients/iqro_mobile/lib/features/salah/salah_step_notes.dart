import 'package:flutter/material.dart';

import '../../core/design_system/iqro_widgets.dart';
import 'salah_models.dart';

/// The «?» and «!» icons of a step. A tap opens the note in a bottom sheet;
/// a tap outside, a swipe down, «Close» or Esc closes it.
class SalahStepNotes extends StatelessWidget {
  const SalahStepNotes({required this.notes, super.key});

  final List<SalahStepNote> notes;

  @override
  Widget build(BuildContext context) {
    final labels = salahNoteLabels(context, notes);
    return Semantics(
      container: true,
      label: context.l10n.salahNotes,
      child: Wrap(
        spacing: 2,
        children: <Widget>[
          for (final (index, note) in notes.indexed)
            _NoteIcon(
              key: ValueKey('salah-note-$index'),
              note: note,
              label: labels[index],
              onPressed: () => showSalahNote(context, note, labels[index]),
            ),
        ],
      ),
    );
  }
}

/// «Help», «Important»; numbered when a step has several of one kind, as
/// on the site.
List<String> salahNoteLabels(BuildContext context, List<SalahStepNote> notes) {
  final l10n = context.l10n;
  final labels = <String>[];
  final numbers = <SalahNoteKind, int>{};
  for (final note in notes) {
    final label = note.kind == SalahNoteKind.warning
        ? l10n.salahNoteWarning
        : l10n.salahNoteHelp;
    final number = numbers[note.kind] = (numbers[note.kind] ?? 0) + 1;
    final several = notes.where((other) => other.kind == note.kind).length > 1;
    labels.add(several ? '$label $number' : label);
  }
  return labels;
}

Future<void> showSalahNote(
  BuildContext context,
  SalahStepNote note,
  String label,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (context) => _NoteSheet(note: note, label: label),
);

/// The colours of a note's icon: the course's green for help, amber for a
/// warning (the site's warning tokens).
({Color fill, Color ink, Color border}) _noteColors(
  BuildContext context,
  SalahNoteKind kind,
) {
  final scheme = Theme.of(context).colorScheme;
  final dark = Theme.of(context).brightness == Brightness.dark;
  if (kind == SalahNoteKind.warning) {
    return dark
        ? (
            fill: const Color(0xFF4A3410),
            ink: const Color(0xFFFCD34D),
            border: const Color(0xFFF59E0B),
          )
        : (
            fill: const Color(0xFFFEF3C7),
            ink: const Color(0xFF92400E),
            border: const Color(0xFFD97706),
          );
  }
  return (
    fill: scheme.primaryContainer,
    ink: scheme.onPrimaryContainer,
    border: scheme.primary.withValues(alpha: .55),
  );
}

class _NoteIcon extends StatelessWidget {
  const _NoteIcon({
    required this.note,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final SalahStepNote note;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = _noteColors(context, note.kind);
    // A 32 dp circle in a 48 dp touch target.
    return IconButton(
      tooltip: label,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        fixedSize: const Size.square(32),
        minimumSize: const Size.square(32),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.padded,
        backgroundColor: colors.fill,
        foregroundColor: colors.ink,
        side: BorderSide(color: colors.border, width: 1.5),
      ),
      icon: ExcludeSemantics(
        child: Text(
          note.kind == SalahNoteKind.warning ? '!' : '?',
          style: TextStyle(
            color: colors.ink,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _NoteSheet extends StatelessWidget {
  const _NoteSheet({required this.note, required this.label});

  final SalahStepNote note;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = _noteColors(context, note.kind);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 12, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.fill,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.border, width: 1.5),
                ),
                child: ExcludeSemantics(
                  child: Text(
                    note.kind == SalahNoteKind.warning ? '!' : '?',
                    style: TextStyle(
                      color: colors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    label,
                    key: const ValueKey('salah-note-title'),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('salah-note-close'),
                tooltip: context.l10n.salahNoteClose,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(
            child: SingleChildScrollView(
              child: Text(
                note.text,
                key: const ValueKey('salah-note-text'),
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.55),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
