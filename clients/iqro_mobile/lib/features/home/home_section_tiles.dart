import 'package:flutter/material.dart';

import '../dua/dua_thematic_icon.dart';

/// One section on Home: an illustration from the shared topic art (the same
/// as on More and on the site) and its name.
class HomeSectionTile {
  const HomeSectionTile({
    required this.id,
    required this.art,
    required this.title,
    required this.color,
    required this.onTap,
  });

  /// Stable for tests and the site: `home-section-<id>`.
  final String id;
  final String art;
  final String title;
  final Color color;
  final VoidCallback onTap;
}

/// The sections as large tiles: three in a row on a phone, one row of nine
/// across a wide tablet, and two wide rows of art and name with large text.
class HomeSectionTiles extends StatelessWidget {
  const HomeSectionTiles({required this.tiles, super.key});

  final List<HomeSectionTile> tiles;

  static const _gap = 10.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final large = MediaQuery.textScalerOf(context).scale(16) > 22;
      final columns = large
          ? (constraints.maxWidth < 300 ? 1 : 2)
          : constraints.maxWidth >= 880
          ? tiles.length
          : 3;
      final rows = <Widget>[];
      for (var start = 0; start < tiles.length; start += columns) {
        final row = tiles.skip(start).take(columns).toList();
        rows.add(
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < columns; index++) ...[
                  if (index > 0) const SizedBox(width: _gap),
                  Expanded(
                    child: index < row.length
                        ? _Tile(tile: row[index], wide: large)
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < rows.length; index++) ...[
            if (index > 0) const SizedBox(height: _gap),
            rows[index],
          ],
        ],
      );
    },
  );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.tile, required this.wide});

  final HomeSectionTile tile;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final art = Container(
      width: wide ? 52 : 62,
      height: wide ? 52 : 62,
      padding: EdgeInsets.all(wide ? 6 : 8),
      decoration: BoxDecoration(
        // The light tile keeps the mint of the art apart from tinted cards.
        color: theme.colorScheme.surface.withValues(alpha: .8),
        borderRadius: BorderRadius.circular(wide ? 14 : 18),
      ),
      child: FittedBox(child: DuaThematicIcon(topic: tile.art)),
    );
    final title = Text(
      tile.title,
      textAlign: wide ? TextAlign.start : TextAlign.center,
      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    );
    return Material(
      key: ValueKey('home-section-${tile.id}'),
      color: tile.color,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: tile.onTap,
        child: Padding(
          padding: wide
              ? const EdgeInsets.all(10)
              : const EdgeInsets.fromLTRB(6, 12, 6, 12),
          child: wide
              ? Row(
                  children: [
                    art,
                    const SizedBox(width: 10),
                    Expanded(child: title),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [art, const SizedBox(height: 8), title],
                ),
        ),
      ),
    );
  }
}
