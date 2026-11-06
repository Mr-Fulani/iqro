"use client";

import { useI18n } from "../lib/i18n-context";
import { localizedPath } from "../lib/routing";
import { DuaThematicIcon } from "./DuaThematicIcon";
import { IntentPrefetchLink } from "./IntentPrefetchLink";

// The same sections, art and tints as the app's Home tiles.
const SECTIONS = [
  { id: "mushaf", art: "quran", href: "/quran", label: "home.sectionMushaf", tone: "mint" },
  { id: "dua", art: "dua", href: "/dua", label: "nav.dua", tone: "mint" },
  { id: "courses", art: "courses", href: "/courses", label: "nav.courses", tone: "sand" },
  { id: "memorization", art: "memorization", href: "/memorization", label: "nav.memorization", tone: "lavender" },
  { id: "qibla", art: "qibla", href: "/prayer#qibla", label: "prayer.qibla", tone: "sand" },
  { id: "favorites", art: "favorites", href: "/profile#favorites", label: "profile.favoritesTitle", tone: "soft" },
  { id: "calendar", art: "hijri-calendar", href: "/calendar", label: "calendar.title", tone: "sand" },
  { id: "notes", art: "notes", href: "/notes", label: "notes.title", tone: "soft" },
] as const;

export function HomeSections() {
  const { t, locale } = useI18n();
  return (
    <section className="home-sections" aria-labelledby="home-sections-title" data-testid="home-sections">
      <h2 id="home-sections-title" className="home-sections-title">{t("home.sections")}</h2>
      <div className="home-sections-grid">
        {SECTIONS.map((section) => (
          <IntentPrefetchLink
            key={section.id}
            href={localizedPath(locale, section.href)}
            className={`home-section-tile is-${section.tone}`}
            data-testid={`home-section-${section.id}`}
          >
            <span className="home-section-art">
              <DuaThematicIcon topic={section.art} />
            </span>
            <span className="home-section-name">{t(section.label)}</span>
          </IntentPrefetchLink>
        ))}
      </div>
    </section>
  );
}
