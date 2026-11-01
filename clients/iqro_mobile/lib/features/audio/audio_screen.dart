import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/audio/audio_controller.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/storage/offline_storage_quota.dart';
import '../../core/theme/iqro_theme.dart';
import 'mini_player.dart';
import 'audio_models.dart';
import 'audio_offline_repository.dart';
import 'listening_queue.dart';
import 'recitation_style_label.dart';
import 'reciter_catalog.dart';
import 'reciter_portraits.dart';
import 'premium_reciter_portrait.dart';

/// Widest the Audio tab grows on a tablet, padding included.
const audioTabletContentWidth = 1100.0;

// Space a reciter card keeps around its portrait, and below it for the names.
const _cardSidePadding = 6.0;
const _cardNamesExtent = 92.0;

/// Reciter grid for a content [width]: about 110 dp cards on a phone and
/// 160 dp on a tablet, each portrait as wide as its card.
({int columns, double portrait, double extent}) reciterGridLayout(
  double width, {
  required int count,
}) {
  final target = width < iqroTabletShortestSide ? 110.0 : 160.0;
  var columns = math.max(2, ((width + 10) / (target + 10)).round());
  // Three on a phone, but not with a lone card in the last row.
  if (columns == 3 && count % 3 == 1) columns = 2;
  final card = (width - 10 * (columns - 1)) / columns;
  final portrait = (card - _cardSidePadding * 2).floorToDouble();
  return (
    columns: columns,
    portrait: portrait,
    extent: portrait + _cardNamesExtent,
  );
}

/// How many reciter cards the tab builds and warms before «show all».
const collapsedReciterCount = 30;

/// Loads the reciters and decodes their card portraits while another tab is
/// open, so the Audio tab shows faces at once instead of a spinner, then a
/// slow fade.
Future<void> warmAudioCatalog(BuildContext context, WidgetRef ref) async {
  try {
    final reciters = await ref.read(recitersProvider.future);
    await ref.read(audioRecitationsProvider.future);
    if (!context.mounted) return;
    final apiBaseUrl = ref.read(appConfigProvider).apiBaseUrl;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final people = peopleWithPortraitsFirst(groupRecitersByPerson(reciters));
    // The tab's width (the page padding is 16 on each side) gives the size
    // its cards decode at; a guess here would decode every face twice.
    final screen = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final available = screen.width - padding.left - padding.right;
    final portraitSize = reciterGridLayout(
      iqroPageWidth(
            context,
            available,
            tabletContentWidth: audioTabletContentWidth,
          ) -
          32,
      count: people.length,
    ).portrait;
    for (final person in people.take(collapsedReciterCount)) {
      final url = resolveReciterPortraitUrl(
        person.portraitSource,
        apiBaseUrl: apiBaseUrl,
      );
      if (!context.mounted) continue;
      unawaited(
        precacheImage(
          reciterPortraitImage(
            url,
            size: portraitSize,
            devicePixelRatio: pixelRatio,
          ),
          context,
          onError: (error, stack) {},
        ),
      );
    }
  } on Object {
    // The tab loads the catalog itself and reports what failed.
  }
}

class AudioScreen extends ConsumerStatefulWidget {
  const AudioScreen({super.key});

  @override
  ConsumerState<AudioScreen> createState() => _AudioScreenState();
}

class _AudioScreenState extends ConsumerState<AudioScreen> {
  AccountScopeKey? _accountKey;
  String? _selected;
  String? _selectedRecitationId;
  String _selectedStyle = defaultRecitationStyle;
  var _loadingTrack = false;
  String? _loadingPersonKey;
  var _refreshingReciters = false;
  var _showAllReciters = false;
  String _reciterQuery = '';
  ({
    List<Reciter> reciters,
    List<Recitation> recitations,
    String style,
    ReciterSearch search,
    Set<String> fullPeople,
  })?
  _lastCatalogSearch;
  var _playRequest = 0;
  var _refreshRequest = 0;

  @override
  Widget build(BuildContext context) {
    final accountKey = ref.watch(activeAccountScopeKeyProvider);
    if (_accountKey != accountKey) {
      _accountKey = accountKey;
      _selected = null;
      _selectedRecitationId = null;
      _playRequest += 1;
      _refreshRequest += 1;
      _loadingTrack = false;
      _refreshingReciters = false;
    }
    final reciters = ref.watch(recitersProvider);
    final recitations = ref.watch(audioRecitationsProvider);
    final player = ref.watch(
      audioControllerProvider.select(iqroAudioPresentation),
    );
    final locale = Localizations.localeOf(context).languageCode;
    final apiBaseUrl = ref.watch(appConfigProvider).apiBaseUrl;
    final preferredRecitationId = ref.watch(
      appPreferencesProvider.select((value) => value.listeningRecitationId),
    );
    final listeningActive =
        player.channel == AudioPlaybackChannel.listening &&
        player.standalone == null &&
        player.track != null;
    final listeningController = ref.read(audioControllerProvider.notifier);
    final preferredReciter = recitations.valueOrNull
        ?.where((item) => item.id == preferredRecitationId)
        .firstOrNull
        ?.reciter;
    final listeningReciter =
        listeningController.listeningReciter ?? preferredReciter;
    return Scaffold(
      appBar: IqroTopBar(
        title: context.l10n.navAudio,
        subtitle: context.l10n.quranSubtitle,
        actions: <Widget>[
          IconButton(
            tooltip: context.l10n.refreshReciters,
            onPressed: _refreshingReciters ? null : _refreshReciters,
            icon: _refreshingReciters
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
          if (listeningActive)
            IconButton(
              tooltip: context.l10n.nowPlaying,
              onPressed: () => context.push('/player'),
              icon: const Icon(Icons.graphic_eq),
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: IqroPage(
        tabletContentWidth: audioTabletContentWidth,
        padding: iqroRootTabPadding(
          context,
          playerActive: player.track != null || player.standalone != null,
          playerCollapsed: ref.watch(miniPlayerCollapsedProvider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            IqroCard(
              color: context.iqroColors.ink,
              borderColor: Colors.transparent,
              padding: const EdgeInsets.all(22),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        IqroEyebrow(context.l10n.audioTitle, light: true),
                        const SizedBox(height: 6),
                        Text(
                          _heroTitle(
                            listeningActive
                                ? player.track?.surah
                                : listeningController.listeningSurah,
                            listeningActive
                                ? player.surahName
                                : listeningController.listeningSurahName,
                          ),
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          listeningReciter?.nameFor(locale) ??
                              context.l10n.chooseReciter,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filled(
                    tooltip: listeningActive && player.playing
                        ? context.l10n.pause
                        : context.l10n.play,
                    onPressed: listeningActive
                        ? listeningController.toggle
                        : listeningController.hasListeningPlayback
                        ? _resumeListening
                        : null,
                    icon: Icon(
                      listeningActive && player.playing
                          ? Icons.pause
                          : Icons.play_arrow,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            reciters.when(
              loading: () => const IqroLoading(),
              error: (error, stack) => IqroAsyncError(
                title: context.l10n.noAudio,
                onRetry: () => ref.invalidate(recitersProvider),
              ),
              data: (items) => recitations.when(
                loading: () => const IqroLoading(),
                error: (error, stack) => IqroAsyncError(
                  title: context.l10n.noAudio,
                  onRetry: () => ref.invalidate(audioRecitationsProvider),
                ),
                data: (catalog) => _buildReciterCatalog(
                  reciters: items,
                  recitations: catalog,
                  player: player,
                  locale: locale,
                  apiBaseUrl: apiBaseUrl,
                  preferredRecitationId: preferredRecitationId,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The people with a recording in [style], ready to search. The catalog
  /// changes rarely and this tab rebuilds with every player tick, so this
  /// reuses the last answer rather than walking the catalog each time.
  ({ReciterSearch search, Set<String> fullPeople}) _catalogSearch(
    List<Reciter> reciters,
    List<Recitation> recitations,
    String style,
  ) {
    final last = _lastCatalogSearch;
    if (last != null &&
        identical(last.reciters, reciters) &&
        identical(last.recitations, recitations) &&
        last.style == style) {
      return (search: last.search, fullPeople: last.fullPeople);
    }
    final reciterIds = <String>{
      for (final recitation in recitations)
        if (recitation.style == style &&
            recitation.supports(AudioRecitationRole.listening))
          recitation.reciter.id,
    };
    final search = ReciterSearch(
      peopleWithPortraitsFirst(
        groupRecitersByPerson(reciters)
            .where(
              (person) => person.sources.any(
                (source) => reciterIds.contains(source.id),
              ),
            )
            .toList(growable: false),
      ),
    );
    final fullPeople = <String>{
      for (final recitation in recitations)
        if (recitation.supports(AudioRecitationRole.ayahPlayback))
          reciterPersonKey(recitation.reciter),
    };
    _lastCatalogSearch = (
      reciters: reciters,
      recitations: recitations,
      style: style,
      search: search,
      fullPeople: fullPeople,
    );
    return (search: search, fullPeople: fullPeople);
  }

  Widget _buildReciterCatalog({
    required List<Reciter> reciters,
    required List<Recitation> recitations,
    required IqroAudioPresentation player,
    required String locale,
    required String apiBaseUrl,
    required String? preferredRecitationId,
  }) {
    if (reciters.isEmpty || recitations.isEmpty) {
      return IqroStatusBanner(
        icon: Icons.volume_off_outlined,
        title: context.l10n.noAudio,
      );
    }
    final styles = orderedRecitationStyles(
      recitations.where((item) => item.supports(AudioRecitationRole.listening)),
    );
    if (styles.isEmpty) {
      return IqroStatusBanner(
        icon: Icons.volume_off_outlined,
        title: context.l10n.noAudio,
      );
    }
    final selectedStyle = styles.contains(_selectedStyle)
        ? _selectedStyle
        : styles.first;
    final catalog = _catalogSearch(reciters, recitations, selectedStyle);
    final search = catalog.search;
    final visiblePeople = search.people;
    if (visiblePeople.isEmpty) {
      return IqroStatusBanner(
        icon: Icons.volume_off_outlined,
        title: context.l10n.noAudio,
      );
    }
    final preferredPersonKey = recitations
        .where((item) => item.id == preferredRecitationId)
        .map((item) => reciterPersonKey(item.reciter))
        .firstOrNull;
    final activePersonKey = player.channel == AudioPlaybackChannel.listening
        ? player.reciter == null
              ? preferredPersonKey
              : reciterPersonKey(player.reciter!)
        : preferredPersonKey;
    final foundPeople = search.find(_reciterQuery);
    // A GridView inside the page builds every card at once, so hundreds of
    // reciters open a short list first; the search still reads all of them.
    final shownPeople = _showAllReciters || _reciterQuery.trim().isNotEmpty
        ? foundPeople
        : foundPeople.take(collapsedReciterCount).toList(growable: false);
    final selectedPerson = visiblePeople.firstWhere(
      (item) => item.key == _selected,
      orElse: () => visiblePeople.firstWhere(
        (item) => item.key == activePersonKey,
        orElse: () => visiblePeople.first,
      ),
    );
    final selectedRecitation = recitationForPersonStyle(
      selectedPerson,
      recitations,
      selectedStyle,
      preferredId: _selectedRecitationId ?? preferredRecitationId,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          context.l10n.recitationStyle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        _RecitationStyleFilter(
          styles: styles,
          selected: selectedStyle,
          onSelected: (style) {
            if (style == selectedStyle || _loadingTrack) return;
            setState(() {
              _selectedStyle = style;
              _selected = null;
              _selectedRecitationId = null;
            });
          },
        ),
        if (selectedRecitation?.offlineDownloadAllowed == true) ...<Widget>[
          const SizedBox(height: 12),
          _OfflineAudioCard(recitation: selectedRecitation!),
        ],
        if (selectedRecitation != null) ...<Widget>[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              key: const ValueKey('audio-listen-whole-quran'),
              onPressed: _loadingTrack
                  ? null
                  : () => _openPlayerForPerson(
                      selectedPerson,
                      selectedRecitation,
                      wholeQuran: true,
                    ),
              icon: const Icon(Icons.playlist_play_rounded),
              label: Text(context.l10n.listenWholeQuran),
            ),
          ),
        ],
        const SizedBox(height: 22),
        Text(
          context.l10n.allReciters,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey<String>('audio-reciter-search'),
          decoration: InputDecoration(
            hintText: context.l10n.searchReciters,
            prefixIcon: const Icon(Icons.search_rounded),
          ),
          onChanged: (value) => setState(() => _reciterQuery = value),
          textInputAction: TextInputAction.search,
        ),
        if (catalog.fullPeople.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              const _ReciterFullBadge(),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.l10n.fullReciterHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        if (foundPeople.isEmpty)
          IqroStatusBanner(
            icon: Icons.search_off_rounded,
            title: context.l10n.reciterNotFound,
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            final grid = reciterGridLayout(
              constraints.maxWidth,
              count: shownPeople.length,
            );
            return GridView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: shownPeople.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: grid.columns,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                mainAxisExtent: grid.extent,
              ),
              itemBuilder: (context, index) {
                final person = shownPeople[index];
                final recitation = recitationForPersonStyle(
                  person,
                  recitations,
                  selectedStyle,
                  preferredId: preferredRecitationId,
                );
                final active = person.key == selectedPerson.key;
                return _ReciterCard(
                  reciter: person.primary,
                  portraitSize: grid.portrait,
                  locale: locale,
                  active: active,
                  full: catalog.fullPeople.contains(person.key),
                  loading: _loadingTrack && _loadingPersonKey == person.key,
                  portraitUrl: resolveReciterPortraitUrl(
                    person.portraitSource,
                    apiBaseUrl: apiBaseUrl,
                  ),
                  onTap: _loadingTrack || recitation == null
                      ? null
                      : () => _openPlayerForPerson(person, recitation),
                );
              },
            );
          },
        ),
        if (shownPeople.length < foundPeople.length)
          Align(
            child: TextButton(
              onPressed: () => setState(() => _showAllReciters = true),
              child: Text(context.l10n.showAllReciters(foundPeople.length)),
            ),
          ),
      ],
    );
  }

  Future<void> _refreshReciters() async {
    if (_refreshingReciters) return;
    final controller = ref.read(audioControllerProvider.notifier);
    final activeId = controller.listeningReciter?.id;
    final request = ++_refreshRequest;
    setState(() => _refreshingReciters = true);
    try {
      final repository = ref.read(audioRepositoryProvider);
      final items = await repository.reciters(forceRefresh: true);
      await repository.recitations(forceRefresh: true);
      if (!_isCurrentAudioRequest(controller, request, refresh: true)) {
        return;
      }

      if (activeId != null) {
        for (final person in groupRecitersByPerson(items)) {
          if (person.containsReciter(activeId)) {
            final activeReciter = person.sources.firstWhere(
              (item) => item.id == activeId,
            );
            controller.updateReciterMetadata(
              reciterWithPersonPortrait(
                activeReciter,
                apiBaseUrl: ref.read(appConfigProvider).apiBaseUrl,
                reciters: person.sources,
              ),
              currentReciterId: activeId,
            );
            break;
          }
        }
      }
      final people = groupRecitersByPerson(items);
      if (_selected != null && !people.any((item) => item.key == _selected)) {
        _selected = people.firstOrNull?.key;
        _selectedRecitationId = null;
      }

      ref.invalidate(recitersProvider);
      ref.invalidate(audioRecitationsProvider);
      await Future.wait(<Future<Object?>>[
        ref.read(recitersProvider.future),
        ref.read(audioRecitationsProvider.future),
      ]);
      if (!_isCurrentAudioRequest(controller, request, refresh: true)) {
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(context.l10n.recitersUpdated)));
    } on Object {
      if (!_isCurrentAudioRequest(controller, request, refresh: true)) {
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(context.l10n.recitersRefreshFailed)),
        );
    } finally {
      if (mounted && request == _refreshRequest) {
        setState(() => _refreshingReciters = false);
      }
    }
  }

  /// With [wholeQuran] the recording plays from its first surah and the
  /// queue moves on after each one.
  Future<void> _openPlayerForPerson(
    ReciterPerson person,
    Recitation recitation, {
    bool wholeQuran = false,
  }) async {
    if (_loadingTrack) return;
    final controller = ref.read(audioControllerProvider.notifier);
    final navigationEpoch = controller.navigationEpoch;
    final repository = ref.read(audioRepositoryProvider);
    final listeningSurah = controller.listeningSurah ?? 1;
    // A listening recording may hold only some surahs; start on its first one.
    final surah = wholeQuran
        ? recitationHeldSurahs(recitation).first
        : recitation.coversSurah(listeningSurah)
        ? listeningSurah
        : recitation.coverage?.surahNumbers.firstOrNull ?? listeningSurah;
    final surahName = _surahName(
      surah,
      fallback: controller.listeningSurahName ?? '',
    );
    final request = ++_playRequest;
    setState(() {
      _selected = person.key;
      _loadingTrack = true;
      _loadingPersonKey = person.key;
    });
    try {
      final playback = await repository.playback(
        recitationId: recitation.id,
        surah: surah,
      );
      if (!_isCurrentAudioRequest(
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
          reciters: person.sources,
        ),
        surahName: surahName,
      );
      if (!_isCurrentAudioRequest(
        controller,
        request,
        navigationEpoch: navigationEpoch,
      )) {
        return;
      }
      _selectedRecitationId = recitation.id;
      if (wholeQuran) {
        controller.setQueueMode(
          wholeQuranMode(ref.read(audioControllerProvider).queueMode),
        );
      }
      unawaited(
        ref
            .read(appPreferencesProvider.notifier)
            .setListeningRecitation(recitation.id),
      );
      if (!mounted) return;
      context.push('/player');
    } on Object {
      if (_isCurrentAudioRequest(
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
      if (mounted && request == _playRequest) {
        setState(() {
          _loadingTrack = false;
          _loadingPersonKey = null;
        });
      }
    }
  }

  /// "2 · Аль-Бакара", as the player titles the surah; Al-Fatiha before
  /// anything was heard.
  String _heroTitle(int? surah, String? savedName) {
    if (surah == null) {
      return savedName?.trim().isNotEmpty == true
          ? savedName!
          : context.l10n.alFatiha;
    }
    final locale = Localizations.localeOf(context).languageCode;
    final name = ref
        .watch(quranCatalogProvider)
        .valueOrNull
        ?.surahs
        .where((candidate) => candidate.number == surah)
        .firstOrNull
        ?.nameFor(locale);
    return surahDisplayTitle(
      surah,
      name ?? savedName,
      surahWord: context.l10n.surah,
    );
  }

  String _surahName(int surah, {required String fallback}) {
    final active = ref.read(audioControllerProvider);
    if (active.track?.surah == surah && fallback.trim().isNotEmpty) {
      return fallback;
    }
    final locale = Localizations.localeOf(context).languageCode;
    final catalog = ref.read(quranCatalogProvider).valueOrNull;
    final item = catalog?.surahs
        .where((candidate) => candidate.number == surah)
        .firstOrNull;
    if (item != null) return item.nameFor(locale);
    return surah == 1 ? context.l10n.alFatiha : '${context.l10n.surah} $surah';
  }

  bool _isCurrentAudioRequest(
    AudioController controller,
    int request, {
    bool refresh = false,
    int? navigationEpoch,
  }) {
    return mounted &&
        request == (refresh ? _refreshRequest : _playRequest) &&
        (navigationEpoch == null ||
            controller.navigationEpoch == navigationEpoch) &&
        identical(ref.read(audioControllerProvider.notifier), controller);
  }

  Future<void> _resumeListening() async {
    final controller = ref.read(audioControllerProvider.notifier);
    final navigationEpoch = controller.navigationEpoch;
    try {
      if (await controller.activateListening()) return;
    } on Object {
      // The current saved stream may be temporarily unavailable.
    }
    if (!mounted ||
        !identical(controller, ref.read(audioControllerProvider.notifier)) ||
        controller.navigationEpoch != navigationEpoch) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.noAudio)));
  }
}

class _OfflineAudioCard extends ConsumerStatefulWidget {
  const _OfflineAudioCard({required this.recitation});

  final Recitation recitation;

  @override
  ConsumerState<_OfflineAudioCard> createState() => _OfflineAudioCardState();
}

class _OfflineAudioCardState extends ConsumerState<_OfflineAudioCard> {
  var _preparing = false;

  Recitation get recitation => widget.recitation;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(audioDownloadProvider(recitation.id));
    final downloading = state.status == AudioDownloadStatus.downloading;
    final ready = state.status == AudioDownloadStatus.ready;
    final failed = state.status == AudioDownloadStatus.failed;
    final updateAvailable = state.status == AudioDownloadStatus.updateAvailable;
    final available = ready || updateAvailable;
    final newSurahs = state.totalTracks - state.completedTracks;
    final progressLabel = state.totalTracks <= 0
        ? null
        : '${state.completedTracks} / ${state.totalTracks} · '
              '${_formatAudioMegabytes(state.downloadedBytes)} / '
              '${_formatAudioMegabytes(state.totalBytes)}';
    return IqroCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                available
                    ? Icons.offline_pin_outlined
                    : Icons.download_outlined,
                color: available ? Theme.of(context).colorScheme.primary : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  available
                      ? context.l10n.audioAvailableOffline
                      : downloading
                      ? context.l10n.audioDownloading
                      : context.l10n.offlineAudio,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (!ready)
                IconButton.filledTonal(
                  tooltip: failed
                      ? context.l10n.resumeDownload
                      : updateAvailable
                      ? context.l10n.audioOfflineNewSurahs(newSurahs)
                      : context.l10n.downloadForOffline,
                  onPressed: downloading
                      ? null
                      : _preparing
                      ? null
                      : _prepareDownload,
                  icon: _preparing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          failed
                              ? Icons.refresh_rounded
                              : Icons.download_rounded,
                        ),
                ),
            ],
          ),
          if (failed) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              context.l10n.audioDownloadFailed,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          // A listening-only package may hold only some of the surahs.
          if (updateAvailable) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              context.l10n.audioOfflineNewSurahs(newSurahs),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ] else if (ready &&
              state.totalTracks > 0 &&
              state.totalTracks < 114) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              context.l10n.audioOfflineSurahs(state.totalTracks),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (downloading) ...<Widget>[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: state.totalBytes > 0 ? state.progress : null,
            ),
            if (progressLabel != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(progressLabel, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _prepareDownload() async {
    if (_preparing) return;
    setState(() => _preparing = true);
    try {
      final estimate = await ref
          .read(audioOfflineRepositoryProvider)
          .estimate(recitationId: recitation.id);
      await ensureOfflineStorageCapacity(
        ref.read(localDatabaseProvider),
        packageId: estimate.packageId!,
        packageBytes: estimate.totalBytes,
      );
      if (!mounted) return;
      final remainingSurahs = estimate.totalTracks - estimate.completedTracks;
      final remainingSize = _formatAudioMegabytes(
        estimate.totalBytes - estimate.downloadedBytes,
      );
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.downloadForOffline),
          content: Text(
            remainingSurahs == 114
                ? context.l10n.downloadOfflineConfirmation(remainingSize)
                : context.l10n.downloadOfflineSurahsConfirmation(
                    remainingSurahs,
                    remainingSize,
                  ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.downloadForOffline),
            ),
          ],
        ),
      );
      if (confirmed == true && mounted) {
        unawaited(
          ref.read(audioDownloadProvider(recitation.id).notifier).download(),
        );
      }
    } on OfflineStorageQuotaExceeded {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.offlineStorageQuotaExceeded)),
      );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.networkError)));
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }
}

String _formatAudioMegabytes(int bytes) {
  final value = bytes / (1024 * 1024);
  return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} MB';
}

class _RecitationStyleFilter extends StatelessWidget {
  const _RecitationStyleFilter({
    required this.styles,
    required this.selected,
    required this.onSelected,
  });

  final List<String> styles;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: context.l10n.recitationStyle,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.only(end: 4),
        child: Row(
          children: <Widget>[
            for (var index = 0; index < styles.length; index++) ...<Widget>[
              if (index > 0) const SizedBox(width: 8),
              ChoiceChip(
                label: Text(recitationStyleLabel(context, styles[index])),
                selected: styles[index] == selected,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => onSelected(styles[index]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReciterCard extends StatelessWidget {
  const _ReciterCard({
    required this.reciter,
    required this.portraitSize,
    required this.locale,
    required this.active,
    required this.full,
    required this.loading,
    required this.portraitUrl,
    required this.onTap,
  });

  final Reciter reciter;
  final double portraitSize;
  final String locale;
  final bool active;
  final bool full;
  final bool loading;
  final String? portraitUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: onTap != null,
      selected: active,
      enabled: onTap != null,
      label: reciter.nameFor(locale),
      child: IqroCard(
        onTap: onTap,
        color: active ? colorScheme.primaryContainer : null,
        borderColor: active
            ? colorScheme.primary
            : full
            ? context.iqroColors.gold
            : context.iqroColors.line,
        padding: const EdgeInsets.fromLTRB(
          _cardSidePadding,
          10,
          _cardSidePadding,
          8,
        ),
        child: Column(
          children: <Widget>[
            _ReciterPortrait(
              size: portraitSize,
              portraitUrl: portraitUrl,
              active: active,
              full: full,
              loading: loading,
            ),
            const SizedBox(height: 9),
            Text(
              reciter.nameFor(locale),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(height: 1.15),
            ),
            if (locale != 'ar' && reciter.nameAr.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                reciter.nameAr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Marks a reciter who also plays in the Mushaf and Memorization.
class _ReciterFullBadge extends StatelessWidget {
  const _ReciterFullBadge();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.iqroColors.gold,
        border: Border.all(color: colorScheme.surface, width: 2),
      ),
      child: Icon(
        Icons.menu_book_rounded,
        size: 13,
        color: colorScheme.surface,
      ),
    );
  }
}

class _ReciterPortrait extends StatelessWidget {
  const _ReciterPortrait({
    required this.size,
    required this.portraitUrl,
    required this.active,
    required this.full,
    required this.loading,
  });

  final double size;
  final String? portraitUrl;
  final bool active;
  final bool full;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned.fill(
            child: PremiumReciterPortrait(
              url: portraitUrl,
              size: size,
              selected: active,
            ),
          ),
          if (full)
            const PositionedDirectional(
              start: -1,
              bottom: -1,
              child: _ReciterFullBadge(),
            ),
          PositionedDirectional(
            end: -1,
            bottom: -1,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.primary,
                border: Border.all(color: colorScheme.surface, width: 2),
              ),
              child: Icon(
                active ? Icons.check : Icons.play_arrow,
                size: loading ? 0 : 17,
                color: colorScheme.onPrimary,
              ),
            ),
          ),
          if (loading)
            PositionedDirectional(
              end: 3,
              bottom: 3,
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.onPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
