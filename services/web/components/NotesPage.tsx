"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { api, type AyahAnnotation } from "../lib/api";
import { ayahNotes } from "../lib/ayah-annotations";
import { useAuth } from "../lib/auth-context";
import { useI18n } from "../lib/i18n-context";
import { localizedPath } from "../lib/routing";
import { SYNC_STATE_EVENT } from "../lib/sync-state";

/** Notes on ayahs, newest first, as on the app's Notes screen. */
export default function NotesPage() {
  const { locale, t } = useI18n();
  const { isLoading: authLoading, session } = useAuth();
  const userId = session?.user.id ?? null;
  const [annotations, setAnnotations] = useState<AyahAnnotation[]>([]);
  const [syncing, setSyncing] = useState(true);
  const [syncFailed, setSyncFailed] = useState(false);

  useEffect(() => {
    if (authLoading) return;
    if (!userId) {
      setAnnotations([]);
      setSyncing(false);
      return;
    }
    let cancelled = false;
    const refresh = () => setAnnotations(api.getAyahAnnotations());
    refresh();
    setSyncing(true);
    setSyncFailed(false);
    api
      .syncNow()
      .catch(() => {
        if (!cancelled) setSyncFailed(true);
      })
      .finally(() => {
        if (!cancelled) setSyncing(false);
      });
    window.addEventListener(SYNC_STATE_EVENT, refresh);
    return () => {
      cancelled = true;
      window.removeEventListener(SYNC_STATE_EVENT, refresh);
    };
  }, [authLoading, userId]);

  const notes = ayahNotes(annotations);
  const surahName = (ayah: NonNullable<AyahAnnotation["ayah"]>) => {
    if (locale === "ar") return ayah.surah_name_ar;
    if (locale === "ru") return ayah.surah_name_ru || ayah.surah_name_en;
    return ayah.surah_name_en;
  };

  return (
    <section className="surface" aria-busy={syncing}>
      <div className="surface-head">
        <div>
          <h1 className="surface-title">{t("notes.title")}</h1>
          <p className="surface-subtitle">{t("notes.description")}</p>
        </div>
      </div>

      {syncFailed && (
        <div className="alert alert-error" role="status" style={{ marginBottom: 16 }}>
          {t("notes.syncFailed")}
        </div>
      )}

      {notes.length > 0 ? (
        <ul className="notes-list">
          {notes.map((annotation) => {
            const ayah = annotation.ayah!;
            const name = surahName(ayah);
            return (
              <li key={annotation.id}>
                <Link
                  className="notes-item"
                  href={localizedPath(
                    locale,
                    `/quran?surah=${ayah.surah_number}&ayah=${ayah.ayah_number}`,
                  )}
                  data-highlight={annotation.color_key}
                >
                  <span className="ayah-annotation-swatch" aria-hidden="true" />
                  <span>
                    <strong>
                      {t("common.surah", { surah: ayah.surah_number })}
                      {name ? ` ${name}` : ""}
                      {" · "}
                      {t("common.ayah", { ayah: ayah.ayah_number })}
                    </strong>
                    <p dir="auto">{annotation.note}</p>
                  </span>
                </Link>
              </li>
            );
          })}
        </ul>
      ) : syncing ? (
        <p className="kpi-desc">{t("common.loading")}</p>
      ) : (
        <div style={{ textAlign: "center", padding: "24px 0" }}>
          <p className="kpi-desc" style={{ marginBottom: 16 }}>{t("notes.empty")}</p>
          <Link href={localizedPath(locale, "/quran")} className="btn btn-primary">
            {t("nav.quran")}
          </Link>
        </div>
      )}
    </section>
  );
}
