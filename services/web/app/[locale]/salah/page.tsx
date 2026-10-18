import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { connection } from "next/server";

import { SalahCourseProgress, SalahLessonStatusBadge } from "@/components/SalahCourseProgress";
import { isLocale, localeTag, translate, type Locale } from "@/lib/i18n";
import { getPublishedSalahCourse, PublicContentNotFoundError } from "@/lib/public-content";
import { localizedPath } from "@/lib/routing";
import { orderedLessons, SALAH_COURSE_SLUG, type SalahLesson } from "@/lib/salah";
import { createPageMetadata } from "@/lib/seo";
import "./salah.css";

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
    return await getPublishedSalahCourse(locale, SALAH_COURSE_SLUG);
  } catch (error) {
    if (error instanceof PublicContentNotFoundError) notFound();
    throw error;
  }
}

export async function generateMetadata({ params }: { params: Promise<RouteParams> }): Promise<Metadata> {
  const locale = localeParam((await params).locale);
  return createPageMetadata(locale, {
    titleKey: "salah.title",
    descriptionKey: "salah.description",
    path: "/salah",
  });
}

function lessonMeta(locale: Locale, lesson: SalahLesson): string {
  const format = new Intl.NumberFormat(localeTag(locale));
  const count = lesson.prayer?.rakats
    ? translate(locale, "salah.rakatCount", { count: format.format(lesson.prayer.rakats) })
    : translate(locale, "salah.stepCount", { count: format.format(lesson.steps.length) });
  return [
    translate(locale, "common.minutes", { count: format.format(lesson.minutes) }),
    lesson.prayer?.kind_title,
    count,
  ].filter(Boolean).join(" · ");
}

export default async function SalahCoursePage({ params }: { params: Promise<RouteParams> }) {
  // Only the locale parametrises this page, so `next build` would prerender it
  // without a backend (CI, Docker images). Render it per request instead; the
  // course document itself still comes from the tagged fetch cache.
  await connection();
  const locale = localeParam((await params).locale);
  const document = await publishedCourse(locale);
  const lessons = new Map(document.lessons.map((lesson) => [lesson.slug, lesson]));
  const reviewedAt = new Intl.DateTimeFormat(localeTag(locale), { dateStyle: "long" })
    .format(new Date(document.course.reviewed_at));

  return (
    <div className="salah-page">
      <header className="surface salah-hero">
        <p className="eyebrow">{translate(locale, "salah.eyebrow")}</p>
        <h1>{translate(locale, "salah.title")}</h1>
        <p>{translate(locale, "salah.description")}</p>
        <p className="salah-provenance">
          {translate(locale, "salah.source", { source: document.course.source_title })}
          {" · "}
          {translate(locale, "salah.reviewed", { reviewer: document.course.reviewed_by, date: reviewedAt })}
        </p>
        <SalahCourseProgress
          lessons={orderedLessons(document).map((lesson) => ({
            slug: lesson.slug,
            steps: lesson.steps.map((step) => ({ slug: step.slug })),
          }))}
        />
      </header>

      {document.sections.map((section) => (
        <section key={section.slug} className="surface salah-section" aria-labelledby={`salah-section-${section.slug}`}>
          <h2 id={`salah-section-${section.slug}`}>{section.title}</h2>
          <ol className="salah-lesson-list">
            {section.lessons.map((slug) => {
              const lesson = lessons.get(slug)!;
              return (
                <li key={slug}>
                  <Link href={localizedPath(locale, `/salah/${slug}`)} className="salah-lesson-card">
                    <div className="salah-lesson-head">
                      <h3>{lesson.title}</h3>
                      <SalahLessonStatusBadge slug={slug} />
                    </div>
                    <p className="salah-lesson-summary">{lesson.summary}</p>
                    <p className="salah-lesson-meta">{lessonMeta(locale, lesson)}</p>
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
