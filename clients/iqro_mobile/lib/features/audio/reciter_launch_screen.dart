import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import 'reciter_catalog.dart';
import 'reciter_portraits.dart';

/// `/audio/reciter/<id>?play=1`, the «Listen» button of an announcement:
/// opens this reciter straight in the player, on the listening surah.
class ReciterLaunchScreen extends ConsumerStatefulWidget {
  const ReciterLaunchScreen({
    required this.reciterId,
    this.autoplay = true,
    super.key,
  });

  final String reciterId;
  final bool autoplay;

  @override
  ConsumerState<ReciterLaunchScreen> createState() =>
      _ReciterLaunchScreenState();
}

class _ReciterLaunchScreenState extends ConsumerState<ReciterLaunchScreen> {
  var _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!mounted) return;
    setState(() => _failed = false);
    try {
      final reciters = await ref.read(recitersProvider.future);
      final recitations = await ref.read(audioRecitationsProvider.future);
      final person = groupRecitersByPerson(
        reciters,
      ).where((item) => item.containsReciter(widget.reciterId)).firstOrNull;
      if (person == null) throw StateError('Unknown reciter');
      final own = recitationsForPerson(person, recitations);
      final preferredId = ref
          .read(appPreferencesProvider)
          .listeningRecitationId;
      // The announced reciter's own recording first, then the same person's.
      final recitation =
          preferredRecitation(
            own
                .where((item) => item.reciter.id == widget.reciterId)
                .toList(growable: false),
            preferredId: preferredId,
          ) ??
          preferredRecitation(own, preferredId: preferredId);
      if (recitation == null) throw StateError('No listening recording');
      final controller = ref.read(audioControllerProvider.notifier);
      final listening = controller.listeningSurah ?? 1;
      final surah = recitation.coversSurah(listening)
          ? listening
          : recitation.coverage?.surahNumbers.firstOrNull ?? listening;
      final playback = await ref
          .read(audioRepositoryProvider)
          .playback(recitationId: recitation.id, surah: surah);
      if (!mounted) return;
      await controller.loadPlayback(
        playback: playback,
        reciter: reciterWithPersonPortrait(
          recitation.reciter,
          apiBaseUrl: ref.read(appConfigProvider).apiBaseUrl,
          reciters: person.sources,
        ),
        surahName: _surahName(surah),
        autoplay: widget.autoplay,
      );
      await ref
          .read(appPreferencesProvider.notifier)
          .setListeningRecitation(recitation.id);
      if (!mounted) return;
      context.pushReplacement('/player');
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  String _surahName(int surah) {
    final locale = Localizations.localeOf(context).languageCode;
    final item = ref
        .read(quranCatalogProvider)
        .valueOrNull
        ?.surahs
        .where((candidate) => candidate.number == surah)
        .firstOrNull;
    if (item != null) return item.nameFor(locale);
    return surah == 1 ? context.l10n.alFatiha : '${context.l10n.surah} $surah';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: IqroTopBar(title: context.l10n.navAudio),
      body: _failed
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                IqroAsyncError(title: context.l10n.noAudio, onRetry: _start),
                TextButton(
                  onPressed: () => context.go('/app?tab=3'),
                  child: Text(context.l10n.allReciters),
                ),
              ],
            )
          : const IqroLoading(),
    );
  }
}
