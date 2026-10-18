import type { QuranFoundationMushafPage } from "./api";

export type SurahHeaderSource = NonNullable<QuranFoundationMushafPage["surah_header"]>;
export type SurahHeaderGlyph = { d: string; viewBox: string };

export const SURAH_HEADER_FONT_URL =
  "https://static-cdn.tarteel.ai/qul/fonts/surah-names/surah-header/QCF_SurahHeader_COLOR-Regular.ttf";
/** The pinned file, as in the backend's `surah_header.py`. */
export const SURAH_HEADER_FONT_SHA256 = "de261a309bdd42262e1a268d5ead56b6ea8366cd59124baedea3903561d7370b";
// Glyphs follow .notdef, uni0000, uni0009 and space in surah order.
const FIRST_SURAH_GLYPH_ID = 4;
const fonts = new Map<string, { promise: Promise<DataView>; font?: DataView }>();
const glyphs = new Map<string, SurahHeaderGlyph | null>();

/**
 * Reads a simple glyph's quadratic outline from `glyf`/`loca` as SVG path data
 * in font units with y pointing down. Browsers' font rasterizers drop parts of
 * the QUL surah-header outlines; filling the same outline as a path is exact.
 * Returns null for empty or composite glyphs; malformed data throws.
 *
 * With `keep`, only contours whose bounds it accepts are drawn and the view
 * box is theirs; null when it accepts none.
 */
export function readTrueTypeGlyph(
  font: DataView,
  glyphId: number,
  keep?: (contour: { left: number; top: number; right: number; bottom: number }) => boolean,
): SurahHeaderGlyph | null {
  const tables = new Map<string, number>();
  for (let index = 0; index < font.getUint16(4); index++) {
    const record = 12 + index * 16;
    const tag = String.fromCharCode(...new Uint8Array(font.buffer, font.byteOffset + record, 4));
    tables.set(tag, font.getUint32(record + 8));
  }
  const head = tables.get("head");
  const maxp = tables.get("maxp");
  const loca = tables.get("loca");
  const glyf = tables.get("glyf");
  if (head === undefined || maxp === undefined || loca === undefined || glyf === undefined) return null;
  if (glyphId < 0 || glyphId >= font.getUint16(maxp + 4)) return null;
  const longOffsets = font.getInt16(head + 50) === 1;
  const location = (id: number) => longOffsets ? font.getUint32(loca + id * 4) : font.getUint16(loca + id * 2) * 2;
  if (location(glyphId + 1) <= location(glyphId)) return null;
  const start = glyf + location(glyphId);
  const contours = font.getInt16(start);
  if (contours <= 0) return null;
  const ends = Array.from({ length: contours }, (_, index) => font.getUint16(start + 10 + index * 2));
  const points = ends[ends.length - 1] + 1;
  let offset = start + 10 + contours * 2;
  offset += 2 + font.getUint16(offset);
  const flags = new Uint8Array(points);
  for (let index = 0; index < points;) {
    const flag = font.getUint8(offset++);
    flags[index++] = flag;
    if (flag & 8) {
      for (let repeat = font.getUint8(offset++); repeat > 0; repeat--) flags[index++] = flag;
    }
  }
  const coordinates = (short: number, sameOrPositive: number) => {
    const values = new Float64Array(points);
    let value = 0;
    for (let index = 0; index < points; index++) {
      const flag = flags[index];
      if (flag & short) {
        const delta = font.getUint8(offset++);
        value += flag & sameOrPositive ? delta : -delta;
      } else if (!(flag & sameOrPositive)) {
        value += font.getInt16(offset);
        offset += 2;
      }
      values[index] = value;
    }
    return values;
  };
  const xs = coordinates(2, 16);
  const ys = coordinates(4, 32);
  const commands: string[] = [];
  let kept: { left: number; top: number; right: number; bottom: number } | null = null;
  let first = 0;
  for (const last of ends) {
    const count = last - first + 1;
    if (keep) {
      const bounds = { left: Infinity, top: Infinity, right: -Infinity, bottom: -Infinity };
      for (let index = first; index <= last; index++) {
        bounds.left = Math.min(bounds.left, xs[index]);
        bounds.right = Math.max(bounds.right, xs[index]);
        bounds.top = Math.min(bounds.top, -ys[index]);
        bounds.bottom = Math.max(bounds.bottom, -ys[index]);
      }
      if (!keep(bounds)) {
        first = last + 1;
        continue;
      }
      kept = kept
        ? {
            left: Math.min(kept.left, bounds.left),
            top: Math.min(kept.top, bounds.top),
            right: Math.max(kept.right, bounds.right),
            bottom: Math.max(kept.bottom, bounds.bottom),
          }
        : bounds;
    }
    const at = (index: number): [number, number] => [xs[first + index % count], -ys[first + index % count]];
    const onCurve = (index: number) => (flags[first + index % count] & 1) !== 0;
    const middle = (a: [number, number], b: [number, number]): [number, number] => [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2];
    let startIndex = 0;
    while (startIndex < count && !onCurve(startIndex)) startIndex++;
    // A contour of off-curve points starts on their implied midpoint.
    const allOff = startIndex === count;
    const origin = allOff ? middle(at(count - 1), at(0)) : at(startIndex);
    commands.push(`M${origin[0]} ${origin[1]}`);
    let control: [number, number] | null = null;
    const to = (point: [number, number]) => commands.push(control
      ? `Q${control[0]} ${control[1]} ${point[0]} ${point[1]}`
      : `L${point[0]} ${point[1]}`);
    for (let index = allOff ? 0 : startIndex + 1; index < (allOff ? count : startIndex + count); index++) {
      const point = at(index);
      if (onCurve(index)) {
        to(point);
        control = null;
      } else {
        if (control) to(middle(control, point));
        control = point;
      }
    }
    to(origin);
    commands.push("Z");
    first = last + 1;
  }
  if (keep) {
    return kept && {
      d: commands.join(""),
      viewBox: `${kept.left} ${kept.top} ${kept.right - kept.left} ${kept.bottom - kept.top}`,
    };
  }
  const [xMin, yMin, xMax, yMax] = [2, 4, 6, 8].map((field) => font.getInt16(start + field));
  return { d: commands.join(""), viewBox: `${xMin} ${-yMax} ${xMax - xMin} ${yMax - yMin}` };
}

// In font units: the cartouche's open middle, clear of its border bands and
// end ornaments. Every surah's name lies within it, and nothing else does.
const insideCartouche = (contour: { left: number; top: number; right: number; bottom: number }) =>
  contour.right - contour.left < 3000 &&
  contour.left > 900 &&
  contour.right < 7300 &&
  contour.top > -380 &&
  contour.bottom < 380;

const surahNames = new Map<number, SurahHeaderGlyph | null>();

/** The calligraphic «سورة …» of a Mushaf heading, without its cartouche. */
export function readSurahNameGlyph(font: DataView, surah: number): SurahHeaderGlyph | null {
  if (!Number.isInteger(surah) || surah < 1 || surah > 114) return null;
  return readTrueTypeGlyph(font, FIRST_SURAH_GLYPH_ID + surah - 1, insideCartouche);
}

const pinnedSource = {
  font_url: SURAH_HEADER_FONT_URL,
  font_sha256: SURAH_HEADER_FONT_SHA256,
  glyph_ids: {},
} as SurahHeaderSource;

/** The name of `surah` once the heading font is loaded, else undefined. */
export function loadedSurahNameGlyph(surah: number): SurahHeaderGlyph | null | undefined {
  const font = fonts.get(`${SURAH_HEADER_FONT_URL}:${SURAH_HEADER_FONT_SHA256}`)?.font;
  if (!font) return undefined;
  if (!surahNames.has(surah)) {
    let glyph: SurahHeaderGlyph | null = null;
    try {
      glyph = readSurahNameGlyph(font, surah);
    } catch {
      glyph = null;
    }
    surahNames.set(surah, glyph);
  }
  return surahNames.get(surah);
}

/** Fetches the pinned heading font once; surah names render from it after. */
export function loadSurahNameFont(): Promise<void> {
  return loadSurahHeaderGlyphs(pinnedSource).then(() => undefined);
}

function headingGlyphs(source: SurahHeaderSource, font: DataView): ReadonlyMap<number, SurahHeaderGlyph> {
  const result = new Map<number, SurahHeaderGlyph>();
  for (const [surah, glyphId] of Object.entries(source.glyph_ids)) {
    const key = `${source.font_sha256}:${glyphId}`;
    if (!glyphs.has(key)) glyphs.set(key, readTrueTypeGlyph(font, glyphId));
    const glyph = glyphs.get(key);
    if (glyph) result.set(Number(surah), glyph);
  }
  return result;
}

/** Headings whose pinned font is already loaded, so page turns do not flicker. */
export function loadedSurahHeaderGlyphs(source: SurahHeaderSource): ReadonlyMap<number, SurahHeaderGlyph> | undefined {
  const font = fonts.get(`${source.font_url}:${source.font_sha256}`)?.font;
  return font && headingGlyphs(source, font);
}

/** Loads the source's heading font once and rejects any other file. */
export async function loadSurahHeaderGlyphs(source: SurahHeaderSource): Promise<ReadonlyMap<number, SurahHeaderGlyph>> {
  if (source.font_url !== SURAH_HEADER_FONT_URL) throw new Error("Unsupported surah header font");
  const key = `${source.font_url}:${source.font_sha256}`;
  let entry = fonts.get(key);
  if (!entry) {
    const created: { promise: Promise<DataView>; font?: DataView } = {
      promise: fetch(source.font_url, { credentials: "omit" }).then(async (response) => {
        if (!response.ok) throw new Error(`Surah header font HTTP ${response.status}`);
        const buffer = await response.arrayBuffer();
        const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", buffer));
        const checksum = Array.from(digest, (byte) => byte.toString(16).padStart(2, "0")).join("");
        if (checksum !== source.font_sha256) throw new Error("Surah header font changed");
        return (created.font = new DataView(buffer));
      }),
    };
    created.promise.catch(() => fonts.delete(key));
    fonts.set(key, created);
    entry = created;
  }
  return headingGlyphs(source, await entry.promise);
}
