import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";

import { SalahStepPlayer } from "@/components/SalahStepPlayer";
import { isLocale, localeTag, translate, type Locale } from "@/lib/i18n";
import { getPublishedSalahCourse, PublicContentNotFoundError } from "@/lib/public-content";
import { localizedPath } from "@/lib/routing";
import {
  findSalahLesson,
  isSalahSlug,
  nextSalahLesson,
  SALAH_COURSE_SLUG,
  salahLessonBundle,
} from "@/lib/salah";
import { createContentMetadata } from "@/lib/seo";
import "../salah.css";

export const revalidate = 3_600;

// Published content is not prerendered at build time; each path is rendered on
// its first request and then served through ISR.
export function generateStaticParams() {
  return [];
}

type RouteParams = { locale: string; lesson: string };

function parseParams(params: RouteParams): { locale: Locale; lesson: string } {
  if (!isLocale(params.locale) || !isSalahSlug(params.lesson)) notFound();
  return { locale: params.locale, lesson: params.lesson };
}

async function publishedLesson(route: { locale: Locale; lesson: string }) {
  let document;
  try {
    document = await getPublishedSalahCourse(route.locale, SALAH_COURSE_SLUG);
  } catch (error) {
    if (error instanceof PublicContentNotFoundError) notFound();
    throw error;
  }
  const lesson = findSalahLesson(document, route.lesson);
  if (!lesson) notFound();
  return { document, lesson };
}

export async function generateMetadata({ params }: { params: Promise<RouteParams> }): Promise<Metadata> {
  const route = parseParams(await params);
  const { lesson } = await publishedLesson(route);
  return createContentMetadata(route.locale, {
    title: `${lesson.title} · ${translate(route.locale, "salah.title")}`,
    description: lesson.summary,
    path: `/salah/${lesson.slug}`,
  });
}

export default async function SalahLessonPage({ params }: { params: Promise<RouteParams> }) {
  const route = parseParams(await params);
  const { document, lesson } = await publishedLesson(route);
  const next = nextSalahLesson(document, lesson.slug);
  const format = new Intl.NumberFormat(localeTag(route.locale));

  return (
    <div className="salah-page">
      <nav className="breadcrumbs" aria-label={translate(route.locale, "salah.breadcrumbs")}>
        <ol>
          <li>
            <Link href={localizedPath(route.locale, "/salah")}>{translate(route.locale, "salah.title")}</Link>
          </li>
          <li aria-current="page">{lesson.title}</li>
        </ol>
      </nav>

      <header className="surface salah-hero salah-lesson-hero">
        <h1>{lesson.title}</h1>
        <p>{lesson.summary}</p>
        <p className="salah-lesson-meta">
          {translate(route.locale, "common.minutes", { count: format.format(lesson.minutes) })}
          {" · "}
          {lesson.prayer?.kind_title ? `${lesson.prayer.kind_title} · ` : null}
          {lesson.prayer
            ? translate(route.locale, "salah.rakatCount", { count: format.format(lesson.prayer.rakats) })
            : translate(route.locale, "salah.stepCount", { count: format.format(lesson.steps.length) })}
        </p>
      </header>

      <SalahStepPlayer
        bundle={salahLessonBundle(document, lesson)}
        nextLesson={next ? { slug: next.slug, title: next.title } : null}
      />
    </div>
  );
}
