import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../audio/audio_models.dart';
import '../audio/premium_reciter_portrait.dart';
import '../audio/recitation_style_label.dart';
import '../audio/reciter_catalog.dart';
import '../audio/reciter_portraits.dart';

/// The reciters the Mushaf plays ayah by ayah, by name, with a search. Opened
/// from the reciter's name in the Mushaf player; returns the chosen one.
Future<Recitation?> showMushafReciterSheet(
  BuildContext context, {
  required List<Recitation> recitations,
  String? selectedId,
}) => showModalBottomSheet<Recitation>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (context) =>
      MushafReciterSheet(recitations: recitations, selectedId: selectedId),
);

class MushafReciterSheet extends ConsumerStatefulWidget {
  const MushafReciterSheet({
    required this.recitations,
    this.selectedId,
    super.key,
  });

  final List<Recitation> recitations;
  final String? selectedId;

  @override
  ConsumerState<MushafReciterSheet> createState() => _MushafReciterSheetState();
}

class _MushafReciterSheetState extends ConsumerState<MushafReciterSheet> {
  var _query = '';
  List<Recitation>? _sorted;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).languageCode;
    final sorted = _sorted ??= recitationsByName(widget.recitations, locale);
    final found = findRecitations(sorted, _query);
    final apiBaseUrl = ref.read(appConfigProvider).apiBaseUrl;
    final reciters = widget.recitations
        .map((item) => item.reciter)
        .toList(growable: false);
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.mushafReciter,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.close,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                key: const ValueKey('mushaf-reciter-search'),
                decoration: InputDecoration(
                  hintText: l10n.searchReciters,
                  prefixIcon: const Icon(Icons.search_rounded),
                ),
                onChanged: (value) => setState(() => _query = value),
                textInputAction: TextInputAction.search,
              ),
            ),
            Expanded(
              child: found.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: IqroStatusBanner(
                        icon: Icons.search_off_rounded,
                        title: l10n.reciterNotFound,
                      ),
                    )
                  : ListView.builder(
                      itemCount: found.length,
                      itemBuilder: (context, index) {
                        final item = found[index];
                        final selected = item.id == widget.selectedId;
                        return ListTile(
                          key: ValueKey('mushaf-reciter-${item.id}'),
                          selected: selected,
                          leading: PremiumReciterPortrait(
                            url: resolveReciterPortraitUrl(
                              item.reciter,
                              apiBaseUrl: apiBaseUrl,
                              reciters: reciters,
                            ),
                            thumbnailUrl: resolveReciterThumbnailUrl(
                              item.reciter,
                              apiBaseUrl: apiBaseUrl,
                              reciters: reciters,
                            ),
                            size: 40,
                            selected: selected,
                          ),
                          title: Text(
                            item.reciter.nameFor(locale),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            recitationStyleLabel(context, item.style),
                          ),
                          trailing: selected
                              ? const Icon(Icons.check_rounded)
                              : null,
                          onTap: () => Navigator.pop(context, item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
