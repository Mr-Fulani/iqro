import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_view/photo_view.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/storage/preferences_store.dart';
import 'quran_models.dart';

class MushafScreen extends ConsumerStatefulWidget {
  const MushafScreen({
    required this.initialPage,
    required this.surah,
    required this.ayah,
    super.key,
  });

  final int initialPage;
  final int surah;
  final int ayah;

  @override
  ConsumerState<MushafScreen> createState() => _MushafScreenState();
}

class _MushafScreenState extends ConsumerState<MushafScreen> {
  late final PageController _pageController;
  final _zoomControllers = <int, PhotoViewController>{};
  var _currentPage = 1;
  var _controlsVisible = false;
  var _zoom = 1.0;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage.clamp(1, 604);
    _pageController = PageController(initialPage: _currentPage - 1);
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final controller in _zoomControllers.values) {
      controller.dispose();
    }
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  Future<void> _setControls(bool visible) async {
    setState(() => _controlsVisible = visible);
    await SystemChrome.setEnabledSystemUIMode(
      visible ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mushafVariant = ref.watch(
      appPreferencesProvider.select((value) => value.mushafVariant),
    );
    final foreground = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFF3EEDC)
        : const Color(0xFF26261F);
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          unawaited(
            SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge),
          );
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFEDE6D3),
        body: Stack(
          children: <Widget>[
            PageView.builder(
              controller: _pageController,
              reverse: true,
              itemCount: 604,
              onPageChanged: (index) {
                final page = index + 1;
                setState(() {
                  _currentPage = page;
                  _controlsVisible = false;
                  _zoom = 1;
                });
                unawaited(
                  SystemChrome.setEnabledSystemUIMode(
                    SystemUiMode.immersiveSticky,
                  ),
                );
                unawaited(_savePagePosition(page));
                if (page < 604) {
                  if (mushafVariant == '5') {
                    ref
                        .read(
                          foundationMushafPageProvider((
                            sourceId: 5,
                            page: page + 1,
                          )).future,
                        )
                        .ignore();
                  } else {
                    ref.read(mushafPageProvider(page + 1).future).ignore();
                  }
                }
              },
              itemBuilder: (context, index) {
                final page = index + 1;
                return _MushafPage(
                  page: page,
                  variant: mushafVariant,
                  controller: _zoomControllers.putIfAbsent(
                    page,
                    PhotoViewController.new,
                  ),
                  onTap: () => _setControls(!_controlsVisible),
                  onScale: (value) {
                    if (page == _currentPage && mounted) {
                      setState(() => _zoom = value);
                    }
                  },
                );
              },
            ),
            IgnorePointer(
              ignoring: !_controlsVisible,
              child: AnimatedSlide(
                offset: _controlsVisible ? Offset.zero : const Offset(0, -1),
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: _controlsVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[Color(0xDD071A16), Color(0x00071A16)],
                      ),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: SizedBox(
                        height: 92,
                        child: Row(
                          children: <Widget>[
                            const SizedBox(width: 6),
                            IconButton(
                              tooltip: context.l10n.back,
                              onPressed: () => context.pop(),
                              color: Colors.white,
                              icon: const Icon(Icons.arrow_back),
                            ),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  Text(
                                    '${context.l10n.page} $_currentPage',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(color: Colors.white),
                                  ),
                                  Text(
                                    '${context.l10n.juz} ${((_currentPage - 1) ~/ 20) + 1}',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: .7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: context.l10n.textMode,
                              onPressed: () async {
                                await ref
                                    .read(appPreferencesProvider.notifier)
                                    .setReaderMode(ReaderMode.text);
                                if (!context.mounted) return;
                                context.pushReplacement(
                                  '/reader/${widget.surah}?ayah=${widget.ayah}',
                                );
                              },
                              color: Colors.white,
                              icon: const Icon(Icons.format_list_bulleted),
                            ),
                            const SizedBox(width: 6),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            IgnorePointer(
              ignoring: !_controlsVisible,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: AnimatedSlide(
                  offset: _controlsVisible ? Offset.zero : const Offset(0, 1),
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    opacity: _controlsVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Container(
                      color: const Color(0xED071A16),
                      padding: EdgeInsetsDirectional.fromSTEB(
                        14,
                        12,
                        14,
                        12 + MediaQuery.paddingOf(context).bottom,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Icon(
                                Icons.zoom_out,
                                color: Colors.white.withValues(alpha: .8),
                              ),
                              Expanded(
                                child: Slider(
                                  value: _zoom.clamp(1, 3),
                                  min: 1,
                                  max: 3,
                                  onChanged: (value) {
                                    _zoomControllers[_currentPage]?.scale =
                                        value;
                                    setState(() => _zoom = value);
                                  },
                                ),
                              ),
                              Icon(
                                Icons.zoom_in,
                                color: Colors.white.withValues(alpha: .8),
                              ),
                              SizedBox(
                                width: 42,
                                child: Text(
                                  '${(_zoom * 100).round()}%',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              IconButton.filledTonal(
                                tooltip:
                                    '${context.l10n.page} ${_currentPage - 1}',
                                onPressed: _currentPage <= 1
                                    ? null
                                    : () => _pageController.previousPage(
                                        duration: const Duration(
                                          milliseconds: 420,
                                        ),
                                        curve: Curves.easeInOutCubic,
                                      ),
                                icon: const Icon(Icons.chevron_left),
                              ),
                              Column(
                                children: <Widget>[
                                  Text(
                                    '$_currentPage / 604',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(color: Colors.white),
                                  ),
                                  Text(
                                    context.l10n.listenPage,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: .65,
                                      ),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              IconButton.filledTonal(
                                tooltip:
                                    '${context.l10n.page} ${_currentPage + 1}',
                                onPressed: _currentPage >= 604
                                    ? null
                                    : () => _pageController.nextPage(
                                        duration: const Duration(
                                          milliseconds: 420,
                                        ),
                                        curve: Curves.easeInOutCubic,
                                      ),
                                icon: const Icon(Icons.chevron_right),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (!_controlsVisible)
              PositionedDirectional(
                start: 0,
                end: 0,
                bottom: 58 + MediaQuery.paddingOf(context).bottom,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: .65,
                    duration: const Duration(milliseconds: 300),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(Icons.more_horiz, color: foreground),
                        const SizedBox(width: 6),
                        Text(
                          context.l10n.tapForControls,
                          style: TextStyle(color: foreground, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _savePagePosition(int page) async {
    final repository = ref.read(quranRepositoryProvider);
    final current = await repository.position();
    try {
      final pageData = await ref.read(mushafPageProvider(page).future);
      final reference = pageData.firstAyahReference;
      await repository.savePosition(
        surah: reference?.surah ?? current.surah,
        ayah: reference?.ayah ?? current.ayah,
        page: page,
      );
    } on Object {
      await repository.savePosition(
        surah: current.surah,
        ayah: current.ayah,
        page: page,
      );
    }
    ref.invalidate(readingPositionProvider);
  }
}

class _MushafPage extends ConsumerWidget {
  const _MushafPage({
    required this.page,
    required this.variant,
    required this.controller,
    required this.onTap,
    required this.onScale,
  });

  final int page;
  final String variant;
  final PhotoViewController controller;
  final VoidCallback onTap;
  final ValueChanged<double> onScale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourceId = int.tryParse(variant);
    if (sourceId == 5) {
      return _FoundationMushafPage(
        page: page,
        sourceId: 5,
        controller: controller,
        onTap: onTap,
        onScale: onScale,
      );
    }
    final data = ref.watch(mushafPageProvider(page));
    return data.when(
      loading: () =>
          const ColoredBox(color: Color(0xFFEDE6D3), child: IqroLoading()),
      error: (error, stack) => ColoredBox(
        color: const Color(0xFFEDE6D3),
        child: IqroAsyncError(
          title: context.l10n.noQuranData,
          message: context.l10n.networkError,
          onRetry: () => ref.invalidate(mushafPageProvider(page)),
        ),
      ),
      data: (pageData) {
        final width = MediaQuery.sizeOf(context).width;
        final asset = pageData.bestAssetFor(
          width,
          MediaQuery.devicePixelRatioOf(context),
        );
        if (asset == null) {
          return ColoredBox(
            color: const Color(0xFFEDE6D3),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  context.l10n.noQuranData,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        return PhotoView(
          imageProvider: CachedNetworkImageProvider(asset.url),
          controller: controller,
          backgroundDecoration: const BoxDecoration(color: Color(0xFFEDE6D3)),
          minScale: PhotoViewComputedScale.contained,
          initialScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.contained * 3,
          basePosition: Alignment.center,
          filterQuality: FilterQuality.high,
          semanticLabel:
              '${context.l10n.mushafMode}, ${context.l10n.page} $page',
          onTapUp: (context, details, controllerValue) => onTap(),
          onScaleEnd: (context, details, controllerValue) =>
              onScale(controllerValue.scale ?? 1),
          loadingBuilder: (context, event) => const IqroLoading(),
          errorBuilder: (context, error, stackTrace) => IqroAsyncError(
            title: context.l10n.noQuranData,
            onRetry: () => ref.invalidate(mushafPageProvider(page)),
          ),
        );
      },
    );
  }
}

class _FoundationMushafPage extends ConsumerWidget {
  const _FoundationMushafPage({
    required this.page,
    required this.sourceId,
    required this.controller,
    required this.onTap,
    required this.onScale,
  });

  final int page;
  final int sourceId;
  final PhotoViewController controller;
  final VoidCallback onTap;
  final ValueChanged<double> onScale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(
      foundationMushafPageProvider((sourceId: sourceId, page: page)),
    );
    return data.when(
      loading: () =>
          const ColoredBox(color: Color(0xFFEDE6D3), child: IqroLoading()),
      error: (error, stack) => ColoredBox(
        color: const Color(0xFFEDE6D3),
        child: IqroAsyncError(
          title: context.l10n.noQuranData,
          message: context.l10n.networkError,
          onRetry: () => ref.invalidate(
            foundationMushafPageProvider((sourceId: sourceId, page: page)),
          ),
        ),
      ),
      data: (pageData) {
        if (pageData.lines.isEmpty) {
          return ColoredBox(
            color: const Color(0xFFEDE6D3),
            child: Center(child: Text(context.l10n.noQuranData)),
          );
        }
        return PhotoView.customChild(
          controller: controller,
          backgroundDecoration: const BoxDecoration(color: Color(0xFFEDE6D3)),
          minScale: PhotoViewComputedScale.contained,
          initialScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.contained * 3,
          basePosition: Alignment.center,
          onTapUp: (context, details, controllerValue) => onTap(),
          onScaleEnd: (context, details, controllerValue) =>
              onScale(controllerValue.scale ?? 1),
          child: _MushafTextSheet(data: pageData),
        );
      },
    );
  }
}

class _MushafTextSheet extends StatelessWidget {
  const _MushafTextSheet({required this.data});

  final FoundationMushafPageData data;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFEDE6D3),
      child: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFFFFCF2),
            border: Border.all(color: const Color(0xFFC8B88D)),
            borderRadius: BorderRadius.circular(3),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 14,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 22, 12, 16),
            child: Column(
              children: <Widget>[
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: data.lines
                        .map((words) {
                          final line = words.map((word) => word.text).join(' ');
                          return SizedBox(
                            width: double.infinity,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                line,
                                textAlign: TextAlign.center,
                                textDirection: TextDirection.rtl,
                                style: const TextStyle(
                                  color: Color(0xFF17140D),
                                  fontFamily: 'serif',
                                  fontSize: 30,
                                  height: 1.65,
                                ),
                              ),
                            ),
                          );
                        })
                        .toList(growable: false),
                  ),
                ),
                Text(
                  '${data.pageNumber}',
                  style: const TextStyle(
                    color: Color(0xFF766942),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
