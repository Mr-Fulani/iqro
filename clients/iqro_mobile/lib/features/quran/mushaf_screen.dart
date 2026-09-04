import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/auth/account_scope.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/storage/local_database.dart';
import '../../core/storage/preferences_store.dart';
import '../../core/utils/latest_async_work_queue.dart';
import '../audio/mini_player.dart';
import '../plan/plan_repository.dart';
import 'ayah_action_sheet.dart';
import 'native_mushaf_page.dart';
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
      _pageTransitionScope = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _currentAccountKey() == activeAccount) {
          unawaited(
            SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge),
          );
          context.go('/app?tab=1');
        }
      });
      // Keep the previous owner's page and selection out of the next frame.
      return const Scaffold(body: IqroLoading());
    }
    final divisions = ref.watch(quranJuzProvider).valueOrNull;
    final currentJuz = divisions
        ?.where(
          (division) =>
              _currentPage >= division.startPage &&
              _currentPage <= division.endPage,
        )
        .firstOrNull
        ?.number;
    final player = ref.watch(
      audioControllerProvider.select(
        (value) => (
          surah: value.track?.surah,
          ayah: value.activeAyah,
          active: value.active,
        ),
      ),
    );
    final playingAyah =
        player.active && player.surah != null && player.ayah != null
        ? QuranAyahReference(id: '', surah: player.surah!, ayah: player.ayah!)
        : null;
    final foreground = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFF3EEDC)
        : const Color(0xFF26261F);
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          unawaited(
            SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge),
          );
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFEDE6D3),
        body: Stack(
          children: <Widget>[
            PageView.builder(
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
                  page: page,
                  controller: _zoomControllers.putIfAbsent(
                    page,
                    NativeMushafPageController.new,
                  ),
                  selectedAyah: _selectedAyah,
                  playingAyah: playingAyah,
                  onSelectAyah: _selectAyah,
                  onBackgroundTap: () => _setControls(!_controlsVisible),
                  onScale: (value) {
                    if (page == _currentPage && mounted) {
                      setState(() => _zoom = value);
                    }
                  },
                );
              },
            ),
            IgnorePointer(
              ignoring: !_controlsVisible,
              child: AnimatedSlide(
                offset: _controlsVisible ? Offset.zero : const Offset(0, -1),
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: _controlsVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[Color(0xDD071A16), Color(0x00071A16)],
                      ),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: SizedBox(
                        height: 92,
                        child: Row(
                          children: <Widget>[
                            const SizedBox(width: 6),
                            IconButton(
                              tooltip: context.l10n.back,
                              onPressed: () => context.pop(),
                              color: Colors.white,
                              icon: const Icon(Icons.arrow_back),
                            ),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  Text(
                                    '${context.l10n.page} $_currentPage',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(color: Colors.white),
                                  ),
                                  Text(
                                    '${context.l10n.juz} ${currentJuz ?? '—'}',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: .7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: context.l10n.quickJump,
                              onPressed: _showQuickJump,
                              color: Colors.white,
                              icon: const Icon(Icons.layers_outlined),
                            ),
                            IconButton(
                              tooltip: context.l10n.textMode,
                              onPressed: () async {
                                final reference =
                                    _selectedAyah ??
                                    _pageReference ??
                                    QuranAyahReference(
                                      id: '',
                                      surah: widget.surah,
                                      ayah: widget.ayah,
                                    );
                                await ref
                                    .read(appPreferencesProvider.notifier)
                                    .setReaderMode(ReaderMode.text);
                                if (!context.mounted) return;
                                context.pushReplacement(
                                  '/reader/${reference.surah}'
                                  '?ayah=${reference.ayah}',
                                );
                              },
                              color: Colors.white,
                              icon: const Icon(Icons.format_list_bulleted),
                            ),
                            const SizedBox(width: 6),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            IgnorePointer(
              ignoring: !_controlsVisible,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: AnimatedSlide(
                  offset: _controlsVisible ? Offset.zero : const Offset(0, 1),
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    opacity: _controlsVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Container(
                      color: const Color(0xED071A16),
                      padding: EdgeInsetsDirectional.fromSTEB(
                        14,
                        12,
                        14,
                        12 + MediaQuery.paddingOf(context).bottom,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Icon(
                                Icons.zoom_out,
                                color: Colors.white.withValues(alpha: .8),
                              ),
                              Expanded(
                                child: Slider(
                                  value: _zoom.clamp(1, 3),
                                  min: 1,
                                  max: 3,
                                  onChanged: (value) {
                                    _zoomControllers[_currentPage]?.setZoom(
                                      value,
                                    );
                                    setState(() => _zoom = value);
                                  },
                                ),
                              ),
                              Icon(
                                Icons.zoom_in,
                                color: Colors.white.withValues(alpha: .8),
                              ),
                              SizedBox(
                                width: 42,
                                child: Text(
                                  '${(_zoom * 100).round()}%',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              IconButton.filledTonal(
                                tooltip:
                                    '${context.l10n.page} ${_currentPage - 1}',
                                onPressed: _currentPage <= 1
                                    ? null
                                    : () => _turnPage(-1),
                                icon: const Icon(Icons.chevron_left),
                              ),
                              Expanded(
                                child: Column(
                                  children: <Widget>[
                                    Text(
                                      '$_currentPage / 604',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(color: Colors.white),
                                    ),
                                    Text(
                                      context.l10n.tapAyahForDetails,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: .65,
                                        ),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton.filledTonal(
                                tooltip:
                                    '${context.l10n.page} ${_currentPage + 1}',
                                onPressed: _currentPage >= 604
                                    ? null
                                    : () => _turnPage(1),
                                icon: const Icon(Icons.chevron_right),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (player.active && !_controlsVisible)
              PositionedDirectional(
                start: 0,
                end: 0,
                bottom: 18 + MediaQuery.paddingOf(context).bottom,
                child: const IqroMiniPlayer(),
              ),
            if (!_controlsVisible)
              PositionedDirectional(
                start: 0,
                end: 0,
                bottom:
                    (player.active ? 98 : 58) +
                    MediaQuery.paddingOf(context).bottom,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: .65,
                    duration: const Duration(milliseconds: 300),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(Icons.more_horiz, color: foreground),
                        const SizedBox(width: 6),
                        Text(
                          context.l10n.tapForControls,
                          style: TextStyle(color: foreground, fontSize: 12),
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
    _initialPageHandled = true;
    _zoomControllers[_currentPage]?.setZoom(1);
    setState(() {
      _currentPage = page;
      _controlsVisible = false;
      _zoom = 1;
      _selectedAyah = null;
      _pageReference = null;
    });
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
    _queuePagePositionSave(page, accountScope: _pageTransitionScope);
    _zoomControllers.removeWhere((key, value) => (key - page).abs() > 2);
    _prefetchAdjacentPages(page);
  }

  void _prefetchAdjacentPages(int page) {
    final logicalWidth = MediaQuery.sizeOf(context).width;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final repository = ref.read(quranRepositoryProvider);
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

  void _turnPage(int delta) {
    final target = (_currentPage + delta).clamp(1, 604).toInt();
    if (target == _currentPage) return;
    final scope = ref.read(localDatabaseProvider).accountScope.current;
    if (scope == null || !_isCurrentAccount(scope)) return;
    _pageTransitionScope = scope;
    final navigation = _pageController.animateToPage(
      target - 1,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOutCubic,
    );
    unawaited(
      navigation.whenComplete(() {
        if (identical(_pageTransitionScope, scope)) {
          _pageTransitionScope = null;
        }
      }),
    );
  }

  Future<void> _showQuickJump() async {
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
          initialMode: QuranQuickJumpMode.page,
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

  Future<void> _selectAyah(QuranAyahReference reference) async {
    final repository = ref.read(quranRepositoryProvider);
    late final AccountScopeSnapshot scope;
    try {
      scope = await repository.captureAccount();
    } on AccountScopeChanged {
      return;
    }
    if (!_isCurrentAccount(scope)) return;
    _positionSaves.clearPending();
    _positionRequest++;
    setState(() {
      _selectedAyah = reference;
      _pageReference = reference;
      _controlsVisible = false;
    });
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (!_isCurrentAccount(scope)) return;
    try {
      await repository.savePosition(
        surah: reference.surah,
        ayah: reference.ayah,
        page: _currentPage,
        accountScope: scope,
      );
    } on AccountScopeChanged {
      return;
    }
    if (!_isCurrentAccount(scope) || !mounted) return;
    ref.invalidate(readingPositionProvider(accountScopeKey(scope)));
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          AyahActionSheet(reference: reference, page: _currentPage),
    );
    if (_isCurrentAccount(scope)) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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
