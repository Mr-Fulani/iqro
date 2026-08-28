"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api, MemorizationDashboard } from "../lib/api";
import { useAuth } from "../lib/auth-context";
import { useI18n } from "../lib/i18n-context";
import { localizedPath } from "../lib/routing";

function browserTimezone(): string {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
  } catch {
    return "UTC";
  }
}

export function MemorizationPlannerCard() {
  const { session, isLoading: authLoading } = useAuth();
  const { formatNumber, locale, t } = useI18n();
  const [dashboard, setDashboard] = useState<MemorizationDashboard | null>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    if (!api.getSession()) {
      setLoading(false);
      return;
    }
    setLoading(true);
    try {
      setDashboard(await api.getMemorizationDashboard(browserTimezone(), 7));
    } catch {
      setDashboard(null);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (!authLoading) void load();
  }, [authLoading, load, session]);

  useEffect(() => {
    const refresh = () => void load();
    window.addEventListener("memorization-progress-changed", refresh);
    return () => window.removeEventListener("memorization-progress-changed", refresh);
  }, [load]);

  const completed = dashboard?.today.completed_repetitions || 0;
  const target = dashboard?.today.target_repetitions || 0;
  const percent = target > 0 ? Math.min(100, (completed / target) * 100) : 0;

  return (
    <section className="surface memorization-planner-card" data-testid="memorization-planner-card">
      <div className="surface-head">
        <div>
          <p className="eyebrow">{t("memorization.plannerEyebrow")}</p>
          <h2 className="surface-title">{t("memorization.plannerTitle")}</h2>
          <p className="surface-subtitle">
            {dashboard?.plan
              ? t("memorization.rangeTitle", {
                  surah: formatNumber(dashboard.plan.start_ayah.surah_number),
                  start: formatNumber(dashboard.plan.start_ayah.ayah_number),
                  end: formatNumber(dashboard.plan.end_ayah.ayah_number),
                })
              : t("memorization.plannerEmpty")}
          </p>
        </div>
        <Link href={localizedPath(locale, "/memorization")} className="btn btn-primary">
          {dashboard?.plan ? t("memorization.continue") : t("memorization.createPlan")}
        </Link>
      </div>
      {loading ? <p>{t("common.loading")}</p> : dashboard?.plan && (
        <>
          <div className="today-progress-track" aria-label={t("memorization.todayProgress")}>
            <span style={{ width: `${percent}%` }} />
          </div>
          <p className="field-help">
            {t("memorization.progressSummary", {
              completed: formatNumber(completed),
              target: formatNumber(target),
            })}
          </p>
        </>
      )}
    </section>
  );
}
