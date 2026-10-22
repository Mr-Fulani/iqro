"use client";

import { useEffect, useState } from "react";
import {
  ANNOUNCEMENT_STORAGE_KEY,
  cardAnnouncement,
  externalLink,
  forAudience,
  modalAnnouncement,
  type Announcement,
} from "../../lib/announcements";
import { useAuth } from "../../lib/auth-context";
import { useI18n } from "../../lib/i18n-context";
import { IntentPrefetchLink } from "../IntentPrefetchLink";
import {
  clickAnnouncement,
  countImpression,
  dismissAnnouncement,
  updateAnnouncementState,
  useAnnouncementState,
  useReceiptSync,
} from "./announcement-store";
import { AnnouncementDialog } from "./AnnouncementDialog";
import { AnnouncementPicture, KIND_LABELS } from "./AnnouncementParts";

// Runs before the first paint: a card this visitor already closed or read must
// not flash and then collapse the page (the home page is cached for everyone).
const hideScript = (id: string) =>
  `(function(){try{var s=JSON.parse(localStorage.getItem(${JSON.stringify(ANNOUNCEMENT_STORAGE_KEY)})||"{}");` +
  `if((s.read&&s.read[${JSON.stringify(id)}])||(s.dismissed&&s.dismissed[${JSON.stringify(id)}])){` +
  `var c=document.currentScript.previousElementSibling;if(c)c.hidden=true}}catch(e){}})();`;

const DESKTOP = "(min-width: 769px)";

/** The desktop card under the hero; phones get the bubble in the header instead. */
export function AnnouncementCard({ items }: { items: Announcement[] }) {
  const { t, formatDate } = useI18n();
  const { session } = useAuth();
  const state = useAnnouncementState();
  const [explained, setExplained] = useState<Announcement | null>(null);
  const signedIn = session?.user.status === "active";
  useReceiptSync(session?.user.id);
  const audience = forAudience(items, signedIn);
  const item = cardAnnouncement(audience, state);

  useEffect(() => {
    if (!item || !window.matchMedia(DESKTOP).matches) return;
    countImpression(item, "card");
  }, [item]);

  useEffect(() => {
    if (!window.matchMedia(DESKTOP).matches) return;
    const due = modalAnnouncement(audience, state, Date.now());
    if (!due) return;
    updateAnnouncementState((value) => ({ ...value, lastModalAt: new Date().toISOString() }));
    setExplained(due);
    // Decided once per page view; later marks must not reopen it.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const dialog = explained ? (
    <AnnouncementDialog items={[explained]} surface="modal" onClose={() => setExplained(null)} />
  ) : null;
  if (!item) return dialog;

  const internal = item.action.web_path;
  const external = externalLink(item, "card");
  const label = item.action.label;

  return (
    <>
      <section
        key={item.id}
        className="surface announcement-card"
        aria-labelledby={`announcement-${item.id}`}
        data-announcement-card={item.id}
        suppressHydrationWarning
      >
        <AnnouncementPicture item={item} size={104} />
        <div className="announcement-card-text">
          <div className="announcement-card-meta">
            <span className="announcement-chip">{t(KIND_LABELS[item.kind])}</span>
            <time dateTime={item.starts_at}>{formatDate(item.starts_at, { day: "numeric", month: "long" })}</time>
          </div>
          <h2 id={`announcement-${item.id}`} className="announcement-card-title">{item.title}</h2>
          <p className="announcement-summary">{item.summary}</p>
          <div className="announcement-card-actions">
            {internal && label ? (
              <IntentPrefetchLink href={internal} className="btn btn-primary" onClick={() => clickAnnouncement(item, "card")}>
                {label}
              </IntentPrefetchLink>
            ) : null}
            {external && label ? (
              <a href={external} target="_blank" rel="noopener noreferrer" className="btn btn-primary" onClick={() => clickAnnouncement(item, "card")}>
                {label} ↗
              </a>
            ) : null}
            {item.steps.length || item.body ? (
              <button type="button" className="btn btn-secondary" onClick={() => setExplained(item)}>
                {item.steps.length ? t("news.howTo") : t("news.more")}
              </button>
            ) : null}
          </div>
        </div>
        <button
          type="button"
          className="announcement-close announcement-card-close"
          onClick={() => dismissAnnouncement(item, "card")}
          aria-label={t("news.hide")}
          title={t("news.hide")}
        >
          ×
        </button>
      </section>
      <script dangerouslySetInnerHTML={{ __html: hideScript(item.id) }} suppressHydrationWarning />
      {dialog}
    </>
  );
}
