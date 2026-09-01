import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../audio/audio_models.dart';
import '../audio/audio_repository.dart';
import 'quran_models.dart';
import 'quran_repository.dart';

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
  var _bookmarked = false;
  int? _translationSourceId;
  int? _tafsirSourceId;
  String? _recitationId;
  var _dependenciesReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dependenciesReady) return;
    _dependenciesReady = true;
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final audio = ref.watch(
      audioControllerProvider.select(
        (value) => (
          playing: value.playing,
          surah: value.track?.surah,
          ayah: value.activeAyah,
          recitationId: value.track?.recitationId,
          rangeStartAyah: value.rangeStartAyah,
          rangeEndAyah: value.rangeEndAyah,
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
        audio.rangeEndAyah == widget.reference.ayah;
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
              : _content(playingThis, loadedThis),
        ),
      ),
    );
  }

  Widget _content(bool playingThis, bool loadedThis) {
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
              Text(
                details.ayah?.textUthmani ?? '',
                textAlign: TextAlign.right,
                textDirection: TextDirection.rtl,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontFamily: 'serif',
                  fontSize: 30,
                  height: 1.85,
                ),
              ),
              const SizedBox(height: 12),
              _actionRow(playingThis, loadedThis),
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
                '${item.reciter.nameFor(locale)} · ${item.style}',
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
          ref
              .read(appPreferencesProvider.notifier)
              .setPreferredRecitation(value),
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final locale = Localizations.localeOf(context).languageCode;
      final quran = ref.read(quranRepositoryProvider);
      final audio = ref.read(audioRepositoryProvider);
      final first = await Future.wait<Object>(<Future<Object>>[
        quran.ayahs(widget.reference.surah),
        _safeTranslationEditions(quran, locale),
        _safeTafsirEditions(quran, locale),
        _safeRecitations(audio),
        _safeBookmark(quran),
      ]);
      final ayahs = first[0] as List<QuranAyah>;
      final translationEditions = first[1] as List<QuranTranslationEdition>;
      final tafsirEditions = first[2] as List<QuranTafsirEdition>;
      final recitations = first[3] as List<Recitation>;
      final bookmarked = first[4] as bool;
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
              .where((item) => item.id == preferences.preferredRecitationId)
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
      if (!mounted) return;
      final translations = second[0] as List<QuranAyahTranslation>;
      final tafsirs = second[1] as List<QuranAyahTafsir>;
      setState(() {
        _bookmarked = bookmarked;
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
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Recitation? _preferredRecitation(List<Recitation> recitations) {
    final activeReciterId = ref.read(audioControllerProvider).reciter?.id;
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
      return (await repository.recitations())
          .where((item) => item.timingsAvailable)
          .toList(growable: false);
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

  Future<bool> _safeBookmark(QuranRepository repository) async {
    try {
      return await repository.isBookmarked(
        widget.reference.surah,
        widget.reference.ayah,
      );
    } on Object {
      return false;
    }
  }

  Future<void> _play() async {
    final recitation = _details?.recitations
        .where((item) => item.id == _recitationId)
        .firstOrNull;
    if (recitation == null) return;
    setState(() => _audioLoading = true);
    try {
      final playback = await ref
          .read(audioRepositoryProvider)
          .playback(recitationId: recitation.id, surah: widget.reference.surah);
      if (!mounted) return;
      await ref
          .read(audioControllerProvider.notifier)
          .loadPlayback(
            playback: playback,
            reciter: recitation.reciter,
            surahName: '${context.l10n.surah} ${widget.reference.surah}',
            startAyah: widget.reference.ayah,
            endAyah: widget.reference.ayah,
          );
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.noAudio)));
      }
    } finally {
      if (mounted) setState(() => _audioLoading = false);
    }
  }

  Future<void> _toggleBookmark() async {
    setState(() => _bookmarkLoading = true);
    try {
      final active = await ref
          .read(quranRepositoryProvider)
          .toggleBookmark(
            widget.reference.surah,
            widget.reference.ayah,
            page: widget.page,
          );
      if (!mounted) return;
      setState(() => _bookmarked = active);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            active ? context.l10n.bookmarkAdded : context.l10n.bookmarkRemoved,
          ),
        ),
      );
    } on Object {
      if (mounted) _showContentError();
    } finally {
      if (mounted) setState(() => _bookmarkLoading = false);
    }
  }

  Future<void> _changeTranslation(int sourceId) async {
    setState(() => _translationSourceId = sourceId);
    try {
      final translations = await ref
          .read(quranRepositoryProvider)
          .translations(sourceId: sourceId, surah: widget.reference.surah);
      if (!mounted || _details == null || _translationSourceId != sourceId) {
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
      if (mounted) _showContentError();
    }
  }

  Future<void> _changeTafsir(int sourceId) async {
    setState(() => _tafsirSourceId = sourceId);
    try {
      final tafsirs = await ref
          .read(quranRepositoryProvider)
          .tafsirs(sourceId: sourceId, surah: widget.reference.surah);
      if (!mounted || _details == null || _tafsirSourceId != sourceId) return;
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
      if (mounted) _showContentError();
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
              Icon(icon, size: 20),
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
