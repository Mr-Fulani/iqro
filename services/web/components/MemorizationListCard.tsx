"use client";

import { useState } from "react";
import { api, type MemorizationItem, type MemorizationList, type Surah } from "../lib/api";
import { useI18n } from "../lib/i18n-context";

type MemorizationListCardProps = {
  list: MemorizationList;
  surahs: Surah[];
  /** Reloads the dashboard after the list changed on the server. */
  onChanged: () => Promise<unknown>;
};

/**
 * The current range, the queue and the memorized count, above the practice.
 * Marking the current range memorized offers the next queued one.
 */
export function MemorizationListCard({ list, surahs, onChanged }: MemorizationListCardProps) {
  const { formatNumber, locale, t } = useI18n();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const active = list.items.find((item) => item.status === "active") ?? null;
  const queued = list.items.filter((item) => item.status === "queued");
  // With no current range (just marked memorized) the queue's head is offered.
  const next = active ? null : queued[0] ?? null;

  const label = (item: MemorizationItem) => {
    const surah = surahs.find((entry) => entry.number === item.start_ayah.surah_number);
    const name = surah
      ? locale === "ar" ? surah.name_ar : locale === "ru" ? surah.name_ru : surah.name_en
      : formatNumber(item.start_ayah.surah_number);
    const start = formatNumber(item.start_ayah.ayah_number);
    const end = formatNumber(item.end_ayah.ayah_number);
    return t("memorization.list.itemRange", {
      surah: name,
      range: start === end ? start : `${start}–${end}`,
    });
  };

  const run = async (action: () => Promise<unknown>) => {
    setBusy(true);
    setError(null);
    try {
      await action();
      await onChanged();
      window.dispatchEvent(new Event("memorization-progress-changed"));
    } catch (reason) {
      setError(api.normalizeError(reason));
      await onChanged().catch(() => undefined);
    } finally {
      setBusy(false);
    }
  };

  const start = (item: MemorizationItem) => run(() => api.updateMemorizationItem(item.id, {
    status: "active",
    base_revision: list.revision,
  }));

  return (
    <section className="surface memorization-list" data-testid="memorization-list">
      <div className="memorization-list-head">
        <div>
          <p className="eyebrow">{t("memorization.list.current")}</p>
          <strong data-testid="memorization-list-current">
            {active ? label(active) : t("memorization.list.noCurrent")}
          </strong>
        </div>
        <span className="memorization-list-count">
          {t("memorization.list.memorizedCount", { count: formatNumber(list.memorized_ayah_count) })}
        </span>
      </div>
      {active && (
        <button
          type="button"
          className="btn btn-secondary btn-sm"
          disabled={busy}
          onClick={() => void run(() => api.updateMemorizationItem(active.id, {
            status: "memorized",
            base_revision: list.revision,
          }))}
        >
          {t("memorization.list.markMemorized")}
        </button>
      )}
      {next && (
        <div className="memorization-list-next" role="status">
          <span>{t("memorization.list.nextPrompt", { range: label(next) })}</span>
          <button type="button" className="btn btn-primary btn-sm" disabled={busy} onClick={() => void start(next)}>
            {t("memorization.list.begin")}
          </button>
        </div>
      )}
      {queued.length > 0 && (
        <div className="memorization-list-queue">
          <p className="form-label">{t("memorization.list.queue", { count: formatNumber(queued.length) })}</p>
          <ol>
            {queued.map((item) => (
              <li key={item.id}>
                <span>{label(item)}</span>
                <span className="memorization-list-queue-actions">
                  <button type="button" className="btn btn-secondary btn-sm" disabled={busy} onClick={() => void start(item)}>
                    {t("memorization.list.learnNow")}
                  </button>
                  <button
                    type="button"
                    className="btn btn-secondary btn-sm"
                    disabled={busy}
                    onClick={() => void run(() => api.removeMemorizationItem(item.id, list.revision))}
                    aria-label={t("memorization.list.remove", { range: label(item) })}
                  >
                    ×
                  </button>
                </span>
              </li>
            ))}
          </ol>
        </div>
      )}
      {error && <p className="error-text" role="alert">{error}</p>}
    </section>
  );
}
