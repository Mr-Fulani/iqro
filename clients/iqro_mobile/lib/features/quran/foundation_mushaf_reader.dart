import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import 'quran_models.dart';

class FoundationMushafReaderController {
  Future<void> Function(double value)? _setZoom;

  Future<void> setZoom(double value) async {
    await _setZoom?.call(value);
  }
}

class FoundationMushafReader extends ConsumerStatefulWidget {
  const FoundationMushafReader({
    required this.variant,
    required this.page,
    required this.dark,
    required this.controller,
    required this.onToggleControls,
    required this.onNextPage,
    required this.onPreviousPage,
    required this.onPageLoaded,
    super.key,
  });

  final MushafVariant variant;
  final int page;
  final bool dark;
  final FoundationMushafReaderController controller;
  final VoidCallback onToggleControls;
  final VoidCallback onNextPage;
  final VoidCallback onPreviousPage;
  final ValueChanged<FoundationMushafPage> onPageLoaded;

  @override
  ConsumerState<FoundationMushafReader> createState() =>
      _FoundationMushafReaderState();
}

class _FoundationMushafReaderState
    extends ConsumerState<FoundationMushafReader> {
  late final WebViewController _webViewController;
  var _shellReady = false;
  var _loadGeneration = 0;
  Object? _error;
  var _direction = 'next';

  @override
  void initState() {
    super.initState();
    _webViewController = WebViewController();
    widget.controller._setZoom = _setZoom;
    unawaited(_initialize());
  }

  @override
  void didUpdateWidget(covariant FoundationMushafReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.controller._setZoom = _setZoom;
    if (oldWidget.page != widget.page ||
        oldWidget.variant.sourceId != widget.variant.sourceId ||
        oldWidget.dark != widget.dark) {
      _direction = widget.page < oldWidget.page ? 'previous' : 'next';
      if (_shellReady) unawaited(_render());
    }
  }

  @override
  void dispose() {
    widget.controller._setZoom = null;
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      await _webViewController.setJavaScriptMode(JavaScriptMode.unrestricted);
      await _webViewController.setBackgroundColor(const Color(0xFFEDE6D3));
      await _webViewController.enableZoom(true);
      await _webViewController.addJavaScriptChannel(
        'IqroReader',
        onMessageReceived: _handleMessage,
      );
      await _webViewController.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri != null &&
                const <String>{'file', 'data', 'about'}.contains(uri.scheme)) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
          onPageFinished: (_) {
            if (!_shellReady) {
              _shellReady = true;
              unawaited(_render());
            }
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted) {
              setState(() => _error = error.description);
            }
          },
        ),
      );
      await _webViewController.loadFlutterAsset('assets/mushaf_reader.html');
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _handleMessage(JavaScriptMessage message) {
    final value = _messageMap(message.message);
    switch (value['type']) {
      case 'shellReady':
        if (!_shellReady) {
          _shellReady = true;
          unawaited(_render());
        }
        break;
      case 'toggleControls':
        widget.onToggleControls();
        break;
      case 'next':
        widget.onNextPage();
        break;
      case 'previous':
        widget.onPreviousPage();
        break;
      case 'error':
        if (mounted) setState(() => _error = value['message'] ?? 'font');
        break;
    }
  }

  Map<String, Object?> _messageMap(String message) {
    try {
      final decoded = jsonDecode(message);
      return decoded is Map ? Map<String, Object?>.from(decoded) : const {};
    } on FormatException {
      return const <String, Object?>{};
    }
  }

  Future<void> _render() async {
    final generation = ++_loadGeneration;
    if (mounted) setState(() => _error = null);
    try {
      final repository = ref.read(quranRepositoryProvider);
      final results = await Future.wait<Object>(<Future<Object>>[
        repository.foundationMushafPage(widget.variant.sourceId, widget.page),
        repository.mushafFontDataUri(widget.variant, widget.page),
        repository.surahs(),
      ]);
      if (!mounted || generation != _loadGeneration) return;
      final pageData = results[0] as FoundationMushafPage;
      final fontDataUri = results[1] as String;
      final catalog = results[2] as QuranCatalog;
      final payload = <String, Object?>{
        'variant': <String, Object?>{
          'source_id': widget.variant.sourceId,
          'name': widget.variant.name,
          'qirat_name': widget.variant.qiratName,
          'lines_per_page': widget.variant.linesPerPage,
          'rendering_mode': widget.variant.renderingMode,
        },
        'page': pageData.value,
        'font_data_uri': fontDataUri,
        'surahs': catalog.surahs
            .map(
              (surah) => <String, Object?>{
                'number': surah.number,
                'name_ar': surah.nameAr,
              },
            )
            .toList(growable: false),
        'dark': widget.dark,
        'labels': <String, Object?>{
          'page': context.l10n.page,
          'loading': context.l10n.mushafLoading,
          'fontError': context.l10n.mushafFontError,
        },
      };
      final payloadJson = jsonEncode(payload);
      await _webViewController.runJavaScript(
        'window.iqroReader.renderPage('
        '${jsonEncode(payloadJson)}, ${jsonEncode(_direction)});',
      );
      widget.onPageLoaded(pageData);
      unawaited(
        repository.prefetchFoundationMushaf(widget.variant, widget.page),
      );
    } on Object catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _error = error);
      }
    }
  }

  Future<void> _setZoom(double value) {
    return _webViewController.runJavaScript(
      'window.iqroReader.setZoom(${value.clamp(1, 3)});',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        WebViewWidget(
          controller: _webViewController,
          layoutDirection: TextDirection.ltr,
        ),
        if (_error != null)
          ColoredBox(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF101713)
                : const Color(0xFFEDE6D3),
            child: IqroAsyncError(
              title: context.l10n.noQuranData,
              message: context.l10n.mushafOfflineMissing,
              onRetry: _render,
            ),
          ),
      ],
    );
  }
}
