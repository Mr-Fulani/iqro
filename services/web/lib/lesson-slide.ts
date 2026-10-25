// Which slide a lesson shows now, for «Сообщить об ошибке» (docs/courses/README.md, `slide_number`).
// Apart from course-feedback.ts: the tajweed lesson draws the same carousel without the rest.

const slideNumbers = new Map<string, number>();

/** `number` counts the slides of the whole lesson from 1, across its carousels. */
export function noteSlide(course: string, lesson: string, number: number): void {
  slideNumbers.set(`${course}/${lesson}`, number);
}

/** The slide on screen in this page view; undefined for a lesson without slides. */
export function slideOf(course: string, lesson: string): number | undefined {
  return slideNumbers.get(`${course}/${lesson}`);
}
