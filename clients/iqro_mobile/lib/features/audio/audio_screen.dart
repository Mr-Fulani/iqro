import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import 'audio_models.dart';
import 'reciter_catalog.dart';
import 'reciter_portraits.dart';

class AudioScreen extends ConsumerStatefulWidget {
  const AudioScreen({super.key});

  @override
  ConsumerState<AudioScreen> createState() => _AudioScreenState();
}

class _AudioScreenState extends ConsumerState<AudioScreen> {
  String? _selected;
  String? _selectedRecitationId;
  var _loadingTrack = false;
  var _refreshingReciters = false;

  @override
  Widget build(BuildContext context) {
    final reciters = ref.watch(recitersProvider);
    final player = ref.watch(audioControllerProvider);
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
          if (player.active)
            IconButton(
              tooltip: context.l10n.nowPlaying,
              onPressed: () => context.push('/player'),
              icon: const Icon(Icons.graphic_eq),
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: IqroPage(
        padding: iqroRootTabPadding(playerActive: player.active),
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
                          player.active
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
                    onPressed: player.active
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
              data: (items) {
                if (items.isEmpty) {
                  return IqroStatusBanner(
                    icon: Icons.volume_off_outlined,
                    title: context.l10n.noAudio,
                  );
                }
                final people = groupRecitersByPerson(items);
                final activePersonKey = player.reciter == null
                    ? null
                    : reciterPersonKey(player.reciter!);
                _selected ??= activePersonKey ?? people.first.key;
                final selectedPerson = people.firstWhere(
                  (item) => item.key == _selected,
                  orElse: () => people.first,
                );
                final variants = selectedPerson.sources.length > 1
                    ? ref.watch(recitationVariantsProvider(selectedPerson.key))
                    : null;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (selectedPerson.sources.length > 1) ...<Widget>[
                      _buildStyleSelector(
                        variants!,
                        preferredRecitationId: preferredRecitationId,
                      ),
                      const SizedBox(height: 12),
                    ],
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final preferredColumns = switch (constraints.maxWidth) {
                          < 340 => 2,
                          < 620 => 3,
                          < 900 => 4,
                          _ => 6,
                        };
                        final columns =
                            preferredColumns == 3 && people.length % 3 == 1
                            ? 2
                            : preferredColumns;
                        return GridView.builder(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: people.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                mainAxisExtent: 180,
                              ),
                          itemBuilder: (context, index) {
                            final person = people[index];
                            final reciter = person.primary;
                            final active = person.key == selectedPerson.key;
                            return _ReciterCard(
                              reciter: reciter,
                              locale: locale,
                              active: active,
                              portraitUrl: resolveReciterPortraitUrl(
                                person.portraitSource,
                                apiBaseUrl: apiBaseUrl,
                              ),
                              onTap: () async {
                                if (activePersonKey != null &&
                                    activePersonKey != person.key) {
                                  await ref
                                      .read(audioControllerProvider.notifier)
                                      .stop();
                                }
                                setState(() {
                                  _selected = person.key;
                                  _selectedRecitationId = null;
                                });
                              },
                            );
                          },
                        );
                      },
                    ),
                  ],
                );
              },
            ),
            if (!player.active) ...<Widget>[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _loadingTrack ? null : _playSelected,
                  icon: _loadingTrack
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(context.l10n.play),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStyleSelector(
    AsyncValue<List<Recitation>> variants, {
    required String? preferredRecitationId,
  }) {
    return variants.when(
      loading: () => const _RecitationStyleCard.loading(),
      error: (error, stack) =>
          _RecitationStyleCard(value: context.l10n.noAudio, onTap: null),
      data: (items) {
        if (items.length < 2) return const SizedBox.shrink();
        final selected = preferredRecitation(
          items,
          preferredId: _selectedRecitationId ?? preferredRecitationId,
        );
        return _RecitationStyleCard(
          value: selected == null
              ? context.l10n.chooseRecitationStyle
              : _styleLabel(context, selected.style),
          onTap: () => _chooseRecitationStyle(items, selected?.id),
        );
      },
    );
  }

  Future<void> _chooseRecitationStyle(
    List<Recitation> variants,
    String? selectedId,
  ) async {
    final selected = await showModalBottomSheet<Recitation>(
      context: context,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              title: Text(
                context.l10n.chooseRecitationStyle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            for (final variant in variants)
              ListTile(
                leading: Icon(
                  variant.id == selectedId
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(_styleLabel(context, variant.style)),
                onTap: () => Navigator.pop(context, variant),
              ),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() => _selectedRecitationId = selected.id);
    unawaited(
      ref
          .read(appPreferencesProvider.notifier)
          .setPreferredRecitation(selected.id),
    );
  }

  Future<void> _refreshReciters() async {
    if (_refreshingReciters) return;
    setState(() => _refreshingReciters = true);
    try {
      final items = await ref
          .read(audioRepositoryProvider)
          .reciters(forceRefresh: true);
      if (!mounted) return;

      final activeId = ref.read(audioControllerProvider).reciter?.id;
      if (activeId != null) {
        for (final person in groupRecitersByPerson(items)) {
          if (person.containsReciter(activeId)) {
            ref
                .read(audioControllerProvider.notifier)
                .updateReciterMetadata(
                  person.portraitSource,
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
      await ref.read(recitersProvider.future);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(context.l10n.recitersUpdated)));
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(context.l10n.recitersRefreshFailed)),
        );
    } finally {
      if (mounted) setState(() => _refreshingReciters = false);
    }
  }

  Future<void> _playSelected() async {
    final surahName = context.l10n.alFatiha;
    final items = await ref.read(audioRepositoryProvider).reciters();
    final people = groupRecitersByPerson(items);
    final person =
        people.where((item) => item.key == _selected).firstOrNull ??
        people.firstOrNull;
    if (person == null) return;
    setState(() => _loadingTrack = true);
    try {
      final repository = ref.read(audioRepositoryProvider);
      final variants = await repository.recitationsForReciters(
        person.sources.map((item) => item.id),
      );
      final recitation = preferredRecitation(
        variants,
        preferredId:
            _selectedRecitationId ??
            ref.read(appPreferencesProvider).preferredRecitationId,
      );
      if (recitation == null) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(context.l10n.noAudio)));
        }
        return;
      }
      final playback = await repository.playback(
        recitationId: recitation.id,
        surah: 1,
      );
      await ref
          .read(audioControllerProvider.notifier)
          .loadPlayback(
            playback: playback,
            reciter: person.portraitSource,
            surahName: surahName,
          );
      _selectedRecitationId = recitation.id;
      unawaited(
        ref
            .read(appPreferencesProvider.notifier)
            .setPreferredRecitation(recitation.id),
      );
      if (mounted) context.push('/player');
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.noAudio)));
      }
    } finally {
      if (mounted) setState(() => _loadingTrack = false);
    }
  }
}

String _styleLabel(BuildContext context, String style) => switch (style) {
  'mujawwad' => context.l10n.styleMujawwad,
  'muallim' => context.l10n.styleMuallim,
  _ => context.l10n.styleMurattal,
};

class _RecitationStyleCard extends StatelessWidget {
  const _RecitationStyleCard({required this.value, required this.onTap})
    : loading = false;

  const _RecitationStyleCard.loading()
    : value = '',
      onTap = null,
      loading = true;

  final String value;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return IqroCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.tune_rounded)),
        title: Text(context.l10n.recitationStyle),
        subtitle: loading ? null : Text(value),
        trailing: loading
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : onTap == null
            ? null
            : const Icon(Icons.expand_more_rounded),
      ),
    );
  }
}

class _ReciterCard extends StatelessWidget {
  const _ReciterCard({
    required this.reciter,
    required this.locale,
    required this.active,
    required this.portraitUrl,
    required this.onTap,
  });

  final Reciter reciter;
  final String locale;
  final bool active;
  final String? portraitUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: active,
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
  });

  final String initials;
  final String? portraitUrl;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fallback = ColoredBox(
      color: colorScheme.primaryContainer,
      child: Center(
        child: Text(
          initials,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    );
    return SizedBox(
      width: 88,
      height: 88,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned.fill(
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.surface,
                border: Border.all(
                  color: active ? colorScheme.primary : context.iqroColors.line,
                  width: active ? 3 : 1,
                ),
              ),
              child: ClipOval(
                child: portraitUrl == null
                    ? fallback
                    : CachedNetworkImage(
                        imageUrl: portraitUrl!,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => fallback,
                        errorWidget: (context, url, error) => fallback,
                      ),
              ),
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
                size: 17,
                color: colorScheme.onPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
