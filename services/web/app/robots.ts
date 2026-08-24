import type { MetadataRoute } from "next";
import { SUPPORTED_LOCALES } from "../lib/i18n";
import { localizedPath } from "../lib/routing";
import { absoluteSiteUrl } from "../lib/seo";

export const dynamic = "force-dynamic";

export default function robots(): MetadataRoute.Robots {
  const privatePaths = ["/login", "/register", "/profile"];
  return {
    rules: {
      userAgent: "*",
      allow: "/",
      disallow: [
        "/api/",
        "/admin/",
        ...privatePaths,
        ...SUPPORTED_LOCALES.flatMap((locale) =>
          privatePaths.map((path) => localizedPath(locale, path)),
        ),
      ],
    },
    sitemap: absoluteSiteUrl("/sitemap.xml"),
    host: absoluteSiteUrl("/"),
  };
}
