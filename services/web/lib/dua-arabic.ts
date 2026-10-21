/**
 * One line of a du'a's Arabic text: the du'a itself, or an opening formula
 * (the basmala or the isti'adha) that is read before it. Port of
 * dua_arabic.dart.
 */
export type DuaArabicPart = { text: string; opening: boolean };

// Harakat, tanwin, shadda, sukun, the dagger alif and Quranic marks may sit
// on any letter, and the sources write the formulas with and without them.
const MARKS = "[ً-ٰٟۖ-ۭـ]*";
const ALIF = "[اأإآٱ]";

const letters = (word: string) =>
  [...word].map((letter) => (letter === "ا" ? ALIF : letter) + MARKS).join("");

const phrase = (words: string[]) => words.map(letters).join("\\s+");

const OPENING = new RegExp(
  [
    phrase(["بسم", "الله", "الرحمن", "الرحيم"]),
    phrase(["اعوذ", "بالله", "من", "الشيطان", "الرجيم"]),
  ].join("|"),
  "gu",
);

/**
 * Splits the basmala and the isti'adha off the du'a so they stand on their
 * own lines, as printed in the sources.
 */
export function splitDuaArabic(text: string): DuaArabicPart[] {
  const parts: DuaArabicPart[] = [];
  const addText = (value: string) => {
    // Separators the sources leave around a formula: dots, commas, colons.
    const trimmed = value.replace(/^[\s.,:،؛]+|[\s.,:،؛]+$/gu, "");
    if (trimmed) parts.push({ text: trimmed, opening: false });
  };
  let start = 0;
  for (const match of text.matchAll(OPENING)) {
    addText(text.slice(start, match.index));
    parts.push({ text: match[0], opening: true });
    start = match.index + match[0].length;
  }
  addText(text.slice(start));
  // A formula with nothing after it is the du'a itself (for example a du'a
  // that is only the basmala), so it keeps the full size.
  if (parts.every((part) => part.opening)) {
    return parts.map((part) => ({ text: part.text, opening: false }));
  }
  return parts;
}
