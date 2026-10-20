"use client";

import { useMemo, useState } from "react";
import { PrayerAdjustments, PrayerMethodsResponse } from "../lib/api";
import { useI18n } from "../lib/i18n-context";
import { MessageKey } from "../lib/i18n";
import { dateInTimezone } from "../lib/prayer-location";
import { calculatePrayerMonth, localPrayerMethod, PRAYER_CODES } from "../lib/prayer-engine";

export type PrayerMonthInput = {
  date: string;
  latitude: number;
  longitude: number;
  timezone: string;
  methodId: string;
  asrMethod: "standard" | "hanafi";
  highLatitudeRule: string;
  polarResolution: string;
  adjustments: PrayerAdjustments;
};

const PRAYER_LABELS: Record<(typeof PRAYER_CODES)[number], MessageKey> = {
  fajr: "prayer.fajr",
  sunrise: "prayer.sunrise",
  dhuhr: "prayer.dhuhr",
  asr: "prayer.asr",
  maghrib: "prayer.maghrib",
  isha: "prayer.isha",
};

export default function PrayerMonthCalendar({
  catalog,
  input,
}: {
  catalog: PrayerMethodsResponse;
  input: PrayerMonthInput;
}) {
  const { t, formatDate, direction } = useI18n();
  const [month, setMonth] = useState(() => {
    const [year, monthNumber] = input.date.split("-").map(Number);
    return { year, month: monthNumber };
  });

  const method = useMemo(() => localPrayerMethod(catalog, input.methodId), [catalog, input.methodId]);
  const days = useMemo(() => {
    if (!method) return null;
    try {
      return calculatePrayerMonth(
        {
          latitude: input.latitude,
          longitude: input.longitude,
          method,
          highLatitudeRule: input.highLatitudeRule,
          polarResolution: input.polarResolution,
          hanafiAsr: input.asrMethod === "hanafi",
          adjustments: input.adjustments,
        },
        input.timezone,
        month.year,
        month.month,
      );
    } catch {
      return null;
    }
  }, [input, method, month]);

  const changeMonth = (delta: number) => {
    const next = new Date(Date.UTC(month.year, month.month - 1 + delta, 1));
    const year = next.getUTCFullYear();
    if (year < 1900 || year > 2100) return;
    setMonth({ year, month: next.getUTCMonth() + 1 });
  };

  const today = dateInTimezone(input.timezone);
  // 24-hour times keep the table compact, as the app's calendar does.
  const formatTime = (instant: number) =>
    formatDate(instant, {
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23",
      timeZone: input.timezone,
    });

  return (
    <div className="prayer-month" data-testid="prayer-month">
      <div className="prayer-month-nav">
        <button
          type="button"
          className="btn btn-secondary btn-sm"
          aria-label={t("prayer.previousMonth")}
          onClick={() => changeMonth(-1)}
        >
          {direction === "rtl" ? "›" : "‹"}
        </button>
        <h3 className="surface-title" data-testid="prayer-month-title">
          {formatDate(Date.UTC(month.year, month.month - 1, 1), {
            month: "long",
            year: "numeric",
            timeZone: "UTC",
          })}
        </h3>
        <button
          type="button"
          className="btn btn-secondary btn-sm"
          aria-label={t("prayer.nextMonth")}
          onClick={() => changeMonth(1)}
        >
          {direction === "rtl" ? "‹" : "›"}
        </button>
      </div>

      {!method ? (
        <div className="alert alert-info">{t("prayer.monthUnsupported")}</div>
      ) : !days ? (
        <div className="alert alert-error">{t("prayer.monthFailed")}</div>
      ) : (
        <div className="prayer-month-scroll">
          <table className="prayer-month-table">
            <caption className="sr-only">{t("prayer.monthTitle")}</caption>
            <thead>
              <tr>
                <th scope="col">{t("prayer.monthDate")}</th>
                {PRAYER_CODES.map((code) => (
                  <th scope="col" key={code}>
                    {t(PRAYER_LABELS[code])}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {days.map((day) => {
                const isToday = day.date === today;
                const [year, monthNumber, dayNumber] = day.date.split("-").map(Number);
                return (
                  <tr
                    key={day.date}
                    className={isToday ? "is-today" : undefined}
                    aria-current={isToday ? "date" : undefined}
                    data-date={day.date}
                  >
                    <th scope="row">
                      {formatDate(Date.UTC(year, monthNumber - 1, dayNumber), {
                        weekday: "short",
                        day: "numeric",
                        timeZone: "UTC",
                      })}
                      {isToday && <span className="prayer-month-today">{t("prayer.today")}</span>}
                    </th>
                    {PRAYER_CODES.map((code) => (
                      <td key={code}>{formatTime(day.timesUtc[code])}</td>
                    ))}
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
