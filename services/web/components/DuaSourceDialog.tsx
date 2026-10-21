"use client";

import { useEffect, useId, useRef } from "react";

import type { DuaEntry } from "../lib/api";
import { useI18n } from "../lib/i18n-context";
import { DuaExpandIcon, DuaVerifiedIcon } from "./DuaIcons";

function SourceValue({ label, value, href = false }: { label: string; value: string | undefined; href?: boolean }) {
  const text = value?.trim();
  if (!text) return null;
  return (
    <div className="dua-source-row">
      <dt>{label}</dt>
      <dd>{href ? <a href={text} target="_blank" rel="noreferrer">{text}</a> : text}</dd>
    </div>
  );
}

/**
 * _DuaSourceCard of the app in its bottom sheet: whether the reference was
 * checked, the edition, its author and translator, versions and terms, and
 * every reference with its grade. The site adds the reader and the page the
 * audio comes from.
 */
export function DuaSourceDialog({ entry, onClose }: { entry: DuaEntry; onClose: () => void }) {
  const { locale, t } = useI18n();
  const dialog = useRef<HTMLDialogElement | null>(null);
  const titleId = useId();

  useEffect(() => {
    const element = dialog.current;
    if (element && !element.open) element.showModal();
  }, []);

  const source = entry.source;
  const verified = entry.evidence.length > 0
    && entry.evidence.every((item) => item.verification_status === "editorially_verified");
  const declared = Boolean(source) || entry.evidence.some((item) =>
    item.provider.trim() || item.source_name.trim() || item.source_reference.trim());
  const audio = entry.audio?.[0];
  const reader = locale === "ar" && audio?.reader_name_ar ? audio.reader_name_ar : audio?.reader_name;

  return (
    <dialog
      ref={dialog}
      className="dua-sheet"
      aria-labelledby={titleId}
      onClose={onClose}
      // A tap on the shade around the sheet closes it, as in the app.
      onClick={(event) => {
        if (event.target === event.currentTarget) dialog.current?.close();
      }}
    >
      <div className="dua-sheet-head">
        <span className="dua-sheet-handle" aria-hidden="true" />
        <button
          type="button"
          className="dua-sheet-close"
          onClick={() => dialog.current?.close()}
          aria-label={t("common.close")}
        >
          ×
        </button>
      </div>
      <details className="dua-source-card">
        <summary>
          {verified ? (
            <DuaVerifiedIcon verified />
          ) : (
            // eslint-disable-next-line @next/next/no-img-element -- the seal the app shows for a book.
            <img className="dua-source-seal" src="/iqro-wax-seal-128.webp" alt="" width={28} height={28} />
          )}
          <span>
            <strong id={titleId}>{t("dua.sourceAndVerification")}</strong>
            <small>
              {verified
                ? t("dua.editoriallyVerified")
                : declared
                  ? t("dua.sourceDeclared")
                  : t("dua.sourceUnavailable")}
            </small>
          </span>
          <DuaExpandIcon />
        </summary>
        <dl className="dua-source-rows">
          <SourceValue label={t("dua.sourceEdition")} value={source?.title || source?.provider} />
          <SourceValue label={t("dua.author")} value={source?.author} />
          <SourceValue label={t("dua.translator")} value={source?.translator} />
          <SourceValue label={t("dua.reviewer")} value={source?.reviewer} />
          <SourceValue label={t("dua.sourceVersion")} value={source?.source_version} />
          <SourceValue label={t("dua.sourceReference")} value={source?.source_url} href />
          <SourceValue label={t("dua.rights")} value={source?.rights_url} href />
          {entry.evidence.map((evidence, index) => (
            <div className="dua-source-group" key={`${evidence.source_reference}-${index}`}>
              <SourceValue
                label={evidence.source_name.trim() || t("dua.sourceReference")}
                value={evidence.source_reference}
              />
              <SourceValue label={t("dua.grade")} value={evidence.grade} />
              <SourceValue label={t("dua.sourceReference")} value={evidence.source_url} href />
            </div>
          ))}
          {audio ? (
            <div className="dua-source-group">
              <SourceValue label={t("dua.reader")} value={reader} />
              <SourceValue label={t("dua.audioSource")} value={audio.source_url} href />
            </div>
          ) : null}
        </dl>
      </details>
    </dialog>
  );
}
