// Arabic lines filled to both edges as a printed Mushaf fills them: by
// drawing out the joins between letters (kashida, «ـ»), not by widening the
// spaces between words. The app does the same (kashida.dart).

const MARK = /[ؐ-ًؚ-ٰٟۖ-ۭ࣓-ࣿ]/;
const LETTER = /[ؠ-يٱ-ۓ]/;
const NOT_LETTERS = /[^ؠ-يٱ-ۓ]/g;
const ALLAH = /^(ٱ|ا|و|ب|ف)?(ٱ|ا)?لله$/;
/** Letters that join only the letter before them. */
const RIGHT_JOINING = "اأإآٱدذرزوؤةى";
const ALEFS = "اأإآٱ";
export const TATWEEL = "ـ";

function joinsNext(letter: string) {
  return LETTER.test(letter) && !RIGHT_JOINING.includes(letter) && letter !== "ء";
}

function joinsPrevious(letter: string) {
  return LETTER.test(letter) && letter !== "ء";
}

/**
 * Where a kashida may go in a word, as offsets into it: between two joined
 * letters, after the first one's marks. Never inside lam-alef, which is one
 * shape, nor in the name of Allah.
 */
export function kashidaSpots(word: string): number[] {
  if (ALLAH.test(word.replace(NOT_LETTERS, ""))) return [];
  const bases: number[] = [];
  for (let i = 0; i < word.length; i++) if (!MARK.test(word[i])) bases.push(i);
  const spots: number[] = [];
  for (let b = 0; b < bases.length - 1; b++) {
    const letter = word[bases[b]];
    const next = word[bases[b + 1]];
    if (!joinsNext(letter) || !joinsPrevious(next)) continue;
    if (letter === "ل" && ALEFS.includes(next)) continue;
    spots.push(bases[b + 1]);
  }
  return spots;
}

export function stretchWord(word: string, spot: number, count: number) {
  return word.slice(0, spot) + TATWEEL.repeat(count) + word.slice(spot);
}

export type KashidaLayout = { words: string[]; breaks: Set<number> };

/**
 * Breaks the words into lines no wider than `width` and draws out the joins
 * of each line but the last until it reaches the edge. `marker` follows the
 * last word: it is measured with it, and not drawn out. `measure` gives a
 * text's width in the paragraph's font.
 */
export function kashidaLayout(
  words: string[],
  width: number,
  measure: (text: string) => number,
  { marker = "", fontSize = 16 }: { marker?: string; fontSize?: number } = {},
): KashidaLayout {
  if (!words.length || width <= 0) return { words, breaks: new Set() };
  const space = measure("ب ب") - 2 * measure("ب");
  const wordWidth = (index: number, text: string) => measure(index === words.length - 1 ? text + marker : text);

  const lines: number[][] = [];
  let line: number[] = [];
  let used = 0;
  words.forEach((word, i) => {
    const w = wordWidth(i, word);
    if (line.length && used + space + w > width) {
      lines.push(line);
      line = [];
      used = 0;
    }
    used += line.length ? space + w : w;
    line.push(i);
  });
  lines.push(line);

  const out = [...words];
  const breaks = new Set<number>();
  const cap = Math.max(3, Math.round(fontSize / 8));
  lines.slice(0, -1).forEach((ln) => {
    breaks.add(ln[ln.length - 1]);
    if (ln.length < 2) return;
    const spots = new Map<number, number>();
    for (const i of ln) {
      const found = kashidaSpots(words[i]);
      if (found.length) spots.set(i, found[found.length - 1]);
    }
    const counts = new Map([...spots.keys()].map((i) => [i, 0]));
    let total = ln.reduce((sum, i) => sum + wordWidth(i, words[i]), 0) + space * (ln.length - 1);
    let grew = true;
    while (grew) {
      grew = false;
      // Longer words first, one stroke each, round after round.
      const order = [...spots.keys()].filter((i) => counts.get(i)! < cap)
        .sort((a, b) => words[b].length - words[a].length);
      for (const i of order) {
        const before = wordWidth(i, out[i]);
        const longer = stretchWord(words[i], spots.get(i)!, counts.get(i)! + 1);
        const after = wordWidth(i, longer);
        if (total + after - before > width - 1) continue;
        counts.set(i, counts.get(i)! + 1);
        out[i] = longer;
        total += after - before;
        grew = true;
      }
    }
  });
  return { words: out, breaks };
}
