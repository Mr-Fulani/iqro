"use client";

import { useSyncExternalStore } from "react";
import { useI18n } from "../lib/i18n-context";
import { localizedPath } from "../lib/routing";
import { HomeSectionIcon } from "./HomeSectionIcon";
import { IntentPrefetchLink } from "./IntentPrefetchLink";

// The same sections and line icons as the app's Home tiles; the id is the
// key in lib/home-section-icons.json.
const SECTIONS = [
  { id: "mushaf", href: "/quran", label: "home.sectionMushaf" },
  { id: "dua", href: "/dua", label: "nav.dua" },
  { id: "courses", href: "/courses", label: "nav.courses" },
  { id: "memorization", href: "/memorization", label: "nav.memorization" },
  { id: "qibla", href: "/prayer#qibla", label: "prayer.qibla" },
  { id: "favorites", href: "/profile#favorites", label: "profile.favoritesTitle" },
  { id: "calendar", href: "/calendar", label: "calendar.title" },
  { id: "notes", href: "/notes", label: "notes.title" },
] as const;

const subscribe = () => () => {};

export function HomeSections() {
  const { t, locale } = useI18n();
  // The tiles are drawn in the browser only: they sit below the first screen,
  // and leaving them out of the HTML keeps the home page within the first
  // network round trip (the Lighthouse LCP budget on /ar and /tr).
  const drawn = useSyncExternalStore(subscribe, () => true, () => false);
  return (
    <section className="home-sections" aria-labelledby="home-sections-title" data-testid="home-sections">
      <h2 id="home-sections-title" className="home-sections-title">{t("home.sections")}</h2>
      <div className="home-sections-grid">
        {drawn && SECTIONS.map((section) => (
          <IntentPrefetchLink
            key={section.id}
            href={localizedPath(locale, section.href)}
            className="home-section-tile"
            data-testid={`home-section-${section.id}`}
          >
            <span className="home-section-art">
              <HomeSectionIcon section={section.id} />
            </span>
            <span className="home-section-name">{t(section.label)}</span>
          </IntentPrefetchLink>
        ))}
      </div>
    </section>
  );
}
