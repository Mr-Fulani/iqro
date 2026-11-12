"use client";

import Link from "next/link";
import { useEffect, useId, useRef } from "react";

import type { CourseProgress } from "@/lib/course-progress";
import { useI18n } from "@/lib/i18n-context";
import {
  isNameLearned,
  nameLabel,
  readNamesProgress,
  setNameLearned,
  writeNamesProgress,
  type NamesDocument,
} from "@/lib/names";
import { localizedPath } from "@/lib/routing";
import type { NameVoice } from "./use-name-voice";

/**
 * The card of one name: a bottom sheet on a phone, a dialog on a wide screen.
 * Calligraphy, the reciter's recording, «Выучено», the explanation with its
 * book, the ayah in our reader, and the neighbouring names.
 */
export function NameCard({
  document: list,
  index,
  progress,
  voice,
  onMarked,
  onStep,
  onClose,
}: {
  document: NamesDocument;
  index: number;
  progress: CourseProgress | null;
  voice: NameVoice;
  /** «Выучено» was set or taken back. */
  onMarked: () => void;
  /** Shows another name and turns the wheel to it. */
  onStep: (index: number) => void;
  onClose: () => void;
}) {
  const { locale, t } = useI18n();
  const dialog = useRef<HTMLDialogElement | null>(null);
  const titleId = useId();
  const names = list.names;
  const count = names.length;
  const name = names[index];
  const previous = names[(index - 1 + count) % count];
  const following = names[(index + 1) % count];
  const learned = isNameLearned(progress, name.slug);
  const hasVoice = voice.canSay(name);
  const sounding = voice.playing === name.slug;

  useEffect(() => {
    const element = dialog.current;
    if (element && !element.open) element.showModal();
  }, []);

  const source = [name.tafsir_source, name.tafsir_ref].filter(Boolean).join(", ");

  return (
    <dialog
      ref={dialog}
      className="dua-sheet names-card"
      aria-labelledby={titleId}
      onClose={onClose}
      onClick={(event) => {
        if (event.target === event.currentTarget) dialog.current?.close();
      }}
      data-testid="names-card"
    >
      <div className="dua-sheet-head">
        <span className="dua-sheet-handle" aria-hidden="true" />
        <button type="button" className="dua-sheet-close" onClick={() => dialog.current?.close()} aria-label={t("common.close")}>
          ×
        </button>
      </div>

      <div className="names-card-hero">
        <svg viewBox="0 0 100 100" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth=".5">
          <rect x="22" y="22" width="56" height="56" />
          <rect x="22" y="22" width="56" height="56" transform="rotate(45 50 50)" />
          <circle cx="50" cy="50" r="44" />
          <circle cx="50" cy="50" r="20" />
        </svg>
        <p className="names-card-number">{t("names.cardNumber", { number: name.position, total: count })}</p>
        <p className="names-card-calligraphy" lang="ar" dir="rtl">{name.arabic}</p>
        <h2 id={titleId}>{nameLabel(name)}</h2>
        <span className="names-card-rule" aria-hidden="true" />
        <p className="names-card-meaning">{name.meaning}</p>
      </div>

      <div className="names-card-actions">
        {hasVoice && (
          <button
            type="button"
            className="btn btn-primary"
            onClick={() => (sounding ? voice.stop() : void voice.play(name))}
            data-testid="names-listen"
          >
            {sounding ? t("names.stop") : t("names.listen")}
          </button>
        )}
        <button
          type="button"
          className={`btn btn-secondary names-learned${learned ? " is-on" : ""}`}
          aria-pressed={learned}
          onClick={() => {
            writeNamesProgress(setNameLearned(readNamesProgress(), name.slug, !learned, list.collection.version));
            onMarked();
          }}
          data-testid="names-learned"
        >
          {learned ? `✓ ${t("names.learned")}` : t("names.markLearned")}
        </button>
      </div>
      {hasVoice && voice.missing === name.slug && <p className="names-card-note" role="status">{t("names.noRecording")}</p>}

      <section className="names-card-tafsir">
        <h3>{t("names.tafsir")}</h3>
        <p>{name.tafsir}</p>
        {source && <p className="names-card-source">{t("names.source", { source })}</p>}
      </section>

      {name.ayah && (
        <Link
          className="names-card-ayah"
          href={localizedPath(locale, `/quran?surah=${name.ayah.surah}&ayah=${name.ayah.ayah}`)}
          data-testid="names-ayah"
        >
          <span className="names-card-ayah-icon" aria-hidden="true">
            <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
              <path d="M12 5c-3-2-6-2-10-1v15c4-1 7-1 10 1 3-2 6-2 10-1V4c-4-1-7-1-10 1Zm0 0v15" />
            </svg>
          </span>
          <span className="names-card-ayah-text">
            <small>{t("names.inQuran")}</small>
            <strong>{t("names.ayahLink", { surah: name.ayah.surah, ayah: name.ayah.ayah })}</strong>
          </span>
          <span className="names-card-ayah-chevron" aria-hidden="true">›</span>
        </Link>
      )}

      {list.collection.list_source && (
        <p className="names-card-source names-card-list-source">{t("names.listSource", { source: list.collection.list_source })}</p>
      )}

      <nav className="names-card-nav" aria-label={t("names.neighbours")}>
        <button type="button" onClick={() => onStep((index - 1 + count) % count)} data-testid="names-card-previous">
          <small>{t("names.previous")}</small>
          <span>{nameLabel(previous)}</span>
        </button>
        <button type="button" onClick={() => onStep((index + 1) % count)} data-testid="names-card-next">
          <small>{t("names.following")}</small>
          <span>{nameLabel(following)}</span>
        </button>
      </nav>
    </dialog>
  );
}
