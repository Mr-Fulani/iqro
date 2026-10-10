import catalog from "./dua-topic-catalog.json" with { type: "json" };

import type { DuaCategory, DuaEntry } from "./api.ts";
import type { Locale } from "./i18n.ts";

export type DuaTopic = {
  id: string;
  collection: string;
  chapter_numbers: number[];
  title: Record<Locale, string>;
  description: Record<Locale, string>;
  entry_numbers?: number[];
};

export const duaTopics: DuaTopic[] = catalog.topics;

export function topicCategories(topic: DuaTopic, categories: DuaCategory[]): DuaCategory[] {
  return categories.filter((category) => category.collection === topic.collection
    && (!topic.chapter_numbers.length || topic.chapter_numbers.includes(category.source_number)));
}

export function topicEntries(topic: DuaTopic, entries: DuaEntry[]): DuaEntry[] {
  return entries.filter((entry) => entry.collection === topic.collection
    && (!topic.chapter_numbers.length || topic.chapter_numbers.includes(entry.category.source_number))
    && (!topic.entry_numbers || topic.entry_numbers.includes(entry.source_number)));
}

export function topicEntryCount(topic: DuaTopic, categories: DuaCategory[]): number {
  const members = topicCategories(topic, categories);
  const count = members.reduce((total, item) => total + item.entry_count, 0);
  // Count the curated subset only when the complete source chapter is present.
  // Smaller published source versions must not advertise entries they lack.
  return topic.entry_numbers && count === 24 ? topic.entry_numbers.length : count;
}
