import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";

import { CourseNotes } from "@/components/courses/CourseNotes";
import { LessonMedia } from "@/components/courses/LessonMedia";
import { TajweedLessonPlayer } from "@/components/TajweedLessonPlayer";
import { isLocale, localeTag, type Locale } from "@/lib/i18n";
import { getPublishedTajweedCourse, PublicContentNotFoundError } from "@/lib/public-content";
import { localizedPath } from "@/lib/routing";
import { createContentMetadata } from "@/lib/seo";
import { isTajweedLessonSlug, nextTajweedLesson, TAJWEED_COURSE_SLUG } from "@/lib/tajweed-course";
import { translate } from "@/lib/translate";
import "../tajweed.css";
import "@/components/courses/lesson-media.css";
import "@/components/courses/course-notes.css";

export const revalidate = 3_600;

// Published content is not prerendered at build time; each path is rendered on
// its first request and then served through ISR.
export function generateStaticParams() {
  return [];
}

type RouteParams = { locale: string; lesson: string };

function parseParams(params: RouteParams): { locale: Locale; lesson: string } {
  if (!isLocale(params.locale) || !isTajweedLessonSlug(params.lesson)) notFound();
  return { locale: params.locale, lesson: params.lesson };
}

async function publishedLesson(route: { locale: Locale; lesson: string }) {
  let document;
  try {
    document = await getPublishedTajweedCourse(route.locale, TAJWEED_COURSE_SLUG);
  } catch (error) {
    if (error instanceof PublicContentNotFoundError) notFound();
    throw error;
  }
  const lesson = document.lessons.find((item) => item.slug === route.lesson);
  if (!lesson) notFound();
  return { document, lesson };
}

export async function generateMetadata({ params }: { params: Promise<RouteParams> }): Promise<Metadata> {
  const route = parseParams(await params);
  const { document, lesson } = await publishedLesson(route);
  return createContentMetadata(route.locale, {
    title: `${lesson.title} · ${document.course.title}`,
    description: lesson.summary,
    path: `/tajweed/${lesson.slug}`,
  });
}

export default async function TajweedLessonPage({ params }: { params: Promise<RouteParams> }) {
  const route = parseParams(await params);
  const { document, lesson } = await publishedLesson(route);
  const next = nextTajweedLesson(document, lesson.slug);
  const format = new Intl.NumberFormat(localeTag(route.locale));

  return (
    <div className="tajweed-course-page">
      <nav className="breadcrumbs" aria-label={translate(route.locale, "tajweedCourse.breadcrumbs")}>
        <ol>
          <li>
            <Link href={localizedPath(route.locale, "/tajweed")}>{document.course.title}</Link>
          </li>
          <li aria-current="page">{lesson.title}</li>
        </ol>
      </nav>

      <header className="surface tajweed-course-hero">
        <h1>{lesson.title}</h1>
        <p>{lesson.summary}</p>
        <p className="tajweed-course-meta">
          {translate(route.locale, "common.minutes", { count: format.format(lesson.minutes) })}
        </p>
      </header>

      <TajweedLessonPlayer
        courseSlug={document.course.slug}
        courseVersion={document.course.version}
        lesson={lesson}
        target={document.targets[lesson.target]!}
        reviewPending={document.course.review_status === "pending_teacher_review"}
        nextLesson={next ? { slug: next.slug, title: next.title } : null}
        // The rule step shows them above the explanation, as the app does; the video remembers
        // its place under courses.position.tajweed, a slug no thematic course can have.
        media={
          <LessonMedia
            blocks={lesson.media}
            locale={route.locale}
            language={document.course.language}
            courseSlug={document.course.slug}
            lessonSlug={lesson.slug}
            title={lesson.title}
          />
        }
        // Server HTML like the media: the «!»/«?» notes and links need no client JS. An Arabic
        // lesson keeps the interface font, as its plain paragraphs had.
        explanation={lesson.explanation_blocks ? (
          <CourseNotes
            blocks={lesson.explanation_blocks}
            locale={route.locale}
            id="tajweed-explanation"
            plainArabic={route.locale === "ar"}
          />
        ) : null}
        how={lesson.how_blocks ? (
          <CourseNotes blocks={lesson.how_blocks} locale={route.locale} id="tajweed-how" plainArabic={route.locale === "ar"} />
        ) : null}
      />
    </div>
  );
}
