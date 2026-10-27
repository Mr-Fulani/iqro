import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import 'memorization_repository.dart';

/// "Learn" from the Mushaf ayah menu, one ayah at a time: the app's
/// counterpart of the site's dialog. The server decides which choice fits:
/// with an empty list the ayah starts straight away; otherwise it is already
/// in the list, extends the current range, or is queued (the default) versus
/// learnt now. The API also takes ranges.
Future<void> showMemorizeAyahSheet(
  BuildContext context, {
  required int surah,
  required int ayah,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => MemorizeAyahSheet(surah: surah, ayah: ayah),
);

class MemorizeAyahSheet extends ConsumerStatefulWidget {
  const MemorizeAyahSheet({required this.surah, required this.ayah, super.key});

  final int surah;
  final int ayah;

  @override
  ConsumerState<MemorizeAyahSheet> createState() => _MemorizeAyahSheetState();
}

class _MemorizeAyahSheetState extends ConsumerState<MemorizeAyahSheet> {
  MemorizationSelectionPreview? _preview;
  var _failed = false;
  var _busy = false;
  var _addedToQueue = false;

  MemorizationSelection get _selection => MemorizationSelection(
    startSurah: widget.surah,
    startAyah: widget.ayah,
    endSurah: widget.surah,
    endAyah: widget.ayah,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_loadPreview());
  }

  Future<void> _loadPreview() async {
    setState(() {
      _preview = null;
      _failed = false;
    });
    try {
      final preview = await ref
          .read(memorizationRepositoryProvider)
          .preview(_selection);
      if (!mounted) return;
      setState(() => _preview = preview);
      // An empty list has nothing to choose between: the ayah becomes current.
      if (preview.state == MemorizationPreviewState.empty) {
        await _add(MemorizationAddMode.now);
      }
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _add(MemorizationAddMode mode) async {
    final preview = _preview;
    if (preview == null || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(memorizationProvider.notifier)
          .addSelection(
            _selection,
            mode: mode,
            baseRevision: preview.revision,
            recitationId: ref
                .read(appPreferencesProvider)
                .memorizationDefaultRecitationId,
          );
      if (!mounted) return;
      if (result == 'queued' || result == 'merged') {
        setState(() => _addedToQueue = true);
        return;
      }
      _open();
    } on Object {
      if (!mounted) return;
      // A failed automatic start offers a retry instead of an empty sheet.
      if (_preview?.state == MemorizationPreviewState.empty) {
        setState(() => _failed = true);
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.networkError)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _open() {
    final router = GoRouter.of(context);
    Navigator.pop(context);
    unawaited(router.push('/memorization'));
  }

  String _range(int start, int end, [int? surah]) {
    final number = surah ?? widget.surah;
    return start == end ? '$number:$start' : '$number:$start–$end';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              l10n.memorizationListLearnTitle(_range(widget.ayah, widget.ayah)),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            ..._choices(context),
          ],
        ),
      ),
    );
  }

  List<Widget> _choices(BuildContext context) {
    final l10n = context.l10n;
    Widget message(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    );
    Widget primary(String label, VoidCallback onPressed, {Key? key}) =>
        FilledButton(
          key: key,
          onPressed: _busy ? null : onPressed,
          child: Text(label),
        );
    Widget secondary(String label, VoidCallback onPressed, {Key? key}) =>
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton(
            key: key,
            onPressed: _busy ? null : onPressed,
            child: Text(label),
          ),
        );

    if (_addedToQueue) {
      return <Widget>[
        message(l10n.memorizationListAddedToQueue),
        secondary(l10n.memorizationListOpen, _open),
      ];
    }
    if (_failed) {
      return <Widget>[
        IqroAsyncError(title: l10n.networkError, onRetry: _loadPreview),
      ];
    }
    final preview = _preview;
    if (preview == null || preview.state == MemorizationPreviewState.empty) {
      return const <Widget>[
        Center(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(),
          ),
        ),
      ];
    }
    final current = preview.item;
    switch (preview.state) {
      case MemorizationPreviewState.duplicate:
        return <Widget>[
          message(
            current == null
                ? l10n.memorizationListAlreadyInShort
                : l10n.memorizationListAlreadyIn(
                    _range(
                      current.startAyah.ayah,
                      current.endAyah.ayah,
                      current.surah,
                    ),
                  ),
          ),
          primary(
            l10n.memorizationListOpen,
            _open,
            key: const ValueKey('memorize-open'),
          ),
        ];
      case MemorizationPreviewState.empty:
        return const <Widget>[];
      case MemorizationPreviewState.extendable:
        return <Widget>[
          message(l10n.memorizationListContinuesCurrent),
          primary(
            l10n.memorizationListExtendTo(
              _range(
                preview.extendStartAyah ?? widget.ayah,
                preview.extendEndAyah ?? widget.ayah,
                preview.extendSurah,
              ),
            ),
            () => _add(MemorizationAddMode.extend),
            key: const ValueKey('memorize-extend'),
          ),
          secondary(
            l10n.memorizationListQueueSeparately,
            () => _add(MemorizationAddMode.queue),
            key: const ValueKey('memorize-queue'),
          ),
        ];
      case MemorizationPreviewState.choose:
        return <Widget>[
          if (current != null)
            message(
              l10n.memorizationListCurrentIs(
                _range(
                  current.startAyah.ayah,
                  current.endAyah.ayah,
                  current.surah,
                ),
              ),
            ),
          primary(
            l10n.memorizationListAddToQueue,
            () => _add(MemorizationAddMode.queue),
            key: const ValueKey('memorize-queue'),
          ),
          secondary(
            l10n.memorizationListLearnNow,
            () => _add(MemorizationAddMode.now),
            key: const ValueKey('memorize-now'),
          ),
        ];
    }
  }
}
