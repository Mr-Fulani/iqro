"use client";

import Link from "next/link";
import { useEffect, useId, useRef, useState } from "react";
import type { AyahAnnotation } from "../lib/api";
import {
  AYAH_HIGHLIGHT_COLOR_KEYS,
  normalizeAyahHighlightColor,
  type AyahHighlightColorKey,
} from "../lib/ayah-annotations";
import { useI18n } from "../lib/i18n-context";
import { localizedPath } from "../lib/routing";

const NOTE_MAX_LENGTH = 2000;

type AyahAnnotationDialogProps = {
  ayahKey: string;
  annotation: AyahAnnotation | undefined;
  /** False until the reader's sync settles; saving earlier could overwrite or fork a record. */
  ready: boolean;
  onSave: (colorKey: AyahHighlightColorKey, note: string) => Promise<string | null>;
  onRemove: () => Promise<string | null>;
  onClose: () => void;
};

/**
 * Highlight and note of one ayah, the web counterpart of the app's ayah sheet:
 * a highlight may carry a note, and removing the highlight removes the note.
 * The callbacks resolve to an error message, or null once the dialog may close.
 * Until the user edits something, the form follows the annotation as sync
 * delivers it, so a note written in the app is never replaced by an empty one.
 */
export default function AyahAnnotationDialog({
  ayahKey,
  annotation,
  ready,
  onSave,
  onRemove,
  onClose,
}: AyahAnnotationDialogProps) {
  const { locale, t } = useI18n();
  const dialog = useRef<HTMLDialogElement>(null);
  const titleId = useId();
  const noteId = useId();
  const [colorKey, setColorKey] = useState<AyahHighlightColorKey>(
    normalizeAyahHighlightColor(annotation?.color_key),
  );
  const [note, setNote] = useState(annotation?.note ?? "");
  const source = annotation ? `${annotation.id}:${annotation.revision}:${annotation.updated_at}` : "";
  const [shownSource, setShownSource] = useState(source);
  const [edited, setEdited] = useState(false);
  if (source !== shownSource && !edited) {
    setShownSource(source);
    setColorKey(normalizeAyahHighlightColor(annotation?.color_key));
    setNote(annotation?.note ?? "");
  }
  const [busy, setBusy] = useState(false);
  const [confirmRemove, setConfirmRemove] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const element = dialog.current;
    if (element && !element.open) element.showModal();
  }, []);

  const run = async (action: () => Promise<string | null>) => {
    setBusy(true);
    setError(null);
    const failure = await action();
    setBusy(false);
    if (failure) setError(failure);
    // Closing the dialog itself returns focus to the control that opened it.
    else dialog.current?.close();
  };

  const remove = () => {
    if (annotation?.note.trim() && !confirmRemove) {
      setConfirmRemove(true);
      return;
    }
    void run(onRemove);
  };

  return (
    <dialog
      ref={dialog}
      className="ayah-annotation-dialog"
      aria-labelledby={titleId}
      onClose={onClose}
    >
      <form
        method="dialog"
        onSubmit={(event) => {
          event.preventDefault();
          void run(() => onSave(colorKey, note));
        }}
      >
        <div className="ayah-annotation-dialog-head">
          <h2 id={titleId}>{t("common.ayah", { ayah: ayahKey })}</h2>
          <button
            type="button"
            className="btn btn-secondary btn-sm"
            onClick={() => dialog.current?.close()}
            aria-label={t("common.close")}
          >
            ×
          </button>
        </div>

        <fieldset className="ayah-annotation-colors" disabled={busy}>
          <legend className="form-label">{t("annotation.colorLegend")}</legend>
          {AYAH_HIGHLIGHT_COLOR_KEYS.map((key) => (
            <label key={key} className="ayah-annotation-color" data-highlight={key}>
              <input
                type="radio"
                name="ayah-highlight-color"
                value={key}
                checked={colorKey === key}
                onChange={() => {
                  setEdited(true);
                  setColorKey(key);
                }}
              />
              <span className="ayah-annotation-swatch" aria-hidden="true" />
              <span>{t(`annotation.color.${key}`)}</span>
            </label>
          ))}
        </fieldset>

        <div className="form-group">
          <label className="form-label" htmlFor={noteId}>{t("annotation.noteLabel")}</label>
          <textarea
            id={noteId}
            rows={5}
            maxLength={NOTE_MAX_LENGTH}
            value={note}
            placeholder={t("annotation.noteHint")}
            onChange={(event) => {
              setEdited(true);
              setNote(event.target.value);
            }}
            disabled={busy}
            dir="auto"
          />
        </div>

        {error && <div className="alert alert-error" role="alert">{error}</div>}
        {confirmRemove && (
          <p className="field-help" role="status">{t("annotation.removeHighlightWithNote")}</p>
        )}

        <div className="ayah-annotation-actions">
          {annotation && (
            <button type="button" className="btn btn-secondary" onClick={remove} disabled={busy || !ready}>
              {confirmRemove ? t("common.delete") : t("annotation.removeHighlight")}
            </button>
          )}
          <Link href={localizedPath(locale, "/notes")} className="btn btn-secondary">
            {t("annotation.allNotes")}
          </Link>
          <button type="submit" className="btn btn-primary" disabled={busy || !ready}>
            {busy ? t("common.saving") : ready ? t("common.save") : t("common.loading")}
          </button>
        </div>
      </form>
    </dialog>
  );
}
