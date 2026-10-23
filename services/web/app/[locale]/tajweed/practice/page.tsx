import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { connection } from "next/server";

import { TajweedPractice } from "@/components/TajweedPractice";
import { isLocale, type Locale } from "@/lib/i18n";
import { getPublishedTajweedCourse, PublicContentNotFoundError } from "@/lib/public-content";
import { localizedPath } from "@/lib/routing";
import { createContentMetadata } from "@/lib/seo";
import { courseLessons, TAJWEED_COURSE_SLUG } from "@/lib/tajweed-course";
import { translate } from "@/lib/translate";
import "../tajweed.css";

export const revalidate = 3_600;

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
  return createContentMetadata(locale, {
    title: translate(locale, "tajweedPractice.title"),
    description: translate(locale, "tajweedPractice.description"),
    path: "/tajweed/practice",
  });
}

export default async function TajweedPracticePage({ params }: { params: Promise<RouteParams> }) {
  // The page is built from the published course; render it per request, like the course page.
  await connection();
  const locale = localeParam((await params).locale);
  const document = await publishedCourse(locale);

  return (
    <div className="tajweed-course-page">
      <nav className="breadcrumbs" aria-label={translate(locale, "tajweedCourse.breadcrumbs")}>
        <ol>
          <li>
            <Link href={localizedPath(locale, "/tajweed")}>{document.course.title}</Link>
          </li>
          <li aria-current="page">{translate(locale, "tajweedPractice.short")}</li>
        </ol>
      </nav>

      <header className="surface tajweed-course-hero">
        <h1>{translate(locale, "tajweedPractice.title")}</h1>
        <p>{translate(locale, "tajweedPractice.description")}</p>
      </header>

      <TajweedPractice
        courseSlug={document.course.slug}
        lessons={courseLessons(document).map((lesson) => ({
          slug: lesson.slug,
          title: lesson.title,
          target: lesson.target,
        }))}
        targets={document.targets}
      />
    </div>
  );
}
