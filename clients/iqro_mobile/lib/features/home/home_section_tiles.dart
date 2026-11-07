import 'package:flutter/material.dart';

import '../../core/theme/iqro_theme.dart';
import 'home_section_icon.dart';

/// One section on Home: a thin-line icon from the shared set (the same as on
/// the site) and its name.
class HomeSectionTile {
  const HomeSectionTile({
    required this.id,
    required this.title,
    required this.onTap,
  });

  /// Stable for tests and the site: `home-section-<id>`; also the key of the
  /// icon in `home-section-icons.json`.
  final String id;
  final String title;
  final VoidCallback onTap;
}

/// The sections as calm tiles: a light surface with a fine border and one
/// emerald line. Three in a row on a phone, one row across a wide tablet, and
/// two wide rows of icon and name with large text.
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
      width: wide ? 44 : 56,
      height: wide ? 44 : 56,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(wide ? 13 : 16),
      ),
      child: Center(
        child: HomeSectionIcon(
          section: tile.id,
          color: theme.colorScheme.primary,
          size: wide ? 24 : 30,
        ),
      ),
    );
    final title = Text(
      tile.title,
      textAlign: wide ? TextAlign.start : TextAlign.center,
      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    );
    return Material(
      key: ValueKey('home-section-${tile.id}'),
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: context.iqroColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: tile.onTap,
        child: Padding(
          padding: wide
              ? const EdgeInsets.all(10)
              : const EdgeInsets.fromLTRB(6, 14, 6, 12),
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
                  children: [art, const SizedBox(height: 9), title],
                ),
        ),
      ),
    );
  }
}
