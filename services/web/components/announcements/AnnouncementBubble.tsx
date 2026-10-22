"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import {
  bubbleAnnouncements,
  forAudience,
  readBubbleSession,
  recordBubbleShown,
  writeBubbleSession,
  type Announcement,
} from "../../lib/announcements";
import { useAuth } from "../../lib/auth-context";
import { useI18n } from "../../lib/i18n-context";
import {
  countImpression,
  updateAnnouncementState,
  useActiveAnnouncements,
  useAnnouncementState,
  useReceiptSync,
} from "./announcement-store";
import { AnnouncementDialog } from "./AnnouncementDialog";
import { AnnouncementIcon } from "./AnnouncementParts";

const PHONE = "(max-width: 768px)";
const POP_MS = 320;

/**
 * The live bubble in the top corner of the home screen on a phone. A tap pops
 * it and opens the window; it comes back by the admin's frequency until read.
 */
export function AnnouncementBubble() {
  const { locale, t } = useI18n();
  const { session } = useAuth();
  const active = useActiveAnnouncements(locale);
  const state = useAnnouncementState();
  const [shownThisSession, setShownThisSession] = useState<Set<string> | null>(null);
  // The moment this page opened: frequency is judged once per view.
  const [openedAt, setOpenedAt] = useState(0);
  const [phase, setPhase] = useState<"idle" | "popping" | "open">("idle");
  const [opened, setOpened] = useState<Announcement[]>([]);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useReceiptSync(session?.user.id);

  useEffect(() => {
    if (window.matchMedia(PHONE).matches) {
      setOpenedAt(Date.now());
      setShownThisSession(readBubbleSession());
    }
    return () => {
      if (timer.current) clearTimeout(timer.current);
    };
  }, []);

  const items = useMemo(
    () =>
      shownThisSession
        ? bubbleAnnouncements(forAudience(active, session?.user.status === "active"), state, openedAt, shownThisSession)
        : [],
    [active, openedAt, session, shownThisSession, state],
  );

  useEffect(() => {
    if (!shownThisSession || !items.length) return;
    const fresh = items.filter((item) => !shownThisSession.has(item.id));
    if (!fresh.length) return;
    updateAnnouncementState((value) => recordBubbleShown(value, fresh, Date.now(), shownThisSession));
    const next = new Set([...shownThisSession, ...fresh.map((item) => item.id)]);
    writeBubbleSession(next);
    setShownThisSession(next);
    for (const item of fresh) countImpression(item, "bubble");
  }, [items, shownThisSession]);

  const dialog =
    phase === "open" && opened.length ? (
      <AnnouncementDialog items={opened} surface="bubble" onClose={() => setPhase("idle")} />
    ) : null;
  if (!items.length || phase === "open") return dialog;

  const first = items[0];
  const portrait = first.bubble.icon === "portrait" && first.image ? first.image.thumb_url || first.image.url : null;

  return (
    <div className="announcement-bubble-slot">
      <button
        type="button"
        className={`announcement-bubble${phase === "popping" ? " is-popping" : ""}`}
        aria-label={t("news.bubble", { count: items.length })}
        data-testid="announcement-bubble"
        onClick={() => {
          if (phase !== "idle") return;
          setOpened(items);
          const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
          setPhase("popping");
          timer.current = setTimeout(() => setPhase("open"), reduced ? 0 : POP_MS);
        }}
      >
        <span className="announcement-bubble-rim" aria-hidden="true" />
        <span className="announcement-bubble-face" aria-hidden="true">
          {portrait ? (
            // eslint-disable-next-line @next/next/no-img-element -- the server-made 96 px thumbnail.
            <img src={portrait} alt="" width={34} height={34} />
          ) : (
            <AnnouncementIcon name={first.bubble.icon === "portrait" ? "headphones" : first.bubble.icon} size={20} />
          )}
        </span>
        {items.length > 1 ? <span className="announcement-bubble-count" aria-hidden="true">{items.length}</span> : null}
      </button>
      {phase === "popping" ? (
        <span className="announcement-bubble-burst" aria-hidden="true">
          {Array.from({ length: 6 }, (_, index) => <span key={index} className={`drop drop-${index + 1}`} />)}
        </span>
      ) : null}
    </div>
  );
}
