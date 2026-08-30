import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import 'audio_models.dart';

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
                return IqroCard(
                  padding: EdgeInsets.zero,
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: items.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final reciter = items[index];
                      final active = reciter.id == _selected;
                      return Semantics(
                        selected: active,
                        child: ListTile(
                          minTileHeight: 72,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 4,
                          ),
                          leading: _ReciterPortrait(reciter: reciter),
                          title: Text(
                            reciter.nameFor(locale),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          subtitle: Text(reciter.countryCode ?? 'Murattal'),
                          trailing: Icon(
                            active ? Icons.check_circle : Icons.circle_outlined,
                            color: active
                                ? Theme.of(context).colorScheme.primary
                                : null,
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
                        ),
                      );
                    },
                  ),
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

class _ReciterPortrait extends StatelessWidget {
  const _ReciterPortrait({required this.reciter});
  final Reciter reciter;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 25,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      backgroundImage: reciter.portraitUrl == null
          ? null
          : CachedNetworkImageProvider(reciter.portraitUrl!),
      child: reciter.portraitUrl == null ? Text(reciter.initials) : null,
    );
  }
}
