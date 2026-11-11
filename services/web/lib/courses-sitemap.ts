import type { Locale } from "./i18n";
import { localizedSitemapEntry } from "./sitemap-xml";

export const COURSES_SITEMAP_PATH = "/sitemaps/courses/sitemap.xml";

/** A course and its lessons, only on the languages its release has. */
export function courseSitemapEntries(
  course: string,
  lessons: readonly string[],
  locales: readonly Locale[],
): string {
  return [`/courses/${course}`, ...lessons.map((lesson) => `/courses/${course}/${lesson}`)]
    .map((path) => localizedSitemapEntry(path, undefined, locales))
    .join("");
}
