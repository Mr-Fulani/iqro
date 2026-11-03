import catalog from "./dua-topic-catalog.json" with { type: "json" };

import type { DuaCategory, DuaEntry, DuaTimeOfDay } from "./api.ts";
import type { Locale } from "./i18n.ts";

export type DuaTopic = {
  id: string;
  collection: string;
  chapter_numbers: number[];
  title: Record<Locale, string>;
  description: Record<Locale, string>;
  entry_numbers?: number[];
  /** Cards read the entries' own reading for this time of day. */
  time_of_day?: DuaTimeOfDay;
};

export const duaTopics = catalog.topics as DuaTopic[];

/**
 * The entry as the morning or evening card reads it (forTimeOfDay in
 * dua_repository.dart): the source keeps both readings with notes such as
 * «in the evening say…», each card only its own.
 */
export function duaEntryForTime(entry: DuaEntry, time: DuaTimeOfDay | undefined): DuaEntry {
  const variant = time ? entry.time_variants?.[time] : undefined;
  if (!variant) return entry;
  return {
    ...entry,
    arabic_text: variant.arabic_text,
    translation: entry.translation && {
      ...entry.translation,
      meaning_text: variant.meaning_text,
      transliteration: variant.transliteration,
    },
  };
}

export function topicCategories(topic: DuaTopic, categories: DuaCategory[]): DuaCategory[] {
  return categories.filter((category) => category.collection === topic.collection
    && (!topic.chapter_numbers.length || topic.chapter_numbers.includes(category.source_number)));
}

export function topicEntries(topic: DuaTopic, entries: DuaEntry[]): DuaEntry[] {
  return entries.filter((entry) => entry.collection === topic.collection
    && (!topic.chapter_numbers.length || topic.chapter_numbers.includes(entry.category.source_number))
    && (!topic.entry_numbers || topic.entry_numbers.includes(entry.source_number)))
    .map((entry) => duaEntryForTime(entry, topic.time_of_day));
}

export function topicEntryCount(topic: DuaTopic, categories: DuaCategory[]): number {
  const members = topicCategories(topic, categories);
  const count = members.reduce((total, item) => total + item.entry_count, 0);
  // Count the curated subset only when the complete source chapter is present.
  // Smaller published source versions must not advertise entries they lack.
  return topic.entry_numbers && count === 24 ? topic.entry_numbers.length : count;
}
