import type { Locale } from "@/lib/i18n";
import { localizedPath } from "@/lib/routing";
import { translate } from "@/lib/translate";

/** A course from a newer release than this page knows: a reload brings the new site code. */
export function CourseOutdated({ locale, path }: { locale: Locale; path: string }) {
  return (
    <div className="courses-page">
      <section className="surface courses-empty" data-testid="course-outdated">
        <h1>{translate(locale, "courses.outdatedTitle")}</h1>
        <p>{translate(locale, "courses.outdatedText")}</p>
        <a href={localizedPath(locale, path)} className="btn btn-primary">{translate(locale, "courses.reload")}</a>
      </section>
    </div>
  );
}
