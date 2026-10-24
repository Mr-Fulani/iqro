import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";

import { CourseNotes } from "@/components/courses/CourseNotes";
import { CourseOutdated } from "@/components/courses/CourseOutdated";
import { LessonStatusBadge } from "@/components/courses/CourseProgress";
import { LateArabicFont } from "@/components/courses/LateArabicFont";
import { LessonCompleteBar } from "@/components/courses/LessonCompleteBar";
import { LessonMedia } from "@/components/courses/LessonMedia";
import { formatClock } from "@/lib/audio-content";
import { isLocale, localeTag, type Locale } from "@/lib/i18n";
import { getPublishedCourse, PublicContentNotFoundError } from "@/lib/public-content";
import { localizedPath } from "@/lib/routing";
import { createContentMetadata } from "@/lib/seo";
import { isCourseSlug, isLessonSlug, mediaVideo } from "@/lib/thematic-courses";
import { translate } from "@/lib/translate";
import "../../courses.css";

export const revalidate = 3_600;

// Published content is not prerendered at build time; each path is rendered on
// its first request and then served through ISR.
export function generateStaticParams() {
  return [];
}

type RouteParams = { locale: string; course: string; lesson: string };

function parseParams(params: RouteParams): { locale: Locale; course: string; lesson: string } {
  if (!isLocale(params.locale) || !isCourseSlug(params.course) || !isLessonSlug(params.lesson)) notFound();
  return { locale: params.locale, course: params.course, lesson: params.lesson };
}

async function publishedLesson(route: { locale: Locale; course: string; lesson: string }) {
  let result;
  try {
    result = await getPublishedCourse(route.locale, route.course);
  } catch (error) {
    if (error instanceof PublicContentNotFoundError) notFound();
    throw error;
  }
  if (result.outdated) return null;
  const index = result.document.lessons.findIndex((item) => item.slug === route.lesson);
  if (index < 0) notFound();
  return { document: result.document, index };
}

export async function generateMetadata({ params }: { params: Promise<RouteParams> }): Promise<Metadata> {
  const route = parseParams(await params);
  const found = await publishedLesson(route);
  if (!found) {
    return createContentMetadata(route.locale, {
      title: translate(route.locale, "courses.outdatedTitle"),
      description: translate(route.locale, "courses.outdatedText"),
      path: `/courses/${route.course}/${route.lesson}`,
      index: false,
    });
  }
  const { course } = found.document;
  const lesson = found.document.lessons[found.index]!;
  return createContentMetadata(route.locale, {
    title: `${lesson.title} · ${course.title}`,
    description: lesson.summary,
    path: `/courses/${course.slug}/${lesson.slug}`,
    locales: course.languages.filter(isLocale),
  });
}

export default async function CourseLessonPage({ params }: { params: Promise<RouteParams> }) {
  const route = parseParams(await params);
  const found = await publishedLesson(route);
  if (!found) return <CourseOutdated locale={route.locale} path={`/courses/${route.course}/${route.lesson}`} />;
  const { document, index } = found;
  const { course, lessons } = document;
  const lesson = lessons[index]!;
  const previous = lessons[index - 1] ?? null;
  const next = lessons[index + 1] ?? null;
  const format = new Intl.NumberFormat(localeTag(route.locale));
  const lessonHref = (slug: string) => localizedPath(route.locale, `/courses/${course.slug}/${slug}`);
  const video = mediaVideo(lesson.media);

  return (
    <div className="courses-page course-lesson-page">
      <nav className="breadcrumbs" aria-label={translate(route.locale, "courses.breadcrumbs")}>
        <ol>
          <li><Link href={localizedPath(route.locale, "/courses")}>{translate(route.locale, "courses.title")}</Link></li>
          <li><Link href={localizedPath(route.locale, `/courses/${course.slug}`)}>{course.title}</Link></li>
          <li aria-current="page">{lesson.title}</li>
        </ol>
      </nav>

      <div className="course-lesson-layout">
        <article className="course-lesson-main">
          <header className="course-lesson-header">
            <p className="eyebrow">
              {translate(route.locale, "courses.lessonOf", {
                number: format.format(lesson.number),
                total: format.format(lessons.length),
              })}
            </p>
            <h1>{lesson.title}</h1>
            <p className="courses-card-meta">
              {translate(route.locale, "common.minutes", { count: format.format(lesson.minutes) })}
              {video
                ? ` · ${translate(route.locale, "courses.videoDuration", { duration: formatClock(video.duration_ms, format.format) })}`
                : null}
            </p>
          </header>

          <LessonMedia
            blocks={lesson.media}
            locale={route.locale}
            language={course.language}
            courseSlug={course.slug}
            lessonSlug={lesson.slug}
            title={lesson.title}
          />

          <section className="surface course-lesson-notes" aria-labelledby="course-notes-title">
            <h2 id="course-notes-title">{translate(route.locale, "courses.notes")}</h2>
            <LateArabicFont>
              <CourseNotes blocks={lesson.notes} locale={route.locale} />
            </LateArabicFont>
            {lesson.sources.length ? (
              <div className="course-lesson-sources">
                <h3>{translate(route.locale, "courses.sources")}</h3>
                <ol>
                  {lesson.sources.map((source, item) => <li key={item} dir="auto">{source}</li>)}
                </ol>
              </div>
            ) : null}
          </section>

          <LessonCompleteBar
            courseSlug={course.slug}
            courseVersion={course.version}
            lessonSlug={lesson.slug}
            previous={previous ? { slug: previous.slug, title: previous.title } : null}
            next={next ? { slug: next.slug, title: next.title } : null}
          />
        </article>

        <aside className="surface course-outline" aria-labelledby="course-outline-title">
          <h2 id="course-outline-title">{translate(route.locale, "courses.lessons")}</h2>
          <ol>
            {lessons.map((item) => (
              <li key={item.slug}>
                <Link
                  href={lessonHref(item.slug)}
                  aria-current={item.slug === lesson.slug ? "page" : undefined}
                >
                  <span className="course-outline-number" aria-hidden="true">{format.format(item.number)}</span>
                  <span className="course-outline-title">{item.title}</span>
                  <LessonStatusBadge courseSlug={course.slug} lessonSlug={item.slug} />
                </Link>
              </li>
            ))}
          </ol>
        </aside>
      </div>
    </div>
  );
}
