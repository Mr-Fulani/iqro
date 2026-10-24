import type { Locale } from "@/lib/i18n";
import { renderCourseNotes } from "@/lib/course-notes";
import type { NoteBlock } from "@/lib/thematic-courses";
import { translate } from "@/lib/translate";

/** The lesson notes as server HTML, without client JS. */
export function CourseNotes({ blocks, locale }: { blocks: NoteBlock[]; locale: Locale }) {
  return renderCourseNotes(blocks, { note: translate(locale, "courses.noteLabel") });
}
