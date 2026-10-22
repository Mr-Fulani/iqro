import type {
  QuranFoundationMushaf,
  TajweedAyah,
  TajweedFragment,
  TajweedReference,
  TajweedRule,
  TajweedTexts,
  TajweedWord,
} from "./api";

/** What the tajweed card shows: one tapped word, or one rule from the legend. */
export type TajweedSelection =
  | { kind: "word"; verseKey: string; position: number }
  | { kind: "rule"; code: string };

export type TajweedRun = { text: string; code: string | null };

/** A word of an ayah as the QCF V4 page font draws it. */
export type TajweedGlyph = {
  key: string;
  text: string;
  fontFamily: string;
  /** Quran.Foundation position of a word in its ayah; null for the ayah end. */
  position: number | null;
};

/** A word and the part of one rule it carries. */
export type TajweedPart = { verseKey: string; word: TajweedWord; fragment: TajweedFragment };

export type TajweedRuleText = {
  code: string;
  color: string;
  name: string;
  variantName: string | null;
  arabicName: string;
  why: string;
  how: string;
};

/** The coloured QCF V4 tajweed Mushaf (Quran.Foundation Mushaf 19). */
export function isTajweedMushaf(mushaf: QuranFoundationMushaf): boolean {
  return (
    mushaf.default_font_name === "v4-tajweed" &&
    mushaf.rendering.available &&
    mushaf.rendering.mode === "page-font" &&
    mushaf.rendering.color_format === "COLRv1"
  );
}

export function tajweedWordKey(verseKey: string, position: number): string {
  return `${verseKey}#${position}`;
}

export function tajweedWordIndex(ayahs: readonly TajweedAyah[]): Map<string, TajweedWord> {
  const index = new Map<string, TajweedWord>();
  for (const ayah of ayahs) {
    for (const word of ayah.words) index.set(tajweedWordKey(ayah.verse_key, word.position), word);
  }
  return index;
}

export function localizedText(texts: TajweedTexts, locale: string): string {
  return texts[locale] || texts.en || texts.ru || "";
}

/** Rules in legend order, limited to the given codes. */
export function presentRules(reference: TajweedReference, codes: readonly string[]): TajweedRule[] {
  const wanted = new Set(codes);
  return reference.rules.filter((rule) => wanted.has(rule.code));
}

export function ruleText(
  reference: TajweedReference,
  code: string,
  locale: string,
  variantCode = "",
): TajweedRuleText | null {
  const rule = reference.rules.find((item) => item.code === code);
  if (!rule) return null;
  const variant = rule.variants.find((item) => item.code === variantCode);
  return {
    code,
    color: rule.color,
    name: localizedText(rule.name, locale),
    variantName: variant ? localizedText(variant.name, locale) : null,
    arabicName: rule.arabic_name,
    why: localizedText((variant ?? rule).why, locale),
    how: localizedText((variant ?? rule).how, locale),
  };
}

const COMBINING_MARK = /\p{M}/u;

/**
 * Splits a word into runs for colouring. Where rules nest (a silent alef inside
 * a madd), the narrower rule wins, as in the coloured Mushaf. A run never starts
 * on a vowel mark: the mark stays with its letter, so the word keeps its shape.
 */
export function highlightRuns(text: string, fragments: readonly TajweedFragment[]): TajweedRun[] {
  const codes: (string | null)[] = Array.from({ length: text.length }, () => null);
  const widths: number[] = Array.from({ length: text.length }, () => Infinity);
  for (const fragment of fragments) {
    const width = fragment.end - fragment.start;
    for (let index = Math.max(0, fragment.start); index < Math.min(text.length, fragment.end); index += 1) {
      if (width < widths[index]) {
        widths[index] = width;
        codes[index] = fragment.code;
      }
    }
  }
  const runs: TajweedRun[] = [];
  for (let index = 0; index < text.length; index += 1) {
    const previous = runs.at(-1);
    if (previous && (previous.code === codes[index] || COMBINING_MARK.test(text[index]))) {
      previous.text += text[index];
    } else {
      runs.push({ text: text[index], code: codes[index] });
    }
  }
  return runs;
}

// Arabic letters that never connect to the following letter.
const NOT_JOINING_FORWARD = new Set([..."ءآأؤإاةدذرزوٱٲ"]);
const ZWJ = "\u200d";

function joinsForward(run: string): boolean {
  const letter = [...run].reverse().find((char) => !COMBINING_MARK.test(char));
  return Boolean(letter && /\p{Script=Arabic}/u.test(letter) && /\p{Lo}/u.test(letter) && !NOT_JOINING_FORWARD.has(letter));
}

function joinsBack(run: string): boolean {
  return /^\p{Lo}/u.test(run) && run[0] !== "ء";
}

/**
 * Coloured runs are separate elements; a zero-width joiner on both sides of a
 * break keeps letters that connect in the word connected on screen.
 */
export function joinedRuns(runs: readonly TajweedRun[]): TajweedRun[] {
  return runs.map((run, index) => {
    const next = runs[index + 1];
    const previous = runs[index - 1];
    let text = run.text;
    if (previous && joinsForward(previous.text) && joinsBack(text)) text = ZWJ + text;
    if (next && joinsForward(run.text) && joinsBack(next.text)) text += ZWJ;
    return { ...run, text };
  });
}

/** The word's own part of a rule plus the neighbouring words the rule continues into. */
export function joinedParts(ayah: TajweedAyah, word: TajweedWord, fragment: TajweedFragment): TajweedPart[] {
  const parts: TajweedPart[] = [{ verseKey: ayah.verse_key, word, fragment }];
  const neighbour = (position: number, joins: "joins_previous" | "joins_next") => {
    const other = ayah.words.find((item) => item.position === position);
    const part = other?.rules.find((item) => item.code === fragment.code && item[joins]);
    return other && part ? { verseKey: ayah.verse_key, word: other, fragment: part } : null;
  };
  if (fragment.joins_previous) {
    const previous = neighbour(word.position - 1, "joins_next");
    if (previous) parts.unshift(previous);
  }
  if (fragment.joins_next) {
    const next = neighbour(word.position + 1, "joins_previous");
    if (next) parts.push(next);
  }
  return parts;
}

/** Every place a rule occurs; a rule spanning two words is one occurrence. */
export function ruleOccurrences(ayahs: readonly TajweedAyah[], code: string): TajweedPart[][] {
  const occurrences: TajweedPart[][] = [];
  for (const ayah of ayahs) {
    for (const word of ayah.words) {
      for (const fragment of word.rules) {
        if (fragment.code !== code || fragment.joins_previous) continue;
        occurrences.push(joinedParts(ayah, word, fragment));
      }
    }
  }
  return occurrences;
}

/** One step of an ayah's breakdown: one rule in one place, in reading order. */
export type TajweedStep = { code: string; variant: string | null; parts: TajweedPart[] };

/**
 * The steps of a tajweed breakdown: every rule of the ayah where it occurs, word
 * after word. Several rules in one word are several steps; a rule that crosses
 * into the next word is one step, shown on both words.
 */
export function tajweedSteps(ayah: TajweedAyah, reference: TajweedReference): TajweedStep[] {
  const known = new Set(reference.rules.map((rule) => rule.code));
  const steps: TajweedStep[] = [];
  for (const word of [...ayah.words].sort((left, right) => left.position - right.position)) {
    for (const fragment of word.rules) {
      if (!known.has(fragment.code)) continue;
      const parts = joinedParts(ayah, word, fragment);
      // A rule continued from the previous word is that word's step.
      if (parts[0].word !== word) continue;
      steps.push({ code: fragment.code, variant: fragment.variant ?? null, parts });
    }
  }
  return steps;
}

/** The rules a breakdown met, in the order they first occur, with their step indexes. */
export function stepRules(steps: readonly TajweedStep[]): { code: string; steps: number[] }[] {
  const rules = new Map<string, number[]>();
  steps.forEach((step, index) => {
    const indexes = rules.get(step.code) ?? [];
    indexes.push(index);
    rules.set(step.code, indexes);
  });
  return [...rules].map(([code, indexes]) => ({ code, steps: indexes }));
}

/** `[start_ms, end_ms)` of a step's words, from the first word to the last. */
export function stepTiming(
  words: readonly (readonly number[])[] | undefined,
  step: TajweedStep,
): { startMs: number; endMs: number } | null {
  const first = wordTiming(words, step.parts[0].word.position);
  const last = wordTiming(words, step.parts.at(-1)!.word.position);
  return first && last && last.endMs > first.startMs ? { startMs: first.startMs, endMs: last.endMs } : null;
}

/** The word sounding at `ms` of the reciter's track, if it is timed. */
export function timedPosition(words: readonly (readonly number[])[] | undefined, ms: number): number | null {
  const row = words?.find((item) => item.length === 3 && item[1] <= ms && ms < item[2]);
  return row ? row[0] : null;
}

export function findTajweedWord(
  ayahs: readonly TajweedAyah[],
  verseKey: string,
  position: number,
): { ayah: TajweedAyah; word: TajweedWord } | null {
  const ayah = ayahs.find((item) => item.verse_key === verseKey);
  const word = ayah?.words.find((item) => item.position === position);
  return ayah && word ? { ayah, word } : null;
}

/** `[start_ms, end_ms)` of one word in the reciter's surah track, if timed. */
export function wordTiming(
  words: readonly (readonly number[])[] | undefined,
  position: number,
): { startMs: number; endMs: number } | null {
  const row = words?.find((item) => item[0] === position);
  if (!row || row.length !== 3 || !(row[2] > row[1]) || row[1] < 0) return null;
  return { startMs: row[1], endMs: row[2] };
}

export function parseVerseKey(verseKey: string): { surah: number; ayah: number } | null {
  const [surah, ayah] = verseKey.split(":").map(Number);
  return Number.isInteger(surah) && Number.isInteger(ayah) && surah > 0 && ayah > 0 ? { surah, ayah } : null;
}

const ARABIC_SPAN = /[\u0600-\u06ff\u0750-\u077f\u08a0-\u08ff]+(?:[\s/]+[\u0600-\u06ff\u0750-\u077f\u08a0-\u08ff]+)*/gu;

/** Splits an explanation into plain and Arabic parts so Arabic examples can be isolated. */
export function arabicParts(text: string): { text: string; arabic: boolean }[] {
  const parts: { text: string; arabic: boolean }[] = [];
  let index = 0;
  for (const match of text.matchAll(ARABIC_SPAN)) {
    if (match.index > index) parts.push({ text: text.slice(index, match.index), arabic: false });
    parts.push({ text: match[0], arabic: true });
    index = match.index + match[0].length;
  }
  if (index < text.length) parts.push({ text: text.slice(index), arabic: false });
  return parts;
}
