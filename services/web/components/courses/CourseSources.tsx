import type { Locale } from "@/lib/i18n";
import { translate } from "@/lib/translate";

/**
 * «Author and sources» of a course and «Sources» at the end of a lesson: the same blocks in
 * thematic courses, the prayer course and tajweed (docs/salah/sources.md). Nothing without text.
 */
export function CourseSource({ source, locale }: { source: string; locale: Locale }) {
  if (!source) return null;
  return (
    <p className="course-source">
      <strong>{translate(locale, "courses.source")}:</strong> {source}
    </p>
  );
}

export function CourseLessonSources({ sources, locale }: { sources: string[]; locale: Locale }) {
  if (!sources.length) return null;
  return (
    <div className="course-lesson-sources" data-testid="course-lesson-sources">
      <h3>{translate(locale, "courses.sources")}</h3>
      <ol>
        {sources.map((source, item) => <li key={item} dir="auto">{source}</li>)}
      </ol>
    </div>
  );
}
