import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/audio/audio_controller.dart';
import '../../core/auth/account_scope.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/storage/local_database.dart';
import 'reciter_portraits.dart';

class IqroMiniPlayer extends ConsumerStatefulWidget {
  const IqroMiniPlayer({super.key});

  @override
  ConsumerState<IqroMiniPlayer> createState() => _IqroMiniPlayerState();
}

class _IqroMiniPlayerState extends ConsumerState<IqroMiniPlayer> {
  var _changingSurah = false;
  var _changeRequest = 0;
  AudioController? _visibleController;

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(
      audioControllerProvider.select(iqroAudioPresentation),
    );
    final controller = ref.read(audioControllerProvider.notifier);
    if (!identical(_visibleController, controller)) {
      _visibleController = controller;
      _changeRequest += 1;
      _changingSurah = false;
    }
    final locale = Localizations.localeOf(context).languageCode;
    final currentSurah = player.track?.surah;
    final reciter = player.reciter;
    final reciters = reciter == null
        ? null
        : ref.watch(recitersProvider).valueOrNull;
    final portraitUrl = reciter == null
        ? null
        : resolveReciterPortraitUrl(
            reciter,
            apiBaseUrl: ref.watch(appConfigProvider).apiBaseUrl,
            reciters: reciters,
          );
    final controlsEnabled =
        player.track != null && !player.buffering && !_changingSurah;
    return SafeArea(
      top: false,
      bottom: false,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 10, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(17),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0x52030F0C),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: Colors.white.withValues(alpha: .16)),
            ),
            child: ListTile(
              minTileHeight: 66,
              contentPadding: const EdgeInsetsDirectional.fromSTEB(8, 0, 6, 0),
              leading: _MiniPlayerPortrait(
                portraitUrl: portraitUrl,
                name: reciter?.nameFor(locale) ?? '',
              ),
              title: Text(
                player.track == null
                    ? context.l10n.audioTitle
                    : player.surahName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                reciter?.nameFor(locale) ?? context.l10n.chooseReciter,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white.withValues(alpha: .68)),
              ),
              trailing: SizedBox(
                width: 144,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    _MiniPlayerControl(
                      tooltip: context.l10n.previousSurah,
                      icon: Icons.skip_previous_rounded,
                      onPressed:
                          controlsEnabled &&
                              currentSurah != null &&
                              currentSurah > 1
                          ? () => _changeSurah(-1)
                          : null,
                    ),
                    _MiniPlayerControl(
                      tooltip: player.playing
                          ? context.l10n.pause
                          : context.l10n.play,
                      icon: player.playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      emphasized: true,
                      loading: player.buffering || _changingSurah,
                      onPressed: player.track == null
                          ? () => context.push('/app?tab=3')
                          : controlsEnabled
                          ? () => ref
                                .read(audioControllerProvider.notifier)
                                .toggle()
                          : null,
                    ),
                    _MiniPlayerControl(
                      tooltip: context.l10n.nextSurah,
                      icon: Icons.skip_next_rounded,
                      onPressed:
                          controlsEnabled &&
                              currentSurah != null &&
                              currentSurah < 114
                          ? () => _changeSurah(1)
                          : null,
                    ),
                  ],
                ),
              ),
              onTap: () =>
                  context.push(player.track == null ? '/app?tab=3' : '/player'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _changeSurah(int direction) async {
    if (_changingSurah) return;
    final database = ref.read(localDatabaseProvider);
    final accountScope = database.accountScope.current;
    if (accountScope == null) return;
    final controller = ref.read(audioControllerProvider.notifier);
    final request = ++_changeRequest;
    final player = ref.read(audioControllerProvider);
    final reciter = player.reciter;
    final recitationId = player.track?.recitationId;
    final currentSurah = player.track?.surah;
    if (reciter == null || recitationId == null || currentSurah == null) return;
    final targetSurah = currentSurah + direction;
    if (targetSurah < 1 || targetSurah > 114) return;

    final locale = Localizations.localeOf(context).languageCode;
    var surahName = '${context.l10n.surah} $targetSurah';
    final catalog = ref.read(quranCatalogProvider).valueOrNull;
    if (catalog != null) {
      for (final surah in catalog.surahs) {
        if (surah.number == targetSurah) {
          surahName = surah.nameFor(locale);
          break;
        }
      }
    }

    setState(() => _changingSurah = true);
    try {
      final playback = await ref
          .read(audioRepositoryProvider)
          .playback(recitationId: recitationId, surah: targetSurah);
      if (!_isCurrentRequest(
        database: database,
        accountScope: accountScope,
        controller: controller,
        request: request,
      )) {
        return;
      }
      await controller.loadPlayback(
        playback: playback,
        reciter: reciter,
        surahName: surahName,
      );
    } on Object {
      if (!mounted) return;
      if (!_isCurrentRequest(
        database: database,
        accountScope: accountScope,
        controller: controller,
        request: request,
      )) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.noAudio)));
    } finally {
      if (mounted && request == _changeRequest) {
        setState(() => _changingSurah = false);
      }
    }
  }

  bool _isCurrentRequest({
    required LocalDatabase database,
    required AccountScopeSnapshot accountScope,
    required AudioController controller,
    required int request,
  }) {
    if (!mounted || request != _changeRequest) return false;
    if (!database.accountScope.isCurrent(accountScope)) return false;
    return identical(controller, ref.read(audioControllerProvider.notifier));
  }

  @override
  void dispose() {
    _changeRequest += 1;
    super.dispose();
  }
}

class _MiniPlayerPortrait extends StatelessWidget {
  const _MiniPlayerPortrait({required this.portraitUrl, required this.name});

  final String? portraitUrl;
  final String name;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: const Color(0xFF163C33),
      child: const Center(
        child: Icon(Icons.person_rounded, color: Color(0xFF9BDECB)),
      ),
    );
    return Semantics(
      image: true,
      label: name,
      child: Container(
        width: 48,
        height: 48,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF9BDECB), width: 1.5),
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
    );
  }
}

class _MiniPlayerControl extends StatelessWidget {
  const _MiniPlayerControl({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.emphasized = false,
    this.loading = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool emphasized;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      style: emphasized
          ? IconButton.styleFrom(
              backgroundColor: const Color(0xFF9BDECB),
              foregroundColor: const Color(0xFF08241D),
              disabledBackgroundColor: const Color(0x339BDECB),
            )
          : IconButton.styleFrom(
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white24,
            ),
      icon: loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: emphasized ? 25 : 23),
    );
  }
}
