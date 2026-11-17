// Fits an ayah or a du'a into the share card, or splits it into a series of
// cards: nothing is ever cut. The app runs the same steps
// (core/share/share_card_compose.dart); both pass docs/share-card/fixtures.json.
// Word widths are in em, so one measurement serves every font size.

export type ShareCardFormat = "story" | "post";

export type ShareCardLayout = {
  formats: Record<ShareCardFormat, {
    width: number;
    height: number;
    field: { left: number; top: number; right: number; bottom: number };
  }>;
  colours: string[];
  inset: number;
  ink: string;
  shadow: { color: string; opacity: number; dx: number; dy: number; blur: number };
  arabic: { max: number; min: number; seriesMax: number; lineHeight: number };
  translation: { max: number; min: number; seriesMax: number; lineHeight: number };
  reference: { size: number; minSize: number; lineHeight: number; rule: number; ruleGap: number };
  signature: { text: string; size: number; lineHeight: number; opacity: number; gap: number };
  divider: { width: number; thickness: number; rosette: number; height: number };
  gap: number;
  steps: number;
  seriesStep: number;
  maxCards: number;
};

/** A line: the words from `[0]` up to, not including, `[1]`. */
export type ShareCardLine = [start: number, end: number];

export type ShareCardPage = {
  arabicSize: number;
  arabicLines: ShareCardLine[];
  translationSize: number;
  translationLines: ShareCardLine[];
};

/** The text area of a format, inside the frame and its inset. */
export function shareCardField(layout: ShareCardLayout, format: ShareCardFormat) {
  const { width, height, field } = layout.formats[format];
  const scale = width / 1080;
  return {
    left: field.left * width + layout.inset * scale,
    top: field.top * height + layout.inset * scale,
    width: ((field.right - field.left) * width) / scale - layout.inset * 2,
    height: ((field.bottom - field.top) * height) / scale - layout.inset * 2,
    scale,
  };
}

/** The reference and the signature under the text, with the gap above them. */
export function shareCardTailHeight(layout: ShareCardLayout): number {
  const { reference, signature } = layout;
  return layout.gap + reference.size * reference.lineHeight + signature.gap + signature.size * signature.lineHeight;
}

/** Greedy wrap of whole words; a word wider than the line gets a line of its own. */
export function wrapWords(widths: readonly number[], space: number, limit: number): ShareCardLine[] {
  const lines: ShareCardLine[] = [];
  let start = 0;
  let lineWidth = 0;
  widths.forEach((width, index) => {
    if (index > start && lineWidth + space + width > limit) {
      lines.push([start, index]);
      start = index;
      lineWidth = 0;
    }
    lineWidth += (index > start ? space : 0) + width;
  });
  if (widths.length > start) lines.push([start, widths.length]);
  return lines;
}

/** The same number of lines at the narrowest width that keeps it: lines of like length. */
function balancedLines(widths: readonly number[], space: number, limit: number): ShareCardLine[] {
  const lines = wrapWords(widths, space, limit);
  if (lines.length < 2) return lines;
  let low = Math.max(...widths);
  let high = limit;
  let best = lines;
  for (let step = 0; step < 14 && low < high; step += 1) {
    const middle = (low + high) / 2;
    const candidate = wrapWords(widths, space, middle);
    if (candidate.length === lines.length) {
      best = candidate;
      high = middle;
    } else {
      low = middle;
    }
  }
  return best;
}

// The largest size that needs the fewest cards, and its lines card by card,
// as evenly as they divide.
function paginate(
  widths: readonly number[],
  space: number,
  fieldWidth: number,
  available: number,
  { min, seriesMax, lineHeight }: { min: number; seriesMax: number; lineHeight: number },
  step: number,
): { size: number; cards: ShareCardLine[][] } {
  let chosen: { size: number; lines: ShareCardLine[]; count: number } | null = null;
  for (let size = min; size <= seriesMax; size += step) {
    const lines = wrapWords(widths, space, fieldWidth / size);
    const perCard = Math.max(1, Math.floor(available / (size * lineHeight)));
    const count = Math.ceil(lines.length / perCard);
    if (!chosen || count <= chosen.count) chosen = { size, lines, count };
  }
  const { size, lines, count } = chosen!;
  const base = Math.floor(lines.length / count);
  const extra = lines.length % count;
  const cards: ShareCardLine[][] = [];
  let from = 0;
  for (let card = 0; card < count; card += 1) {
    const length = base + (card < extra ? 1 : 0);
    cards.push(lines.slice(from, from + length));
    from += length;
  }
  return { size, cards };
}

/**
 * The cards of a text: one where the Arabic and the meaning fit together,
 * shrinking both in step; else the Arabic on its cards and the meaning on its
 * own. Null when it takes more cards than a series may have.
 */
export function composeShareCard(
  layout: ShareCardLayout,
  format: ShareCardFormat,
  arabic: { widths: readonly number[]; space: number },
  translation: { widths: readonly number[]; space: number },
): ShareCardPage[] | null {
  const field = shareCardField(layout, format);
  const tail = shareCardTailHeight(layout);
  const hasTranslation = translation.widths.length > 0;
  const middle = hasTranslation ? layout.gap * 2 + layout.divider.height : 0;
  for (let step = 0; step <= layout.steps; step += 1) {
    const shrink = step / layout.steps;
    const arabicSize = Math.round(layout.arabic.max - (layout.arabic.max - layout.arabic.min) * shrink);
    const translationSize = Math.round(
      layout.translation.max - (layout.translation.max - layout.translation.min) * shrink,
    );
    const arabicLines = wrapWords(arabic.widths, arabic.space, field.width / arabicSize);
    const translationLines = wrapWords(translation.widths, translation.space, field.width / translationSize);
    const height = arabicLines.length * arabicSize * layout.arabic.lineHeight + middle
      + translationLines.length * translationSize * layout.translation.lineHeight + tail;
    if (height <= field.height) {
      return [{
        arabicSize,
        arabicLines: balancedLines(arabic.widths, arabic.space, field.width / arabicSize),
        translationSize,
        translationLines: balancedLines(translation.widths, translation.space, field.width / translationSize),
      }];
    }
  }
  const available = field.height - tail;
  const arabicCards = paginate(arabic.widths, arabic.space, field.width, available, layout.arabic, layout.seriesStep);
  const pages: ShareCardPage[] = arabicCards.cards.map((arabicLines) => ({
    arabicSize: arabicCards.size,
    arabicLines,
    translationSize: 0,
    translationLines: [],
  }));
  if (hasTranslation) {
    const cards = paginate(
      translation.widths, translation.space, field.width, available, layout.translation, layout.seriesStep,
    );
    pages.push(...cards.cards.map((translationLines) => ({
      arabicSize: 0,
      arabicLines: [],
      translationSize: cards.size,
      translationLines,
    })));
  }
  return pages.length > layout.maxCards ? null : pages;
}
