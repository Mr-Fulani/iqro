import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/platform/reader_haptics.dart';
import '../../core/audio/audio_controller.dart';

import '../../app/providers.dart';
import '../../core/auth/account_scope.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/storage/local_database.dart';
import '../../core/storage/preferences_store.dart';
import '../../core/utils/latest_async_work_queue.dart';
import '../audio/mini_player.dart';
import '../audio/audio_models.dart';
import '../audio/reciter_catalog.dart';
import '../audio/reciter_portraits.dart';
import '../memorization/memorize_ayah_sheet.dart';
import '../plan/plan_repository.dart';
import '../tajweed/tajweed_breakdown.dart';
import '../tajweed/tajweed_models.dart';
import 'ayah_annotations.dart';
import 'ayah_action_sheet.dart';
import 'native_mushaf_page.dart';
import 'mushaf_paper.dart';
import 'mushaf_bookmarks_sheet.dart';
import 'mushaf_reader_controls.dart';
import 'mushaf_reciter_sheet.dart';
import 'quick_jump_sheet.dart';
import 'quran_screen.dart';
import 'quran_models.dart';
import 'quran_repository.dart';
import 'surah_open_reporter.dart';
import 'word_range.dart';

/// A stretch of one surah on a Mushaf page, played as one clip.
typedef MushafPageRun = ({int surah, int start, int end});

/// What the Mushaf's play button reads: the page's ayahs from [from] (the
/// first, when it is not on the page) to the last, one run per surah, since a
/// page may end one surah and begin the next.
List<MushafPageRun> mushafPageRuns(
  List<QuranAyahReference> ayahs, {
  QuranAyahReference? from,
}) {
  final first = from == null
      ? 0
      : ayahs.indexWhere(
          (item) => item.surah == from.surah && item.ayah == from.ayah,
        );
  final runs = <MushafPageRun>[];
  for (final item in ayahs.skip(first < 0 ? 0 : first)) {
    final last = runs.isEmpty ? null : runs.last;
    if (last != null && last.surah == item.surah && item.ayah > last.end) {
      runs[runs.length - 1] = (
        surah: last.surah,
        start: last.start,
        end: item.ayah,
      );
    } else {
      runs.add((surah: item.surah, start: item.ayah, end: item.ayah));
    }
  }
  return runs;
}

typedef _PendingPositionSave = ({
  int page,
  QuranAyahReference? preferredReference,
  AccountScopeSnapshot? accountScope,
  Future<MushafPageData> pageData,
});

class MushafScreen extends ConsumerStatefulWidget {
  const MushafScreen({
    required this.initialPage,
    required this.surah,
    required this.ayah,
    this.initialPageIsPhysical = false,
    this.savesReadingPlace = true,
    super.key,
  });

  final int initialPage;
  final int surah;
  final int ayah;
  final bool initialPageIsPhysical;

  /// False when opened from a bookmark or favourite: reading there still
  /// counts for the plan, but it does not move the saved reading place.
  final bool savesReadingPlace;

  @override
  ConsumerState<MushafScreen> createState() => _MushafScreenState();
}

class _MushafScreenState extends ConsumerState<MushafScreen>
    with WidgetsBindingObserver {
  late PageController _pageController;
  bool _resolvingInitialPage = false;
  bool _initialPageError = false;
  int _initialNavigationGeneration = 0;
  int get _pageCount => ref.read(selectedMushafPageCountProvider);
  final _zoomControllers = <int, NativeMushafPageController>{};
  // Keeps the autoDispose page data of the ±2 window alive between swipes.
  final _pageKeepAlive =
      <int, ProviderSubscription<AsyncValue<MushafPageData>>>{};
  var _currentPage = 1;
  var _controlsVisible = false;
  var _zoom = 1.0;
  var _audioLoading = false;
  var _audioRequest = 0;
  var _playerExpanded = false;
  // The page the Mushaf's sound reads and its runs; the sound never leaves it.
  int? _playbackPage;
  QuranAyahReference? _playbackFrom;
  List<MushafPageRun> _runs = const <MushafPageRun>[];
  var _run = 0;
  ProviderSubscription<IqroAudioState>? _audioSubscription;
  var _bookmarkLoading = false;
  var _detailsOpen = false;
  int? _dotTargetPage;
  QuranAyahReference? _selectedAyah;
  QuranAyahReference? _pageReference;
  var _initialPageHandled = false;
  var _positionRequest = 0;
  AccountScopeKey? _accountKey;
  AccountScopeSnapshot? _pageTransitionScope;
  AccountScopeSnapshot? _initialAccountScope;
  ReadingSessionRecorder? _readingSession;
  late final LocalDatabase _database;
  late final QuranRepository _quranRepository;
  late final LatestAsyncWorkQueue<_PendingPositionSave> _positionSaves;
  late final WordRangeController _words;

  @override
  void initState() {
    super.initState();
    _words = WordRangeController(ref)..addListener(_onWords);
    _database = ref.read(localDatabaseProvider);
    _quranRepository = ref.read(quranRepositoryProvider);
    _positionSaves = LatestAsyncWorkQueue<_PendingPositionSave>(
      (request) => _savePagePosition(
        request.page,
        preferredReference: request.preferredReference,
        accountScope: request.accountScope,
        pageData: request.pageData,
      ),
      onError: (error, stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'IQRO Mushaf position persistence',
          ),
        );
      },
    );
    WidgetsBinding.instance.addObserver(this);
    _audioSubscription = ref.listenManual(
      audioControllerProvider,
      _followPageRuns,
    );
    _currentPage = widget.initialPage.clamp(1, _pageCount);
    _initialAccountScope = _database.accountScope.current;
    _accountKey = _initialAccountScope == null
        ? null
        : accountScopeKey(_initialAccountScope!);
    if (_initialAccountScope != null) {
      _readingSession = ref
          .read(planRepositoryProvider)
          .startReadingSession(accountScope: _initialAccountScope!);
    }
    _selectedAyah = QuranAyahReference(
      id: '',
      surah: widget.surah,
      ayah: widget.ayah,
    );
    _pageReference = _selectedAyah;
    _pageController = PageController(initialPage: _currentPage - 1);
    _resolvingInitialPage =
        ref.read(selectedMushafIdentityProvider).isFoundation &&
        !widget.initialPageIsPhysical;
    WidgetsBinding.instance.addPostFrameCallback((_) => _openInitialPage());
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
  }

  Future<void> _openInitialPage() async {
    final generation = ++_initialNavigationGeneration;
    if (_initialPageError) {
      setState(() {
        _initialPageError = false;
        _resolvingInitialPage = true;
      });
    }
    if (_resolvingInitialPage) {
      try {
        final reference = _selectedAyah ?? _pageReference;
        final resolved = await ref
            .read(selectedMushafRepositoryProvider)
            .pageForAyah(
              reference?.surah ?? widget.surah,
              reference?.ayah ?? widget.ayah,
              fallback: _currentPage,
            );
        if (!mounted || generation != _initialNavigationGeneration) return;
        _currentPage = resolved.clamp(1, _pageCount);
        _pageController.dispose();
        _pageController = PageController(initialPage: _currentPage - 1);
      } on Object {
        if (!mounted || generation != _initialNavigationGeneration) return;
        setState(() {
          _initialPageError = true;
          _resolvingInitialPage = false;
        });
        return;
      }
      setState(() => _resolvingInitialPage = false);
    }
    if (!mounted) return;
    if (!_initialPageHandled) {
      _initialPageHandled = true;
      _queuePagePositionSave(
        _currentPage,
        preferredReference: _selectedAyah,
        accountScope: _initialAccountScope,
      );
    }
    _prefetchAdjacentPages(_currentPage);
  }

  @override
  void dispose() {
    _words
      ..removeListener(_onWords)
      ..dispose();
    _positionSaves.close(discardPending: false);
    WidgetsBinding.instance.removeObserver(this);
    _audioSubscription?.close();
    unawaited(_readingSession?.finish());
    for (final subscription in _pageKeepAlive.values) {
      subscription.close();
    }
    _pageController.dispose();
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _readingSession?.resume();
      ref.invalidate(ayahBookmarkProvider);
    } else {
      _readingSession?.pause();
    }
  }

  void _onWords() {
    if (mounted) setState(() {});
  }

  void _selectWords(QuranWordRange range, int count) {
    if (_words.range == null && _controlsVisible) {
      unawaited(_setControls(false));
    }
    _words.select(range, wordCount: count);
  }

  Future<void> _setControls(bool visible) async {
    setState(() => _controlsVisible = visible);
    await SystemChrome.setEnabledSystemUIMode(
      visible ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(selectedMushafPageCountProvider);
    ref.listen(selectedMushafIdentityProvider, (previous, next) {
      if (previous == next || !next.isFoundation) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _resolvingInitialPage = true);
        unawaited(_openInitialPage());
      });
    });
    final activeAccount = ref.watch(activeAccountScopeKeyProvider);
    if (_accountKey != activeAccount) {
      _accountKey = activeAccount;
      _positionRequest += 1;
      _audioRequest += 1;
      _pageTransitionScope = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _currentAccountKey() == activeAccount) {
          unawaited(
            SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge),
          );
          context.go('/app?tab=1');
        }
      });
      return const Scaffold(body: IqroLoading());
    }
    if (_resolvingInitialPage) return const Scaffold(body: IqroLoading());
    if (_initialPageError) {
      return Scaffold(
        body: IqroAsyncError(
          title: context.l10n.noQuranData,
          message: context.l10n.networkError,
          onRetry: _openInitialPage,
        ),
      );
    }
    final annotationRows = activeAccount == null
        ? const <Map<String, Object?>>[]
        : ref.watch(ayahAnnotationsProvider(activeAccount)).valueOrNull ??
              const <Map<String, Object?>>[];
    final highlightColors = ayahHighlightColorsFromRows(annotationRows);
    final divisions =
        ref.watch(quranJuzProvider).valueOrNull ?? const <QuranDivision>[];
    final catalog = ref.watch(quranCatalogProvider).valueOrNull;
    final reference = _selectedAyah ?? _pageReference;
    final bookmarkState = reference == null || activeAccount == null
        ? null
        : ref.watch(
            ayahBookmarkProvider((
              account: activeAccount,
              surah: reference.surah,
              ayah: reference.ayah,
            )),
          );
    final surah = catalog?.surahs
        .where((s) => s.number == reference?.surah)
        .firstOrNull;
    final locale = Localizations.localeOf(context).languageCode;
    final surahLabel = surah == null
        ? '${context.l10n.surah} ${reference?.surah ?? widget.surah}'
        : '${surah.number}. ${surah.nameFor(locale)}';
    final currentJuz = divisions
        .where((d) => d.containsAyah(reference))
        .firstOrNull
        ?.number;
    final player = ref.watch(
      audioControllerProvider.select(
        (value) => (
          surah: value.track?.surah,
          ayah: value.activeAyah,
          active: value.active && value.channel == AudioPlaybackChannel.mushaf,
          playing: value.playing,
          buffering: value.buffering,
          start: value.rangeStartAyah,
          end: value.rangeEndAyah,
        ),
      ),
    );
    final playingAyah =
        player.active && player.surah != null && player.ayah != null
        ? QuranAyahReference(id: '', surah: player.surah!, ayah: player.ayah!)
        : null;
    // The round button pauses the page that sounds and plays any other.
    final playingSelected =
        player.active && player.playing && _playbackPage == _currentPage;
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          unawaited(
            SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge),
          );
        }
      },
      child: Scaffold(
        backgroundColor: mushafPaperColor,
        body: Stack(
          children: <Widget>[
            SurahOpenReporter(surah: reference?.surah),
            SafeArea(
              child: PageView.builder(
                controller: _pageController,
                // Builds the neighbouring pages so a swipe reveals a laid-out,
                // decoded page instead of a spinner.
                allowImplicitScrolling: true,
                reverse: true,
                physics: _zoom > 1.01
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(parent: ClampingScrollPhysics()),
                itemCount: ref.watch(selectedMushafPageCountProvider),
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) {
                  final page = index + 1;
                  return NativeMushafPage(
                    key: ValueKey(
                      '${ref.watch(selectedMushafIdentityProvider).code}:$page',
                    ),
                    page: page,
                    controller: _zoomControllers.putIfAbsent(
                      page,
                      NativeMushafPageController.new,
                    ),
                    selectedAyah: _selectedAyah,
                    playingAyah: playingAyah,
                    highlightColors: highlightColors,
                    surahs: catalog?.surahs ?? const <Surah>[],
                    divisions: divisions,
                    showPageLabels: !_controlsVisible,
                    onSelectAyah: _selectAyah,
                    onTajweedWord: (reference) =>
                        _selectAyah(reference, toggleControls: false),
                    tajweedRecitation: _tajweedRecitationId,
                    onOpenAyah: _openAyah,
                    wordRange: _words.range,
                    playingWord: _words.playingWord,
                    onWordRange: _selectWords,
                    onBackgroundTap: () => _words.range != null
                        ? _words.clear()
                        : _setControls(!_controlsVisible),
                    onScale: (value) {
                      if (page == _currentPage && mounted) {
                        setState(() => _zoom = value);
                      }
                    },
                  );
                },
              ),
            ),
            PositionedDirectional(
              start: 12,
              end: 12,
              top: 8 + MediaQuery.paddingOf(context).top,
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: AnimatedOpacity(
                  opacity: _controlsVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Row(
                    children: <Widget>[
                      MushafCircleButton(
                        icon: Icons.arrow_back_rounded,
                        tooltip: context.l10n.back,
                        onPressed: () => context.pop(),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: MushafControlSurface(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(40),
                            onTap: () =>
                                _showQuickJump(mode: QuranQuickJumpMode.ayah),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 7,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      Flexible(
                                        child: Text(
                                          surahLabel,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: mushafInkColor,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      const Icon(
                                        Icons.expand_more_rounded,
                                        size: 18,
                                        color: mushafInkColor,
                                      ),
                                    ],
                                  ),
                                  Text(
                                    reference == null
                                        ? context.l10n.mushafMode
                                        : '${context.l10n.ayah} ${reference.key}',
                                    style: const TextStyle(
                                      color: mushafAccentColor,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      MushafControlSurface(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            IconButton(
                              key: const ValueKey('mushaf-bookmark'),
                              tooltip: context.l10n.favorites,
                              onPressed:
                                  reference == null ||
                                      activeAccount == null ||
                                      _bookmarkLoading
                                  ? null
                                  : _bookmarkSelected,
                              color: mushafAccentColor,
                              isSelected: bookmarkState?.valueOrNull ?? false,
                              selectedIcon: const Icon(Icons.bookmark_rounded),
                              icon: const Icon(Icons.bookmark_border_rounded),
                            ),
                            IconButton(
                              tooltip: context.l10n.quickJump,
                              onPressed: () =>
                                  _showQuickJump(mode: QuranQuickJumpMode.ayah),
                              color: mushafAccentColor,
                              icon: const Icon(Icons.search_rounded),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_words.range != null && !_controlsVisible)
              Positioned.fill(
                child: WordRangePanelLayer(
                  controller: _words,
                  selection: wordRangeBounds,
                  onMore: () {
                    final start = _words.range?.start;
                    if (start == null) return;
                    unawaited(
                      _openAyah(
                        QuranAyahReference(
                          id: '',
                          surah: start.surah,
                          ayah: start.ayah,
                        ),
                      ),
                    );
                  },
                ),
              ),
            PositionedDirectional(
              start: 12,
              end: 12,
              bottom: 12 + MediaQuery.paddingOf(context).bottom,
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: AnimatedOpacity(
                  opacity: _controlsVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      // A swipe folds the player into the round button below,
                      // as the Audio tab's bar folds; the sound plays on.
                      if (_playerExpanded && player.active)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: IqroMiniPlayer(
                            allowCollapse: false,
                            mushafControls: true,
                            onReciterTap: _chooseReciter,
                            onRepeatTap: _toggleRepeat,
                            onSwipeAway: () =>
                                setState(() => _playerExpanded = false),
                          ),
                        ),
                      if (!_playerExpanded || !player.active)
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: SizedBox.square(
                              dimension: 52,
                              child: FloatingActionButton(
                                heroTag: 'mushaf-play-selected',
                                tooltip: playingSelected
                                    ? context.l10n.pause
                                    : '${context.l10n.listen} ${_selectedAyah?.key ?? ''}'
                                          .trim(),
                                backgroundColor: mushafAccentColor,
                                foregroundColor: Colors.white,
                                elevation: 1,
                                shape: const CircleBorder(),
                                onPressed: _audioLoading ? null : _playSelected,
                                child:
                                    _audioLoading ||
                                        (playingSelected && player.buffering)
                                    ? const SizedBox.square(
                                        dimension: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Icon(
                                        playingSelected
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                        size: 30,
                                      ),
                              ),
                            ),
                          ),
                        ),
                      Row(
                        children: <Widget>[
                          // The text of the same place, as the Mushaf button
                          // in the text reader's bar.
                          MushafCircleButton(
                            key: const ValueKey('mushaf-open-text'),
                            icon: Icons.subject_rounded,
                            tooltip: context.l10n.textMode,
                            onPressed: _switchToText,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: MushafPageScrubber(
                              pagesCount: _pageCount,
                              page: _currentPage,
                              juz: currentJuz,
                              onJump: _scrubToPage,
                            ),
                          ),
                          const SizedBox(width: 8),
                          MushafCircleButton(
                            icon: Icons.article_outlined,
                            tooltip: context.l10n.translation,
                            onPressed: reference == null
                                ? null
                                : () => _openAyah(reference),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A tajweed card opening over the page leaves the controls as they are.
  void _selectAyah(QuranAyahReference reference, {bool toggleControls = true}) {
    // A tap beside the selected words clears them, as with selected text.
    if (_words.range != null && toggleControls) {
      _words.clear();
      return;
    }
    final scope = _database.accountScope.current;
    if (scope == null || !_isCurrentAccount(scope)) return;
    final show = reference != _selectedAyah || !_controlsVisible;
    _positionRequest++;
    _audioRequest++;
    setState(() {
      _selectedAyah = reference;
      _pageReference = reference;
      _audioLoading = false;
      _playerExpanded = false;
    });
    if (toggleControls) unawaited(_setControls(show));
    _queuePagePositionSave(
      _currentPage,
      preferredReference: reference,
      accountScope: scope,
    );
  }

  /// The sound stays within its page: a turn to another page, by a swipe,
  /// the page bar or a jump to a surah or ayah, stops it.
  void _stopPageSound() {
    final current = ref.read(audioControllerProvider);
    _playbackPage = null;
    _runs = const <MushafPageRun>[];
    if (current.channel == AudioPlaybackChannel.mushaf && current.playing) {
      unawaited(ref.read(audioControllerProvider.notifier).toggle());
    }
  }

  /// The play button reads the open page: from the selected ayah, or the
  /// first, to the last ayah of the page. A second press pauses or resumes.
  Future<void> _playSelected() async {
    final scope = _database.accountScope.current;
    if (_audioLoading || scope == null || !_isCurrentAccount(scope)) return;
    final controller = ref.read(audioControllerProvider.notifier);
    final navigationEpoch = controller.navigationEpoch;
    final current = ref.read(audioControllerProvider);
    final from = _selectedAyah;
    if (current.error == null &&
        current.active &&
        current.channel == AudioPlaybackChannel.mushaf &&
        _playbackPage == _currentPage &&
        (from == null || from == _playbackFrom || _isPlayingAyah(from))) {
      setState(() => _playerExpanded = true);
      await controller.toggle();
      return;
    }
    final request = ++_audioRequest;
    final page = _currentPage;
    bool ownsRequest() =>
        _isCurrentAccount(scope) &&
        request == _audioRequest &&
        controller.navigationEpoch == navigationEpoch &&
        page == _currentPage &&
        from == _selectedAyah &&
        identical(controller, ref.read(audioControllerProvider.notifier));
    setState(() => _audioLoading = true);
    try {
      final pageData = await ref.read(mushafPageProvider(page).future);
      if (!ownsRequest()) return;
      final runs = mushafPageRuns(pageData.ayahReferences, from: from);
      if (runs.isEmpty) throw StateError('The page has no ayahs');
      final recitations = await ref
          .read(audioRepositoryProvider)
          .recitationsForRole(AudioRecitationRole.ayahPlayback);
      if (!ownsRequest()) return;
      final recitation = preferredRecitation(
        recitations,
        preferredId:
            ref.read(appPreferencesProvider).mushafRecitationId ??
            (current.channel == AudioPlaybackChannel.mushaf
                ? current.track?.recitationId
                : null),
        role: AudioRecitationRole.ayahPlayback,
      );
      if (recitation == null) throw StateError('No timed recitation');
      _playbackPage = page;
      _playbackFrom = from;
      _runs = runs;
      await _playRun(
        0,
        recitation: recitation,
        recitations: recitations,
        owns: ownsRequest,
      );
      if (ownsRequest()) setState(() => _playerExpanded = true);
    } on AccountScopeChanged {
      return;
    } on Object {
      if (ownsRequest() && mounted) {
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

  bool _isPlayingAyah(QuranAyahReference reference) {
    final current = ref.read(audioControllerProvider);
    return current.track?.surah == reference.surah &&
        current.displayedAyah == reference.ayah;
  }

  /// Loads run [index] of the page; with repeat on, only its first ayah,
  /// which then sounds over and over.
  Future<void> _playRun(
    int index, {
    required Recitation recitation,
    required List<Recitation> recitations,
    required bool Function() owns,
    bool autoplay = true,
  }) async {
    final run = _runs[index];
    final playback = await ref
        .read(audioRepositoryProvider)
        .playback(recitationId: recitation.id, surah: run.surah);
    if (!owns() || !mounted) return;
    final surah = ref
        .read(quranCatalogProvider)
        .valueOrNull
        ?.surahs
        .where((s) => s.number == run.surah)
        .firstOrNull;
    final controller = ref.read(audioControllerProvider.notifier);
    _run = index;
    await controller.loadPlayback(
      playback: playback,
      reciter: reciterWithPersonPortrait(
        recitation.reciter,
        apiBaseUrl: ref.read(appConfigProvider).apiBaseUrl,
        reciters: recitations.map((r) => r.reciter),
      ),
      surahName:
          surah?.nameFor(Localizations.localeOf(context).languageCode) ??
          '${context.l10n.surah} ${run.surah}',
      channel: AudioPlaybackChannel.mushaf,
      startAyah: run.start,
      endAyah: ref.read(audioControllerProvider).repeatEnabled
          ? run.start
          : run.end,
      autoplay: autoplay,
    );
  }

  /// A page that ends one surah and begins the next reads on into the next
  /// once the first run ends by itself.
  void _followPageRuns(IqroAudioState? previous, IqroAudioState next) {
    if (previous == null ||
        !previous.playing ||
        next.playing ||
        next.error != null ||
        next.repeatEnabled ||
        next.channel != AudioPlaybackChannel.mushaf ||
        _playbackPage != _currentPage ||
        _run + 1 >= _runs.length) {
      return;
    }
    final run = _runs[_run];
    if (next.track?.surah != run.surah ||
        next.rangeEndAyah != run.end ||
        next.position <
            next.rangeEndPosition - const Duration(milliseconds: 600)) {
      return;
    }
    final scope = _database.accountScope.current;
    if (scope == null || !_isCurrentAccount(scope)) return;
    final controller = ref.read(audioControllerProvider.notifier);
    final navigationEpoch = controller.navigationEpoch;
    final request = ++_audioRequest;
    final page = _currentPage;
    bool ownsRequest() =>
        _isCurrentAccount(scope) &&
        request == _audioRequest &&
        controller.navigationEpoch == navigationEpoch &&
        page == _currentPage &&
        identical(controller, ref.read(audioControllerProvider.notifier));
    unawaited(() async {
      try {
        final recitations = await ref
            .read(audioRepositoryProvider)
            .recitationsForRole(AudioRecitationRole.ayahPlayback);
        final recitation = recitations
            .where((item) => item.id == next.track?.recitationId)
            .firstOrNull;
        if (recitation == null || !ownsRequest()) return;
        await _playRun(
          _run + 1,
          recitation: recitation,
          recitations: recitations,
          owns: ownsRequest,
        );
      } on Object {
        // The first surah has played; the page simply stops there.
      }
    }());
  }

  /// Repeat sounds the current ayah over and over; switched off, the page
  /// reads on from that ayah.
  Future<void> _toggleRepeat() async {
    final current = ref.read(audioControllerProvider);
    final ayah = current.displayedAyah;
    if (current.channel != AudioPlaybackChannel.mushaf ||
        current.track == null ||
        ayah == null) {
      return;
    }
    final controller = ref.read(audioControllerProvider.notifier);
    await controller.toggleRepeat();
    final repeat = ref.read(audioControllerProvider).repeatEnabled;
    final run = _runs
        .where((item) => item.surah == current.track?.surah)
        .firstOrNull;
    try {
      await controller.setAyahRange(
        ayah,
        repeat ? ayah : run?.end ?? current.rangeEndAyah ?? ayah,
        autoplay: current.playing,
      );
    } on Object {
      // A range without timings keeps the clip that plays now.
    }
  }

  /// The player's reciter list. A new reciter is the Mushaf's from now on;
  /// the ayah in the player starts again in the new voice, or waits paused.
  Future<void> _chooseReciter() async {
    final scope = _database.accountScope.current;
    if (scope == null || !_isCurrentAccount(scope)) return;
    final repository = ref.read(audioRepositoryProvider);
    final List<Recitation> recitations;
    try {
      recitations = await repository.recitationsForRole(
        AudioRecitationRole.ayahPlayback,
      );
    } on Object {
      if (_isCurrentAccount(scope) && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.noAudio)));
      }
      return;
    }
    if (!_isCurrentAccount(scope) || !mounted) return;
    final shown = ref.read(audioControllerProvider);
    final chosen = await showMushafReciterSheet(
      context,
      recitations: recitations,
      selectedId: shown.channel == AudioPlaybackChannel.mushaf
          ? shown.track?.recitationId
          : ref.read(appPreferencesProvider).mushafRecitationId,
    );
    if (chosen == null || !_isCurrentAccount(scope) || !mounted) return;
    unawaited(
      ref.read(appPreferencesProvider.notifier).setMushafRecitation(chosen.id),
    );
    final controller = ref.read(audioControllerProvider.notifier);
    final current = ref.read(audioControllerProvider);
    final track = current.track;
    if (current.channel != AudioPlaybackChannel.mushaf ||
        track == null ||
        track.recitationId == chosen.id ||
        current.rangeStartAyah == null) {
      return;
    }
    final navigationEpoch = controller.navigationEpoch;
    final request = ++_audioRequest;
    bool ownsRequest() =>
        _isCurrentAccount(scope) &&
        request == _audioRequest &&
        controller.navigationEpoch == navigationEpoch &&
        identical(controller, ref.read(audioControllerProvider.notifier));
    setState(() => _audioLoading = true);
    try {
      final playback = await repository.playback(
        recitationId: chosen.id,
        surah: track.surah,
      );
      if (!ownsRequest()) return;
      await controller.loadPlayback(
        playback: playback,
        reciter: reciterWithPersonPortrait(
          chosen.reciter,
          apiBaseUrl: ref.read(appConfigProvider).apiBaseUrl,
          reciters: recitations.map((r) => r.reciter),
        ),
        surahName: current.surahName,
        channel: AudioPlaybackChannel.mushaf,
        startAyah: current.displayedAyah ?? current.rangeStartAyah,
        endAyah: current.rangeEndAyah,
        autoplay: current.playing,
      );
    } on AccountScopeChanged {
      return;
    } on Object {
      if (ownsRequest() && mounted) {
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

  /// The tajweed of an ayah on a QF Mushaf 19 page, once the page has it.
  ({TajweedReference reference, TajweedAyah ayah})? _tajweedAyah(
    QuranAyahReference reference,
    int page,
  ) {
    final pageData = ref.read(mushafPageProvider(page)).valueOrNull;
    if (pageData?.foundation?.sourceId != tajweedMushafId) return null;
    final rules = ref.read(tajweedRulesProvider).valueOrNull;
    final ayah = ref
        .read(tajweedPageProvider(page))
        .valueOrNull
        ?.ayah(reference.key);
    if (rules == null || ayah == null || ayah.words.isEmpty) return null;
    return (reference: rules, ayah: ayah);
  }

  /// The reciter the play button would use, for words played from a card.
  Future<String?> _tajweedRecitationId() async {
    final recitations = await ref
        .read(audioRepositoryProvider)
        .recitationsForRole(AudioRecitationRole.ayahPlayback);
    if (!mounted) return null;
    final current = ref.read(audioControllerProvider);
    return preferredRecitation(
      recitations,
      preferredId:
          ref.read(appPreferencesProvider).mushafRecitationId ??
          (current.channel == AudioPlaybackChannel.mushaf
              ? current.track?.recitationId
              : null),
      role: AudioRecitationRole.ayahPlayback,
    )?.id;
  }

  Future<void> _bookmarkSelected() async {
    final reference = _selectedAyah ?? _pageReference;
    final scope = _database.accountScope.current;
    if (_bookmarkLoading ||
        reference == null ||
        scope == null ||
        !_isCurrentAccount(scope)) {
      return;
    }
    setState(() => _bookmarkLoading = true);
    try {
      final saved = await _quranRepository.toggleBookmark(
        reference.surah,
        reference.ayah,
        page: _currentPage,
        accountScope: scope,
      );
      if (_isCurrentAccount(scope) && mounted) {
        ref.invalidate(
          ayahBookmarkProvider((
            account: accountScopeKey(scope),
            surah: reference.surah,
            ayah: reference.ayah,
          )),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              saved ? context.l10n.bookmarkAdded : context.l10n.bookmarkRemoved,
            ),
          ),
        );
      }
    } on AccountScopeChanged {
      return;
    } on Object {
      if (_isCurrentAccount(scope) && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.networkError)));
      }
    } finally {
      if (mounted) setState(() => _bookmarkLoading = false);
    }
  }

  void _scrubToPage(int page) {
    final scope = _database.accountScope.current;
    if (scope == null || !_isCurrentAccount(scope) || page == _currentPage) {
      return;
    }
    _dotTargetPage = page.clamp(1, _pageCount);
    _pageTransitionScope = scope;
    _zoomControllers[_currentPage]?.setZoom(1);
    _pageController.jumpToPage(_dotTargetPage! - 1);
    _pageTransitionScope = null;
  }

  Future<void> _switchToText() async {
    final reference = _selectedAyah ?? _pageReference;
    await ref
        .read(appPreferencesProvider.notifier)
        .setReaderMode(ReaderMode.text);
    if (mounted) {
      context.pushReplacement(
        '/reader/${reference?.surah ?? widget.surah}?ayah=${reference?.ayah ?? widget.ayah}'
        '${widget.savesReadingPlace ? '' : '&from=bookmark'}',
      );
    }
  }

  /// The page zoom in the ayah menu, beside pinching the page.
  Widget _zoomSlider() => StatefulBuilder(
    builder: (context, update) => Padding(
      key: const ValueKey('mushaf-zoom'),
      padding: const EdgeInsetsDirectional.fromSTEB(14, 4, 16, 4),
      child: Row(
        children: <Widget>[
          const Icon(Icons.zoom_out_rounded),
          Expanded(
            child: Slider(
              value: _zoom.clamp(1, 3),
              min: 1,
              max: 3,
              onChanged: (value) {
                _zoomControllers[_currentPage]?.setZoom(value);
                setState(() => _zoom = value);
                update(() {});
              },
            ),
          ),
          Text('${(_zoom * 100).round()}%'),
        ],
      ),
    ),
  );

  Future<void> _showBookmarks() async {
    final scope = _database.accountScope.current;
    if (scope == null || !_isCurrentAccount(scope)) return;
    final selection = await showIqroSheet<QuranAyahReference>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => MushafBookmarksSheet(
        load: () async {
          final rows = await _quranRepository.bookmarks(accountScope: scope);
          if (!_isCurrentAccount(scope)) throw const AccountScopeChanged();
          return rows
              .map(
                (row) => QuranAyahReference(
                  id: '',
                  surah: row['surah']! as int,
                  ayah: row['ayah']! as int,
                ),
              )
              .toSet()
              .toList();
        },
        surahs: ref.read(quranCatalogProvider).valueOrNull?.surahs ?? const [],
      ),
    );
    if (selection == null || !_isCurrentAccount(scope)) return;
    try {
      var page = await ref
          .read(selectedMushafRepositoryProvider)
          .pageForAyah(selection.surah, selection.ayah, fallback: 0);
      if (!_isCurrentAccount(scope)) return;
      if (page == 0) {
        final ayahs = await _quranRepository.ayahs(selection.surah);
        if (!_isCurrentAccount(scope)) return;
        page =
            ayahs
                .where((ayah) => ayah.number == selection.ayah)
                .firstOrNull
                ?.pages
                .firstOrNull ??
            0;
      }
      if (page < 1) throw const FormatException('Missing bookmark page');
      await _jumpToPage(page, selection, accountScope: scope);
    } on AccountScopeChanged {
      return;
    } on Object {
      if (!mounted || !_isCurrentAccount(scope)) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.networkError)));
    }
  }

  void _onPageChanged(int index) {
    final page = index + 1;
    if (!_initialPageHandled && page == _currentPage) {
      _initialPageHandled = true;
      _queuePagePositionSave(
        page,
        preferredReference: _selectedAyah,
        accountScope: _pageTransitionScope,
      );
      _prefetchAdjacentPages(page);
      return;
    }
    if (page == _currentPage) return;
    final keepControls = page == _dotTargetPage;
    _dotTargetPage = null;
    unawaited(
      ReaderHaptics.pageChanged(
        enabled: ref.read(appPreferencesProvider).readerHaptics,
      ),
    );
    _audioRequest++;
    _audioLoading = false;
    _playerExpanded = false;
    _stopPageSound();
    _initialPageHandled = true;
    _zoomControllers[_currentPage]?.setZoom(1);
    setState(() {
      _currentPage = page;
      _controlsVisible = keepControls;
      _zoom = 1;
      _selectedAyah = null;
      _pageReference = null;
    });
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        keepControls ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
      ),
    );
    _queuePagePositionSave(page, accountScope: _pageTransitionScope);
    _zoomControllers.removeWhere((key, value) => (key - page).abs() > 2);
    _prefetchAdjacentPages(page);
  }

  static const _prefetchRadius = 2;

  void _prefetchAdjacentPages(int page) {
    final window = <int>{
      for (
        var candidate = page - _prefetchRadius;
        candidate <= page + _prefetchRadius;
        candidate++
      )
        if (candidate >= 1 && candidate <= _pageCount) candidate,
    };
    _pageKeepAlive.removeWhere((candidate, subscription) {
      if (window.contains(candidate)) return false;
      subscription.close();
      return true;
    });
    final logicalWidth = MediaQuery.sizeOf(context).width;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final repository = ref.read(selectedMushafRepositoryProvider);
    for (final candidate in window) {
      _pageKeepAlive.putIfAbsent(
        candidate,
        () => ref.listenManual(mushafPageProvider(candidate), (_, _) {}),
      );
      if (candidate == page) continue;
      final pageFuture = ref.read(mushafPageProvider(candidate).future);
      unawaited(() async {
        try {
          final pageData = await pageFuture;
          final asset = pageData.bestAssetFor(logicalWidth, pixelRatio);
          if (asset == null) return;
          final file = await repository.cachedMushafPageAsset(pageData, asset);
          if (!mounted || !_pageKeepAlive.containsKey(candidate)) return;
          // Same provider and key MushafRaster resolves, so the swipe finds
          // the frame already decoded in the ImageCache.
          await precacheImage(FileImage(file), context);
        } on Object {
          // Prefetch is opportunistic; the visible page owns retry feedback.
        }
      }());
    }
  }

  Future<void> _showQuickJump({
    QuranQuickJumpMode mode = QuranQuickJumpMode.page,
  }) async {
    final repository = ref.read(quranRepositoryProvider);
    AccountScopeSnapshot? scope;
    try {
      scope = await repository.captureAccount();
      if (!_isCurrentAccount(scope)) return;
      final results = await Future.wait<Object?>(<Future<Object?>>[
        _optionalQuickJumpData(repository.surahs()),
        _optionalQuickJumpData(repository.juz()),
        _optionalQuickJumpData(repository.hizb()),
        _optionalQuickJumpData(repository.rubElHizb()),
      ]);
      if (!_isCurrentAccount(scope) || !mounted) return;
      final catalog = results[0] as QuranCatalog?;
      final juz = results[1] as List<QuranDivision>?;
      final hizb = results[2] as List<QuranDivision>?;
      final rubElHizb = results[3] as List<QuranDivision>?;
      final reference = _selectedAyah ?? _pageReference;
      final selection = await showIqroSheet<QuranQuickJumpSelection>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => QuranQuickJumpSheet(
          surahs: catalog?.surahs ?? const <Surah>[],
          juz: juz ?? const <QuranDivision>[],
          hizb: hizb ?? const <QuranDivision>[],
          rubElHizb: rubElHizb ?? const <QuranDivision>[],
          initialMode: mode,
          initialSurah: reference?.surah ?? widget.surah,
          initialAyah: reference?.ayah ?? widget.ayah,
          initialPage: _currentPage,
          pagesCount: _pageCount,
        ),
      );
      if (selection == null || !_isCurrentAccount(scope)) return;
      var page = selection.page;
      QuranAyahReference? targetReference;
      if (selection.mode == QuranQuickJumpMode.ayah) {
        final ayahs = await repository.ayahs(selection.surah);
        if (!_isCurrentAccount(scope)) return;
        final target = ayahs
            .where((item) => item.number == selection.ayah)
            .firstOrNull;
        page = target?.pages.firstOrNull ?? page;
        targetReference = QuranAyahReference(
          id: target?.id ?? '',
          surah: selection.surah,
          ayah: selection.ayah,
        );
      } else if (selection.mode != QuranQuickJumpMode.page) {
        targetReference = QuranAyahReference(
          id: '',
          surah: selection.surah,
          ayah: selection.ayah,
        );
      }
      if (!_isCurrentAccount(scope)) return;
      if (targetReference != null) {
        page = await ref
            .read(selectedMushafRepositoryProvider)
            .pageForAyah(
              targetReference.surah,
              targetReference.ayah,
              fallback: page,
            );
      }
      if (!_isCurrentAccount(scope)) return;
      await _jumpToPage(page, targetReference, accountScope: scope);
    } on AccountScopeChanged {
      return;
    } on Object {
      if (scope == null || !_isCurrentAccount(scope) || !mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.networkError)));
    }
  }

  Future<T?> _optionalQuickJumpData<T>(Future<T> request) async {
    try {
      return await request;
    } on AccountScopeChanged {
      rethrow;
    } on Object {
      return null;
    }
  }

  Future<void> _jumpToPage(
    int requestedPage,
    QuranAyahReference? reference, {
    required AccountScopeSnapshot accountScope,
  }) async {
    if (!_isCurrentAccount(accountScope)) return;
    final page = requestedPage.clamp(1, _pageCount);
    _zoomControllers[_currentPage]?.setZoom(1);
    _pageTransitionScope = accountScope;
    if ((page - _currentPage).abs() <= 3) {
      await _pageController.animateToPage(
        page - 1,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _pageController.jumpToPage(page - 1);
    }
    if (identical(_pageTransitionScope, accountScope)) {
      _pageTransitionScope = null;
    }
    if (!_isCurrentAccount(accountScope)) return;
    setState(() {
      _currentPage = page;
      _selectedAyah = reference;
      _pageReference = reference;
      _controlsVisible = false;
      _zoom = 1;
    });
    if (reference != null) {
      _queuePagePositionSave(
        page,
        preferredReference: reference,
        accountScope: accountScope,
      );
    }
    if (!_isCurrentAccount(accountScope)) return;
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _savePagePosition(
    int page, {
    QuranAyahReference? preferredReference,
    AccountScopeSnapshot? accountScope,
    required Future<MushafPageData> pageData,
  }) async {
    final request = ++_positionRequest;
    final repository = _quranRepository;
    final AccountScopeSnapshot scope;
    try {
      scope = accountScope ?? await repository.captureAccount();
      if (!_isCurrentPositionRequest(scope, request, page)) return;
    } on AccountScopeChanged {
      return;
    }

    final ReadingPosition current;
    try {
      current = await repository.position(accountScope: scope);
    } on AccountScopeChanged {
      return;
    } on Object {
      // Without a stable account-owned starting position there is no safe
      // fallback for a page metadata failure.
      return;
    }
    if (!_isCurrentPositionRequest(scope, request, page)) return;

    try {
      final resolvedPage = await pageData;
      if (!_isCurrentPositionRequest(scope, request, page)) {
        return;
      }
      final preferredIsOnPage =
          preferredReference != null &&
          (resolvedPage.ayahReferences.isEmpty ||
              resolvedPage.ayahReferences.contains(preferredReference));
      final reference = preferredIsOnPage
          ? (surah: preferredReference.surah, ayah: preferredReference.ayah)
          : resolvedPage.firstAyahReference;
      if (mounted && reference != null && page == _currentPage) {
        setState(() {
          _pageReference = QuranAyahReference(
            id: '',
            surah: reference.surah,
            ayah: reference.ayah,
          );
          if (_selectedAyah != null &&
              resolvedPage.ayahReferences.isNotEmpty &&
              !resolvedPage.ayahReferences.contains(_selectedAyah)) {
            _selectedAyah = null;
          }
        });
      }
      var canonicalPage = page;
      if (resolvedPage.foundation != null && reference != null) {
        final ayahs = await repository.ayahs(reference.surah);
        canonicalPage = ayahs
            .firstWhere((ayah) => ayah.number == reference.ayah)
            .pages
            .first;
        if (!_isCurrentPositionRequest(scope, request, page)) return;
      }
      if (widget.savesReadingPlace) {
        await repository.savePosition(
          surah: reference?.surah ?? current.surah,
          ayah: reference?.ayah ?? current.ayah,
          page: canonicalPage,
          accountScope: scope,
        );
      }
      if (mounted) {
        _readingSession?.observe(
          surah: reference?.surah ?? current.surah,
          ayah: reference?.ayah ?? current.ayah,
          page: canonicalPage,
        );
      }
    } on AccountScopeChanged {
      return;
    } on Object {
      if (ref.read(selectedMushafIdentityProvider).isFoundation) return;
      if (!_isCurrentPositionRequest(scope, request, page)) {
        return;
      }
      try {
        if (widget.savesReadingPlace) {
          await repository.savePosition(
            surah: preferredReference?.surah ?? current.surah,
            ayah: preferredReference?.ayah ?? current.ayah,
            page: page,
            accountScope: scope,
          );
        }
        if (mounted) {
          _readingSession?.observe(
            surah: preferredReference?.surah ?? current.surah,
            ayah: preferredReference?.ayah ?? current.ayah,
            page: page,
          );
        }
      } on AccountScopeChanged {
        return;
      }
    }
    if (mounted && _isCurrentPositionRequest(scope, request, page)) {
      ref.invalidate(readingPositionProvider(accountScopeKey(scope)));
    }
  }

  /// The ayah's menu: a tap on its number, or «⋯» on the selection panel.
  Future<void> _openAyah(QuranAyahReference reference) async {
    final scope = _database.accountScope.current;
    if (_detailsOpen || scope == null || !_isCurrentAccount(scope)) return;
    _detailsOpen = true;
    _audioRequest++;
    _positionRequest++;
    final page = _currentPage;
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      _selectedAyah = reference;
      _pageReference = reference;
      _controlsVisible = false;
      _audioLoading = false;
      _playerExpanded = false;
    });
    _queuePagePositionSave(
      page,
      preferredReference: reference,
      accountScope: scope,
    );
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      if (!_isCurrentAccount(scope) || !mounted) return;
      final tajweed = _tajweedAyah(reference, page);
      var breakdown = false;
      var memorize = false;
      VoidCallback? leave;
      await showIqroSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: false,
        backgroundColor: Colors.transparent,
        builder: (context) => AyahActionSheet(
          reference: reference,
          page: page,
          onTajweedBreakdown: tajweed == null ? null : () => breakdown = true,
          onMemorize: () => memorize = true,
          readerZoom: _zoomSlider(),
          readerActions: <AyahSheetReaderAction>[
            (
              key: const ValueKey('mushaf-bookmarks'),
              icon: Icons.bookmarks_rounded,
              title: context.l10n.bookmarks,
              onTap: () => leave = () => unawaited(_showBookmarks()),
            ),
            (
              key: const ValueKey('mushaf-edition'),
              icon: Icons.menu_book_outlined,
              title: context.l10n.chooseMushaf,
              onTap: () =>
                  leave = () => unawaited(showMushafPicker(context, ref)),
            ),
            (
              key: const ValueKey('mushaf-notes'),
              icon: Icons.note_alt_outlined,
              title: context.l10n.notes,
              onTap: () => leave = () => context.push('/notes'),
            ),
          ],
        ),
      );
      if (leave != null && mounted) leave!();
      if (memorize && mounted) {
        await showMemorizeAyahSheet(
          context,
          surah: reference.surah,
          ayah: reference.ayah,
        );
      }
      if (breakdown && tajweed != null && mounted) {
        await showTajweedBreakdown(
          context,
          reference: tajweed.reference,
          ayah: tajweed.ayah,
          recitation: _tajweedRecitationId,
        );
      }
    } finally {
      _detailsOpen = false;
      if (mounted && _isCurrentAccount(scope)) {
        ref.invalidate(
          ayahBookmarkProvider((
            account: accountScopeKey(scope),
            surah: reference.surah,
            ayah: reference.ayah,
          )),
        );
      }
      if (_isCurrentAccount(scope)) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    }
  }

  void _queuePagePositionSave(
    int page, {
    QuranAyahReference? preferredReference,
    AccountScopeSnapshot? accountScope,
  }) {
    _positionSaves.add((
      page: page,
      preferredReference: preferredReference,
      accountScope: accountScope,
      pageData: ref.read(mushafPageProvider(page).future),
    ));
  }

  bool _isCurrentAccount(AccountScopeSnapshot scope) {
    return mounted &&
        _accountKey == accountScopeKey(scope) &&
        ref.read(localDatabaseProvider).accountScope.isCurrent(scope);
  }

  AccountScopeKey? _currentAccountKey() {
    final scope = ref.read(localDatabaseProvider).accountScope.current;
    return scope == null ? null : accountScopeKey(scope);
  }

  bool _isCurrentPositionRequest(
    AccountScopeSnapshot scope,
    int request,
    int page,
  ) =>
      request == _positionRequest &&
      page == _currentPage &&
      _accountKey == accountScopeKey(scope) &&
      _database.accountScope.isCurrent(scope);
}
