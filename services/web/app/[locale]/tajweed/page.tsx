import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { connection } from "next/server";

import { TajweedCourseProgress, TajweedLessonStatusBadge } from "@/components/TajweedCourseProgress";
import { isLocale, localeTag, type Locale } from "@/lib/i18n";
import { getPublishedTajweedCourse, PublicContentNotFoundError } from "@/lib/public-content";
import { localizedPath } from "@/lib/routing";
import { createPageMetadata } from "@/lib/seo";
import { courseLessons, lessonOutline, TAJWEED_COURSE_SLUG } from "@/lib/tajweed-course";
import { translate } from "@/lib/translate";
import "./tajweed.css";

export const revalidate = 3_600;

// Published content is not prerendered at build time; each path is rendered on
// its first request and then served through ISR.
export function generateStaticParams() {
  return [];
}

type RouteParams = { locale: string };

function localeParam(value: string): Locale {
  if (!isLocale(value)) notFound();
  return value;
}

async function publishedCourse(locale: Locale) {
  try {
    return await getPublishedTajweedCourse(locale, TAJWEED_COURSE_SLUG);
  } catch (error) {
    if (error instanceof PublicContentNotFoundError) notFound();
    throw error;
  }
}

export async function generateMetadata({ params }: { params: Promise<RouteParams> }): Promise<Metadata> {
  const locale = localeParam((await params).locale);
  return createPageMetadata(locale, {
    titleKey: "tajweedCourse.title",
    descriptionKey: "tajweedCourse.description",
    path: "/tajweed",
  });
}

export default async function TajweedCoursePage({ params }: { params: Promise<RouteParams> }) {
  // Only the locale parametrises this page, so `next build` would prerender it
  // without a backend (CI, Docker images). Render it per request instead; the
  // course document itself still comes from the tagged fetch cache.
  await connection();
  const locale = localeParam((await params).locale);
  const document = await publishedCourse(locale);
  const lessons = new Map(document.lessons.map((lesson) => [lesson.slug, lesson]));
  const minutes = new Intl.NumberFormat(localeTag(locale));

  return (
    <div className="tajweed-course-page">
      <header className="surface tajweed-course-hero">
        <p className="eyebrow">{translate(locale, "tajweedCourse.eyebrow")}</p>
        <h1>{document.course.title}</h1>
        <p>{document.course.summary}</p>
        {document.course.review_status === "pending_teacher_review" ? (
          <p className="tajweed-review-note">{translate(locale, "tajweed.reviewNote")}</p>
        ) : null}
        <TajweedCourseProgress lessons={courseLessons(document).map(lessonOutline)} />
      </header>

      {document.sections.map((section) => (
        <section
          key={section.slug}
          className="surface tajweed-course-section"
          aria-labelledby={`tajweed-section-${section.slug}`}
        >
          <h2 id={`tajweed-section-${section.slug}`}>{section.title}</h2>
          <ol className="tajweed-course-lessons">
            {section.lessons.map((slug) => {
              const lesson = lessons.get(slug)!;
              const target = document.targets[lesson.target]!;
              return (
                <li key={slug}>
                  <Link href={localizedPath(locale, `/tajweed/${slug}`)} className="tajweed-course-card">
                    <div className="tajweed-course-card-head">
                      <h3>
                        <span className="tajweed-dot" style={{ background: target.color }} aria-hidden="true" />
                        {lesson.title}
                      </h3>
                      <TajweedLessonStatusBadge slug={slug} />
                    </div>
                    <p className="tajweed-course-summary">{lesson.summary}</p>
                    <p className="tajweed-course-meta">
                      {translate(locale, "common.minutes", { count: minutes.format(lesson.minutes) })}
                    </p>
                  </Link>
                </li>
              );
            })}
          </ol>
        </section>
      ))}
    </div>
  );
}
