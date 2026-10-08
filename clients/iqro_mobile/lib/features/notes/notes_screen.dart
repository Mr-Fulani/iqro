import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../quran/ayah_annotations.dart';

class NotesScreen extends ConsumerWidget {
  const NotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountKey = ref.watch(activeAccountScopeKeyProvider);
    final annotations = accountKey == null
        ? null
        : ref.watch(ayahAnnotationsProvider(accountKey));
    return Scaffold(
      appBar: IqroTopBar(title: context.l10n.notes),
      body: IqroPage(
        scrollable: false,
        child: accountKey == null || annotations == null
            ? const IqroLoading()
            : annotations.when(
                loading: () => const IqroLoading(),
                error: (_, _) => IqroAsyncError(
                  title: context.l10n.networkError,
                  onRetry: () =>
                      ref.invalidate(ayahAnnotationsProvider(accountKey)),
                ),
                data: (rows) {
                  final notes = rows
                      .where(
                        (row) =>
                            (row['note']?.toString().trim() ?? '').isNotEmpty,
                      )
                      .toList(growable: false);
                  if (notes.isEmpty) {
                    return Center(
                      child: IqroStatusBanner(
                        icon: Icons.note_alt_outlined,
                        title: context.l10n.emptyNotes,
                        actionLabel: context.l10n.navQuran,
                        onAction: () => context.go('/app?tab=1'),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: notes.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final note = notes[index];
                      final surah = (note['surah'] as num?)?.toInt() ?? 0;
                      final ayah = (note['ayah'] as num?)?.toInt() ?? 0;
                      final color = ayahHighlightColor(
                        note['color_key']?.toString(),
                      );
                      return IqroCard(
                        onTap: () =>
                            context.push('/mushaf?surah=$surah&ayah=$ayah'),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Container(
                              width: 12,
                              height: 12,
                              margin: const EdgeInsets.only(top: 5),
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    '${context.l10n.surah} $surah · '
                                    '${context.l10n.ayah} $ayah',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    note['note']?.toString() ?? '',
                                    maxLines: 5,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
      ),
    );
  }
}
