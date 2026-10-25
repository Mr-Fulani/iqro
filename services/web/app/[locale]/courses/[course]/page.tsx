import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";

import { CourseOutdated } from "@/components/courses/CourseOutdated";
import { CourseProgressSummary, LessonStatusBadge } from "@/components/courses/CourseProgress";
import { CourseRating } from "@/components/courses/CourseRating";
import { CourseShareButton } from "@/components/courses/CourseShareButton";
import { isLocale, localeTag, type Locale } from "@/lib/i18n";
import { getPublishedCourse, PublicContentNotFoundError } from "@/lib/public-content";
import { localizedPath } from "@/lib/routing";
import { absoluteSiteUrl, createContentMetadata } from "@/lib/seo";
import { formatClock } from "@/lib/audio-content";
import { courseOutline, isCourseSlug, videoMinutes } from "@/lib/thematic-courses";
import { translate } from "@/lib/translate";
import "../courses.css";

export const revalidate = 3_600;

// Published content is not prerendered at build time; each path is rendered on
// its first request and then served through ISR.
export function generateStaticParams() {
  return [];
}

type RouteParams = { locale: string; course: string };

function parseParams(params: RouteParams): { locale: Locale; course: string } {
  if (!isLocale(params.locale) || !isCourseSlug(params.course)) notFound();
  return { locale: params.locale, course: params.course };
}

async function publishedCourse(route: { locale: Locale; course: string }) {
  try {
    return await getPublishedCourse(route.locale, route.course);
  } catch (error) {
    if (error instanceof PublicContentNotFoundError) notFound();
    throw error;
  }
}

export async function generateMetadata({ params }: { params: Promise<RouteParams> }): Promise<Metadata> {
  const route = parseParams(await params);
  const result = await publishedCourse(route);
  if (result.outdated) {
    return createContentMetadata(route.locale, {
      title: translate(route.locale, "courses.outdatedTitle"),
      description: translate(route.locale, "courses.outdatedText"),
      path: `/courses/${route.course}`,
      index: false,
    });
  }
  const { course } = result.document;
  return createContentMetadata(route.locale, {
    title: course.title,
    description: course.summary,
    path: `/courses/${course.slug}`,
    locales: course.languages.filter(isLocale),
    image: course.cover ?? undefined,
  });
}

export default async function CoursePage({ params }: { params: Promise<RouteParams> }) {
  const route = parseParams(await params);
  const result = await publishedCourse(route);
  if (result.outdated) return <CourseOutdated locale={route.locale} path={`/courses/${route.course}`} />;
  const { document } = result;
  const { course } = document;
  const format = new Intl.NumberFormat(localeTag(route.locale));
  const minutes = document.lessons.reduce((total, lesson) => total + lesson.minutes, 0);
  const video = videoMinutes(document.lessons);

  return (
    <div className="courses-page">
      <nav className="breadcrumbs" aria-label={translate(route.locale, "courses.breadcrumbs")}>
        <ol>
          <li><Link href={localizedPath(route.locale, "/courses")}>{translate(route.locale, "courses.title")}</Link></li>
          <li aria-current="page">{course.title}</li>
        </ol>
      </nav>

      <header className={`surface course-hero${course.cover ? " has-cover" : ""}`}>
        <div className="course-hero-copy">
          <p className="eyebrow">{translate(route.locale, "courses.eyebrow")}</p>
          <h1>{course.title}</h1>
          <p>{course.summary}</p>
          <p className="courses-card-meta">
            {translate(route.locale, "courses.lessonCount", { count: format.format(document.lessons.length) })}
            {" · "}
            {translate(route.locale, "common.minutes", { count: format.format(minutes) })}
            {video ? ` · ${translate(route.locale, "courses.videoMinutes", { count: format.format(video) })}` : null}
          </p>
          {course.source ? (
            <p className="course-source">
              <strong>{translate(route.locale, "courses.source")}:</strong> {course.source}
            </p>
          ) : null}
          <CourseProgressSummary course={courseOutline(document)} />
          <CourseShareButton
            title={course.title}
            text={course.summary}
            url={absoluteSiteUrl(localizedPath(route.locale, `/courses/${course.slug}`))}
          />
        </div>
        {course.cover ? (
          // eslint-disable-next-line @next/next/no-img-element -- a ready 16:9 WebP from the media host
          <img
            className="course-hero-cover"
            src={course.cover.url}
            srcSet={`${course.cover.thumb_url} 640w, ${course.cover.url} 1280w`}
            sizes="(max-width: 768px) 100vw, 420px"
            width={course.cover.width}
            height={course.cover.height}
            alt=""
            fetchPriority="high"
          />
        ) : null}
      </header>

      <section className="surface course-lessons" aria-labelledby="course-lessons-title">
        <h2 id="course-lessons-title">{translate(route.locale, "courses.lessons")}</h2>
        <ol className="course-lesson-list">
          {document.lessons.map((lesson) => (
            <li key={lesson.slug}>
              <Link href={localizedPath(route.locale, `/courses/${course.slug}/${lesson.slug}`)} className="course-lesson-card">
                <span className="course-lesson-number" aria-hidden="true">{format.format(lesson.number)}</span>
                <span className="course-lesson-copy">
                  <span className="course-lesson-title">{lesson.title}</span>
                  <span className="course-lesson-summary">{lesson.summary}</span>
                  <span className="courses-card-meta">
                    {translate(route.locale, "common.minutes", { count: format.format(lesson.minutes) })}
                    {lesson.video
                      ? ` · ${translate(route.locale, "courses.videoDuration", { duration: formatClock(lesson.video.duration_ms, format.format) })}`
                      : null}
                  </span>
                </span>
                <LessonStatusBadge courseSlug={course.slug} lessonSlug={lesson.slug} />
              </Link>
            </li>
          ))}
        </ol>
      </section>

      <CourseRating
        courseSlug={course.slug}
        language={course.language}
        lessonSlugs={document.lessons.map((lesson) => lesson.slug)}
      />
    </div>
  );
}
