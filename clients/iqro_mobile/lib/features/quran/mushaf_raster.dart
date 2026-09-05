import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/design_system/iqro_widgets.dart';
import 'mushaf_paper.dart';
import 'mushaf_scan_layout.dart';
import 'mushaf_scan_whitespace.dart';

/// Uses Flutter's shared FileImage cache: excerpts reuse the decoded page.
class MushafRaster extends StatefulWidget {
  const MushafRaster({
    required this.file,
    required this.builder,
    this.fallback,
    this.cutCandidates = const [],
    this.onVerifiedCuts,
    this.cropRegions = const [],
    this.onVerifiedCrops,
    super.key,
  });
  final File file;
  final Widget Function(ui.Image image) builder;
  final Widget? fallback;
  final List<double> cutCandidates;
  final ValueChanged<List<double>>? onVerifiedCuts;
  final List<Rect> cropRegions;
  final ValueChanged<List<Rect>>? onVerifiedCrops;

  @override
  State<MushafRaster> createState() => _MushafRasterState();
}

class _MushafRasterState extends State<MushafRaster> {
  static final _whitespaceCache = <String, Future<List<double>>>{};
  static final _cropCache = <String, Future<List<Rect>>>{};
  ImageStream? _stream;
  ImageInfo? _image;
  Object? _error;
  var _analysisPending = false;
  late final _listener = ImageStreamListener(_loaded, onError: _failed);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant MushafRaster oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) _resolve();
  }

  void _resolve() {
    final stream = FileImage(
      widget.file,
    ).resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _image?.dispose();
    _image = null;
    _error = null;
    _analysisPending = false;
    _stream = stream..addListener(_listener);
  }

  void _loaded(ImageInfo image, bool synchronousCall) {
    if (!mounted) {
      image.dispose();
      return;
    }
    setState(() {
      _image?.dispose();
      _image = image;
      _error = null;
      _analysisPending =
          widget.onVerifiedCrops != null ||
          (widget.onVerifiedCuts != null && widget.cutCandidates.isNotEmpty);
    });
    if (widget.onVerifiedCuts != null && widget.cutCandidates.isNotEmpty) {
      unawaited(_verifyCuts(image.image));
    } else if (widget.onVerifiedCrops != null) {
      unawaited(_verifyCrops(image.image));
    }
  }

  Future<void> _verifyCuts(ui.Image image) async {
    final path = widget.file.path;
    final candidates = widget.cutCandidates;
    final key = '$path:${image.width}:${image.height}:${candidates.join(',')}';
    var result = _whitespaceCache[key];
    if (result == null) {
      // Keep only tiny analysis results/futures, never decoded image buffers.
      if (_whitespaceCache.length >= 6) {
        _whitespaceCache.remove(_whitespaceCache.keys.first);
      }
      final retained = image.clone();
      result = () async {
        try {
          final bytes = await retained.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          if (bytes == null) return const <double>[];
          return await compute(verifyMushafWhitespace, (
            pixels: TransferableTypedData.fromList([
              bytes.buffer.asUint8List(),
            ]),
            width: retained.width,
            height: retained.height,
            candidates: candidates,
          ));
        } on Object {
          // A failed analysis must never lead to guessed/corrupt scan cuts.
          return const <double>[];
        } finally {
          retained.dispose();
        }
      }();
      _whitespaceCache[key] = result;
    }
    final cuts = await result;
    if (mounted &&
        widget.file.path == path &&
        identical(_image?.image, image)) {
      widget.onVerifiedCuts?.call(cuts);
      setState(() => _analysisPending = false);
    }
  }

  Future<void> _verifyCrops(ui.Image image) async {
    final path = widget.file.path;
    final regions = widget.cropRegions;
    final key = '$path:${image.width}:${image.height}:${regions.join(',')}';
    var result = _cropCache[key];
    if (result == null) {
      if (_cropCache.length >= 6) _cropCache.remove(_cropCache.keys.first);
      final retained = image.clone();
      result = () async {
        try {
          final bytes = await retained.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          if (bytes == null) return const <Rect>[];
          return await compute(verifyMushafCrops, (
            pixels: TransferableTypedData.fromList([
              bytes.buffer.asUint8List(),
            ]),
            width: retained.width,
            height: retained.height,
            regions: regions,
          ));
        } on Object {
          return const <Rect>[];
        } finally {
          retained.dispose();
        }
      }();
      _cropCache[key] = result;
    }
    final crops = await result;
    if (mounted &&
        widget.file.path == path &&
        identical(_image?.image, image)) {
      widget.onVerifiedCrops?.call(crops);
      setState(() => _analysisPending = false);
    }
  }

  void _failed(Object error, StackTrace? stack) {
    if (mounted) setState(() => _error = error);
  }

  @override
  Widget build(BuildContext context) => _analysisPending
      ? const IqroLoading()
      : _image != null
      ? widget.builder(_image!.image)
      : _error != null
      ? widget.fallback ?? Center(child: Text(context.l10n.noQuranData))
      : const IqroLoading();

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _image?.dispose();
    super.dispose();
  }
}

class MushafScanPainter extends CustomPainter {
  const MushafScanPainter({
    required this.image,
    required this.layout,
    this.clip,
  });
  final ui.Image image;
  final MushafScanLayout layout;
  final Path? clip;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    if (clip != null) canvas.clipPath(clip!);
    final ink = Paint()
      ..filterQuality = FilterQuality.high
      ..colorFilter = const ColorFilter.mode(
        mushafPaperColor,
        BlendMode.multiply,
      );
    for (final band in layout.bands) {
      final source = Rect.fromLTRB(
        band.source.left * image.width,
        band.source.top * image.height,
        band.source.right * image.width,
        band.source.bottom * image.height,
      );
      canvas.drawImageRect(image, source, band.destination, ink);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant MushafScanPainter oldDelegate) =>
      image != oldDelegate.image ||
      layout != oldDelegate.layout ||
      clip != oldDelegate.clip;
}
