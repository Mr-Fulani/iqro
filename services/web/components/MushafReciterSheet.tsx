"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import type { Recitation } from "../lib/api";
import { reciterName } from "../lib/audio-content";
import { useI18n } from "../lib/i18n-context";
import { recitationStyleLabel, reciterSearch } from "../lib/reciter-catalog";
import { reciterAvatarUrl } from "../lib/reciter-portraits";

/**
 * The reciters the Mushaf plays ayah by ayah, in the order given (by name),
 * with a search. Opened from the reciter's name in the reader's player, as
 * the app's MushafReciterSheet.
 */
export function MushafReciterSheet({
  recitations,
  selectedId,
  onSelect,
  onClose,
}: {
  recitations: Recitation[];
  selectedId: string;
  onSelect: (recitationId: string) => void;
  onClose: () => void;
}) {
  const { locale, t } = useI18n();
  const [query, setQuery] = useState("");
  const close = useRef<HTMLButtonElement>(null);
  const search = useMemo(() => reciterSearch(recitations.map((item) => item.reciter)), [recitations]);
  const found = useMemo(() => {
    const reciters = new Set(search(query));
    return recitations.filter((item) => reciters.has(item.reciter));
  }, [query, recitations, search]);

  useEffect(() => {
    close.current?.focus({ preventScroll: true });
  }, []);

  return (
    <>
      <div className="reader-panel-backdrop" onClick={onClose} aria-hidden="true" />
      <section
        className="mushaf-reciter-sheet"
        role="dialog"
        aria-modal="true"
        aria-label={t("mushafAudio.sheetTitle")}
        onKeyDown={(event) => {
          if (event.key !== "Escape") return;
          event.preventDefault();
          event.stopPropagation();
          onClose();
        }}
      >
        <div className="reader-panel-heading">
          <strong>{t("mushafAudio.sheetTitle")}</strong>
          <button ref={close} type="button" onClick={onClose} aria-label={t("common.close")}>
            <svg width="20" height="20" viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
              <path d="M6 6l12 12M18 6 6 18" />
            </svg>
          </button>
        </div>
        <input
          type="search"
          className="mushaf-reciter-search"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder={t("audio.searchReciters")}
          aria-label={t("audio.searchReciters")}
        />
        {found.length === 0 ? (
          <p className="mushaf-reciter-empty">{t("audio.noRecitersFound")}</p>
        ) : (
          <ul className="mushaf-reciter-list">
            {found.map((item) => {
              const selected = item.id === selectedId;
              return (
                <li key={item.id}>
                  <button type="button" aria-pressed={selected} onClick={() => onSelect(item.id)}>
                    {/* eslint-disable-next-line @next/next/no-img-element -- avatar copies are pre-sized. */}
                    <img src={reciterAvatarUrl(item.reciter)} alt="" width={40} height={40} loading="lazy" decoding="async" />
                    <span>
                      <strong>{reciterName(item.reciter, locale) || item.reciter.name_en}</strong>
                      <small>{recitationStyleLabel(item.style, t)}</small>
                    </span>
                    {selected && (
                      <svg width="20" height="20" viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round">
                        <path d="m5 12 5 5 9-10" />
                      </svg>
                    )}
                  </button>
                </li>
              );
            })}
          </ul>
        )}
      </section>
    </>
  );
}
