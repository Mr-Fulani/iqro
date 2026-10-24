// Thematic courses (docs/courses/README.md): topic courses with notes, made in the admin.
// The prayer and tajweed courses have their own modules and are not part of this API.

const SLUG_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

/** Course slugs the backend never gives out: they would clash with routes and the old courses. */
export const RESERVED_COURSE_SLUGS: ReadonlySet<string> = new Set([
  "salah",
  "tajweed",
  "quiz",
  "courses",
  "new",
  "preview",
  "events",
]);

function isSlug(value: string): boolean {
  return value.length <= 64 && SLUG_PATTERN.test(value);
}

export function isCourseSlug(value: string): boolean {
  return isSlug(value) && !RESERVED_COURSE_SLUGS.has(value);
}

export function isQuizSlug(value: string): boolean {
  return isSlug(value) && !RESERVED_COURSE_SLUGS.has(value);
}
