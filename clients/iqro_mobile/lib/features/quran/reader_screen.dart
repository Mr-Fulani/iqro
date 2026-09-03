import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/audio/audio_controller.dart';
import '../../core/auth/account_scope.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/storage/preferences_store.dart';
import '../../core/theme/iqro_theme.dart';
import 'ayah_action_sheet.dart';
import 'quran_models.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({required this.surah, this.initialAyah = 1, super.key});
  final int surah;
  final int initialAyah;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  final _bookmarks = <int>{};
  final _scrollController = ScrollController();
  final _viewportKey = GlobalKey();
  final _ayahKeys = <int, GlobalKey>{};
  var _showTranslation = true;
  var _showTafsir = false;
  var _selectedAyah = 1;
  var _contentInitialized = false;
  var _contentLoading = false;
  int? _audioLoadingAyah;
  List<QuranTranslationEdition> _translationEditions = const [];
  List<QuranTafsirEdition> _tafsirEditions = const [];
  int? _translationSourceId;
  int? _tafsirSourceId;
  Map<int, QuranAyahTranslation> _translations = const {};
  Map<int, QuranAyahTafsir> _tafsirs = const {};
  var _restoreScheduled = false;
  var _contentRestoreScheduled = false;
  var _restoringPosition = false;
  var _readerWasDragged = false;
  int? _lastPersistedAyah;
  AccountScopeKey? _accountKey;
  var _audioRequest = 0;
  AccountScopeSnapshot? _initialAccountScope;

  @override
  void initState() {
    super.initState();
    _selectedAyah = widget.initialAyah;
    _initialAccountScope = ref.read(localDatabaseProvider).accountScope.current;
    _accountKey = _initialAccountScope == null
        ? null
        : accountScopeKey(_initialAccountScope!);
    if (_accountKey != null) _loadBookmarks(_accountKey!);
  }

  @override
  void dispose() {
    _audioRequest += 1;
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_contentInitialized) return;
    _contentInitialized = true;
    unawaited(_loadReaderContent());
  }

  Future<void> _loadBookmarks(AccountScopeKey expectedAccount) async {
    late final List<Map<String, Object?>> rows;
    try {
      rows = await ref.read(quranRepositoryProvider).bookmarks();
    } on AccountScopeChanged {
      // A rapid account switch invalidates the scoped read. The next owner
      // schedules its own reload from build().
      return;
    } on Object catch (error, stack) {
      if (_isCurrentKey(expectedAccount)) {
        FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stack),
        );
      }
      return;
    }
    if (!_isCurrentKey(expectedAccount)) return;
    setState(() {
      _bookmarks
        ..clear()
        ..addAll(
          rows
              .where((row) => row['surah'] == widget.surah)
              .map((row) => row['ayah']! as int),
        );
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeAccount = ref.watch(activeAccountScopeKeyProvider);
    if (activeAccount != _accountKey) {
      _accountKey = activeAccount;
      _audioRequest += 1;
      _audioLoadingAyah = null;
      _bookmarks.clear();
      _lastPersistedAyah = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _currentAccountKey() == activeAccount) {
          context.go('/app?tab=1');
        }
      });
      // Never paint or persist the previous account's route-derived location.
      return const Scaffold(body: IqroLoading());
    }
    final ayahs = ref.watch(ayahsProvider(widget.surah));
    final catalog = ref.watch(quranCatalogProvider).valueOrNull;
    final audio = ref.watch(
      audioControllerProvider.select(
        (value) => (
          surah: value.track?.surah,
          ayah: value.activeAyah,
          playing: value.playing,
        ),
      ),
    );
    final locale = Localizations.localeOf(context).languageCode;
    final surah = catalog?.surahs
        .where((item) => item.number == widget.surah)
        .firstOrNull;
    final title =
        surah?.nameFor(locale) ?? '${context.l10n.surah} ${widget.surah}';
    return Scaffold(
      appBar: IqroTopBar(
        title: title,
        subtitle:
            '${context.l10n.surah} ${widget.surah} · ${surah?.ayahCount ?? ''} ${context.l10n.ayahs}',
        actions: <Widget>[
          IconButton(
            tooltip: context.l10n.readerSettings,
            onPressed: _showSettings,
            icon: const Icon(Icons.tune),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ayahs.when(
        loading: () => const IqroLoading(),
        error: (error, stack) => IqroAsyncError(
          title: context.l10n.noQuranData,
          onRetry: () => ref.invalidate(ayahsProvider(widget.surah)),
        ),
        data: (items) => Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 6, 14, 8),
              child: IqroStatusBanner(
                icon: Icons.sync,
                title: context.l10n.savedAutomatically,
                actionLabel: context.l10n.mushafMode,
                onAction: () async {
                  final page =
                      items
                          .where((item) => item.number == _selectedAyah)
                          .firstOrNull
                          ?.pages
                          .firstOrNull ??
                      surah?.firstPage ??
                      1;
                  await ref
                      .read(appPreferencesProvider.notifier)
                      .setReaderMode(ReaderMode.mushaf);
                  if (!context.mounted) return;
                  context.push(
                    '/mushaf?page=$page&surah=${widget.surah}&ayah=$_selectedAyah',
                  );
                },
              ),
            ),
            Expanded(child: _readerList(items, surah, title, audio)),
          ],
        ),
      ),
    );
  }

  Widget _readerList(
    List<QuranAyah> items,
    Surah? surah,
    String title,
    ({int? surah, int? ayah, bool playing}) audio,
  ) {
    _schedulePositionRestore(items);
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth != 0) return false;
        if (notification is ScrollStartNotification &&
            notification.dragDetails != null) {
          _readerWasDragged = true;
        }
        if (notification is ScrollEndNotification && !_restoringPosition) {
          unawaited(_persistTopVisibleAyah(items));
        }
        return false;
      },
      child: ListView.builder(
        key: _viewportKey,
        controller: _scrollController,
        padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 14, 100),
        itemCount: items.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _ReaderIntro(surah: surah, title: title);
          }
          final ayah = items[index - 1];
          final audioActive =
              audio.surah == ayah.surahNumber && audio.ayah == ayah.number;
          return Padding(
            key: _ayahKeys.putIfAbsent(ayah.number, GlobalKey.new),
            padding: const EdgeInsets.only(bottom: 10),
            child: _AyahCard(
              ayah: ayah,
              selected: ayah.number == _selectedAyah,
              audioActive: audioActive,
              audioPlaying: audioActive && audio.playing,
              audioLoading: _audioLoadingAyah == ayah.number,
              bookmarked: _bookmarks.contains(ayah.number),
              showTranslation: _showTranslation,
              showTafsir: _showTafsir,
              translation: _translations[ayah.number],
              tafsir: _tafsirs[ayah.number],
              contentLoading: _contentLoading,
              onSelected: () => _select(ayah),
              onBookmark: () => _toggleBookmark(ayah),
              onPlay: () => audioActive
                  ? ref.read(audioControllerProvider.notifier).toggle()
                  : _play(ayah, title),
            ),
          );
        },
      ),
    );
  }

  void _schedulePositionRestore(List<QuranAyah> items) {
    if (items.isEmpty) return;
    final scope = _initialAccountScope;
    if (scope == null) return;
    if (!_restoreScheduled) {
      _restoreScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_restorePosition(items, scope));
      });
      return;
    }
    if (!_contentLoading && !_contentRestoreScheduled && !_readerWasDragged) {
      _contentRestoreScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_readerWasDragged) {
          unawaited(_restorePosition(items, scope));
        }
      });
    }
  }

  Future<void> _restorePosition(
    List<QuranAyah> items,
    AccountScopeSnapshot scope,
  ) async {
    if (!_isCurrentAccount(scope)) return;
    final target = items
        .where((item) => item.number == widget.initialAyah)
        .firstOrNull;
    if (target == null || !_scrollController.hasClients) {
      return;
    }
    if (target.number <= 1) {
      await _persistPosition(target, accountScope: scope);
      return;
    }
    _restoringPosition = true;
    try {
      for (var attempt = 0; attempt < 4 && mounted; attempt++) {
        final targetContext = _ayahKeys[target.number]?.currentContext;
        if (targetContext != null && targetContext.mounted) {
          await Scrollable.ensureVisible(
            targetContext,
            alignment: .03,
            duration: attempt == 0
                ? Duration.zero
                : const Duration(milliseconds: 180),
          );
          if (!_isCurrentAccount(scope)) return;
          await _persistPosition(target, accountScope: scope);
          return;
        }
        final ratio = (target.number - 1) / items.length;
        final offset = _scrollController.position.maxScrollExtent * ratio;
        _scrollController.jumpTo(
          offset.clamp(0, _scrollController.position.maxScrollExtent),
        );
        await WidgetsBinding.instance.endOfFrame;
        if (!_isCurrentAccount(scope)) return;
      }
      await _persistPosition(target, accountScope: scope);
    } finally {
      _restoringPosition = false;
    }
  }

  Future<void> _persistTopVisibleAyah(List<QuranAyah> items) async {
    final scope = ref.read(localDatabaseProvider).accountScope.current;
    if (scope == null || !_isCurrentAccount(scope)) return;
    final viewportContext = _viewportKey.currentContext;
    if (viewportContext == null) return;
    final viewportBox = viewportContext.findRenderObject();
    if (viewportBox is! RenderBox || !viewportBox.hasSize) return;
    final viewportTop = viewportBox.localToGlobal(Offset.zero).dy;
    final viewportBottom = viewportTop + viewportBox.size.height;
    QuranAyah? candidate;
    QuranAyah? fallback;
    var fallbackVisible = 0.0;
    for (final ayah in items) {
      final itemContext = _ayahKeys[ayah.number]?.currentContext;
      final itemBox = itemContext?.findRenderObject();
      if (itemBox is! RenderBox || !itemBox.hasSize) continue;
      final itemTop = itemBox.localToGlobal(Offset.zero).dy;
      final itemBottom = itemTop + itemBox.size.height;
      final visible =
          (itemBottom.clamp(viewportTop, viewportBottom) -
                  itemTop.clamp(viewportTop, viewportBottom))
              .clamp(0, itemBox.size.height)
              .toDouble();
      if (visible > fallbackVisible) {
        fallback = ayah;
        fallbackVisible = visible;
      }
      if (visible >= (itemBox.size.height * .2).clamp(36, 96)) {
        candidate = ayah;
        break;
      }
    }
    await _persistPosition(candidate ?? fallback, accountScope: scope);
  }

  Future<void> _persistPosition(
    QuranAyah? ayah, {
    AccountScopeSnapshot? accountScope,
  }) async {
    if (ayah == null || ayah.number == _lastPersistedAyah) return;
    final scope =
        accountScope ?? ref.read(localDatabaseProvider).accountScope.current;
    if (scope == null || !_isCurrentAccount(scope)) return;
    final previousAyah = _lastPersistedAyah;
    _lastPersistedAyah = ayah.number;
    try {
      await ref
          .read(quranRepositoryProvider)
          .savePosition(
            surah: ayah.surahNumber,
            ayah: ayah.number,
            page: ayah.pages.firstOrNull ?? 1,
            accountScope: scope,
          );
      if (_isCurrentAccount(scope)) {
        ref.invalidate(readingPositionProvider(accountScopeKey(scope)));
      }
    } on AccountScopeChanged {
      if (_lastPersistedAyah == ayah.number) {
        _lastPersistedAyah = previousAyah;
      }
    }
  }

  Future<void> _select(QuranAyah ayah) async {
    final scope = ref.read(localDatabaseProvider).accountScope.current;
    if (scope == null || !_isCurrentAccount(scope)) return;
    setState(() => _selectedAyah = ayah.number);
    _lastPersistedAyah = null;
    await _persistPosition(ayah, accountScope: scope);
    if (!_isCurrentAccount(scope) || !mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      builder: (context) => AyahActionSheet(
        reference: QuranAyahReference(
          id: ayah.id,
          surah: ayah.surahNumber,
          ayah: ayah.number,
        ),
        page: ayah.pages.firstOrNull ?? 1,
      ),
    );
  }

  Future<void> _toggleBookmark(QuranAyah ayah) async {
    final scope = ref.read(localDatabaseProvider).accountScope.current;
    if (scope == null || !_isCurrentAccount(scope)) return;
    try {
      final active = await ref
          .read(quranRepositoryProvider)
          .toggleBookmark(
            ayah.surahNumber,
            ayah.number,
            page: ayah.pages.firstOrNull,
            accountScope: scope,
          );
      if (!_isCurrentAccount(scope) || !mounted) return;
      setState(
        () => active
            ? _bookmarks.add(ayah.number)
            : _bookmarks.remove(ayah.number),
      );
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
      if (_isCurrentAccount(scope) && mounted) _showOptionalContentError();
    }
  }

  bool _isCurrentAccount(AccountScopeSnapshot scope) {
    return mounted &&
        _accountKey == accountScopeKey(scope) &&
        ref.read(localDatabaseProvider).accountScope.isCurrent(scope);
  }

  bool _isCurrentKey(AccountScopeKey key) =>
      mounted && _accountKey == key && _currentAccountKey() == key;

  AccountScopeKey? _currentAccountKey() {
    final scope = ref.read(localDatabaseProvider).accountScope.current;
    return scope == null ? null : accountScopeKey(scope);
  }

  Future<void> _play(QuranAyah ayah, String surahName) async {
    if (_audioLoadingAyah != null) return;
    final database = ref.read(localDatabaseProvider);
    final scope = database.accountScope.current;
    if (scope == null) return;
    final controller = ref.read(audioControllerProvider.notifier);
    final repository = ref.read(audioRepositoryProvider);
    final activeReciterId = ref.read(audioControllerProvider).reciter?.id;
    final preferredRecitationId = ref
        .read(appPreferencesProvider)
        .preferredRecitationId;
    final request = ++_audioRequest;
    setState(() => _audioLoadingAyah = ayah.number);
    try {
      final recitations = (await repository.recitations())
          .where((item) => item.timingsAvailable)
          .toList(growable: false);
      if (!_isCurrentAudioRequest(scope, controller, request)) return;
      final recitation =
          recitations
              .where((item) => item.id == preferredRecitationId)
              .firstOrNull ??
          recitations
              .where((item) => item.reciter.id == activeReciterId)
              .firstOrNull ??
          recitations
              .where((item) => item.code.startsWith('qf-7-'))
              .firstOrNull ??
          recitations.firstOrNull;
      if (recitation == null) throw const FormatException('no recitation');
      final playback = await repository.playback(
        recitationId: recitation.id,
        surah: ayah.surahNumber,
      );
      if (!_isCurrentAudioRequest(scope, controller, request)) return;
      await controller.loadPlayback(
        playback: playback,
        reciter: recitation.reciter,
        surahName: surahName,
        startAyah: ayah.number,
        endAyah: ayah.number,
      );
    } on AccountScopeChanged {
      return;
    } on Object {
      if (_isCurrentAudioRequest(scope, controller, request)) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.noAudio)));
      }
    } finally {
      if (mounted && request == _audioRequest) {
        setState(() => _audioLoadingAyah = null);
      }
    }
  }

  bool _isCurrentAudioRequest(
    AccountScopeSnapshot scope,
    AudioController controller,
    int request,
  ) {
    return mounted &&
        request == _audioRequest &&
        ref.read(localDatabaseProvider).accountScope.isCurrent(scope) &&
        identical(ref.read(audioControllerProvider.notifier), controller);
  }

  Future<void> _loadReaderContent() async {
    setState(() => _contentLoading = true);
    try {
      final locale = Localizations.localeOf(context).languageCode;
      final repository = ref.read(quranRepositoryProvider);
      final catalogs = await Future.wait<Object>(<Future<Object>>[
        repository.translationEditions(locale),
        repository.tafsirEditions(locale),
      ]);
      final translations = catalogs[0] as List<QuranTranslationEdition>;
      final tafsirs = catalogs[1] as List<QuranTafsirEdition>;
      final preferences = ref.read(appPreferencesProvider);
      _translationSourceId ??=
          translations
              .where(
                (item) =>
                    item.sourceId == preferences.preferredTranslationSourceId,
              )
              .firstOrNull
              ?.sourceId ??
          translations.firstOrNull?.sourceId;
      _tafsirSourceId ??=
          tafsirs
              .where(
                (item) => item.sourceId == preferences.preferredTafsirSourceId,
              )
              .firstOrNull
              ?.sourceId ??
          tafsirs.firstOrNull?.sourceId;
      if (!mounted) return;
      setState(() {
        _translationEditions = translations;
        _tafsirEditions = tafsirs;
      });
      await Future.wait<void>(<Future<void>>[
        if (_translationSourceId != null)
          _loadTranslation(_translationSourceId!),
        if (_tafsirSourceId != null) _loadTafsir(_tafsirSourceId!),
      ]);
    } on Object {
      // The reader remains usable with Arabic text when optional localized
      // content has not yet been cached and the network is unavailable.
    } finally {
      if (mounted) setState(() => _contentLoading = false);
    }
  }

  Future<void> _loadTranslation(int sourceId) async {
    _translationSourceId = sourceId;
    try {
      final items = await ref
          .read(quranRepositoryProvider)
          .translations(sourceId: sourceId, surah: widget.surah);
      if (!mounted || _translationSourceId != sourceId) return;
      setState(() {
        _translations = <int, QuranAyahTranslation>{
          for (final item in items) item.ayah: item,
        };
      });
      unawaited(
        ref
            .read(appPreferencesProvider.notifier)
            .setPreferredTranslationSource(sourceId),
      );
    } on Object {
      if (mounted) _showOptionalContentError();
    }
  }

  Future<void> _loadTafsir(int sourceId) async {
    _tafsirSourceId = sourceId;
    try {
      final items = await ref
          .read(quranRepositoryProvider)
          .tafsirs(sourceId: sourceId, surah: widget.surah);
      if (!mounted || _tafsirSourceId != sourceId) return;
      setState(() {
        _tafsirs = _indexTafsirs(items);
      });
      unawaited(
        ref
            .read(appPreferencesProvider.notifier)
            .setPreferredTafsirSource(sourceId),
      );
    } on Object {
      if (mounted) _showOptionalContentError();
    }
  }

  Map<int, QuranAyahTafsir> _indexTafsirs(List<QuranAyahTafsir> items) {
    final indexed = <int, QuranAyahTafsir>{};
    for (final item in items) {
      for (var ayah = 1; ayah <= 286; ayah++) {
        if (item.covers(widget.surah, ayah)) indexed[ayah] = item;
      }
    }
    return indexed;
  }

  void _showOptionalContentError() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.networkError)));
  }

  Future<void> _showSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return SingleChildScrollView(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        context.l10n.readerSettings,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10n.translation),
                  subtitle: Text(
                    _translationEditions
                            .where(
                              (item) => item.sourceId == _translationSourceId,
                            )
                            .firstOrNull
                            ?.name ??
                        context.l10n.translationUnavailable,
                  ),
                  value: _showTranslation,
                  onChanged: _translationEditions.isEmpty
                      ? null
                      : (value) {
                          setState(() => _showTranslation = value);
                          setSheetState(() {});
                        },
                ),
                if (_translationEditions.length > 1 && _showTranslation)
                  DropdownButtonFormField<int>(
                    initialValue: _translationSourceId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: context.l10n.translation,
                    ),
                    items: _translationEditions
                        .map(
                          (item) => DropdownMenuItem<int>(
                            value: item.sourceId,
                            child: Text(
                              item.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value == null) return;
                      unawaited(_loadTranslation(value));
                      setSheetState(() {});
                    },
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10n.tafsir),
                  subtitle: Text(
                    _tafsirEditions
                            .where((item) => item.sourceId == _tafsirSourceId)
                            .firstOrNull
                            ?.name ??
                        context.l10n.tafsirUnavailable,
                  ),
                  value: _showTafsir,
                  onChanged: _tafsirEditions.isEmpty
                      ? null
                      : (value) {
                          setState(() => _showTafsir = value);
                          setSheetState(() {});
                        },
                ),
                if (_tafsirEditions.length > 1 && _showTafsir)
                  DropdownButtonFormField<int>(
                    initialValue: _tafsirSourceId,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: context.l10n.tafsir),
                    items: _tafsirEditions
                        .map(
                          (item) => DropdownMenuItem<int>(
                            value: item.sourceId,
                            child: Text(
                              item.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value == null) return;
                      unawaited(_loadTafsir(value));
                      setSheetState(() {});
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ReaderIntro extends StatelessWidget {
  const _ReaderIntro({required this.surah, required this.title});
  final Surah? surah;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 18),
      decoration: BoxDecoration(
        color: context.iqroColors.ink,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: <Widget>[
          Text(
            surah?.nameAr ?? title,
            textDirection: TextDirection.rtl,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontFamily: 'serif',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            surah?.revelationType == 'meccan'
                ? context.l10n.meccan
                : context.l10n.medinan,
            style: TextStyle(color: Colors.white.withValues(alpha: .72)),
          ),
        ],
      ),
    );
  }
}

class _AyahCard extends StatelessWidget {
  const _AyahCard({
    required this.ayah,
    required this.selected,
    required this.audioActive,
    required this.audioPlaying,
    required this.audioLoading,
    required this.bookmarked,
    required this.showTranslation,
    required this.showTafsir,
    required this.translation,
    required this.tafsir,
    required this.contentLoading,
    required this.onSelected,
    required this.onBookmark,
    required this.onPlay,
  });
  final QuranAyah ayah;
  final bool selected;
  final bool audioActive;
  final bool audioPlaying;
  final bool audioLoading;
  final bool bookmarked;
  final bool showTranslation;
  final bool showTafsir;
  final QuranAyahTranslation? translation;
  final QuranAyahTafsir? tafsir;
  final bool contentLoading;
  final VoidCallback onSelected;
  final VoidCallback onBookmark;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected || audioActive,
      child: IqroCard(
        onTap: onSelected,
        borderColor: audioActive
            ? Theme.of(context).colorScheme.tertiary
            : selected
            ? Theme.of(context).colorScheme.primary
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${ayah.surahNumber}:${ayah.number}',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: context.l10n.listen,
                  onPressed: audioLoading ? null : onPlay,
                  icon: audioLoading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(audioPlaying ? Icons.pause : Icons.play_arrow),
                ),
                IconButton(
                  tooltip: context.l10n.favorites,
                  isSelected: bookmarked,
                  onPressed: onBookmark,
                  selectedIcon: const Icon(Icons.bookmark),
                  icon: const Icon(Icons.bookmark_border),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '${ayah.textUthmani}  ﴿${ayah.number}﴾',
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontFamily: 'serif',
                fontSize: 30,
                height: 1.9,
              ),
            ),
            if (showTranslation) ...<Widget>[
              const Divider(height: 28),
              _ReaderContentBlock(
                icon: Icons.translate,
                title: context.l10n.translation,
                text: translation?.text,
                loading: contentLoading,
                unavailable: context.l10n.translationUnavailable,
              ),
            ],
            if (showTafsir) ...<Widget>[
              const SizedBox(height: 8),
              _ReaderContentBlock(
                icon: Icons.auto_stories_outlined,
                title: context.l10n.tafsir,
                text: tafsir?.text,
                loading: contentLoading,
                unavailable: context.l10n.tafsirUnavailable,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReaderContentBlock extends StatelessWidget {
  const _ReaderContentBlock({
    required this.icon,
    required this.title,
    required this.text,
    required this.loading,
    required this.unavailable,
  });

  final IconData icon;
  final String title;
  final String? text;
  final bool loading;
  final String unavailable;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              if (loading) ...<Widget>[
                const Spacer(),
                const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
          const SizedBox(height: 9),
          Text(
            text?.isNotEmpty == true ? text! : unavailable,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }
}
