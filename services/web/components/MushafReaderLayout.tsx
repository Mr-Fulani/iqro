"use client";

import { createContext, useContext, useEffect, useRef, useState, useSyncExternalStore, type CSSProperties, type ReactNode } from "react";
import { useI18n } from "../lib/i18n-context";
import { MobileDisclosure } from "./MobileDisclosure";

export const MOBILE_READER_QUERY = "(max-width: 768px), (hover: none) and (pointer: coarse), (max-width: 1024px) and (max-height: 500px) and (orientation: landscape)";
type Panel = "settings" | "audio" | "notes" | "session";
const ReaderContext = createContext<{
  immersive: boolean;
  panel: Panel | null;
  setPanel: (panel: Panel | null) => void;
  audioSlot: HTMLDivElement | null;
  settingsExpanded: boolean;
} | null>(null);

export function useMushafReader() { return useContext(ReaderContext); }

function useMediaQuery(query: string): boolean {
  return useSyncExternalStore(
    (onChange) => {
      const media = window.matchMedia(query);
      media.addEventListener("change", onChange);
      return () => media.removeEventListener("change", onChange);
    },
    () => window.matchMedia(query).matches,
    () => false,
  );
}

function ReaderIcon({ name }: { name: "exit" | "settings" | "audio" | "notes" | "expand" | "menu" | "close" | "session" | "fold" | "text" | "back" | "bookmark" }) {
  const paths: Record<typeof name, ReactNode> = {
    exit: <><path d="M10 4H4v16h6M8 12h13m-4-4 4 4-4 4" /></>,
    settings: <><path d="M4 6h16M4 12h16M4 18h16" /><circle cx="9" cy="6" r="2" /><circle cx="15" cy="12" r="2" /><circle cx="9" cy="18" r="2" /></>,
    audio: <><path d="M3 14v-2a9 9 0 0 1 18 0v2M3 13h3v8H4a1 1 0 0 1-1-1Zm18 0h-3v8h2a1 1 0 0 0 1-1Z" /></>,
    notes: <><path d="M12 5c-3-2-6-2-10-1v15c4-1 7-1 10 1 3-2 6-2 10-1V4c-4-1-7-1-10 1Zm0 0v15" /></>,
    expand: <path d="M8 3H3v5m13-5h5v5M3 16v5h5m13-5v5h-5" />,
    menu: <path d="M4 6h16M4 12h16M4 18h16" />,
    close: <path d="m6 6 12 12M6 18 18 6" />,
    fold: <path d="m5 9 7 7 7-7" />,
    session: <><circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" /></>,
    text: <path d="M5 6h14M5 10h14M5 14h14M10 18h9" />,
    back: <path d="M19 12H5m6-6-6 6 6 6" />,
    bookmark: <path d="M6 4h12v17l-6-4-6 4Z" />,
  };
  return <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{paths[name]}</svg>;
}

/**
 * The page scrubber of the app's Mushaf (mushaf_reader_controls.dart): the
 * page and its juz over seven marks, the pages around the open one, laid out
 * right to left like the book. A tap or a drag across them opens that page.
 */
function PageScrubber({ page, count, juz, onJump }: { page: number; count: number; juz?: number | ""; onJump: (page: number) => void }) {
  const { t, formatNumber } = useI18n();
  const slots = Math.min(7, Math.max(1, count));
  // While a finger drags, the marks keep their pages.
  const [dragStart, setDragStart] = useState<number | null>(null);
  const requested = useRef<number | null>(null);
  const moved = useRef(false);
  const start = dragStart ?? Math.min(Math.max(1, page - 3), Math.max(1, count - slots + 1));
  const pages = Array.from({ length: slots }, (_, index) => start + index);
  const pageAt = (x: number, box: DOMRect) => {
    const slot = Math.min(slots - 1, Math.max(0, Math.floor(((x - box.left) / box.width) * slots)));
    return start + slots - 1 - slot;
  };
  const end = () => {
    setDragStart(null);
    requested.current = null;
  };
  return (
    <div className="reader-scrubber" data-testid="reader-scrubber">
      <div className="reader-scrubber-head">
        <strong>{t("common.page", { page: formatNumber(page) })}</strong>
        {juz ? <small>{t("quran.markJuz", { juz: formatNumber(juz) })}</small> : null}
      </div>
      <div
        className="reader-scrubber-marks"
        dir="rtl"
        role="group"
        aria-label={t("quran.pageOf", { page, count })}
        onPointerDown={() => {
          moved.current = false;
          requested.current = page;
          setDragStart(start);
        }}
        onPointerMove={(event) => {
          if (dragStart === null || event.buttons === 0 && event.pointerType === "mouse") return;
          const target = pageAt(event.clientX, event.currentTarget.getBoundingClientRect());
          if (target === requested.current) return;
          moved.current = true;
          requested.current = target;
          onJump(target);
        }}
        onPointerUp={end}
        onPointerCancel={end}
        onPointerLeave={(event) => {
          if (event.pointerType === "mouse") end();
        }}
      >
        {pages.map((item) => (
          <button
            key={item}
            type="button"
            aria-label={t("common.page", { page: formatNumber(item) })}
            aria-current={item === page ? "page" : undefined}
            style={{ "--away": Math.abs(item - page) } as CSSProperties}
            onClick={() => {
              if (!moved.current && item !== page) onJump(item);
            }}
          >
            <span />
          </button>
        ))}
      </div>
    </div>
  );
}

/** Viewport and overlays only. Reader data and all existing controls stay mounted. */
export function MushafReaderLayout({ active, page, count, pageRatio, hasNotes, hasSession, onImmersiveChange, onOpenText, title, subtitle, juz, bookmark, onJumpPage, zoom = 1, settingsRequest = 0, children }: {
  active: boolean;
  page: number;
  count: number;
  pageRatio: number;
  hasNotes: boolean;
  hasSession: boolean;
  onImmersiveChange?: (immersive: boolean) => void;
  /** The text of the same place, as the Mushaf button of the app's text reader. */
  onOpenText?: () => void;
  /** The phone's top bar, as in the app's Mushaf: the surah, then «Mushaf» or the selected ayah. */
  title?: string;
  subtitle?: string;
  /** The juz of the open page, beside the page number on a phone. */
  juz?: number | "";
  /** The bookmark of the selected ayah, in the phone's top bar. */
  bookmark?: { saved: boolean; disabled: boolean; label: string; onToggle: () => void };
  /** Opens a page from the phone's page scrubber. */
  onJumpPage?: (page: number) => void;
  /** The phone reader's page zoom, 1 to 3. */
  zoom?: number;
  /** Counts requests to show the reading settings (the Mushaf choice of the ayah menu). */
  settingsRequest?: number;
  children: ReactNode;
}) {
  const { t, formatNumber } = useI18n();
  const root = useRef<HTMLDivElement>(null);
  const panelTrigger = useRef<HTMLButtonElement | null>(null);
  // Read the viewport during render rather than in an effect: in production the
  // reader mounts on the client only (QuranPage suspends on search params), so
  // phones open straight in the immersive layout instead of switching to it
  // after the first paint (a layout shift above 1.0). When it is hydrated (dev
  // renders it on the server), React reconciles from the `false` server value.
  const compact = useMediaQuery(MOBILE_READER_QUERY);
  const landscape = useMediaQuery("(orientation: landscape)");
  const [focused, setFocused] = useState(true);
  const [controlsVisible, setControlsVisible] = useState(true);
  const [panel, setPanel] = useState<Panel | null>(null);
  const [fullscreen, setFullscreen] = useState(false);
  const [canFullscreen, setCanFullscreen] = useState(false);
  const [fullscreenError, setFullscreenError] = useState(false);
  const [audioSlot, setAudioSlot] = useState<HTMLDivElement | null>(null);
  const [settingsExpanded, setSettingsExpanded] = useState(false);
  const [settingsTarget, setSettingsTarget] = useState<"settings" | "audio" | null>(null);
  const immersive = active && focused && (compact || fullscreen);

  useEffect(() => { onImmersiveChange?.(immersive); }, [immersive, onImmersiveChange]);

  useEffect(() => {
    if (immersive || fullscreen || !settingsTarget) return;
    const target = root.current?.querySelector<HTMLElement>(`.reader-panel-${settingsTarget}`);
    target?.focus({ preventScroll: true });
    target?.scrollIntoView({ block: "start", behavior: "instant" });
    setSettingsTarget(null);
  }, [immersive, fullscreen, settingsTarget]);

  useEffect(() => {
    const updateFullscreen = () => setFullscreen(document.fullscreenElement === root.current);
    setCanFullscreen(Boolean(document.fullscreenEnabled && root.current?.requestFullscreen));
    document.addEventListener("fullscreenchange", updateFullscreen);
    return () => document.removeEventListener("fullscreenchange", updateFullscreen);
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
    const element = root.current;
    const stage = element?.querySelector<HTMLElement>(".mushaf-page-container");
    if (!immersive || !element || !stage) return;
    // The reader bar floats over the bottom of the stage: keep only its current
    // height free below the sheet, not a fixed band. A portrait page ignores the
    // folded bar, which stays clear of a centred sheet.
    const reserveBottom = () => {
      const bottom = stage.getBoundingClientRect().bottom;
      const tops = [...element.querySelectorAll<HTMLElement>(".reader-actions")]
        .filter((overlay) => overlay.getClientRects().length > 0 && (landscape || !overlay.classList.contains("is-folded")))
        .map((overlay) => overlay.getBoundingClientRect().top);
      element.style.setProperty("--reader-bottom-reserve", `${Math.ceil(Math.max(0, ...tops.map((top) => bottom - top)))}px`);
    };
    // The tajweed chips follow a portrait sheet in the stage. It leaves them
    // room, so the page and its chips fit above the reader bar together.
    const fitSheet = () => {
      const style = getComputedStyle(stage);
      const width = stage.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight);
      const height = stage.clientHeight - parseFloat(style.paddingTop) - parseFloat(style.paddingBottom);
      const legend = stage.querySelector<HTMLElement>(":scope > .mushaf-tajweed-legend");
      const legendStyle = legend && getComputedStyle(legend);
      const legendHeight = legend?.getClientRects().length && legendStyle
        ? legend.getBoundingClientRect().height + parseFloat(legendStyle.marginTop) + parseFloat(legendStyle.marginBottom)
        : 0;
      const sheetWidth = landscape ? width : Math.min(width, Math.max(0, height - legendHeight) * pageRatio);
      element.style.setProperty("--reader-sheet-width", `${sheetWidth}px`);
    };
    // Observe the actual reader box after rotation/browser-bar changes, rather
    // than retaining a width calculated against the previous viewport.
    const observer = new ResizeObserver(() => {
      reserveBottom();
      fitSheet();
    });
    const observeParts = () => {
      element.querySelectorAll(".reader-actions, .mushaf-tajweed-legend").forEach((part) => observer.observe(part));
    };
    // The reader bar and the tajweed legend mount and unmount with their state.
    const parts = new MutationObserver(observeParts);
    const surface = element.querySelector(".mushaf-reader-surface");
    if (surface) parts.observe(surface, { childList: true });
    parts.observe(stage, { childList: true });
    observer.observe(stage);
    observeParts();
    return () => {
      parts.disconnect();
      observer.disconnect();
      element.style.removeProperty("--reader-sheet-width");
      element.style.removeProperty("--reader-bottom-reserve");
    };
  }, [immersive, landscape, pageRatio]);

  useEffect(() => {
    const behindPanel = root.current?.querySelectorAll<HTMLElement>(".mushaf-page-container, .reader-actions, .reader-top");
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
  const showSettings = (target: "settings" | "audio") => {
    setSettingsExpanded(true);
    setSettingsTarget(target);
    leaveReader();
  };
  // The ayah menu's «Choose the Mushaf» leads to the reading settings.
  const handledSettingsRequest = useRef(settingsRequest);
  useEffect(() => {
    if (handledSettingsRequest.current === settingsRequest) return;
    handledSettingsRequest.current = settingsRequest;
    setSettingsExpanded(true);
    setSettingsTarget("settings");
    setFocused(false);
    setPanel(null);
    if (document.fullscreenElement === root.current) void document.exitFullscreen().catch(() => {});
  }, [settingsRequest]);

  // A zoomed sheet opens on its middle, then follows the finger.
  useEffect(() => {
    if (!immersive || zoom <= 1) return;
    const stage = root.current?.querySelector<HTMLElement>(".mushaf-page-container");
    if (stage) stage.scrollLeft = (stage.scrollWidth - stage.clientWidth) / 2 * (getComputedStyle(stage).direction === "rtl" ? -1 : 1);
  }, [immersive, zoom]);

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
    <ReaderContext.Provider value={{ immersive, panel, setPanel, audioSlot, settingsExpanded }}>
      <div
        ref={root}
        className={`quran-page-layout${active ? " is-mushaf-mode" : ""}${immersive ? " is-reader-immersive" : ""}`}
        style={{ "--reader-page-ratio": pageRatio, "--reader-zoom": zoom } as CSSProperties}
        data-reader-zoomed={immersive && zoom > 1 ? true : undefined}
        data-reader-orientation={landscape ? "landscape" : "portrait"}
        data-reader-compact={compact}
        onClick={(event) => {
          const target = event.target as Element;
          if (immersive && !panel && target.closest(".mushaf-page-container") && !target.closest("button, a, input, select, [role='button'], .mushaf-tajweed-legend")) {
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
        {active && compact && !immersive && <div className="reader-settings-navigation">
          <button className="btn btn-primary reader-launch" onClick={() => { setSettingsExpanded(false); setFocused(true); }}>{t("quran.enterReader")}</button>
          <button className="btn btn-secondary" onClick={() => showSettings("audio")}>{t("nav.audio")}</button>
        </div>}
        {children}
        {immersive && (
          <>
            {panel && <div className="reader-panel-backdrop" onClick={() => setPanel(null)} aria-hidden="true" />}
            {/* A phone has the app's Mushaf chrome: a bar on top, the player and one row below.
                A computer's full screen keeps the single bar it had. */}
            {compact ? (
              <>
                {controlsVisible && (
                  <div className="reader-top" role="toolbar" aria-label={t("quran.readerControls")}>
                    <button type="button" onClick={leaveReader} aria-label={t("quran.exitReader")} title={t("quran.exitReader")}><ReaderIcon name="back" /></button>
                    <div className="reader-top-title">
                      <strong>{title}</strong>
                      <small>{subtitle}</small>
                    </div>
                    <div className="reader-top-actions">
                      {bookmark && (
                        <button
                          type="button"
                          className={bookmark.saved ? "is-saved" : undefined}
                          onClick={bookmark.onToggle}
                          disabled={bookmark.disabled}
                          aria-pressed={bookmark.saved}
                          aria-label={bookmark.label}
                          title={bookmark.label}
                          data-testid="reader-bookmark"
                        >
                          <ReaderIcon name="bookmark" />
                        </button>
                      )}
                      <button type="button" onClick={() => showSettings("settings")} aria-label={t("quran.readerSettings")} title={t("quran.readerSettings")}><ReaderIcon name="settings" /></button>
                      {canFullscreen && <button type="button" onClick={() => void toggleFullscreen()} aria-label={t(fullscreen ? "quran.exitFullscreen" : "quran.enterFullscreen")} title={t(fullscreen ? "quran.exitFullscreen" : "quran.enterFullscreen")}><ReaderIcon name="expand" /></button>}
                    </div>
                  </div>
                )}
                <div className={`reader-actions is-app${controlsVisible ? "" : " is-folded"}`} role="toolbar" aria-label={t("quran.readerControls")}>
                  {controlsVisible ? (
                    <>
                      <div className="reader-audio-slot" ref={setAudioSlot} />
                      <div className="reader-action-buttons">
                      {onOpenText && (
                        <button
                          type="button"
                          onClick={() => {
                            setPanel(null);
                            if (document.fullscreenElement === root.current) void document.exitFullscreen().catch(() => {});
                            onOpenText();
                          }}
                          aria-label={t("quran.openText")}
                          title={t("quran.openText")}
                          data-testid="reader-open-text"
                          className="reader-labelled"
                        >
                          <ReaderIcon name="text" /><span>{t("surahs.textMode")}</span>
                        </button>
                      )}
                        {onJumpPage ? <PageScrubber page={page} count={count} juz={juz} onJump={onJumpPage} /> : (
                          <span className="reader-page-label" aria-label={t("quran.pageOf", { page, count })}>
                            <strong>{t("common.page", { page: formatNumber(page) })}</strong>
                            {juz ? <small>{t("quran.markJuz", { juz: formatNumber(juz) })}</small> : null}
                          </span>
                        )}
                        {hasSession && <button type="button" onClick={(event) => openPanel("session", event.currentTarget)} aria-label={t("quran.readerSession")} title={t("quran.readerSession")}><ReaderIcon name="session" /></button>}
                        {hasNotes && (
                          <button type="button" className="reader-labelled" onClick={(event) => openPanel("notes", event.currentTarget)} aria-label={t("quran.readerNotes")} title={t("quran.readerNotes")}>
                            <ReaderIcon name="notes" /><span>{t("quran.readerTranslation")}</span>
                          </button>
                        )}
                        {/* A tap on the page hides the chrome too; this is the way without a pointer. */}
                        <button type="button" onClick={() => setControlsVisible(false)} aria-label={t("quran.readerHideControls")} title={t("quran.readerHideControls")}><ReaderIcon name="fold" /></button>
                      </div>
                    </>
                  ) : <button type="button" onClick={() => setControlsVisible(true)} aria-label={t("quran.readerControls")}><ReaderIcon name="menu" /></button>}
                </div>
              </>
            ) : (
            <div className={`reader-actions${controlsVisible ? "" : " is-folded"}`} role="toolbar" aria-label={t("quran.readerControls")}>
              {controlsVisible ? (
                <>
                  <div className="reader-audio-slot" ref={setAudioSlot} />
                  <div className="reader-action-buttons">
                  <button type="button" onClick={leaveReader} aria-label={t("quran.exitReader")} title={t("quran.exitReader")}><ReaderIcon name="exit" /></button>
                  {onOpenText && (
                    <button
                      type="button"
                      onClick={() => {
                        setPanel(null);
                        if (document.fullscreenElement === root.current) void document.exitFullscreen().catch(() => {});
                        onOpenText();
                      }}
                      aria-label={t("quran.openText")}
                      title={t("quran.openText")}
                      data-testid="reader-open-text"
                    >
                      <ReaderIcon name="text" />
                    </button>
                  )}
                  <span className="reader-page-label" dir="ltr" aria-label={t("quran.pageOf", { page, count })}>{formatNumber(page)} / {formatNumber(count)}</span>
                  <button type="button" onClick={() => showSettings("settings")} aria-label={t("quran.readerSettings")} title={t("quran.readerSettings")}><ReaderIcon name="settings" /></button>
                  {hasNotes && <button type="button" onClick={(event) => openPanel("notes", event.currentTarget)} aria-label={t("quran.readerNotes")} title={t("quran.readerNotes")}><ReaderIcon name="notes" /></button>}
                  {hasSession && <button type="button" onClick={(event) => openPanel("session", event.currentTarget)} aria-label={t("quran.readerSession")} title={t("quran.readerSession")}><ReaderIcon name="session" /></button>}
                  {canFullscreen && <button type="button" onClick={() => void toggleFullscreen()} aria-label={t(fullscreen ? "quran.exitFullscreen" : "quran.enterFullscreen")} title={t(fullscreen ? "quran.exitFullscreen" : "quran.enterFullscreen")}><ReaderIcon name="expand" /></button>}
                  <button type="button" onClick={() => setControlsVisible(false)} aria-label={t("quran.readerHideControls")} title={t("quran.readerHideControls")}><ReaderIcon name="fold" /></button>
                  </div>
                </>
              ) : <button type="button" onClick={() => setControlsVisible(true)} aria-label={t("quran.readerControls")}><ReaderIcon name="menu" /></button>}
            </div>
            )}
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
      tabIndex={-1}
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
      <div className="reader-panel-body">{children}</div>
    </section>
  );
}

export function MushafReaderSettings({ children }: { children: ReactNode }) {
  const context = useContext(ReaderContext);
  const { t } = useI18n();
  return (
    <MobileDisclosure title={t("quran.readerSettings")} className="quran-reader-settings" mediaQuery={context?.immersive ? "not all" : MOBILE_READER_QUERY} expanded={context?.settingsExpanded}>
      {children}
    </MobileDisclosure>
  );
}
