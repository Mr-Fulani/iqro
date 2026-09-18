import 'dart:async';

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
import 'reciter_catalog.dart';
import 'reciter_portraits.dart';
import 'premium_reciter_portrait.dart';

class AudioScreen extends ConsumerStatefulWidget {
  const AudioScreen({super.key});

  @override
  ConsumerState<AudioScreen> createState() => _AudioScreenState();
}

class _AudioScreenState extends ConsumerState<AudioScreen> {
  String? _selected;
  String? _selectedRecitationId;
  String _selectedStyle = defaultRecitationStyle;
  var _loadingTrack = false;
  String? _loadingPersonKey;
  var _refreshingReciters = false;
  var _playRequest = 0;
  var _refreshRequest = 0;

  @override
  Widget build(BuildContext context) {
    final reciters = ref.watch(recitersProvider);
    final recitations = ref.watch(audioRecitationsProvider);
    final player = ref.watch(
      audioControllerProvider.select(iqroAudioPresentation),
    );
    final locale = Localizations.localeOf(context).languageCode;
    final apiBaseUrl = ref.watch(appConfigProvider).apiBaseUrl;
    final preferredRecitationId = ref.watch(
      appPreferencesProvider.select((value) => value.preferredRecitationId),
    );
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
          if (player.track != null)
            IconButton(
              tooltip: context.l10n.nowPlaying,
              onPressed: () => context.push('/player'),
              icon: const Icon(Icons.graphic_eq),
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: IqroPage(
        padding: iqroRootTabPadding(
          playerActive: player.track != null,
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
                          player.track != null
                              ? player.surahName
                              : context.l10n.alFatiha,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          player.reciter?.nameFor(locale) ??
                              context.l10n.chooseReciter,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filled(
                    tooltip: player.playing
                        ? context.l10n.pause
                        : context.l10n.play,
                    onPressed: player.track != null
                        ? () => ref
                              .read(audioControllerProvider.notifier)
                              .toggle()
                        : null,
                    icon: Icon(player.playing ? Icons.pause : Icons.play_arrow),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            IqroSectionHeader(
              title: context.l10n.chooseReciter,
              eyebrow: context.l10n.allReciters,
            ),
            const SizedBox(height: 12),
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
    final people = groupRecitersByPerson(reciters);
    final styles = orderedRecitationStyles(recitations);
    if (styles.isEmpty) {
      return IqroStatusBanner(
        icon: Icons.volume_off_outlined,
        title: context.l10n.noAudio,
      );
    }
    final selectedStyle = styles.contains(_selectedStyle)
        ? _selectedStyle
        : styles.first;
    final visiblePeople = people
        .where(
          (person) =>
              recitationForPersonStyle(person, recitations, selectedStyle) !=
              null,
        )
        .toList(growable: false);
    if (visiblePeople.isEmpty) {
      return IqroStatusBanner(
        icon: Icons.volume_off_outlined,
        title: context.l10n.noAudio,
      );
    }
    final activePersonKey = player.reciter == null
        ? null
        : reciterPersonKey(player.reciter!);
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
        if (selectedRecitation != null) ...<Widget>[
          const SizedBox(height: 12),
          _OfflineAudioCard(recitation: selectedRecitation),
        ],
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final preferredColumns = switch (constraints.maxWidth) {
              < 340 => 2,
              < 620 => 3,
              < 900 => 4,
              _ => 6,
            };
            final columns =
                preferredColumns == 3 && visiblePeople.length % 3 == 1
                ? 2
                : preferredColumns;
            return GridView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: visiblePeople.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                mainAxisExtent: 180,
              ),
              itemBuilder: (context, index) {
                final person = visiblePeople[index];
                final recitation = recitationForPersonStyle(
                  person,
                  recitations,
                  selectedStyle,
                  preferredId: preferredRecitationId,
                );
                final active = person.key == selectedPerson.key;
                return _ReciterCard(
                  reciter: person.primary,
                  locale: locale,
                  active: active,
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
      ],
    );
  }

  Future<void> _refreshReciters() async {
    if (_refreshingReciters) return;
    final controller = ref.read(audioControllerProvider.notifier);
    final activeId = ref.read(audioControllerProvider).reciter?.id;
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

  Future<void> _openPlayerForPerson(
    ReciterPerson person,
    Recitation recitation,
  ) async {
    if (_loadingTrack) return;
    final controller = ref.read(audioControllerProvider.notifier);
    final repository = ref.read(audioRepositoryProvider);
    final player = ref.read(audioControllerProvider);
    final surah = player.track?.surah ?? 1;
    final surahName = _surahName(surah, fallback: player.surahName);
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
      if (!_isCurrentAudioRequest(controller, request)) return;
      await controller.loadPlayback(
        playback: playback,
        reciter: reciterWithPersonPortrait(
          recitation.reciter,
          apiBaseUrl: ref.read(appConfigProvider).apiBaseUrl,
          reciters: person.sources,
        ),
        surahName: surahName,
      );
      if (!_isCurrentAudioRequest(controller, request)) return;
      _selectedRecitationId = recitation.id;
      unawaited(
        ref
            .read(appPreferencesProvider.notifier)
            .setPreferredRecitation(recitation.id),
      );
      if (!mounted) return;
      context.push('/player');
    } on Object {
      if (_isCurrentAudioRequest(controller, request)) {
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
  }) {
    return mounted &&
        request == (refresh ? _refreshRequest : _playRequest) &&
        identical(ref.read(audioControllerProvider.notifier), controller);
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
    if (!recitation.offlineDownloadAllowed) {
      return IqroCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: <Widget>[
            const Icon(Icons.cloud_off_outlined),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.l10n.audioOfflineUnavailable,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );
    }
    final state = ref.watch(audioDownloadProvider(recitation.id));
    final downloading = state.status == AudioDownloadStatus.downloading;
    final ready = state.status == AudioDownloadStatus.ready;
    final failed = state.status == AudioDownloadStatus.failed;
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
                ready ? Icons.offline_pin_outlined : Icons.download_outlined,
                color: ready ? Theme.of(context).colorScheme.primary : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ready
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
          const SizedBox(height: 6),
          Text(
            failed
                ? context.l10n.audioDownloadFailed
                : context.l10n.offlineAudioDescription,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (downloading) ...<Widget>[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: state.totalBytes > 0 ? state.progress : null,
            ),
          ],
          if (progressLabel != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(progressLabel, style: Theme.of(context).textTheme.bodySmall),
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
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.downloadForOffline),
          content: Text(
            context.l10n.downloadOfflineConfirmation(
              _formatAudioMegabytes(estimate.totalBytes),
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

String _styleLabel(BuildContext context, String style) => switch (style) {
  'murattal' => context.l10n.styleMurattal,
  'mujawwad' => context.l10n.styleMujawwad,
  'muallim' => context.l10n.styleMuallim,
  _ => style,
};

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
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (final style in styles)
            ChoiceChip(
              label: Text(_styleLabel(context, style)),
              selected: style == selected,
              onSelected: (_) => onSelected(style),
            ),
        ],
      ),
    );
  }
}

class _ReciterCard extends StatelessWidget {
  const _ReciterCard({
    required this.reciter,
    required this.locale,
    required this.active,
    required this.loading,
    required this.portraitUrl,
    required this.onTap,
  });

  final Reciter reciter;
  final String locale;
  final bool active;
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
        borderColor: active ? colorScheme.primary : context.iqroColors.line,
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
        child: Column(
          children: <Widget>[
            _ReciterPortrait(
              initials: reciter.initials,
              portraitUrl: portraitUrl,
              active: active,
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

class _ReciterPortrait extends StatelessWidget {
  const _ReciterPortrait({
    required this.initials,
    required this.portraitUrl,
    required this.active,
    required this.loading,
  });

  final String initials;
  final String? portraitUrl;
  final bool active;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 88,
      height: 88,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned.fill(
            child: PremiumReciterPortrait(
              url: portraitUrl,
              size: 88,
              initials: initials,
              selected: active,
            ),
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
