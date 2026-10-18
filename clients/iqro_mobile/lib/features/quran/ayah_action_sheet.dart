import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_system/iqro_icon.dart';
import '../../app/providers.dart';
import '../../core/audio/audio_controller.dart';
import '../../core/auth/account_scope.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../audio/audio_models.dart';
import '../audio/recitation_style_label.dart';
import '../audio/audio_repository.dart';
import '../audio/reciter_portraits.dart';
import 'ayah_annotations.dart';
import 'mushaf_paper.dart';
import 'mushaf_ayah_excerpt.dart';
import 'quran_models.dart';
import 'quran_repository.dart';
import '../../core/share/content_share.dart';
import 'ayah_share.dart';

enum _CopyAyahFeedback { idle, copying, copied, failed }

class AyahActionSheet extends ConsumerStatefulWidget {
  const AyahActionSheet({
    required this.reference,
    required this.page,
    super.key,
  });

  final QuranAyahReference reference;
  final int page;

  @override
  ConsumerState<AyahActionSheet> createState() => _AyahActionSheetState();
}

class _AyahActionSheetState extends ConsumerState<AyahActionSheet> {
  _AyahDetails? _details;
  Object? _error;
  var _loading = true;
  var _audioLoading = false;
  var _bookmarkLoading = false;
  var _detailsSaving = false;
  var _copyFeedback = _CopyAyahFeedback.idle;
  var _bookmarked = false;
  var _highlightColor = 'lime';
  var _highlighted = false;
  var _note = '';
  int? _translationSourceId;
  int? _tafsirSourceId;
  String? _recitationId;
  var _dependenciesReady = false;
  var _audioRequest = 0;
  var _loadRequest = 0;
  var _bookmarkRequest = 0;
  var _translationRequest = 0;
  var _tafsirRequest = 0;
  Timer? _copyFeedbackTimer;
  String? _ownerId;

  @override
  void initState() {
    super.initState();
    _ownerId = ref.read(sessionProvider).valueOrNull?.userId;
  }

  @override
  void dispose() {
    _copyFeedbackTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dependenciesReady) return;
    _dependenciesReady = true;
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final ownerId = ref.watch(sessionProvider).valueOrNull?.userId;
    if (_ownerId != ownerId) {
      _ownerId = ownerId;
      _audioRequest += 1;
      _loadRequest += 1;
      _bookmarkRequest += 1;
      _translationRequest += 1;
      _tafsirRequest += 1;
      _details = null;
      _error = null;
      _loading = true;
      _audioLoading = false;
      _bookmarkLoading = false;
      _detailsSaving = false;
      _bookmarked = false;
      _highlightColor = 'lime';
      _highlighted = false;
      _note = '';
      _recitationId = null;
      if (ownerId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _ownerId == ownerId) unawaited(_load());
        });
      }
    }
    final audio = ref.watch(
      audioControllerProvider.select(
        (value) => (
          playing: value.playing,
          surah: value.track?.surah,
          ayah: value.activeAyah,
          recitationId: value.track?.recitationId,
          rangeStartAyah: value.rangeStartAyah,
          rangeEndAyah: value.rangeEndAyah,
          repeatEnabled: value.repeatEnabled,
          active: value.channel == AudioPlaybackChannel.mushaf,
          hasError: value.error != null,
        ),
      ),
    );
    final loadedThis =
        !audio.hasError &&
        audio.surah == widget.reference.surah &&
        audio.ayah == widget.reference.ayah &&
        audio.recitationId == _recitationId &&
        audio.rangeStartAyah == widget.reference.ayah &&
        audio.rangeEndAyah == widget.reference.ayah &&
        audio.active;
    final playingThis = loadedThis && audio.playing;
    return SafeArea(
      top: false,
      child: FractionallySizedBox(
        heightFactor: .92,
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: _loading
              ? const IqroLoading()
              : _error != null
              ? IqroAsyncError(title: context.l10n.networkError, onRetry: _load)
              : _content(
                  playingThis,
                  loadedThis,
                  repeatEnabled: loadedThis && audio.repeatEnabled,
                ),
        ),
      ),
    );
  }

  Widget _content(
    bool playingThis,
    bool loadedThis, {
    required bool repeatEnabled,
  }) {
    final details = _details!;
    return CustomScrollView(
      slivers: <Widget>[
        SliverAppBar(
          pinned: true,
          automaticallyImplyLeading: false,
          backgroundColor: Theme.of(context).colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('${context.l10n.ayah} ${widget.reference.key}'),
              Text(
                '${context.l10n.page} ${widget.page}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          actions: <Widget>[
            IconButton(
              tooltip: context.l10n.close,
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
            const SizedBox(width: 6),
          ],
        ),
        SliverPadding(
          padding: const EdgeInsetsDirectional.fromSTEB(18, 10, 18, 28),
          sliver: SliverList.list(
            children: <Widget>[
              if (details.ayah != null)
                MushafAyahExcerpt(ayah: details.ayah!, page: widget.page)
              else
                const MushafAyahText(text: ''),
              const SizedBox(height: 12),
              _actionRow(playingThis, loadedThis),
              const SizedBox(height: 12),
              _quickActions(
                repeatEnabled: repeatEnabled,
                canCopyOrShare: details.ayah != null,
              ),
              const SizedBox(height: 20),
              _reciterSelector(details),
              const SizedBox(height: 22),
              _translationSection(details),
              const SizedBox(height: 22),
              _tafsirSection(details),
            ],
          ),
        ),
      ],
    );
  }

  Widget _actionRow(bool playingThis, bool loadedThis) {
    return Row(
      children: <Widget>[
        Expanded(
          child: FilledButton.icon(
            onPressed: _audioLoading
                ? null
                : loadedThis
                ? () => ref.read(audioControllerProvider.notifier).toggle()
                : _play,
            icon: _audioLoading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(playingThis ? Icons.pause : Icons.play_arrow),
            label: Text(playingThis ? context.l10n.pause : context.l10n.listen),
          ),
        ),
        const SizedBox(width: 10),
        IconButton.filledTonal(
          tooltip: context.l10n.favorites,
          onPressed: _bookmarkLoading ? null : _toggleBookmark,
          isSelected: _bookmarked,
          selectedIcon: const Icon(Icons.bookmark),
          icon: const Icon(Icons.bookmark_border),
        ),
      ],
    );
  }

  Widget _quickActions({
    required bool repeatEnabled,
    required bool canCopyOrShare,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: <Widget>[
          _ActionTile(
            icon: Icons.repeat_rounded,
            title: context.l10n.repeatSelectedAyah,
            subtitle: repeatEnabled
                ? context.l10n.repeatOn
                : context.l10n.repeatOff,
            onTap: _toggleRepeatSelectedAyah,
          ),
          const Divider(height: 1),
          _ActionTile(
            icon: Icons.palette_outlined,
            title: context.l10n.chooseHighlightColor,
            trailing: _detailsSaving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : _HighlightDots(
                    colorKey: _highlighted ? _highlightColor : null,
                  ),
            onTap: _detailsSaving ? null : _chooseHighlightColor,
          ),
          const Divider(height: 1),
          _ActionTile(
            icon: Icons.note_alt_outlined,
            title: _note.trim().isEmpty
                ? context.l10n.addNote
                : context.l10n.editNote,
            subtitle: _note.trim().isEmpty ? null : _note.trim(),
            onTap: _detailsSaving ? null : _editNote,
          ),
          const Divider(height: 1),
          _ActionTile(
            icon: switch (_copyFeedback) {
              _CopyAyahFeedback.copied => Icons.check_circle_rounded,
              _CopyAyahFeedback.failed => Icons.error_outline_rounded,
              _ => Icons.copy_outlined,
            },
            iconColor: switch (_copyFeedback) {
              _CopyAyahFeedback.copied => Theme.of(context).colorScheme.primary,
              _CopyAyahFeedback.failed => Theme.of(context).colorScheme.error,
              _ => null,
            },
            title: switch (_copyFeedback) {
              _CopyAyahFeedback.copied => context.l10n.copied,
              _CopyAyahFeedback.failed => context.l10n.copyAyahFailed,
              _ => context.l10n.copyAyah,
            },
            trailing: switch (_copyFeedback) {
              _CopyAyahFeedback.copying => const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              _CopyAyahFeedback.copied => Icon(
                Icons.check_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              _CopyAyahFeedback.failed => Icon(
                Icons.error_outline_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
              _CopyAyahFeedback.idle => null,
            },
            onTap: canCopyOrShare && _copyFeedback != _CopyAyahFeedback.copying
                ? _copyAyah
                : null,
          ),
          const Divider(height: 1),
          _ActionTile(
            icon: Icons.ios_share_outlined,
            title: context.l10n.shareAyah,
            onTap: canCopyOrShare ? _shareAyah : null,
          ),
        ],
      ),
    );
  }

  Widget _reciterSelector(_AyahDetails details) {
    if (details.recitations.isEmpty) {
      return IqroStatusBanner(
        icon: Icons.volume_off_outlined,
        title: context.l10n.noAudio,
      );
    }
    final locale = Localizations.localeOf(context).languageCode;
    return DropdownButtonFormField<String>(
      key: ValueKey(_recitationId),
      initialValue: _recitationId,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: context.l10n.chooseReciter,
        prefixIcon: const Icon(Icons.record_voice_over_outlined),
      ),
      items: details.recitations
          .map(
            (item) => DropdownMenuItem<String>(
              value: item.id,
              child: Text(
                '${item.reciter.nameFor(locale)} · '
                '${recitationStyleLabel(context, item.style)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(growable: false),
      onChanged: (value) {
        if (value == null) return;
        setState(() => _recitationId = value);
        unawaited(
          ref.read(appPreferencesProvider.notifier).setMushafRecitation(value),
        );
      },
    );
  }

  Widget _translationSection(_AyahDetails details) {
    return _ContentSection(
      icon: Icons.translate,
      title: context.l10n.translation,
      selector: details.translationEditions.length <= 1
          ? null
          : DropdownButton<int>(
              value: _translationSourceId,
              isExpanded: true,
              items: details.translationEditions
                  .map(
                    (item) => DropdownMenuItem<int>(
                      value: item.sourceId,
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) unawaited(_changeTranslation(value));
              },
            ),
      source: details.translationEditions
          .where((item) => item.sourceId == _translationSourceId)
          .firstOrNull
          ?.name,
      body: details.translation?.text,
      emptyMessage: context.l10n.translationUnavailable,
      footnotes: details.translation?.footnotes ?? const <String>[],
    );
  }

  Widget _tafsirSection(_AyahDetails details) {
    return _ContentSection(
      icon: Icons.auto_stories_outlined,
      title: context.l10n.tafsir,
      selector: details.tafsirEditions.length <= 1
          ? null
          : DropdownButton<int>(
              value: _tafsirSourceId,
              isExpanded: true,
              items: details.tafsirEditions
                  .map(
                    (item) => DropdownMenuItem<int>(
                      value: item.sourceId,
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) unawaited(_changeTafsir(value));
              },
            ),
      source: details.tafsirEditions
          .where((item) => item.sourceId == _tafsirSourceId)
          .firstOrNull
          ?.name,
      body: details.tafsir?.text,
      emptyMessage: context.l10n.tafsirUnavailable,
      footnotes: const <String>[],
      range:
          details.tafsir == null ||
              details.tafsir!.startVerseKey == details.tafsir!.endVerseKey
          ? null
          : '${details.tafsir!.startVerseKey}–${details.tafsir!.endVerseKey}',
    );
  }

  Future<void> _load() async {
    final scope = ref.read(localDatabaseProvider).accountScope.current;
    if (scope == null || !_isCurrentAccount(scope)) return;
    final request = ++_loadRequest;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final locale = Localizations.localeOf(context).languageCode;
      final quran = ref.read(quranRepositoryProvider);
      final audio = ref.read(audioRepositoryProvider);
      final first = await Future.wait<Object?>(<Future<Object?>>[
        quran.ayahs(widget.reference.surah),
        _safeTranslationEditions(quran, locale),
        _safeTafsirEditions(quran, locale),
        _safeRecitations(audio),
        _safeIsBookmarked(quran, scope),
        _safeAnnotationDetails(quran, scope),
      ]);
      if (!_isCurrentLoad(scope, request)) return;
      final ayahs = first[0] as List<QuranAyah>;
      final translationEditions = first[1] as List<QuranTranslationEdition>;
      final tafsirEditions = first[2] as List<QuranTafsirEdition>;
      final recitations = first[3] as List<Recitation>;
      final bookmarked = first[4] as bool;
      final annotation = first[5] as Map<String, Object?>?;
      final preferences = ref.read(appPreferencesProvider);
      _translationSourceId ??=
          translationEditions
              .where(
                (item) =>
                    item.sourceId == preferences.preferredTranslationSourceId,
              )
              .firstOrNull
              ?.sourceId ??
          translationEditions.firstOrNull?.sourceId;
      _tafsirSourceId ??=
          tafsirEditions
              .where(
                (item) => item.sourceId == preferences.preferredTafsirSourceId,
              )
              .firstOrNull
              ?.sourceId ??
          tafsirEditions.firstOrNull?.sourceId;
      _recitationId ??=
          recitations
              .where((item) => item.id == preferences.mushafRecitationId)
              .firstOrNull
              ?.id ??
          _preferredRecitation(recitations)?.id;

      final second = await Future.wait<Object>(<Future<Object>>[
        if (_translationSourceId != null)
          _safeTranslations(
            quran,
            sourceId: _translationSourceId!,
            surah: widget.reference.surah,
          )
        else
          Future<List<QuranAyahTranslation>>.value(
            const <QuranAyahTranslation>[],
          ),
        if (_tafsirSourceId != null)
          _safeTafsirs(
            quran,
            sourceId: _tafsirSourceId!,
            surah: widget.reference.surah,
          )
        else
          Future<List<QuranAyahTafsir>>.value(const <QuranAyahTafsir>[]),
      ]);
      if (!_isCurrentLoad(scope, request)) return;
      final translations = second[0] as List<QuranAyahTranslation>;
      final tafsirs = second[1] as List<QuranAyahTafsir>;
      setState(() {
        _bookmarked = bookmarked;
        _highlightColor = normalizeAyahHighlightColor(
          annotation?['color_key']?.toString(),
        );
        _highlighted = annotation != null;
        _note = annotation?['note']?.toString() ?? '';
        _details = _AyahDetails(
          ayah: ayahs
              .where((item) => item.number == widget.reference.ayah)
              .firstOrNull,
          translationEditions: translationEditions,
          tafsirEditions: tafsirEditions,
          recitations: recitations,
          translation: translations
              .where((item) => item.ayah == widget.reference.ayah)
              .firstOrNull,
          tafsir: tafsirs
              .where(
                (item) =>
                    item.covers(widget.reference.surah, widget.reference.ayah),
              )
              .firstOrNull,
        );
        _loading = false;
      });
    } on AccountScopeChanged {
      return;
    } on Object catch (error) {
      if (!_isCurrentLoad(scope, request)) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Recitation? _preferredRecitation(List<Recitation> recitations) {
    final current = ref.read(audioControllerProvider);
    final activeReciterId = current.channel == AudioPlaybackChannel.mushaf
        ? current.reciter?.id
        : null;
    return recitations
            .where((item) => item.reciter.id == activeReciterId)
            .firstOrNull ??
        recitations
            .where((item) => item.code.startsWith('qf-7-'))
            .firstOrNull ??
        recitations.firstOrNull;
  }

  Future<List<Recitation>> _safeRecitations(AudioRepository repository) async {
    try {
      return repository.recitationsForRole(AudioRecitationRole.ayahPlayback);
    } on Object {
      return const <Recitation>[];
    }
  }

  Future<List<QuranTranslationEdition>> _safeTranslationEditions(
    QuranRepository repository,
    String locale,
  ) async {
    try {
      return await repository.translationEditions(locale);
    } on Object {
      return const <QuranTranslationEdition>[];
    }
  }

  Future<List<QuranTafsirEdition>> _safeTafsirEditions(
    QuranRepository repository,
    String locale,
  ) async {
    try {
      return await repository.tafsirEditions(locale);
    } on Object {
      return const <QuranTafsirEdition>[];
    }
  }

  Future<List<QuranAyahTranslation>> _safeTranslations(
    QuranRepository repository, {
    required int sourceId,
    required int surah,
  }) async {
    try {
      return await repository.translations(sourceId: sourceId, surah: surah);
    } on Object {
      return const <QuranAyahTranslation>[];
    }
  }

  Future<List<QuranAyahTafsir>> _safeTafsirs(
    QuranRepository repository, {
    required int sourceId,
    required int surah,
  }) async {
    try {
      return await repository.tafsirs(sourceId: sourceId, surah: surah);
    } on Object {
      return const <QuranAyahTafsir>[];
    }
  }

  Future<bool> _safeIsBookmarked(
    QuranRepository repository,
    AccountScopeSnapshot scope,
  ) async {
    try {
      return await repository.isBookmarked(
        widget.reference.surah,
        widget.reference.ayah,
        accountScope: scope,
      );
    } on AccountScopeChanged {
      rethrow;
    } on Object {
      return false;
    }
  }

  Future<Map<String, Object?>?> _safeAnnotationDetails(
    QuranRepository repository,
    AccountScopeSnapshot scope,
  ) async {
    try {
      return await repository.annotationDetails(
        widget.reference.surah,
        widget.reference.ayah,
        accountScope: scope,
      );
    } on AccountScopeChanged {
      rethrow;
    } on Object {
      return null;
    }
  }

  Future<void> _toggleRepeatSelectedAyah() async {
    final controller = ref.read(audioControllerProvider.notifier);
    bool isSelected(IqroAudioState state) {
      return state.channel == AudioPlaybackChannel.mushaf &&
          state.track?.surah == widget.reference.surah &&
          state.rangeStartAyah == widget.reference.ayah &&
          state.rangeEndAyah == widget.reference.ayah;
    }

    if (!isSelected(ref.read(audioControllerProvider))) {
      await _play();
    }
    if (!mounted || !isSelected(ref.read(audioControllerProvider))) return;
    await controller.toggleRepeat();
  }

  Future<void> _chooseHighlightColor() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final key in ayahHighlightColorKeys)
              _colorChoice(context, key, _highlightColorLabel(context, key)),
            if (_highlighted)
              ListTile(
                leading: const Icon(Icons.format_color_reset_outlined),
                title: Text(context.l10n.removeHighlight),
                onTap: () => Navigator.pop(context, _removeHighlightChoice),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    if (selected == _removeHighlightChoice) {
      await _removeHighlight();
      return;
    }
    await _saveAyahAnnotation(note: _note, colorKey: selected);
  }

  static const _removeHighlightChoice = '';

  // The highlight and the note are one annotation, and any annotation is
  // highlighted, so removing the highlight removes the note as well.
  Future<void> _removeHighlight() async {
    if (_note.trim().isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.removeHighlight),
          content: Text(context.l10n.removeHighlightWithNote),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.delete),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    final scope = ref.read(localDatabaseProvider).accountScope.current;
    if (scope == null || !_isCurrentAccount(scope) || _detailsSaving) return;
    setState(() => _detailsSaving = true);
    try {
      await ref
          .read(quranRepositoryProvider)
          .deleteAyahAnnotation(
            widget.reference.surah,
            widget.reference.ayah,
            accountScope: scope,
          );
      if (!_isCurrentAccount(scope) || !mounted) return;
      setState(() {
        _highlighted = false;
        _highlightColor = 'lime';
        _note = '';
      });
      ref.invalidate(ayahAnnotationsProvider(accountScopeKey(scope)));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.highlightRemoved)));
    } on AccountScopeChanged {
      return;
    } on Object {
      if (mounted) _showContentError();
    } finally {
      if (mounted) setState(() => _detailsSaving = false);
    }
  }

  Widget _colorChoice(BuildContext context, String key, String label) {
    return ListTile(
      leading: _ColorDot(color: ayahHighlightColor(key)),
      title: Text(label),
      trailing: _highlighted && key == _highlightColor
          ? const Icon(Icons.check_rounded)
          : null,
      onTap: () => Navigator.pop(context, key),
    );
  }

  Future<void> _editNote() async {
    final result = await showModalBottomSheet<_NoteEditorResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      builder: (_) => _NoteEditorSheet(
        reference: widget.reference,
        initialNote: _note,
        canDelete: _note.trim().isNotEmpty,
      ),
    );
    if (result == null || !mounted) return;
    final saved = await _saveAyahAnnotation(
      note: result.note,
      colorKey: _highlightColor,
    );
    if (!saved || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.deleted || result.note.trim().isEmpty
              ? context.l10n.noteRemoved
              : context.l10n.noteSaved,
        ),
      ),
    );
  }

  Future<bool> _saveAyahAnnotation({
    required String note,
    required String colorKey,
  }) async {
    final scope = ref.read(localDatabaseProvider).accountScope.current;
    if (scope == null || !_isCurrentAccount(scope) || _detailsSaving) {
      return false;
    }
    final normalizedNote = note.trim();
    final normalizedColor = normalizeAyahHighlightColor(colorKey);
    setState(() => _detailsSaving = true);
    try {
      await ref
          .read(quranRepositoryProvider)
          .updateAyahAnnotation(
            widget.reference.surah,
            widget.reference.ayah,
            page: widget.page,
            note: normalizedNote,
            colorKey: normalizedColor,
            accountScope: scope,
          );
      if (!_isCurrentAccount(scope) || !mounted) return false;
      setState(() {
        _note = normalizedNote;
        _highlightColor = normalizedColor;
        _highlighted = true;
      });
      ref.invalidate(ayahAnnotationsProvider(accountScopeKey(scope)));
      return true;
    } on AccountScopeChanged {
      return false;
    } on Object {
      if (mounted) _showContentError();
      return false;
    } finally {
      if (mounted) setState(() => _detailsSaving = false);
    }
  }

  Future<void> _copyAyah() async {
    final ayah = _details?.ayah;
    if (ayah == null || _copyFeedback == _CopyAyahFeedback.copying) return;
    _copyFeedbackTimer?.cancel();
    setState(() => _copyFeedback = _CopyAyahFeedback.copying);
    try {
      await Clipboard.setData(ClipboardData(text: ayah.textUthmani));
      if (!mounted) return;
      _showCopyFeedback(_CopyAyahFeedback.copied);
      unawaited(HapticFeedback.lightImpact().catchError((Object _) {}));
    } on Object {
      if (!mounted) return;
      _showCopyFeedback(_CopyAyahFeedback.failed);
      unawaited(HapticFeedback.vibrate().catchError((Object _) {}));
    }
  }

  void _showCopyFeedback(_CopyAyahFeedback feedback) {
    _copyFeedbackTimer?.cancel();
    setState(() => _copyFeedback = feedback);
    _copyFeedbackTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) {
        setState(() => _copyFeedback = _CopyAyahFeedback.idle);
      }
    });
  }

  Future<void> _shareAyah() async {
    final details = _details;
    final ayah = details?.ayah;
    if (details == null || ayah == null) return;
    final locale = Localizations.localeOf(context).languageCode;
    final reference = widget.reference;
    final surahName =
        ref
            .read(quranCatalogProvider)
            .valueOrNull
            ?.surahs
            .where((surah) => surah.number == reference.surah)
            .firstOrNull
            ?.nameFor(locale) ??
        '${context.l10n.surah} ${reference.surah}';
    final edition = details.translationEditions
        .where((item) => item.sourceId == _translationSourceId)
        .firstOrNull;
    final box = context.findRenderObject();
    await shareContent(
      context,
      ayahContentShare(
        locale: locale,
        surahName: surahName,
        surah: reference.surah,
        ayah: reference.ayah,
        arabic: ayah.textUthmani,
        translation: details.translation?.text ?? '',
        translator: edition == null
            ? ''
            : edition.authorName.trim().isEmpty
            ? edition.name
            : edition.authorName,
        readInIqro: context.l10n.shareReadInIqro,
      ),
      origin: box is RenderBox
          ? box.localToGlobal(Offset.zero) & box.size
          : null,
    );
  }

  Future<void> _play() async {
    final recitation = _details?.recitations
        .where((item) => item.id == _recitationId)
        .firstOrNull;
    if (recitation == null) return;
    final database = ref.read(localDatabaseProvider);
    final scope = database.accountScope.current;
    if (scope == null) return;
    final controller = ref.read(audioControllerProvider.notifier);
    final navigationEpoch = controller.navigationEpoch;
    final repository = ref.read(audioRepositoryProvider);
    final surahName = '${context.l10n.surah} ${widget.reference.surah}';
    final request = ++_audioRequest;
    setState(() => _audioLoading = true);
    try {
      final playback = await repository.playback(
        recitationId: recitation.id,
        surah: widget.reference.surah,
      );
      if (!_isCurrentAudioRequest(
        scope,
        controller,
        request,
        navigationEpoch: navigationEpoch,
      )) {
        return;
      }
      await controller.loadPlayback(
        playback: playback,
        reciter: reciterWithPersonPortrait(
          recitation.reciter,
          apiBaseUrl: ref.read(appConfigProvider).apiBaseUrl,
          reciters: _details!.recitations.map((item) => item.reciter),
        ),
        surahName: surahName,
        channel: AudioPlaybackChannel.mushaf,
        startAyah: widget.reference.ayah,
        endAyah: widget.reference.ayah,
      );
      if (_isCurrentAudioRequest(
            scope,
            controller,
            request,
            navigationEpoch: navigationEpoch,
          ) &&
          ref.read(appPreferencesProvider).mushafRecitationId !=
              recitation.id) {
        unawaited(
          ref
              .read(appPreferencesProvider.notifier)
              .setMushafRecitation(recitation.id),
        );
      }
    } on AccountScopeChanged {
      return;
    } on Object {
      if (_isCurrentAudioRequest(
        scope,
        controller,
        request,
        navigationEpoch: navigationEpoch,
      )) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.noAudio)));
      }
    } finally {
      if (mounted && request == _audioRequest) {
        setState(() => _audioLoading = false);
      }
    }
  }

  bool _isCurrentAudioRequest(
    AccountScopeSnapshot scope,
    AudioController controller,
    int request, {
    int? navigationEpoch,
  }) {
    return mounted &&
        request == _audioRequest &&
        (navigationEpoch == null ||
            controller.navigationEpoch == navigationEpoch) &&
        ref.read(sessionProvider).valueOrNull?.userId == scope.userId &&
        ref.read(localDatabaseProvider).accountScope.isCurrent(scope) &&
        identical(ref.read(audioControllerProvider.notifier), controller);
  }

  Future<void> _toggleBookmark() async {
    final scope = ref.read(localDatabaseProvider).accountScope.current;
    if (scope == null || !_isCurrentAccount(scope)) return;
    final request = ++_bookmarkRequest;
    setState(() => _bookmarkLoading = true);
    try {
      final active = await ref
          .read(quranRepositoryProvider)
          .toggleBookmark(
            widget.reference.surah,
            widget.reference.ayah,
            page: widget.page,
            accountScope: scope,
          );
      if (!_isCurrentBookmark(scope, request) || !mounted) return;
      setState(() {
        _bookmarked = active;
      });
      _invalidateBookmarkProvider(scope);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            active ? context.l10n.bookmarkAdded : context.l10n.bookmarkRemoved,
          ),
        ),
      );
    } on AccountScopeChanged {
      return;
    } on Object {
      if (_isCurrentBookmark(scope, request) && mounted) _showContentError();
    } finally {
      if (mounted && request == _bookmarkRequest) {
        setState(() => _bookmarkLoading = false);
      }
    }
  }

  bool _isCurrentAccount(AccountScopeSnapshot scope) {
    return mounted &&
        _ownerId == scope.userId &&
        ref.read(sessionProvider).valueOrNull?.userId == scope.userId &&
        ref.read(localDatabaseProvider).accountScope.isCurrent(scope);
  }

  bool _isCurrentLoad(AccountScopeSnapshot scope, int request) =>
      request == _loadRequest && _isCurrentAccount(scope);

  bool _isCurrentBookmark(AccountScopeSnapshot scope, int request) =>
      request == _bookmarkRequest && _isCurrentAccount(scope);

  void _invalidateBookmarkProvider(AccountScopeSnapshot scope) {
    ref.invalidate(
      ayahBookmarkProvider((
        account: accountScopeKey(scope),
        surah: widget.reference.surah,
        ayah: widget.reference.ayah,
      )),
    );
  }

  Future<void> _changeTranslation(int sourceId) async {
    final scope = ref.read(localDatabaseProvider).accountScope.current;
    if (scope == null || !_isCurrentAccount(scope)) return;
    final request = ++_translationRequest;
    setState(() => _translationSourceId = sourceId);
    try {
      final translations = await ref
          .read(quranRepositoryProvider)
          .translations(sourceId: sourceId, surah: widget.reference.surah);
      if (request != _translationRequest ||
          !_isCurrentAccount(scope) ||
          _details == null ||
          _translationSourceId != sourceId) {
        return;
      }
      setState(() {
        _details = _details!.withTranslation(
          translations
              .where((item) => item.ayah == widget.reference.ayah)
              .firstOrNull,
        );
      });
      unawaited(
        ref
            .read(appPreferencesProvider.notifier)
            .setPreferredTranslationSource(sourceId),
      );
    } on Object {
      if (request == _translationRequest && _isCurrentAccount(scope)) {
        _showContentError();
      }
    }
  }

  Future<void> _changeTafsir(int sourceId) async {
    final scope = ref.read(localDatabaseProvider).accountScope.current;
    if (scope == null || !_isCurrentAccount(scope)) return;
    final request = ++_tafsirRequest;
    setState(() => _tafsirSourceId = sourceId);
    try {
      final tafsirs = await ref
          .read(quranRepositoryProvider)
          .tafsirs(sourceId: sourceId, surah: widget.reference.surah);
      if (request != _tafsirRequest ||
          !_isCurrentAccount(scope) ||
          _details == null ||
          _tafsirSourceId != sourceId) {
        return;
      }
      setState(() {
        _details = _details!.withTafsir(
          tafsirs
              .where(
                (item) =>
                    item.covers(widget.reference.surah, widget.reference.ayah),
              )
              .firstOrNull,
        );
      });
      unawaited(
        ref
            .read(appPreferencesProvider.notifier)
            .setPreferredTafsirSource(sourceId),
      );
    } on Object {
      if (request == _tafsirRequest && _isCurrentAccount(scope)) {
        _showContentError();
      }
    }
  }

  void _showContentError() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.networkError)));
  }
}

class _ContentSection extends StatelessWidget {
  const _ContentSection({
    required this.icon,
    required this.title,
    required this.body,
    required this.emptyMessage,
    required this.footnotes,
    this.selector,
    this.source,
    this.range,
  });

  final IconData icon;
  final String title;
  final String? body;
  final String emptyMessage;
  final List<String> footnotes;
  final Widget? selector;
  final String? source;
  final String? range;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              IqroIcon(icon, size: 20),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (range != null)
                Text(range!, style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
          if (selector != null) ...<Widget>[
            const SizedBox(height: 8),
            selector!,
          ] else if (source != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(source!, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          Text(
            body?.isNotEmpty == true ? body! : emptyMessage,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(height: 1.55),
          ),
          if (footnotes.isNotEmpty) ...<Widget>[
            const Divider(height: 28),
            for (var index = 0; index < footnotes.length; index += 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${index + 1}. ${footnotes[index]}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _AyahDetails {
  const _AyahDetails({
    required this.ayah,
    required this.translationEditions,
    required this.tafsirEditions,
    required this.recitations,
    required this.translation,
    required this.tafsir,
  });

  final QuranAyah? ayah;
  final List<QuranTranslationEdition> translationEditions;
  final List<QuranTafsirEdition> tafsirEditions;
  final List<Recitation> recitations;
  final QuranAyahTranslation? translation;
  final QuranAyahTafsir? tafsir;

  _AyahDetails withTranslation(QuranAyahTranslation? value) {
    return _AyahDetails(
      ayah: ayah,
      translationEditions: translationEditions,
      tafsirEditions: tafsirEditions,
      recitations: recitations,
      translation: value,
      tafsir: tafsir,
    );
  }

  _AyahDetails withTafsir(QuranAyahTafsir? value) {
    return _AyahDetails(
      ayah: ayah,
      translationEditions: translationEditions,
      tafsirEditions: tafsirEditions,
      recitations: recitations,
      translation: translation,
      tafsir: value,
    );
  }
}

class _NoteEditorResult {
  const _NoteEditorResult({required this.note}) : deleted = false;

  const _NoteEditorResult.delete() : note = '', deleted = true;

  final String note;
  final bool deleted;
}

class _NoteEditorSheet extends StatefulWidget {
  const _NoteEditorSheet({
    required this.reference,
    required this.initialNote,
    required this.canDelete,
  });

  final QuranAyahReference reference;
  final String initialNote;
  final bool canDelete;

  @override
  State<_NoteEditorSheet> createState() => _NoteEditorSheetState();
}

class _NoteEditorSheetState extends State<_NoteEditorSheet> {
  late final TextEditingController _controller;
  late int _wordCount;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNote);
    _wordCount = _countWords(_controller.text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static int _countWords(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 0;
    return trimmed.split(RegExp(r'\s+')).length;
  }

  void _save() {
    Navigator.of(context).pop(_NoteEditorResult(note: _controller.text));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: Material(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: media.size.height * .9),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.onSurfaceVariant.withValues(alpha: .45),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '${context.l10n.ayah} ${widget.reference.key}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton.filled(
                        tooltip: context.l10n.save,
                        onPressed: _save,
                        icon: const Icon(Icons.check_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(child: Divider(color: scheme.outlineVariant)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Text(
                          context.l10n.noteLabel,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: scheme.onSurfaceVariant,
                                letterSpacing: 2.2,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      Expanded(child: Divider(color: scheme.outlineVariant)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    constraints: const BoxConstraints(minHeight: 230),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      minLines: 8,
                      maxLines: 12,
                      maxLength: 2000,
                      onChanged: (value) =>
                          setState(() => _wordCount = _countWords(value)),
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: context.l10n.noteHint,
                        contentPadding: EdgeInsets.zero,
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Text(
                        context.l10n.noteWordCount(_wordCount),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      if (widget.canDelete)
                        TextButton.icon(
                          onPressed: () => Navigator.of(
                            context,
                          ).pop(const _NoteEditorResult.delete()),
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: Text(context.l10n.removeNote),
                          style: TextButton.styleFrom(
                            foregroundColor: scheme.error,
                          ),
                        ),
                    ],
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

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconColor,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? iconColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final foreground = enabled
        ? (iconColor ?? scheme.onPrimaryContainer)
        : scheme.onSurface.withValues(alpha: .38);
    return ListTile(
      contentPadding: const EdgeInsetsDirectional.fromSTEB(14, 4, 10, 4),
      minVerticalPadding: 8,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: enabled
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, animation) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutBack,
            );
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: curved, child: child),
            );
          },
          child: IqroIcon(
            icon,
            key: ValueKey<IconData>(icon),
            color: foreground,
            size: 21,
          ),
        ),
      ),
      title: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        layoutBuilder: (currentChild, previousChildren) => Stack(
          alignment: AlignmentDirectional.centerStart,
          children: <Widget>[...previousChildren, ?currentChild],
        ),
        child: Text(title, key: ValueKey<String>(title)),
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing:
          trailing ??
          (onTap == null ? null : const Icon(Icons.chevron_right_rounded)),
      onTap: onTap,
    );
  }
}

class _HighlightDots extends StatelessWidget {
  const _HighlightDots({required this.colorKey});

  /// The ayah's colour, or null when it is not highlighted.
  final String? colorKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final key in ayahHighlightColorKeys) ...<Widget>[
          _ColorDot(
            color: ayahHighlightColor(key),
            selected:
                colorKey != null &&
                key == normalizeAyahHighlightColor(colorKey),
          ),
          if (key != ayahHighlightColorKeys.last) const SizedBox(width: 5),
        ],
      ],
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color, this.selected = false});

  final Color color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.onSurface;
    final size = selected ? 18.0 : 14.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? outline : outline.withValues(alpha: .18),
          width: selected ? 2 : 1,
        ),
      ),
    );
  }
}

String _highlightColorLabel(BuildContext context, String key) {
  return switch (key) {
    'yellow' => context.l10n.highlightColorYellow,
    'blue' => context.l10n.highlightColorBlue,
    'pink' => context.l10n.highlightColorPink,
    'lime' => context.l10n.highlightColorLime,
    'lavender' => context.l10n.highlightColorLavender,
    _ => context.l10n.highlightColorEmerald,
  };
}
