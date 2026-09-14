import 'package:flutter/material.dart';

import '../../core/design_system/iqro_widgets.dart';
import 'quran_models.dart';

class MushafBookmarksSheet extends StatefulWidget {
  const MushafBookmarksSheet({
    required this.load,
    required this.surahs,
    super.key,
  });

  final Future<List<QuranAyahReference>> Function() load;
  final List<Surah> surahs;

  @override
  State<MushafBookmarksSheet> createState() => _MushafBookmarksSheetState();
}

class _MushafBookmarksSheetState extends State<MushafBookmarksSheet> {
  late Future<List<QuranAyahReference>> _bookmarks = widget.load();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .65,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.bookmarks,
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
            Expanded(
              child: FutureBuilder<List<QuranAyahReference>>(
                future: _bookmarks,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              l10n.bookmarksLoadError,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            TextButton.icon(
                              onPressed: () => setState(() {
                                _bookmarks = widget.load();
                              }),
                              icon: const Icon(Icons.refresh_rounded),
                              label: Text(l10n.retry),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  final bookmarks = snapshot.data!;
                  if (bookmarks.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.bookmark_border_rounded,
                              size: 40,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              l10n.emptyBookmarks,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      12,
                      0,
                      12,
                      16,
                    ),
                    itemCount: bookmarks.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final bookmark = bookmarks[index];
                      final surah = widget.surahs
                          .where((s) => s.number == bookmark.surah)
                          .firstOrNull;
                      return ListTile(
                        key: ValueKey(
                          'bookmark-${bookmark.surah}-${bookmark.ayah}',
                        ),
                        leading: Icon(
                          Icons.bookmark_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(
                          surah?.nameFor(
                                Localizations.localeOf(context).languageCode,
                              ) ??
                              '${l10n.surah} ${bookmark.surah}',
                        ),
                        subtitle: Text(
                          '${l10n.ayah} ${bookmark.surah}:${bookmark.ayah}',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.pop(context, bookmark),
                      );
                    },
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
