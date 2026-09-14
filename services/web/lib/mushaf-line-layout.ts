export type LineMetrics = { width: number; height: number; words: number; centered: boolean };

/** Keep glyph proportions and a common page scale; justify only word spaces. */
export function fitMushafLines(lines: LineMetrics[], width: number, height: number) {
  const naturalGap = 3.5;
  const scale = Math.min(1, ...lines.map((line) => Math.min(
    width / Math.max(1, line.width + naturalGap * Math.max(0, line.words - 1)),
    height / Math.max(1, line.height),
  )));
  return {
    scale,
    gaps: lines.map((line) => line.centered || line.words < 2 ? naturalGap
      : Math.max(naturalGap, (width / scale - line.width) / (line.words - 1))),
  };
}

/** Half-row grid permits exact centering of odd and even opening blocks. */
export function qulGridRow(line: number, page: number, lineCount: number, occupiedRows: number) {
  return 2 * line - 1 + (page <= 2 ? lineCount - occupiedRows : 0);
}
