// The share picture of the app's ShareCard (core/share/content_share.dart),
// drawn on a canvas: the owner's silk with its frame, and in the frame the
// Arabic, a rule with a rosette, the meaning, the reference between two rules
// and the site. A long text becomes a series of cards; nothing is cut. Sizes
// come from share-card-layout.json (docs/share-card), which the app reads too.

import {
  composeShareCard,
  shareCardField,
  type ShareCardFormat,
  type ShareCardLayout,
  type ShareCardLine,
  type ShareCardPage,
} from "./share-card-compose.ts";
import layoutJson from "./share-card-layout.json" with { type: "json" };

export const shareCardLayout = layoutJson as unknown as ShareCardLayout;

/** A word in its Mushaf page font, as drawn by the reader. */
export type ShareCardGlyph = { text: string; fontFamily: string };

export type ShareCardContent = {
  arabic: string;
  /**
   * The Arabic word by word, each word its pieces: a word in a font of the
   * selected Mushaf, loaded, or the last word of an ayah with its end sign.
   * When it is null or empty, fails or is late, the card draws `arabic`.
   */
  arabicUnits?: Promise<ShareCardGlyph[][] | null>;
  /** The end sign of an ayah drawn from `arabic`, «۝٢٨٦». */
  arabicEnd?: string;
  translation: string;
  /** The line under the meaning: «Аль-Бакара · 2:286», or the du'a's source. */
  cardReference: string;
};

export type ShareCardStyle = { format: ShareCardFormat; colour: string };

/** The fabric colours of the card, as the layout names them. */
export const SHARE_CARD_COLOURS: Record<string, string> = {
  emerald: "#074d45",
  turquoise: "#2e6a63",
  midnight: "#1a2a4b",
};

export const SHARE_CARD_STYLE_KEY = "iqro_share_card_style_v1";

/** The shape and the colour picked last time, as the app stores them: «story:emerald». */
export function parseShareCardStyle(stored: string | null): ShareCardStyle {
  const [format, colour] = (stored ?? "").split(":");
  return {
    format: format === "post" ? "post" : "story",
    colour: colour in SHARE_CARD_COLOURS ? colour : "emerald",
  };
}

/** The card's own Arabic face, for words drawn in the plain script. */
export const SHARE_CARD_ARABIC_FONT = "IQRO Share Arabic";
const ARABIC_FONT = SHARE_CARD_ARABIC_FONT;
const TEXT_FONT = "IQRO Share Serif";
const TEXT_FAMILY = `"${TEXT_FONT}", "${ARABIC_FONT}", serif`;
// How long the picture waits for the pages and fonts of the Mushaf, as the app.
const GLYPHS_WAIT_MS = 4000;

/** A word of the Arabic: one piece, or the last word with the ayah's end sign. */
type Unit = ShareCardGlyph[];

/** The Arabic as words; the end sign stays with the last word. Whitespace aside, nothing changes. */
export function shareCardArabicUnits(arabic: string, arabicEnd: string, loaded: Unit[] | null): Unit[] {
  if (loaded?.length) return loaded;
  const units: Unit[] = arabic.trim().split(/\s+/).map((text) => [{ text, fontFamily: ARABIC_FONT }]);
  if (arabicEnd && units.length > 0) units[units.length - 1].push({ text: arabicEnd, fontFamily: ARABIC_FONT });
  return units;
}

/** The meaning in quotes, as words. */
export function shareCardTranslationWords(translation: string): string[] {
  return translation.trim() ? `«${translation.trim()}»`.split(/\s+/) : [];
}

let fonts: Promise<unknown> | null = null;

// The card's own faces, the files the app draws with.
function loadFonts(): Promise<unknown> {
  fonts ??= Promise.all([
    [ARABIC_FONT, "/share-card/AmiriQuran-Regular.ttf"],
    [TEXT_FONT, "/share-card/PTSerif-Regular.ttf"],
  ].map(async ([family, url]) => {
    const face = await new FontFace(family, `url(${url})`).load();
    document.fonts.add(face);
  })).catch((error) => {
    fonts = null;
    throw error;
  });
  return fonts;
}

async function loadImage(url: string): Promise<HTMLImageElement> {
  const image = new Image();
  image.src = url;
  await image.decode();
  return image;
}

type Measured = {
  units: Unit[];
  /** The width of each piece of each unit, in em. */
  pieces: number[][];
  arabicSpace: number;
  translationWords: string[];
  arabic: { widths: number[]; space: number };
  translation: { widths: number[]; space: number };
};

function measure(context: CanvasRenderingContext2D, units: Unit[], translationWords: string[]): Measured {
  const em = (text: string, family: string) => {
    context.font = `100px ${family}`;
    return context.measureText(text).width / 100;
  };
  const arabicSpace = em(" ", `"${ARABIC_FONT}"`);
  const pieces = units.map((unit) => unit.map((piece) => em(piece.text, `"${piece.fontFamily}"`)));
  return {
    units,
    pieces,
    arabicSpace,
    translationWords,
    arabic: {
      widths: pieces.map((widths) => widths.reduce((sum, width) => sum + width, 0) + arabicSpace * (widths.length - 1)),
      space: arabicSpace,
    },
    translation: {
      widths: translationWords.map((word) => em(word, TEXT_FAMILY)),
      space: em(" ", TEXT_FAMILY),
    },
  };
}

// The baseline of a line box, where Flutter puts it: the font's ascent and
// descent share the line's height in proportion.
function baseline(context: CanvasRenderingContext2D, top: number, lineHeight: number): number {
  const metrics = context.measureText("x");
  const ascent = metrics.fontBoundingBoxAscent;
  return top + (lineHeight * ascent) / (ascent + metrics.fontBoundingBoxDescent);
}

// A rule that thins to its ends.
function rule(context: CanvasRenderingContext2D, from: number, to: number, y: number, weight: number) {
  context.moveTo(from, y);
  context.quadraticCurveTo((from + to) / 2, y - weight, to, y);
  context.quadraticCurveTo((from + to) / 2, y + weight, from, y);
}

function drawPage(
  context: CanvasRenderingContext2D,
  layout: ShareCardLayout,
  format: ShareCardFormat,
  background: HTMLImageElement,
  measured: Measured,
  page: ShareCardPage,
  reference: string,
) {
  const { width, height } = layout.formats[format];
  const field = shareCardField(layout, format);
  const centre = field.left + field.width / 2;
  context.shadowColor = "transparent";
  context.drawImage(background, 0, 0, width, height);

  const referenceHeight = layout.reference.size * layout.reference.lineHeight;
  const signatureHeight = layout.signature.size * layout.signature.lineHeight;
  const arabicLine = page.arabicSize * layout.arabic.lineHeight;
  const translationLine = page.translationSize * layout.translation.lineHeight;
  const hasDivider = page.arabicLines.length > 0 && page.translationLines.length > 0;
  const total = page.arabicLines.length * arabicLine
    + (hasDivider ? layout.gap * 2 + layout.divider.height : 0)
    + page.translationLines.length * translationLine
    + layout.gap + referenceHeight + layout.signature.gap + signatureHeight;
  let top = field.top + (field.height - total) / 2;

  context.fillStyle = layout.ink;
  context.shadowColor = `rgba(0, 0, 0, ${layout.shadow.opacity})`;
  context.shadowOffsetX = layout.shadow.dx;
  context.shadowOffsetY = layout.shadow.dy;
  context.shadowBlur = layout.shadow.blur * 1.4;
  context.textBaseline = "alphabetic";

  // A line wider than the field, a single long word, is scaled down to it.
  const fitted = (lineWidth: number, draw: () => void) => {
    const scale = Math.min(1, field.width / lineWidth);
    context.save();
    context.translate(centre, 0);
    context.scale(scale, 1);
    context.translate(-centre, 0);
    draw();
    context.restore();
  };

  // The Arabic, right to left, each word in its own font.
  context.direction = "rtl";
  context.textAlign = "right";
  for (const [start, end] of page.arabicLines) {
    const size = page.arabicSize;
    const lineWidth = size * (measured.arabic.widths.slice(start, end).reduce((sum, word) => sum + word, 0)
      + measured.arabicSpace * (end - start - 1));
    context.font = `${size}px "${measured.units[start][0].fontFamily}"`;
    const y = baseline(context, top, arabicLine);
    fitted(lineWidth, () => {
      let x = centre + lineWidth / 2;
      for (let word = start; word < end; word += 1) {
        measured.units[word].forEach((piece, index) => {
          context.font = `${size}px "${piece.fontFamily}"`;
          context.fillText(piece.text, x, y);
          x -= (measured.pieces[word][index] + measured.arabicSpace) * size;
        });
      }
    });
    top += arabicLine;
  }

  if (hasDivider) {
    const { rosette, thickness } = layout.divider;
    const y = top + layout.gap + layout.divider.height / 2;
    const half = layout.divider.width / 2;
    context.beginPath();
    rule(context, centre - half, centre - rosette * 0.8, y, thickness);
    rule(context, centre + rosette * 0.8, centre + half, y, thickness);
    context.fill();
    // An eight-petal flower.
    for (let petal = 0; petal < 8; petal += 1) {
      const angle = (petal * Math.PI) / 4;
      context.beginPath();
      context.ellipse(
        centre + Math.sin(angle) * rosette * 0.27, y - Math.cos(angle) * rosette * 0.27,
        rosette * 0.1, rosette * 0.21, angle, 0, Math.PI * 2,
      );
      context.fill();
    }
    context.beginPath();
    context.arc(centre, y, rosette * 0.1, 0, Math.PI * 2);
    context.fill();
    top += layout.gap * 2 + layout.divider.height;
  }

  context.direction = "ltr";
  context.textAlign = "center";
  context.font = `${page.translationSize}px ${TEXT_FAMILY}`;
  for (const [start, end] of page.translationLines) {
    const line = measured.translationWords.slice(start, end).join(" ");
    const y = baseline(context, top, translationLine);
    fitted(context.measureText(line).width, () => context.fillText(line, centre, y));
    top += translationLine;
  }

  // The reference between two rules; a long one gets a smaller size.
  top += layout.gap;
  const { rule: ruleWidth, ruleGap } = layout.reference;
  context.font = `${layout.reference.size}px ${TEXT_FAMILY}`;
  const room = field.width - (ruleWidth + ruleGap) * 2;
  const natural = context.measureText(reference).width;
  const scale = Math.min(1, room / natural);
  context.font = `${layout.reference.size * scale}px ${TEXT_FAMILY}`;
  const textWidth = natural * scale;
  context.fillText(reference, centre, baseline(context, top + (referenceHeight * (1 - scale)) / 2, referenceHeight * scale));
  const ruleY = top + referenceHeight / 2;
  context.beginPath();
  rule(context, centre - textWidth / 2 - ruleGap - ruleWidth, centre - textWidth / 2 - ruleGap, ruleY, layout.divider.thickness);
  rule(context, centre + textWidth / 2 + ruleGap, centre + textWidth / 2 + ruleGap + ruleWidth, ruleY, layout.divider.thickness);
  context.fill();
  top += referenceHeight + layout.signature.gap;

  context.font = `${layout.signature.size}px ${TEXT_FAMILY}`;
  context.globalAlpha = layout.signature.opacity;
  context.fillText(layout.signature.text, centre, baseline(context, top, signatureHeight));
  context.globalAlpha = 1;
}

function encode(canvas: HTMLCanvasElement): Promise<Blob> {
  return new Promise((resolve, reject) => {
    canvas.toBlob((jpeg) => (jpeg ? resolve(jpeg) : reject(new Error("JPEG encoding failed"))), "image/jpeg", 0.9);
  });
}

/** The lines of a page as text, for tests: what the card draws, in order. */
export function shareCardLines<T>(words: readonly T[], lines: readonly ShareCardLine[]): T[][] {
  return lines.map(([start, end]) => words.slice(start, end));
}

/**
 * Draws the cards of a text as JPEG; null when the text needs more cards
 * than a series may have. The Arabic waits a few seconds for the pages and
 * fonts of the Mushaf and is otherwise drawn in the plain script.
 */
export async function renderShareCards(content: ShareCardContent, style: ShareCardStyle): Promise<Blob[] | null> {
  const layout = shareCardLayout;
  const glyphs = content.arabicUnits
    ? Promise.race([
      content.arabicUnits.catch(() => null),
      new Promise<null>((resolve) => setTimeout(() => resolve(null), GLYPHS_WAIT_MS)),
    ])
    : null;
  const [background, loadedGlyphs] = await Promise.all([
    loadImage(`/share-card/${style.format}-${style.colour}.webp`),
    glyphs,
    loadFonts(),
  ]);
  const { width, height } = layout.formats[style.format];
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const context = canvas.getContext("2d");
  if (!context) throw new Error("Canvas 2D is unavailable");
  const measured = measure(
    context,
    shareCardArabicUnits(content.arabic, content.arabicEnd ?? "", loadedGlyphs),
    shareCardTranslationWords(content.translation),
  );
  const pages = composeShareCard(layout, style.format, measured.arabic, measured.translation);
  if (!pages) return null;
  const cards: Blob[] = [];
  for (const [index, page] of pages.entries()) {
    const reference = pages.length > 1
      ? `${content.cardReference} · ${index + 1}/${pages.length}`
      : content.cardReference;
    drawPage(context, layout, style.format, background, measured, page, reference);
    cards.push(await encode(canvas));
  }
  return cards;
}
