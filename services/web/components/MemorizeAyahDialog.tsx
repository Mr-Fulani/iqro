"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useId, useRef, useState } from "react";
import { api, type MemorizationSelectionPreview } from "../lib/api";
import { useI18n } from "../lib/i18n-context";
import { loadReciterPreference } from "../lib/reciter-preference";
import { localizedPath } from "../lib/routing";

type MemorizeAyahDialogProps = {
  surah: number;
  ayah: number;
  onClose: () => void;
};

function browserTimezone(): string {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
  } catch {
    return "UTC";
  }
}

/**
 * "Learn" from the Mushaf ayah menu, one ayah at a time. The server decides
 * which choice fits: with an empty list the ayah starts straight away;
 * otherwise it is already in the list, extends the current range, or is
 * queued (the default) versus learnt now. The API also takes ranges.
 */
export default function MemorizeAyahDialog({ surah, ayah, onClose }: MemorizeAyahDialogProps) {
  const { formatNumber, locale, t } = useI18n();
  const router = useRouter();
  const dialog = useRef<HTMLDialogElement>(null);
  const titleId = useId();
  const [preview, setPreview] = useState<MemorizationSelectionPreview | null>(null);
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const memorizationHref = localizedPath(locale, "/memorization");

  useEffect(() => {
    const element = dialog.current;
    if (element && !element.open) element.showModal();
  }, []);

  useEffect(() => {
    let active = true;
    api.previewMemorizationSelection({
      start_surah: surah,
      start_ayah: ayah,
      end_surah: surah,
      end_ayah: ayah,
    })
      .then((next) => {
        if (active) setPreview(next);
      })
      .catch((reason) => {
        if (active) setError(api.normalizeError(reason));
      });
    return () => {
      active = false;
    };
  }, [ayah, surah]);

  const range = (start: number, end: number, surahNumber = surah) => (
    start === end
      ? `${formatNumber(surahNumber)}:${formatNumber(start)}`
      : `${formatNumber(surahNumber)}:${formatNumber(start)}–${formatNumber(end)}`
  );

  const add = async (mode: "queue" | "now" | "extend", revision = preview?.revision) => {
    if (revision === undefined) return;
    setBusy(true);
    setError(null);
    try {
      const result = await api.addMemorizationSelection({
        start_surah: surah,
        start_ayah: ayah,
        end_surah: surah,
        end_ayah: ayah,
        mode,
        timezone_name: browserTimezone(),
        base_revision: revision,
        recitation_id: loadReciterPreference("memorization")?.recitationId ?? null,
      });
      window.dispatchEvent(new Event("memorization-progress-changed"));
      if (result.result === "queued" || result.result === "merged") {
        setDone(t("memorization.list.addedToQueue"));
        return;
      }
      router.push(memorizationHref);
      dialog.current?.close();
    } catch (reason) {
      setError(api.normalizeError(reason));
    } finally {
      setBusy(false);
    }
  };

  // An empty list has nothing to choose between: the ayah becomes the current one.
  const started = useRef(false);
  useEffect(() => {
    if (preview?.state !== "empty" || started.current) return;
    started.current = true;
    void add("now", preview.revision);
  });

  const extendTo = preview?.extend_to;

  return (
    <dialog
      ref={dialog}
      className="ayah-annotation-dialog memorize-ayah-dialog"
      aria-labelledby={titleId}
      onClose={onClose}
      data-testid="memorize-ayah-dialog"
    >
      <div className="memorize-ayah-body">
        <div className="ayah-annotation-dialog-head">
          <h2 id={titleId}>{t("memorization.list.learnTitle", { range: range(ayah, ayah) })}</h2>
          <button
            type="button"
            className="btn btn-secondary btn-sm"
            onClick={() => dialog.current?.close()}
            aria-label={t("common.close")}
          >
            ×
          </button>
        </div>

        {error && <div className="alert alert-error" role="alert">{error}</div>}

        {done ? (
          <div className="memorize-ayah-actions" role="status">
            <p>{done}</p>
            <Link href={memorizationHref} className="btn btn-secondary">{t("memorization.list.open")}</Link>
          </div>
        ) : !preview || preview.state === "empty" ? (
          !error && <p className="field-help">{t("common.loading")}</p>
        ) : preview.state === "duplicate" ? (
          <div className="memorize-ayah-actions">
            <p>
              {preview.item
                ? t("memorization.list.alreadyIn", {
                    range: range(
                      preview.item.start_ayah.ayah_number,
                      preview.item.end_ayah.ayah_number,
                      preview.item.start_ayah.surah_number,
                    ),
                  })
                : t("memorization.list.alreadyInShort")}
            </p>
            <Link href={memorizationHref} className="btn btn-primary">{t("memorization.list.open")}</Link>
          </div>
        ) : preview.state === "extendable" && extendTo ? (
          <div className="memorize-ayah-actions">
            <p>{t("memorization.list.continuesCurrent")}</p>
            <button type="button" className="btn btn-primary" disabled={busy} onClick={() => void add("extend")}>
              {t("memorization.list.extendTo", {
                range: range(extendTo.start_ayah_number, extendTo.end_ayah_number, extendTo.surah_number),
              })}
            </button>
            <button type="button" className="btn btn-secondary" disabled={busy} onClick={() => void add("queue")}>
              {t("memorization.list.queueSeparately")}
            </button>
          </div>
        ) : (
          <div className="memorize-ayah-actions">
            {preview.item && (
              <p>
                {t("memorization.list.currentIs", {
                  range: range(
                    preview.item.start_ayah.ayah_number,
                    preview.item.end_ayah.ayah_number,
                    preview.item.start_ayah.surah_number,
                  ),
                })}
              </p>
            )}
            <button type="button" className="btn btn-primary" disabled={busy} onClick={() => void add("queue")}>
              {t("memorization.list.addToQueue")}
            </button>
            <button type="button" className="btn btn-secondary" disabled={busy} onClick={() => void add("now")}>
              {t("memorization.list.learnNow")}
            </button>
          </div>
        )}
      </div>
    </dialog>
  );
}
