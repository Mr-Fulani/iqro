"use client";

import { useEffect, useId, useRef, type CSSProperties, type KeyboardEvent, type ReactNode, type RefObject } from "react";
import type { TajweedFragment, TajweedReference } from "../lib/api";
import { useI18n } from "../lib/i18n-context";
import { arabicParts, highlightRuns, joinedRuns, ruleText, type TajweedPart } from "../lib/tajweed";

/* Pieces of the tajweed cards: the word card, the rule card and the breakdown. */

type ColorStyle = CSSProperties & { "--tajweed-color": string };

export function colorStyle(color: string): ColorStyle {
  return { "--tajweed-color": color };
}

export function Letters({ parts, reference }: { parts: TajweedPart[]; reference: TajweedReference }) {
  return (
    <span className="tajweed-letters" dir="rtl" lang="ar">
      {parts.map((part, index) => (
        <span key={`${part.verseKey}-${part.word.position}`}>
          {index > 0 && " "}
          {joinedRuns(highlightRuns(part.word.text, [part.fragment])).map((run, runIndex) => run.code ? (
            <mark
              key={runIndex}
              style={colorStyle(reference.rules.find((rule) => rule.code === run.code)?.color ?? "currentColor")}
            >
              {run.text}
            </mark>
          ) : run.text)}
        </span>
      ))}
    </span>
  );
}

/** An explanation whose Arabic examples keep their own direction and font. */
export function Explanation({ text }: { text: string }) {
  return (
    <p>
      {arabicParts(text).map((part, index) => part.arabic
        ? <bdi key={index} className="tajweed-inline-arabic" lang="ar">{part.text}</bdi>
        : part.text)}
    </p>
  );
}

export function RuleHeading({ reference, code, variant }: { reference: TajweedReference; code: string; variant?: string }) {
  const { locale } = useI18n();
  const text = ruleText(reference, code, locale, variant);
  if (!text) return null;
  return (
    <>
      <h3 className="tajweed-rule-name">
        <span className="tajweed-dot" style={{ background: text.color }} aria-hidden="true" />
        {text.name}
        {text.variantName && <span className="tajweed-rule-variant"> · {text.variantName}</span>}
      </h3>
      {text.arabicName !== text.name && (
        <p className="tajweed-rule-arabic" dir="rtl" lang="ar">{text.arabicName}</p>
      )}
    </>
  );
}

/** A word with the letters of its rules in their Mushaf colours. */
export function HighlightedWord({
  reference,
  text,
  fragments,
}: {
  reference: TajweedReference;
  text: string;
  fragments: readonly TajweedFragment[];
}) {
  return (
    <span dir="rtl" lang="ar">
      {joinedRuns(highlightRuns(text, fragments)).map((run, index) => run.code ? (
        <mark key={index} style={colorStyle(reference.rules.find((item) => item.code === run.code)?.color ?? "currentColor")}>
          {run.text}
        </mark>
      ) : run.text)}
    </span>
  );
}

/**
 * The sheet the tajweed cards open in: a bottom sheet on a phone, a dialog on a
 * wide screen. Esc and a tap on the shade close it; focus returns to the opener.
 * The title takes focus when the sheet opens and whenever `focusKey` changes.
 * Content that closes the sheet itself calls `close()` on `dialogRef`.
 */
export function TajweedDialog({
  title,
  focusKey,
  onClose,
  onKeyDown,
  className,
  testId,
  dialogRef,
  children,
}: {
  title: ReactNode;
  focusKey: string;
  onClose: () => void;
  onKeyDown?: (event: KeyboardEvent<HTMLDialogElement>) => void;
  className?: string;
  testId: string;
  dialogRef?: RefObject<HTMLDialogElement | null>;
  children: ReactNode;
}) {
  const { direction, locale, t } = useI18n();
  const own = useRef<HTMLDialogElement | null>(null);
  const dialog = dialogRef ?? own;
  const heading = useRef<HTMLHeadingElement | null>(null);
  const opener = useRef<Element | null>(null);
  const titleId = useId();

  useEffect(() => {
    const element = dialog.current;
    opener.current = document.activeElement;
    if (element && !element.open) element.showModal();
    return () => {
      const previous = opener.current;
      if (previous instanceof HTMLElement && previous.isConnected) previous.focus({ preventScroll: true });
    };
  }, [dialog]);

  useEffect(() => {
    heading.current?.focus({ preventScroll: true });
  }, [focusKey]);

  return (
    <dialog
      ref={dialog}
      className={className ? `tajweed-sheet ${className}` : "tajweed-sheet"}
      lang={locale}
      dir={direction}
      aria-labelledby={titleId}
      onClose={onClose}
      onClick={(event) => {
        if (event.target === event.currentTarget) dialog.current?.close();
      }}
      // The card opens after its lazy chunk loads, so the click's activation has
      // expired and Chrome would spend the first Esc on a cancel request.
      onKeyDown={(event) => {
        if (event.key !== "Escape") {
          onKeyDown?.(event);
          return;
        }
        event.preventDefault();
        dialog.current?.close();
      }}
      data-testid={testId}
    >
      <div className="tajweed-sheet-head">
        <span className="tajweed-sheet-handle" aria-hidden="true" />
        <button
          type="button"
          className="tajweed-sheet-close"
          onClick={() => dialog.current?.close()}
          aria-label={t("common.close")}
        >
          ×
        </button>
      </div>
      <h2 id={titleId} ref={heading} tabIndex={-1} className="tajweed-sheet-title">
        {title}
      </h2>
      {children}
    </dialog>
  );
}
