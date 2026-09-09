import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'mushaf_raster.dart';
import 'mushaf_scan_layout.dart';

/// Exactly one rectangle and one uniform scale for the complete source page.
/// Printed frames, headers, footers and colour legends are source content too.
MushafScanLayout facsimilePageLayout({
  required Size source,
  required Size viewport,
  required bool fitWidth,
}) {
  final scale = fitWidth
      ? viewport.width / source.width
      : math.min(
          viewport.width / source.width,
          viewport.height / source.height,
        );
  final imageSize = source * scale;
  final canvasSize = Size(
    viewport.width,
    math.max(viewport.height, imageSize.height),
  );
  return MushafScanLayout(
    size: canvasSize,
    bands: [
      (
        source: const Rect.fromLTWH(0, 0, 1, 1),
        destination: Rect.fromLTWH(
          (canvasSize.width - imageSize.width) / 2,
          (canvasSize.height - imageSize.height) / 2,
          imageSize.width,
          imageSize.height,
        ),
      ),
    ],
  );
}

class MushafFacsimilePage extends StatefulWidget {
  const MushafFacsimilePage({
    required this.file,
    required this.fitWidth,
    required this.onTap,
    required this.onZoomChanged,
    this.error,
    super.key,
  });

  final File file;
  final bool fitWidth;
  final VoidCallback onTap;
  final ValueChanged<bool> onZoomChanged;
  final Widget? error;

  @override
  State<MushafFacsimilePage> createState() => _MushafFacsimilePageState();
}

class _MushafFacsimilePageState extends State<MushafFacsimilePage> {
  final _transform = TransformationController();
  Size? _viewport;
  var _zoomed = false;

  void _reset() {
    _transform.value = Matrix4.identity();
    if (_zoomed) {
      _zoomed = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onZoomChanged(false);
      });
    }
  }

  @override
  void didUpdateWidget(covariant MushafFacsimilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fitWidth != widget.fitWidth ||
        oldWidget.file.path != widget.file.path) {
      _reset();
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.white,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.biggest;
        if (_viewport != viewport) {
          _viewport = viewport;
          _reset();
        }
        // Keep the decoded source frame across rotation and fit-mode changes.
        return MushafRaster(
          file: widget.file,
          continuityKey: widget.file.path,
          fallback: widget.error,
          builder: (image) {
            final layout = facsimilePageLayout(
              source: Size(image.width.toDouble(), image.height.toDouble()),
              viewport: viewport,
              fitWidth: widget.fitWidth,
            );
            final scrollable = layout.size.height > viewport.height + .01;
            return ClipRect(
              child: InteractiveViewer(
                key: const ValueKey('facsimile-viewer'),
                transformationController: _transform,
                constrained: false,
                alignment: Alignment.topLeft,
                minScale: 1,
                maxScale: 3,
                panEnabled: scrollable || _zoomed,
                panAxis: _zoomed ? PanAxis.free : PanAxis.vertical,
                onInteractionEnd: (_) {
                  final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
                  if (zoomed == _zoomed) return;
                  setState(() => _zoomed = zoomed);
                  widget.onZoomChanged(zoomed);
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onTap,
                  onDoubleTap: () => setState(_reset),
                  child: RepaintBoundary(
                    child: CustomPaint(
                      key: const ValueKey('facsimile-raster'),
                      size: layout.size,
                      painter: MushafScanPainter(image: image, layout: layout),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ),
  );
}
