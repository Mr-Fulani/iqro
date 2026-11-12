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
  onStep,
  onClose,
}: {
  document: NamesDocument;
  index: number;
  progress: CourseProgress | null;
  voice: NameVoice;
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
  const hasVoice = Boolean(name.ayah && name.ayah.word !== null);
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

      <p className="names-card-number">{t("names.cardNumber", { number: name.position, total: count })}</p>
      <div className="names-card-calligraphy">
        <svg viewBox="0 0 100 100" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth=".8">
          <rect x="20" y="20" width="60" height="60" />
          <rect x="20" y="20" width="60" height="60" transform="rotate(45 50 50)" />
          <circle cx="50" cy="50" r="46" strokeDasharray="1 3" />
        </svg>
        <span lang="ar" dir="rtl">{name.arabic}</span>
      </div>

      <div className="names-card-head">
        <h2 id={titleId}>{nameLabel(name)}</h2>
        <p>{name.meaning}</p>
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
          onClick={() => writeNamesProgress(setNameLearned(readNamesProgress(), name.slug, !learned, list.collection.version))}
          data-testid="names-learned"
        >
          {learned ? `✓ ${t("names.learned")}` : t("names.markLearned")}
        </button>
      </div>
      {hasVoice && voice.missing === name.slug && <p className="names-card-note" role="status">{t("names.noRecording")}</p>}

      <section className="names-card-block">
        <h3>{t("names.tafsir")}</h3>
        <p>{name.tafsir}</p>
        {source && <p className="names-card-source">{t("names.source", { source })}</p>}
      </section>

      {name.ayah && (
        <section className="names-card-block">
          <h3>{t("names.inQuran")}</h3>
          <Link
            className="names-card-ayah"
            href={localizedPath(locale, `/quran?surah=${name.ayah.surah}&ayah=${name.ayah.ayah}`)}
            data-testid="names-ayah"
          >
            {t("names.ayahLink", { surah: name.ayah.surah, ayah: name.ayah.ayah })}
          </Link>
        </section>
      )}

      {list.collection.list_source && (
        <p className="names-card-source">{t("names.listSource", { source: list.collection.list_source })}</p>
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
