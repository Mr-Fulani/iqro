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
    super.key,
  });
  final int page;
  final int? juz;
  final ValueChanged<int> onJump;
  final VoidCallback onCatalog;

  @override
  State<MushafPageScrubber> createState() => _MushafPageScrubberState();
}

class _MushafPageScrubberState extends State<MushafPageScrubber> {
  double? _preview;

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
                        '${context.l10n.page} ${_preview?.round() ?? widget.page}',
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
                SizedBox(
                  height: 24,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 5,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 10,
                      ),
                    ),
                    child: Slider(
                      value: _preview ?? widget.page.toDouble(),
                      min: 1,
                      max: 604,
                      divisions: 603,
                      activeColor: mushafAccentColor,
                      inactiveColor: const Color(0xFFDDD9D2),
                      semanticFormatterCallback: (value) =>
                          '${context.l10n.page} ${value.round()}',
                      onChanged: (value) => setState(() => _preview = value),
                      onChangeEnd: (value) {
                        setState(() => _preview = null);
                        widget.onJump(value.round());
                      },
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
