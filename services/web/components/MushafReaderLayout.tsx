"use client";

import { createContext, useContext, useEffect, useRef, useState, type CSSProperties, type ReactNode } from "react";
import { useI18n } from "../lib/i18n-context";
import { MobileDisclosure } from "./MobileDisclosure";

export const MOBILE_READER_QUERY = "(max-width: 768px), (hover: none) and (pointer: coarse), (max-width: 1024px) and (max-height: 500px) and (orientation: landscape)";
type Panel = "settings" | "audio" | "notes" | "session";
const ReaderContext = createContext<{
  immersive: boolean;
  panel: Panel | null;
  setPanel: (panel: Panel | null) => void;
} | null>(null);

function ReaderIcon({ name }: { name: "exit" | "settings" | "audio" | "notes" | "expand" | "menu" | "close" | "session" }) {
  const paths: Record<typeof name, ReactNode> = {
    exit: <><path d="M10 4H4v16h6M8 12h13m-4-4 4 4-4 4" /></>,
    settings: <><path d="M4 6h16M4 12h16M4 18h16" /><circle cx="9" cy="6" r="2" /><circle cx="15" cy="12" r="2" /><circle cx="9" cy="18" r="2" /></>,
    audio: <><path d="M3 14v-2a9 9 0 0 1 18 0v2M3 13h3v8H4a1 1 0 0 1-1-1Zm18 0h-3v8h2a1 1 0 0 0 1-1Z" /></>,
    notes: <><path d="M12 5c-3-2-6-2-10-1v15c4-1 7-1 10 1 3-2 6-2 10-1V4c-4-1-7-1-10 1Zm0 0v15" /></>,
    expand: <path d="M8 3H3v5m13-5h5v5M3 16v5h5m13-5v5h-5" />,
    menu: <path d="M4 6h16M4 12h16M4 18h16" />,
    close: <path d="m6 6 12 12M6 18 18 6" />,
    session: <><circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" /></>,
  };
  return <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{paths[name]}</svg>;
}

/** Viewport and overlays only. Reader data and all existing controls stay mounted. */
export function MushafReaderLayout({ active, page, count, pageRatio, hasNotes, hasSession, children }: {
  active: boolean;
  page: number;
  count: number;
  pageRatio: number;
  hasNotes: boolean;
  hasSession: boolean;
  children: ReactNode;
}) {
  const { t, formatNumber } = useI18n();
  const root = useRef<HTMLDivElement>(null);
  const panelTrigger = useRef<HTMLButtonElement | null>(null);
  const [compact, setCompact] = useState(false);
  const [landscape, setLandscape] = useState(false);
  const [focused, setFocused] = useState(true);
  const [controlsVisible, setControlsVisible] = useState(true);
  const [panel, setPanel] = useState<Panel | null>(null);
  const [fullscreen, setFullscreen] = useState(false);
  const [canFullscreen, setCanFullscreen] = useState(false);
  const [fullscreenError, setFullscreenError] = useState(false);
  const immersive = active && focused && (compact || fullscreen);

  useEffect(() => {
    const mobile = window.matchMedia(MOBILE_READER_QUERY);
    const orientation = window.matchMedia("(orientation: landscape)");
    const update = () => {
      setCompact(mobile.matches);
      setLandscape(orientation.matches);
    };
    const updateFullscreen = () => setFullscreen(document.fullscreenElement === root.current);
    update();
    setCanFullscreen(Boolean(document.fullscreenEnabled && root.current?.requestFullscreen));
    mobile.addEventListener("change", update);
    orientation.addEventListener("change", update);
    document.addEventListener("fullscreenchange", updateFullscreen);
    return () => {
      mobile.removeEventListener("change", update);
      orientation.removeEventListener("change", update);
      document.removeEventListener("fullscreenchange", updateFullscreen);
    };
  }, []);

  useEffect(() => {
    if (!active) {
      setFocused(true);
      setPanel(null);
      setControlsVisible(true);
      if (document.fullscreenElement === root.current) void document.exitFullscreen().catch(() => {});
    }
  }, [active]);

  useEffect(() => {
    if (!immersive) return;
    const stage = root.current?.querySelector<HTMLElement>(".mushaf-page-container");
    stage?.scrollTo({ top: 0, left: 0, behavior: "instant" });
  }, [immersive, landscape, page]);

  useEffect(() => {
    const behindPanel = root.current?.querySelectorAll<HTMLElement>(".mushaf-page-container, .reader-actions");
    behindPanel?.forEach((element) => { element.inert = immersive && panel !== null; });
    if (!panel && panelTrigger.current) {
      if (panelTrigger.current.isConnected && panelTrigger.current.getClientRects().length) panelTrigger.current.focus({ preventScroll: true });
      panelTrigger.current = null;
    }
    return () => behindPanel?.forEach((element) => { element.inert = false; });
  }, [immersive, panel]);

  const openPanel = (name: Panel, trigger: HTMLButtonElement) => {
    panelTrigger.current = trigger;
    setPanel(name);
  };

  const leaveReader = () => {
    setFocused(false);
    setPanel(null);
    if (document.fullscreenElement === root.current) void document.exitFullscreen().catch(() => {});
  };
  const toggleFullscreen = async () => {
    setFullscreenError(false);
    try {
      if (document.fullscreenElement === root.current) await document.exitFullscreen();
      else await root.current?.requestFullscreen({ navigationUI: "hide" });
    } catch {
      setFullscreenError(true);
    }
  };

  return (
    <ReaderContext.Provider value={{ immersive, panel, setPanel }}>
      <div
        ref={root}
        className={`quran-page-layout${active ? " is-mushaf-mode" : ""}${immersive ? " is-reader-immersive" : ""}`}
        style={{ "--reader-page-ratio": pageRatio } as CSSProperties}
        data-reader-orientation={landscape ? "landscape" : "portrait"}
        onClick={(event) => {
          const target = event.target as Element;
          if (immersive && !panel && target.closest(".mushaf-page-container") && !target.closest("button, a, input, select, [role='button']")) {
            setControlsVisible((visible) => !visible);
          }
        }}
        onKeyDown={(event) => {
          if (event.key === "Escape" && immersive && !panel) {
            event.preventDefault();
            leaveReader();
          }
        }}
      >
        {active && compact && !immersive && <button className="btn btn-secondary reader-launch" onClick={() => setFocused(true)}>{t("quran.enterReader")}</button>}
        {children}
        {immersive && (
          <>
            {panel && <div className="reader-panel-backdrop" onClick={() => setPanel(null)} aria-hidden="true" />}
            <div className={`reader-actions${controlsVisible ? "" : " is-folded"}`} role="toolbar" aria-label={t("quran.readerControls")}>
              {controlsVisible ? (
                <>
                  <button type="button" onClick={leaveReader} aria-label={t("quran.exitReader")} title={t("quran.exitReader")}><ReaderIcon name="exit" /></button>
                  <span className="reader-page-label" dir="ltr" aria-label={t("quran.pageOf", { page, count })}>{formatNumber(page)} / {formatNumber(count)}</span>
                  <button type="button" onClick={(event) => openPanel("settings", event.currentTarget)} aria-label={t("quran.readerSettings")} title={t("quran.readerSettings")}><ReaderIcon name="settings" /></button>
                  <button type="button" onClick={(event) => openPanel("audio", event.currentTarget)} aria-label={t("nav.audio")} title={t("nav.audio")}><ReaderIcon name="audio" /></button>
                  {hasNotes && <button type="button" onClick={(event) => openPanel("notes", event.currentTarget)} aria-label={t("quran.readerNotes")} title={t("quran.readerNotes")}><ReaderIcon name="notes" /></button>}
                  {hasSession && <button type="button" onClick={(event) => openPanel("session", event.currentTarget)} aria-label={t("quran.readerSession")} title={t("quran.readerSession")}><ReaderIcon name="session" /></button>}
                  {canFullscreen && <button type="button" onClick={() => void toggleFullscreen()} aria-label={t(fullscreen ? "quran.exitFullscreen" : "quran.enterFullscreen")} title={t(fullscreen ? "quran.exitFullscreen" : "quran.enterFullscreen")}><ReaderIcon name="expand" /></button>}
                </>
              ) : <button type="button" onClick={() => setControlsVisible(true)} aria-label={t("quran.readerControls")}><ReaderIcon name="menu" /></button>}
            </div>
            {fullscreenError && <p className="reader-fullscreen-status" role="status">{t("quran.fullscreenUnavailable")}</p>}
          </>
        )}
      </div>
    </ReaderContext.Provider>
  );
}

export function MushafReaderPanel({ name, label, className = "", children }: {
  name: Panel;
  label: string;
  className?: string;
  children: ReactNode;
}) {
  const context = useContext(ReaderContext);
  const { t } = useI18n();
  const element = useRef<HTMLElement>(null);
  const close = useRef<HTMLButtonElement>(null);
  const isOpen = Boolean(context?.immersive && context.panel === name);

  useEffect(() => {
    if (!isOpen) return;
    close.current?.focus({ preventScroll: true });
  }, [isOpen]);

  return (
    <section
      ref={element}
      className={`reader-panel reader-panel-${name} ${className}`}
      data-reader-open={isOpen}
      role={isOpen ? "dialog" : undefined}
      aria-modal={isOpen ? true : undefined}
      aria-label={label}
      onKeyDown={(event) => {
        if (!isOpen) return;
        if (event.key === "Escape") {
          event.preventDefault();
          event.stopPropagation();
          context?.setPanel(null);
        } else if (event.key === "Tab") {
          const focusable = [...(element.current?.querySelectorAll<HTMLElement>("a[href], button, input, select, textarea, summary, [tabindex]") || [])]
            .filter((item) => item.tabIndex >= 0 && !item.matches(":disabled") && item.getClientRects().length > 0);
          const first = focusable[0];
          const last = focusable.at(-1);
          if (event.shiftKey && document.activeElement === first) {
            event.preventDefault();
            last?.focus();
          } else if (!event.shiftKey && document.activeElement === last) {
            event.preventDefault();
            first?.focus();
          }
        }
      }}
    >
      <div className="reader-panel-heading"><strong>{label}</strong><button ref={close} type="button" onClick={() => context?.setPanel(null)} aria-label={t("common.close")}><ReaderIcon name="close" /></button></div>
      {children}
    </section>
  );
}

export function MushafReaderSettings({ children }: { children: ReactNode }) {
  const context = useContext(ReaderContext);
  const { t } = useI18n();
  return (
    <MobileDisclosure title={t("quran.readerSettings")} className="quran-reader-settings" mediaQuery={context?.immersive ? "not all" : undefined}>
      {children}
    </MobileDisclosure>
  );
}
