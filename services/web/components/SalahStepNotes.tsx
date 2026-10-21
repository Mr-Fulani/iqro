"use client";

import { type FocusEvent, useEffect, useId, useRef, useState } from "react";

import { useI18n } from "../lib/i18n-context";
import type { SalahStepNote } from "../lib/salah";

/**
 * The «?» and «!» icons of a step. Each opens its note in a popover under the
 * step title; Escape, a click outside, leaving it with Tab or turning the step
 * close it. The texts stay in the HTML, hidden, for search engines and readers
 * without scripts.
 */
export function SalahStepNotes({ notes, active }: { notes: SalahStepNote[]; active: boolean }) {
  const { formatNumber, t } = useI18n();
  const [open, setOpen] = useState<number | null>(null);
  const baseId = useId();
  const rootRef = useRef<HTMLDivElement>(null);
  const buttonRefs = useRef<(HTMLButtonElement | null)[]>([]);
  const panelRefs = useRef<(HTMLDivElement | null)[]>([]);

  const labels = notes.map((note, index) => {
    const label = t(note.kind === "warning" ? "salah.noteWarning" : "salah.noteHelp");
    const sameKind = notes.filter((other) => other.kind === note.kind);
    if (sameKind.length < 2) return label;
    const number = notes.slice(0, index + 1).filter((other) => other.kind === note.kind).length;
    return `${label} ${formatNumber(number)}`;
  });

  const close = (returnFocus: boolean) => {
    if (returnFocus && open !== null) buttonRefs.current[open]?.focus();
    setOpen(null);
  };

  // Another step is shown: its notes start closed.
  useEffect(() => {
    if (!active) setOpen(null);
  }, [active]);

  useEffect(() => {
    if (open === null) return;
    // The note is read at once by a screen reader; Tab goes on to its close button.
    panelRefs.current[open]?.focus();
    const onPointerDown = (event: PointerEvent) => {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(null);
    };
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key !== "Escape") return;
      event.preventDefault();
      buttonRefs.current[open]?.focus();
      setOpen(null);
    };
    document.addEventListener("pointerdown", onPointerDown);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("pointerdown", onPointerDown);
      document.removeEventListener("keydown", onKeyDown);
    };
  }, [open]);

  const onBlur = (event: FocusEvent<HTMLDivElement>) => {
    const next = event.relatedTarget as Node | null;
    if (next && !rootRef.current?.contains(next)) setOpen(null);
  };

  return (
    <div className="salah-notes" ref={rootRef} onBlur={onBlur} role="group" aria-label={t("salah.notesAria")}>
      {notes.map((note, index) => (
        <button
          key={index}
          ref={(element) => {
            buttonRefs.current[index] = element;
          }}
          type="button"
          className={`salah-note-icon is-${note.kind}`}
          aria-label={labels[index]}
          title={labels[index]}
          aria-haspopup="dialog"
          aria-expanded={open === index}
          aria-controls={`${baseId}-${index}`}
          onClick={() => setOpen(open === index ? null : index)}
          data-testid="salah-note-icon"
        >
          <span aria-hidden="true">{note.kind === "warning" ? "!" : "?"}</span>
        </button>
      ))}
      {notes.map((note, index) => (
        <div
          key={index}
          id={`${baseId}-${index}`}
          ref={(element) => {
            panelRefs.current[index] = element;
          }}
          className={`salah-note-popover is-${note.kind}`}
          role="dialog"
          aria-labelledby={`${baseId}-${index}-title`}
          tabIndex={-1}
          hidden={open !== index}
          data-testid="salah-note-popover"
        >
          <div className="salah-note-popover-head">
            <strong id={`${baseId}-${index}-title`}>{labels[index]}</strong>
            <button
              type="button"
              className="salah-note-close"
              onClick={() => close(true)}
              aria-label={t("salah.noteClose")}
              title={t("salah.noteClose")}
            >
              <span aria-hidden="true">×</span>
            </button>
          </div>
          <p>{note.text}</p>
        </div>
      ))}
    </div>
  );
}
