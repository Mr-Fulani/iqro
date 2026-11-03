"use client";

import { useEffect, useRef, useState, useSyncExternalStore } from "react";

import { DEFAULT_DUA_DISPLAY, DUA_DISPLAY_STORAGE_KEY, parseDuaDisplay, type DuaDisplay } from "../lib/dua-display";
import { useI18n } from "../lib/i18n-context";
import { DuaCheckIcon, DuaTuneIcon } from "./DuaIcons";

/** Sent after this tab saves the choice; other tabs hear `storage`. */
const DUA_DISPLAY_EVENT = "iqro:dua-display";

function subscribe(onChange: () => void) {
  window.addEventListener("storage", onChange);
  window.addEventListener(DUA_DISPLAY_EVENT, onChange);
  return () => {
    window.removeEventListener("storage", onChange);
    window.removeEventListener(DUA_DISPLAY_EVENT, onChange);
  };
}

function readStored(): string {
  try {
    return window.localStorage.getItem(DUA_DISPLAY_STORAGE_KEY) ?? "";
  } catch {
    return "";
  }
}

/** What du'a cards show besides the Arabic, kept in this browser. */
export function useDuaDisplay(): DuaDisplay {
  const raw = useSyncExternalStore(subscribe, readStored, () => null);
  return raw === null ? DEFAULT_DUA_DISPLAY : parseDuaDisplay(raw);
}

function saveDuaDisplay(next: DuaDisplay) {
  try {
    window.localStorage.setItem(DUA_DISPLAY_STORAGE_KEY, JSON.stringify(next));
  } catch {
    // Without storage the choice is not kept.
  }
  window.dispatchEvent(new Event(DUA_DISPLAY_EVENT));
}

/**
 * DuaDisplayMenu of the app: «What to show» — transliteration and
 * translation. Arabic shows neither, so there it is not offered.
 */
export function DuaDisplayMenu() {
  const { locale, t } = useI18n();
  const display = useDuaDisplay();
  const [open, setOpen] = useState(false);
  const root = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const close = (event: Event) => {
      if (event instanceof KeyboardEvent ? event.key === "Escape" : !root.current?.contains(event.target as Node)) {
        setOpen(false);
      }
    };
    document.addEventListener("pointerdown", close);
    document.addEventListener("keydown", close);
    return () => {
      document.removeEventListener("pointerdown", close);
      document.removeEventListener("keydown", close);
    };
  }, [open]);

  if (locale === "ar") return null;

  const options = [
    { key: "transliteration", label: t("dua.showTransliteration") },
    { key: "translation", label: t("dua.showTranslation") },
  ] as const;

  return (
    <div className="dua-display" ref={root}>
      <button
        type="button"
        className="dua-display-button"
        aria-label={t("dua.displayOptions")}
        aria-haspopup="menu"
        aria-expanded={open}
        onClick={() => setOpen((value) => !value)}
      >
        <DuaTuneIcon />
      </button>
      {open ? (
        <div className="dua-display-menu" role="menu" aria-label={t("dua.displayOptions")}>
          {options.map((option) => (
            <button
              key={option.key}
              type="button"
              role="menuitemcheckbox"
              aria-checked={display[option.key]}
              className="dua-display-option"
              onClick={() => saveDuaDisplay({ ...display, [option.key]: !display[option.key] })}
            >
              <span className="dua-display-check">{display[option.key] ? <DuaCheckIcon /> : null}</span>
              {option.label}
            </button>
          ))}
        </div>
      ) : null}
    </div>
  );
}
