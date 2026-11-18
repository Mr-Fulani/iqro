"use client";

import { forAudience, isFinished } from "../lib/announcements";
import { useAuth } from "../lib/auth-context";
import { useI18n } from "../lib/i18n-context";
import { localizedPath } from "../lib/routing";
import { useActiveAnnouncements, useAnnouncementState } from "./announcements/announcement-store";
import { AnnouncementIcon } from "./announcements/AnnouncementParts";
import { DuaThematicIcon } from "./DuaThematicIcon";
import { IntentPrefetchLink } from "./IntentPrefetchLink";
import { MoreRow } from "./MoreRow";

// The same tools, order, illustrations and tints as the app's More screen
// (clients/iqro_mobile/lib/features/more/more_screen.dart).
const TOOLS = [
  { href: "/calendar", art: "hijri-calendar", label: "more.hijriCalendar", tone: "sand" },
  { href: "/prayer", art: "prayer", label: "more.prayerTimes", tone: "sand" },
  { href: "/courses", art: "courses", label: "nav.courses", tone: "sand" },
  { href: "/memorization", art: "memorization", label: "nav.memorization", tone: "lavender" },
  { href: "/dua", art: "dua", label: "nav.dua", tone: "mint" },
  { href: "/profile#favorites", art: "favorites", label: "profile.favoritesTitle", tone: "soft" },
  { href: "/notes", art: "notes", label: "notes.title", tone: "soft" },
  { href: "/names", art: "quran", label: "nav.namesOfAllah", tone: "soft" },
] as const;

/** The phone's More tab as a screen, like the app's. */
export default function MorePage() {
  const { locale, t } = useI18n();
  const { session } = useAuth();
  const announcementState = useAnnouncementState();
  const unreadNews = forAudience(useActiveAnnouncements(locale), session?.user.status === "active").some(
    (item) => !isFinished(item, announcementState),
  );
  return (
    <div className="more-page">
      <header className="more-head">
        <h1>{t("nav.more")}</h1>
        <p>{t("more.subtitle")}</p>
      </header>

      <div className="more-card">
        <MoreRow
          href="/news"
          icon={<AnnouncementIcon name="sparkle" size={22} />}
          title={t("news.title")}
          subtitle={t("news.description")}
          trailing={unreadNews ? <span className="more-row-new" role="img" aria-label={t("news.unread")} /> : null}
          testId="more-news"
        />
      </div>

      <div className="more-tools" data-testid="more-tools">
        {TOOLS.map((tool) => (
          <IntentPrefetchLink
            key={tool.href}
            href={localizedPath(locale, tool.href)}
            className={`more-tool more-tool-${tool.tone}`}
          >
            <span className="more-tool-art"><DuaThematicIcon topic={tool.art} /></span>
            <strong>{t(tool.label)}</strong>
            <span className="more-tool-arrow" aria-hidden="true">→</span>
          </IntentPrefetchLink>
        ))}
      </div>

      <h2 className="more-section-title">{t("more.account")}</h2>
      <div className="more-card">
        <MoreRow href="/profile" icon="profile" title={t("more.profile")} subtitle={t("more.profileHint")} />
        <MoreRow href="/profile#share-app" icon="share" title={t("more.share")} subtitle={t("more.shareHint")} />
        <MoreRow
          href="/settings"
          icon="settings"
          title={t("home.settings")}
          subtitle={t("settings.language")}
          testId="more-settings"
        />
      </div>

      <div className="more-soon">
        <span>
          <strong>{t("more.booksQuizzes")}</strong>
          <small>{t("more.soon")}</small>
        </span>
        <span className="more-soon-chip">{t("more.soon")}</span>
      </div>
    </div>
  );
}
