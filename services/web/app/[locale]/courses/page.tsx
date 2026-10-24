import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { connection } from "next/server";
import type { ReactNode } from "react";

import { CourseCardProgress, CourseContinueStrip } from "@/components/courses/CourseProgress";
import { isLocale, localeTag, type Locale } from "@/lib/i18n";
import { getPublishedCourse, getPublishedCourses, PublicContentNotFoundError } from "@/lib/public-content";
import { localizedPath } from "@/lib/routing";
import { createPageMetadata } from "@/lib/seo";
import { courseOutline, type CourseListItem, type CourseOutline } from "@/lib/thematic-courses";
import { translate } from "@/lib/translate";
import "./courses.css";

type RouteParams = { locale: string };

function localeParam(value: string): Locale {
  if (!isLocale(value)) notFound();
  return value;
}

/** The published courses with their lesson outlines; the old courses stay when the API is down. */
async function publishedCourses(locale: Locale): Promise<{ course: CourseListItem; outline: CourseOutline | null }[]> {
  let courses: CourseListItem[];
  try {
    courses = await getPublishedCourses(locale);
  } catch (error) {
    if (!(error instanceof PublicContentNotFoundError)) console.error("Courses are temporarily unavailable", error);
    return [];
  }
  return Promise.all(courses.map(async (course) => {
    try {
      const result = await getPublishedCourse(locale, course.slug);
      return { course, outline: result.outdated ? null : courseOutline(result.document) };
    } catch {
      return { course, outline: null };
    }
  }));
}

export async function generateMetadata({ params }: { params: Promise<RouteParams> }): Promise<Metadata> {
  const locale = localeParam((await params).locale);
  return createPageMetadata(locale, {
    titleKey: "courses.title",
    descriptionKey: "courses.description",
    path: "/courses",
  });
}

function CourseIcon({ children }: { children: ReactNode }) {
  return (
    <svg width="34" height="34" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"
      strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      {children}
    </svg>
  );
}

export default async function CoursesPage({ params }: { params: Promise<RouteParams> }) {
  // Only the locale parametrises this page, so `next build` would prerender it
  // without a backend (CI, Docker images). Render it per request instead; the
  // course list itself still comes from the tagged fetch cache.
  await connection();
  const locale = localeParam((await params).locale);
  const courses = await publishedCourses(locale);
  const format = new Intl.NumberFormat(localeTag(locale));
  const outlines = courses.flatMap(({ outline }) => (outline ? [outline] : []));
  // The prayer and tajweed courses keep their own pages and come first.
  const builtIn = [
    {
      href: "/salah",
      title: translate(locale, "nav.salah"),
      summary: translate(locale, "courses.salahSummary"),
      meta: translate(locale, "courses.salahMeta"),
      icon: <><path d="M6 21V9a6 6 0 0 1 12 0v12Z" /><path d="M6 17h12M12 7v3" /></>,
    },
    {
      href: "/tajweed",
      title: translate(locale, "nav.tajweed"),
      summary: translate(locale, "courses.tajweedSummary"),
      meta: translate(locale, "courses.tajweedMeta"),
      icon: <><path d="M4 10c0 5 3.6 8 8 8s8-3 8-8" /><circle cx="9.5" cy="6" r="1.3" fill="currentColor" stroke="none" /><circle cx="14.5" cy="6" r="1.3" fill="currentColor" stroke="none" /></>,
    },
  ];

  return (
    <div className="courses-page">
      <header className="surface courses-hero">
        <p className="eyebrow">{translate(locale, "courses.eyebrow")}</p>
        <h1>{translate(locale, "courses.title")}</h1>
        <p>{translate(locale, "courses.description")}</p>
      </header>

      <CourseContinueStrip courses={outlines} />

      <section aria-labelledby="courses-all-title">
        <h2 id="courses-all-title" className="courses-section-title">{translate(locale, "courses.all")}</h2>
        <ul className="courses-grid">
          {builtIn.map((item) => (
            <li key={item.href}>
              <Link href={localizedPath(locale, item.href)} className="courses-card">
                <span className="courses-card-art courses-card-art-builtin">
                  <span className="courses-card-icon"><CourseIcon>{item.icon}</CourseIcon></span>
                </span>
                <span className="courses-card-body">
                  <span className="courses-card-title">{item.title}</span>
                  <span className="courses-card-summary">{item.summary}</span>
                  <span className="courses-card-meta">{item.meta}</span>
                </span>
              </Link>
            </li>
          ))}
          {courses.map(({ course, outline }) => (
            <li key={course.slug}>
              <Link href={localizedPath(locale, `/courses/${course.slug}`)} className="courses-card">
                <span className="courses-card-art">
                  {course.cover ? (
                    // eslint-disable-next-line @next/next/no-img-element -- a ready 16:9 WebP from the media host
                    <img
                      src={course.cover.thumb_url}
                      srcSet={`${course.cover.thumb_url} 640w, ${course.cover.url} 1280w`}
                      sizes="(max-width: 768px) 100vw, 400px"
                      width={course.cover.width}
                      height={course.cover.height}
                      alt=""
                      loading="lazy"
                      decoding="async"
                    />
                  ) : (
                    <span className="courses-card-icon">
                      <CourseIcon><path d="M12 5c-3-2-6-2-10-1v15c4-1 7-1 10 1 3-2 6-2 10-1V4c-4-1-7-1-10 1Zm0 0v15" /></CourseIcon>
                    </span>
                  )}
                </span>
                <span className="courses-card-body">
                  <span className="courses-card-title">{course.title}</span>
                  <span className="courses-card-summary">{course.summary}</span>
                  <span className="courses-card-meta">
                    {translate(locale, "courses.lessonCount", { count: format.format(course.lesson_count) })}
                    {" · "}
                    {translate(locale, "common.minutes", { count: format.format(course.minutes) })}
                    {course.video_minutes
                      ? ` · ${translate(locale, "courses.videoMinutes", { count: format.format(course.video_minutes) })}`
                      : null}
                  </span>
                  {outline ? <CourseCardProgress course={outline} /> : null}
                </span>
              </Link>
            </li>
          ))}
        </ul>
      </section>

      {courses.length === 0 ? (
        <section className="surface courses-empty" data-testid="courses-empty">
          <span className="courses-card-icon">
            <CourseIcon><path d="M12 5c-3-2-6-2-10-1v15c4-1 7-1 10 1 3-2 6-2 10-1V4c-4-1-7-1-10 1Zm0 0v15" /></CourseIcon>
          </span>
          <h2>{translate(locale, "courses.empty")}</h2>
          <p>{translate(locale, "courses.emptyHint")}</p>
        </section>
      ) : null}
    </div>
  );
}
