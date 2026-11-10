import { courseSitemapEntries } from "@/lib/courses-sitemap";
import { SUPPORTED_LOCALES, type Locale } from "@/lib/i18n";
import { getPublishedCourse, getPublishedCourseCatalog } from "@/lib/public-content";
import { xmlResponse } from "@/lib/sitemap-xml";

export const revalidate = 3_600;

export async function GET() {
  try {
    const catalogs = await Promise.all(SUPPORTED_LOCALES.map(getPublishedCourseCatalog));
    const localesBySlug = new Map<string, Locale[]>();
    catalogs.forEach(({ courses }, index) => {
      for (const { slug } of courses) {
        localesBySlug.set(slug, [...(localesBySlug.get(slug) ?? []), SUPPORTED_LOCALES[index]]);
      }
    });
    const entries = await Promise.all(
      [...localesBySlug].map(async ([slug, locales]) => {
        // The lessons are the same on every language of a release.
        const result = await getPublishedCourse(locales[0], slug);
        if (result.outdated) return "";
        return courseSitemapEntries(
          slug,
          result.document.lessons.map((lesson) => lesson.slug),
          locales,
        );
      }),
    );
    return xmlResponse(
      `<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">${entries.join("")}</urlset>`,
    );
  } catch {
    return xmlResponse(
      `<?xml version="1.0" encoding="UTF-8"?><error>Courses sitemap is temporarily unavailable</error>`,
      503,
    );
  }
}
