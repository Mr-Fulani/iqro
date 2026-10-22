"use client";

import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
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
 * The live bubble that floats slowly over the home screen on a phone, from the
 * top corner. A tap pops it and opens the window; it comes back by the admin's
 * frequency until read. It lives in its own layer, not in the page flow.
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
  // Rises with two big bobs only the first time it shows in this visit.
  const [entering, setEntering] = useState(false);
  // Where the bubble was when tapped: the window grows from there.
  const [origin, setOrigin] = useState<{ x: number; y: number } | null>(null);
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

  useLayoutEffect(() => {
    if (shownThisSession && items.some((item) => !shownThisSession.has(item.id))) setEntering(true);
  }, [items, shownThisSession]);

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
      <AnnouncementDialog items={opened} surface="bubble" origin={origin} onClose={() => setPhase("idle")} />
    ) : null;
  if (!items.length || phase === "open") return dialog;

  const first = items[0];
  const portrait = first.bubble.icon === "portrait" && first.image ? first.image.thumb_url || first.image.url : null;

  return createPortal(
    // Two cosines across and two down, each a layer of its own (see globals.css).
    <div className={`announcement-float${entering ? " is-entering" : ""}`} data-testid="announcement-float">
      <div className="announcement-float-u1">
        <div className="announcement-float-u2">
          <div className="announcement-float-v1">
            <div className="announcement-float-v2">
              <div className="announcement-bubble-slot">
                <button
                  type="button"
                  className={`announcement-bubble${phase === "popping" ? " is-popping" : entering ? " is-entering" : ""}`}
                  aria-label={t("news.bubble", { count: items.length })}
                  data-testid="announcement-bubble"
                  onClick={(event) => {
                    if (phase !== "idle") return;
                    const box = event.currentTarget.getBoundingClientRect();
                    setOrigin({ x: box.left + box.width / 2, y: box.top + box.height / 2 });
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
                      <img src={portrait} alt="" width={46} height={46} />
                    ) : (
                      <AnnouncementIcon name={first.bubble.icon === "portrait" ? "headphones" : first.bubble.icon} size={26} />
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
            </div>
          </div>
        </div>
      </div>
    </div>,
    document.body,
  );
}
