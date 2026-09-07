import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/platform/reader_haptics.dart';

import '../../app/providers.dart';
import '../../core/auth/account_scope.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/storage/local_database.dart';
import '../../core/storage/preferences_store.dart';
import '../../core/utils/latest_async_work_queue.dart';
import '../audio/mini_player.dart';
import '../audio/reciter_catalog.dart';
import '../audio/reciter_portraits.dart';
import '../plan/plan_repository.dart';
import 'ayah_action_sheet.dart';
import 'native_mushaf_page.dart';
import 'mushaf_paper.dart';
import 'mushaf_reader_controls.dart';
import 'quick_jump_sheet.dart';
import 'quran_models.dart';
import 'quran_repository.dart';

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
    super.key,
  });

  final int initialPage;
  final int surah;
  final int ayah;

  @override
  ConsumerState<MushafScreen> createState() => _MushafScreenState();
}

class _MushafScreenState extends ConsumerState<MushafScreen>
    with WidgetsBindingObserver {
  late final PageController _pageController;
  final _zoomControllers = <int, NativeMushafPageController>{};
  var _currentPage = 1;
  var _controlsVisible = false;
  var _zoom = 1.0;
  var _audioLoading = false;
  var _audioRequest = 0;
  var _playerExpanded = false;
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

  @override
  void initState() {
    super.initState();
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
    _currentPage = widget.initialPage.clamp(1, 604);
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
    });
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
  }

  @override
  void dispose() {
    _positionSaves.close(discardPending: false);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_readingSession?.finish());
    _pageController.dispose();
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _readingSession?.resume();
    } else {
      _readingSession?.pause();
    }
  }

  Future<void> _setControls(bool visible) async {
    setState(() => _controlsVisible = visible);
    await SystemChrome.setEnabledSystemUIMode(
      visible ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
  }

  @override
  Widget build(BuildContext context) {
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
    final divisions =
        ref.watch(quranJuzProvider).valueOrNull ?? const <QuranDivision>[];
    final catalog = ref.watch(quranCatalogProvider).valueOrNull;
    final reference = _selectedAyah ?? _pageReference;
    final surah = catalog?.surahs
        .where((s) => s.number == reference?.surah)
        .firstOrNull;
    final locale = Localizations.localeOf(context).languageCode;
    final surahLabel = surah == null
        ? '${context.l10n.surah} ${reference?.surah ?? widget.surah}'
        : '${surah.number}. ${surah.nameFor(locale)}';
    final currentJuz = divisions
        .where((d) => _currentPage >= d.startPage && _currentPage <= d.endPage)
        .firstOrNull
        ?.number;
    final player = ref.watch(
      audioControllerProvider.select(
        (value) => (
          surah: value.track?.surah,
          ayah: value.activeAyah,
          active: value.active,
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
    final playingSelected =
        player.playing &&
        player.surah == reference?.surah &&
        player.start == reference?.ayah &&
        player.end == reference?.ayah;
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
            SafeArea(
              child: PageView.builder(
                controller: _pageController,
                reverse: true,
                physics: _zoom > 1.01
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(parent: ClampingScrollPhysics()),
                itemCount: 604,
                onPageChanged: _onScanPageChanged,
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
                    surahs: catalog?.surahs ?? const <Surah>[],
                    divisions: divisions,
                    onSelectAyah: _selectAyah,
                    onOpenAyah: _openAyah,
                    onBackgroundTap: () => _setControls(!_controlsVisible),
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
                              tooltip: context.l10n.favorites,
                              onPressed: reference == null
                                  ? null
                                  : _bookmarkSelected,
                              color: mushafAccentColor,
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
                      if (_playerExpanded && player.active)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: <Widget>[
                              const Expanded(child: IqroMiniPlayer()),
                              IconButton(
                                tooltip: context.l10n.close,
                                onPressed: () =>
                                    setState(() => _playerExpanded = false),
                                icon: const Icon(Icons.expand_more_rounded),
                                color: mushafAccentColor,
                              ),
                            ],
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
                                    : '${context.l10n.listen} ${reference?.key ?? ''}',
                                backgroundColor: mushafAccentColor,
                                foregroundColor: Colors.white,
                                elevation: 1,
                                shape: const CircleBorder(),
                                onPressed: reference == null || _audioLoading
                                    ? null
                                    : _playSelected,
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
                          MushafCircleButton(
                            icon: Icons.more_horiz,
                            tooltip: context.l10n.readerSettings,
                            onPressed: _showReaderOptions,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: MushafPageScrubber(
                              page: _currentPage,
                              juz: currentJuz,
                              onJump: _scrubToPage,
                              onCatalog: () => _showQuickJump(),
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

  void _selectAyah(QuranAyahReference reference) {
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
    unawaited(_setControls(show));
    _queuePagePositionSave(
      _currentPage,
      preferredReference: reference,
      accountScope: scope,
    );
  }

  Future<void> _playSelected() async {
    final reference = _selectedAyah ?? _pageReference;
    final scope = _database.accountScope.current;
    if (_audioLoading ||
        reference == null ||
        scope == null ||
        !_isCurrentAccount(scope)) {
      return;
    }
    final controller = ref.read(audioControllerProvider.notifier);
    final current = ref.read(audioControllerProvider);
    if (current.error == null &&
        current.track?.surah == reference.surah &&
        current.rangeStartAyah == reference.ayah &&
        current.rangeEndAyah == reference.ayah) {
      setState(() => _playerExpanded = true);
      await controller.toggle();
      return;
    }
    final request = ++_audioRequest;
    final page = _currentPage;
    bool ownsRequest() =>
        _isCurrentAccount(scope) &&
        request == _audioRequest &&
        page == _currentPage &&
        reference == (_selectedAyah ?? _pageReference) &&
        identical(controller, ref.read(audioControllerProvider.notifier));
    setState(() => _audioLoading = true);
    try {
      final repository = ref.read(audioRepositoryProvider);
      final recitations = (await repository.recitations())
          .where((r) => r.timingsAvailable && r.streamAllowed)
          .toList();
      if (!ownsRequest()) return;
      final recitation = preferredRecitation(
        recitations,
        preferredId:
            ref.read(appPreferencesProvider).preferredRecitationId ??
            current.track?.recitationId,
      );
      if (recitation == null) throw StateError('No timed recitation');
      final playback = await repository.playback(
        recitationId: recitation.id,
        surah: reference.surah,
      );
      if (!ownsRequest() || !mounted) return;
      final surah = ref
          .read(quranCatalogProvider)
          .valueOrNull
          ?.surahs
          .where((s) => s.number == reference.surah)
          .firstOrNull;
      await controller.loadPlayback(
        playback: playback,
        reciter: reciterWithPersonPortrait(
          recitation.reciter,
          apiBaseUrl: ref.read(appConfigProvider).apiBaseUrl,
          reciters: recitations.map((r) => r.reciter),
        ),
        surahName:
            surah?.nameFor(Localizations.localeOf(context).languageCode) ??
            '${context.l10n.surah} ${reference.surah}',
        startAyah: reference.ayah,
        endAyah: reference.ayah,
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

  Future<void> _bookmarkSelected() async {
    final reference = _selectedAyah ?? _pageReference;
    final scope = _database.accountScope.current;
    if (_bookmarkLoading ||
        reference == null ||
        scope == null ||
        !_isCurrentAccount(scope)) {
      return;
    }
    _bookmarkLoading = true;
    try {
      final saved = await _quranRepository.toggleBookmark(
        reference.surah,
        reference.ayah,
        page: _currentPage,
        accountScope: scope,
      );
      if (_isCurrentAccount(scope) && mounted) {
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
      _bookmarkLoading = false;
    }
  }

  void _scrubToPage(int page) {
    final scope = _database.accountScope.current;
    if (scope == null || !_isCurrentAccount(scope) || page == _currentPage) {
      return;
    }
    _dotTargetPage = page.clamp(1, 604);
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
        '/reader/${reference?.surah ?? widget.surah}?ayah=${reference?.ayah ?? widget.ayah}',
      );
    }
  }

  Future<void> _showReaderOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, update) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    context.l10n.readerSettings,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Row(
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
                  ListTile(
                    leading: const Icon(Icons.headphones_rounded),
                    title: Text(context.l10n.nowPlaying),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      context.push(
                        ref.read(audioControllerProvider).active
                            ? '/player'
                            : '/app?tab=3',
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.record_voice_over_rounded),
                    title: Text(context.l10n.chooseReciter),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      context.push('/app?tab=3');
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.format_list_bulleted_rounded),
                    title: Text(context.l10n.textMode),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      unawaited(_switchToText());
                    },
                  ),
                  Text(
                    context.l10n.tapAyahForDetails,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _onScanPageChanged(int index) {
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

  void _prefetchAdjacentPages(int page) {
    final logicalWidth = MediaQuery.sizeOf(context).width;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final repository = ref.read(selectedMushafRepositoryProvider);
    for (final candidate in <int>[page - 1, page + 1]) {
      if (candidate < 1 || candidate > 604) continue;
      final pageFuture = ref.read(mushafPageProvider(candidate).future);
      unawaited(() async {
        try {
          final pageData = await pageFuture;
          final asset = pageData.bestAssetFor(logicalWidth, pixelRatio);
          if (asset != null) {
            await repository.cachedMushafPageAsset(pageData, asset);
          }
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
      final selection = await showModalBottomSheet<QuranQuickJumpSelection>(
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
    final page = requestedPage.clamp(1, 604);
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
          (resolvedPage.regions.isEmpty ||
              resolvedPage.regions.any(
                (region) => region.ayah == preferredReference,
              ));
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
              resolvedPage.regions.isNotEmpty &&
              !resolvedPage.regions.any(
                (region) => region.ayah == _selectedAyah,
              )) {
            _selectedAyah = null;
          }
        });
      }
      await repository.savePosition(
        surah: reference?.surah ?? current.surah,
        ayah: reference?.ayah ?? current.ayah,
        page: page,
        accountScope: scope,
      );
      if (mounted) {
        _readingSession?.observe(
          surah: reference?.surah ?? current.surah,
          ayah: reference?.ayah ?? current.ayah,
          page: page,
        );
      }
    } on AccountScopeChanged {
      return;
    } on Object {
      if (!_isCurrentPositionRequest(scope, request, page)) {
        return;
      }
      try {
        await repository.savePosition(
          surah: preferredReference?.surah ?? current.surah,
          ayah: preferredReference?.ayah ?? current.ayah,
          page: page,
          accountScope: scope,
        );
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
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: false,
        backgroundColor: Colors.transparent,
        builder: (context) => AyahActionSheet(reference: reference, page: page),
      );
    } finally {
      _detailsOpen = false;
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
