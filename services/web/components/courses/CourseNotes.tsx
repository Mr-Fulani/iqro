import type { Locale } from "@/lib/i18n";
import { renderCourseNotes, type CourseNotesLabels, type CourseNotesOptions } from "@/lib/course-notes";
import type { NoteBlock } from "@/lib/thematic-courses";
import { translate } from "@/lib/translate";

export function courseNotesLabels(locale: Locale): CourseNotesLabels {
  return {
    note: translate(locale, "courses.noteLabel"),
    warning: translate(locale, "courses.markWarning"),
    help: translate(locale, "courses.markHelp"),
    close: translate(locale, "courses.markClose"),
    newTab: translate(locale, "courses.linkNewTab"),
  };
}

/** The lesson notes as server HTML, without client JS. */
export function CourseNotes({
  blocks,
  locale,
  ...options
}: { blocks: NoteBlock[]; locale: Locale } & Omit<CourseNotesOptions, "locale">) {
  return renderCourseNotes(blocks, courseNotesLabels(locale), { locale, ...options });
}
