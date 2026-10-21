import type { DuaCategory } from "./api.ts";

/**
 * Well-known names of du'a that the translated chapter titles do not use —
 * «истихара» is «молитва испрашивания помощи» in the Russian Hisn
 * al-Muslim — mapped to its chapters. Stems, so «истихару» and «istikharah»
 * match too. Port of dua_search.dart.
 */
const HISN_ALIASES: Array<[number[], string[]]> = [
  [[26], ["истихар", "istikhar", "istihar", "استخار"]],
  [[27, 28], [
    "аятулькурси", "аятелькурси", "аятальк", "аяткурси", "ayatalkursi", "ayatulkursi",
    "ayetelkursi", "ayetelkürsi", "آيةالكرسي",
  ]],
  [[32], ["кунут", "qunut", "kunut", "قنوت"]],
  [[16], ["истифтах", "istiftah", "iftitah", "استفتاح"]],
  [[22], ["ташаххуд", "ташахуд", "tashahhud", "teşehhüd", "تشهد"]],
  [[23, 107], ["салават", "salawat", "salavat", "صلاةعلىالنبي"]],
  [[55, 56], ["джаназ", "жаназ", "janaz", "cenaze", "جناز"]],
  [[129], ["истигфар", "istighfar", "istiğfar", "توب", "استغفار"]],
  [[68], ["ифтар", "iftar", "إفطار"]],
  [[115], ["тальби", "talbiy", "telbiye", "تلبي"]],
  [[63], ["истиск", "istisq", "istiska", "استسقاء"]],
  [[88], ["даджал", "даджжал", "dajjal", "deccal", "دجال"]],
  [[85], ["каффара", "kaffara", "keffaret", "كفارةالمجلس"]],
];

// Letters only: apostrophes, hyphens and spaces are written every which way.
const lettersOf = (value: string) => value.toLowerCase().replace(/[^\p{L}]/gu, "");

/**
 * Chapters a search should offer before individual du'a: those whose title
 * contains the query, and those a well-known name points to.
 */
export function duaChaptersMatching(
  query: string,
  categories: DuaCategory[],
  limit = 8,
): DuaCategory[] {
  const needle = query.trim().toLowerCase();
  const letters = lettersOf(needle);
  if ([...letters].length < 3) return [];
  const numbers = new Set<number>();
  for (const [chapters, names] of HISN_ALIASES) {
    if (names.some((name) => letters.includes(name)
      || ([...letters].length >= 4 && name.startsWith(letters)))) {
      for (const chapter of chapters) numbers.add(chapter);
    }
  }
  const matches = categories.filter((category) =>
    category.collection === "hisn-al-muslim" && numbers.has(category.source_number));
  for (const category of categories) {
    if (matches.length >= limit) break;
    if (!matches.includes(category) && category.title.toLowerCase().includes(needle)) {
      matches.push(category);
    }
  }
  return matches.slice(0, limit);
}
