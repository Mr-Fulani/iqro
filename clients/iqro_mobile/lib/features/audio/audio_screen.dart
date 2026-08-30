import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import 'audio_models.dart';
import 'reciter_portraits.dart';

class AudioScreen extends ConsumerStatefulWidget {
  const AudioScreen({super.key});

  @override
  ConsumerState<AudioScreen> createState() => _AudioScreenState();
}

class _AudioScreenState extends ConsumerState<AudioScreen> {
  String? _selected;
  var _loadingTrack = false;

  @override
  Widget build(BuildContext context) {
    final reciters = ref.watch(recitersProvider);
    final player = ref.watch(audioControllerProvider);
    final locale = Localizations.localeOf(context).languageCode;
    final apiBaseUrl = ref.watch(appConfigProvider).apiBaseUrl;
    return Scaffold(
      appBar: IqroTopBar(
        title: context.l10n.navAudio,
        subtitle: context.l10n.quranSubtitle,
        actions: <Widget>[
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
                _selected ??= player.reciter?.id ?? items.first.id;
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = switch (constraints.maxWidth) {
                      < 340 => 2,
                      < 620 => 3,
                      < 900 => 4,
                      _ => 6,
                    };
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: items.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        mainAxisExtent: 180,
                      ),
                      itemBuilder: (context, index) {
                        final reciter = items[index];
                        final active = reciter.id == _selected;
                        return _ReciterCard(
                          reciter: reciter,
                          locale: locale,
                          active: active,
                          portraitUrl: resolveReciterPortraitUrl(
                            reciter,
                            apiBaseUrl: apiBaseUrl,
                          ),
                          onTap: () async {
                            if (player.reciter?.id != null &&
                                player.reciter?.id != reciter.id) {
                              await ref
                                  .read(audioControllerProvider.notifier)
                                  .stop();
                            }
                            setState(() => _selected = reciter.id);
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 16),
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
            const SizedBox(height: 12),
            IqroStatusBanner(
              icon: Icons.phone_android,
              title: context.l10n.backgroundPlayback,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _playSelected() async {
    final surahName = context.l10n.alFatiha;
    final items = await ref.read(audioRepositoryProvider).reciters();
    final reciter =
        items.where((item) => item.id == _selected).firstOrNull ??
        items.firstOrNull;
    if (reciter == null) return;
    setState(() => _loadingTrack = true);
    try {
      final track = await ref
          .read(audioRepositoryProvider)
          .track(reciterId: reciter.id, surah: 1);
      if (track == null) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(context.l10n.noAudio)));
        }
        return;
      }
      await ref
          .read(audioControllerProvider.notifier)
          .load(track: track, reciter: reciter, surahName: surahName);
      if (mounted) context.push('/player');
    } finally {
      if (mounted) setState(() => _loadingTrack = false);
    }
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
