import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/platform/reader_haptics.dart';
import 'mushaf_facsimile_page.dart';
import 'mushaf_reader_controls.dart';
import 'tajweed_book_preview_source.dart';

class TajweedBookPreviewRoute extends ConsumerWidget {
  const TajweedBookPreviewRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!canShowTajweedBookPreview(ref.watch(appConfigProvider))) {
      return Scaffold(appBar: AppBar(), body: const SizedBox.shrink());
    }
    return TajweedBookPreviewScreen(
      haptics: ref.watch(appPreferencesProvider).readerHaptics,
    );
  }
}

/// Visual sample only: no invented hit map, verse selection, listening or
/// reading-position persistence for a different, unpublished source edition.
class TajweedBookPreviewScreen extends StatefulWidget {
  const TajweedBookPreviewScreen({
    this.loadSample,
    this.haptics = true,
    super.key,
  });

  final Future<File> Function(TajweedBookSample)? loadSample;
  final bool haptics;

  @override
  State<TajweedBookPreviewScreen> createState() =>
      _TajweedBookPreviewScreenState();
}

class _TajweedBookPreviewScreenState extends State<TajweedBookPreviewScreen> {
  final _pages = PageController(initialPage: 1);
  final _source = TajweedBookPreviewSource();
  final _files = <int, Future<File>>{};
  var _index = 1;
  var _controls = true;
  var _fitWidth = true;
  var _zoomed = false;

  @override
  void dispose() {
    _pages.dispose();
    _source.dispose();
    super.dispose();
  }

  Future<File> _load(TajweedBookSample sample) => _files.putIfAbsent(
    sample.page,
    () => (widget.loadSample ?? _source.load)(sample),
  );

  void _info() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.mushafBookPreview),
        content: SingleChildScrollView(
          child: Text(context.l10n.mushafBookPreviewInfo),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.close),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      child: Stack(
        children: [
          PageView.builder(
            controller: _pages,
            // Physical page progression stays RTL in every UI language.
            reverse: Directionality.of(context) == TextDirection.ltr,
            itemCount: TajweedBookSample.samples.length,
            physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
            onPageChanged: (index) {
              setState(() {
                _index = index;
                _zoomed = false;
              });
              unawaited(ReaderHaptics.pageChanged(enabled: widget.haptics));
            },
            itemBuilder: (context, index) {
              final sample = TajweedBookSample.samples[index];
              return FutureBuilder<File>(
                future: _load(sample),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            context.l10n.networkError,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.black87),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.brown.shade800,
                            ),
                            onPressed: () => setState(() {
                              _files.remove(sample.page);
                            }),
                            child: Text(context.l10n.retry),
                          ),
                        ],
                      ),
                    );
                  }
                  final file = snapshot.data;
                  if (file == null) return const Center(child: IqroLoading());
                  return MushafFacsimilePage(
                    key: ValueKey(sample.checksum),
                    file: file,
                    fitWidth: _fitWidth,
                    onTap: () => setState(() => _controls = !_controls),
                    onZoomChanged: (zoomed) {
                      if (index == _index && mounted) {
                        setState(() => _zoomed = zoomed);
                      }
                    },
                  );
                },
              );
            },
          ),
          if (_controls) ...[
            PositionedDirectional(
              top: 8,
              start: 8,
              child: MushafCircleButton(
                icon: Icons.arrow_back_rounded,
                tooltip: context.l10n.close,
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  } else {
                    GoRouter.maybeOf(context)?.go('/app?tab=1');
                  }
                },
              ),
            ),
            PositionedDirectional(
              top: 8,
              end: 8,
              child: MushafCircleButton(
                icon: Icons.info_outline_rounded,
                tooltip: context.l10n.mushafBookPreview,
                onPressed: _info,
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 8,
              child: MushafControlSurface(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.l10n.mushafBookPreview,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 12,
                        ),
                      ),
                      Row(
                        children: [
                          for (final sample in TajweedBookSample.samples)
                            SizedBox(
                              width: 44,
                              child: TextButton(
                                key: ValueKey(
                                  'book-preview-page-${sample.page}',
                                ),
                                onPressed: () => _pages.animateToPage(
                                  TajweedBookSample.samples.indexOf(sample),
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeOut,
                                ),
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  foregroundColor: Colors.brown.shade800,
                                  backgroundColor:
                                      sample.page ==
                                          TajweedBookSample.samples[_index].page
                                      ? const Color(0xFFE7DECF)
                                      : Colors.transparent,
                                ),
                                child: Text('${sample.page}'),
                              ),
                            ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextButton(
                              key: const ValueKey('book-preview-fit'),
                              onPressed: () => setState(() {
                                _fitWidth = !_fitWidth;
                                _zoomed = false;
                              }),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.brown.shade800,
                              ),
                              child: Text(
                                _fitWidth
                                    ? context.l10n.mushafFitWidth
                                    : context.l10n.mushafFitPage,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
