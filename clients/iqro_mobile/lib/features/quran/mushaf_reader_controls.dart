import 'package:flutter/material.dart';

import '../../core/design_system/iqro_widgets.dart';
import 'mushaf_paper.dart';

/// Lightweight floating controls; no continuously recomputed backdrop blur.
class MushafControlSurface extends StatelessWidget {
  const MushafControlSurface({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xF2F9F9F8),
      borderRadius: BorderRadius.circular(40),
      border: Border.all(color: Colors.white, width: 1.4),
      boxShadow: const <BoxShadow>[
        BoxShadow(
          color: Color(0x14000000),
          blurRadius: 12,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: IconTheme(
      data: const IconThemeData(color: mushafAccentColor),
      child: child,
    ),
  );
}

class MushafCircleButton extends StatelessWidget {
  const MushafCircleButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => MushafControlSurface(
    child: SizedBox.square(
      dimension: 48,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
        color: mushafAccentColor,
      ),
    ),
  );
}

class MushafPageScrubber extends StatefulWidget {
  const MushafPageScrubber({
    required this.page,
    required this.juz,
    required this.onJump,
    required this.onCatalog,
    this.pagesCount = 604,
    super.key,
  });
  final int page;
  final int? juz;
  final ValueChanged<int> onJump;
  final VoidCallback onCatalog;
  final int pagesCount;

  @override
  State<MushafPageScrubber> createState() => _MushafPageScrubberState();
}

class _MushafPageScrubberState extends State<MushafPageScrubber> {
  int? _dragWindowStart;
  int? _lastRequestedPage;
  int get _slots => widget.pagesCount.clamp(1, 7);

  int get _windowStart =>
      _dragWindowStart ??
      (widget.page - 3).clamp(1, widget.pagesCount - _slots + 1);

  void _selectAt(double x, double width) {
    if (width <= 0) return;
    final slot = (x / width * _slots).floor().clamp(0, _slots - 1);
    // The Mushaf always progresses right-to-left, independent of UI language.
    final page = _windowStart + _slots - 1 - slot;
    if (page == (_lastRequestedPage ?? widget.page)) return;
    _lastRequestedPage = page;
    widget.onJump(page);
  }

  void _finishDrag() => setState(() {
    _dragWindowStart = null;
    _lastRequestedPage = null;
  });

  @override
  Widget build(BuildContext context) => MushafControlSurface(
    child: Row(
      children: <Widget>[
        IconButton(
          onPressed: widget.onCatalog,
          tooltip: context.l10n.quickJump,
          icon: const Icon(Icons.format_list_bulleted_rounded),
          color: mushafAccentColor,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsetsDirectional.only(
              top: 6,
              end: 12,
              bottom: 2,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '${context.l10n.page} ${widget.page}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: mushafInkColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Text(
                      '${context.l10n.juz} ${widget.juz ?? '—'}',
                      style: const TextStyle(
                        color: mushafInkColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                LayoutBuilder(
                  builder: (context, constraints) => GestureDetector(
                    key: const ValueKey('mushaf-page-dots'),
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (details) {
                      _lastRequestedPage = null;
                      _selectAt(details.localPosition.dx, constraints.maxWidth);
                      _lastRequestedPage = null;
                    },
                    onHorizontalDragStart: (_) => setState(() {
                      _dragWindowStart = _windowStart;
                      _lastRequestedPage = widget.page;
                    }),
                    onHorizontalDragUpdate: (details) => _selectAt(
                      details.localPosition.dx,
                      constraints.maxWidth,
                    ),
                    onHorizontalDragEnd: (_) => _finishDrag(),
                    onHorizontalDragCancel: _finishDrag,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8E6E3),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Row(
                        textDirection: TextDirection.rtl,
                        children: [
                          for (
                            var page = _windowStart;
                            page < _windowStart + _slots;
                            page++
                          )
                            Expanded(
                              child: Semantics(
                                button: true,
                                selected: page == widget.page,
                                label: '${context.l10n.page} $page',
                                onTap: () {
                                  if (page != widget.page) widget.onJump(page);
                                },
                                child: SizedBox(
                                  key: ValueKey('mushaf-page-dot-$page'),
                                  height: 28,
                                  child: Center(
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 120,
                                      ),
                                      width: 5,
                                      height: page == widget.page ? 12 : 10,
                                      decoration: BoxDecoration(
                                        color: page == widget.page
                                            ? mushafAccentColor
                                            : const Color(
                                                0xFFAAA8A3,
                                              ).withValues(
                                                alpha:
                                                    (1 -
                                                            (page - widget.page)
                                                                    .abs() *
                                                                .12)
                                                        .clamp(.3, 1),
                                              ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
