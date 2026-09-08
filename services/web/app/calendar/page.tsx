"use client";

import { useEffect, useState } from "react";
import { api } from "../../lib/api";
import {
  calendarCopy,
  calendarEventsForDay,
  civilToday,
  sourceHref,
  type CalendarEvent,
  type CalendarMonth,
} from "../../lib/calendar";
import { useI18n } from "../../lib/i18n-context";
import styles from "./page.module.css";

const preferenceKey = "iqro_hijri_adjustment_v1";

const eventIcon = (event: CalendarEvent) => event.kind === "voluntary_fast"
  ? "☾"
  : event.kind === "no_fast"
    ? "✦"
    : "◆";

export default function CalendarPage() {
  const { locale } = useI18n();
  const copy = calendarCopy[locale];
  const [query, setQuery] = useState<{date: string} | {year: number; month: number} | null>(null);
  const [adjustment, setAdjustment] = useState(0);
  const [data, setData] = useState<CalendarMonth | null>(null);
  const [selected, setSelected] = useState(1);
  const [loading, setLoading] = useState(true);
  const [failed, setFailed] = useState(false);
  const [refresh, setRefresh] = useState(0);

  useEffect(() => {
    try {
      const stored = Number(localStorage.getItem(preferenceKey) ?? 0);
      if (Number.isInteger(stored) && stored >= -2 && stored <= 2) setAdjustment(stored);
    } catch { /* Storage may be unavailable; calendar still works. */ }
    setQuery({date: civilToday()});
    const timer = window.setInterval(() => {
      if (document.visibilityState === "visible") setRefresh((value) => value + 1);
    }, 300_000);
    return () => window.clearInterval(timer);
  }, []);

  useEffect(() => {
    if (!query) return;
    const controller = new AbortController();
    const timeout = window.setTimeout(() => controller.abort(), 20_000);
    let active = true;
    const params = new URLSearchParams({adjustment: String(adjustment)});
    for (const [key, value] of Object.entries(query)) params.set(key, String(value));
    setLoading(true);
    setFailed(false);
    api.request<CalendarMonth>(`/api/v1/calendar/month?${params}`, {signal: controller.signal})
      .then((result) => {
        if (!active) return;
        if (result.method !== "ummalqura-hijri-3.0.1" || !Array.isArray(result.catalog?.events)) throw new Error("Unsupported calendar");
        setData(result);
        setSelected((current) => result.selected_day ?? Math.min(current, result.days.length));
      })
      .catch(() => { if (active) setFailed(true); })
      .finally(() => { if (active) setLoading(false); window.clearTimeout(timeout); });
    return () => { active = false; controller.abort(); window.clearTimeout(timeout); };
  }, [query, adjustment, refresh]);

  const number = (value: number) => new Intl.NumberFormat(locale, {useGrouping: false}).format(value);
  const civilLabel = (value: string, full = false) => new Intl.DateTimeFormat(locale, {
    calendar: "gregory", timeZone: "UTC", ...(full ? {dateStyle: "full" as const} : {day: "numeric" as const}),
  }).format(new Date(`${value}T12:00:00Z`));
  const day = data?.days.find((value) => value.day === selected);
  const events = data && day ? calendarEventsForDay(data, day) : [];
  const firstWeekday = locale === "ar" ? 7 : 1;
  const skip = data ? (data.first_weekday - firstWeekday + 7) % 7 : 0;
  const shift = (delta: number) => {
    if (!data || loading) return;
    const absolute = data.year * 12 + data.month - 1 + delta;
    setSelected(1);
    setQuery({year: Math.floor(absolute / 12), month: absolute % 12 + 1});
  };
  const changeAdjustment = (value: number) => {
    setAdjustment(value);
    try { localStorage.setItem(preferenceKey, String(value)); } catch { /* Optional storage. */ }
  };

  return <div className={styles.page}>
    <header className={styles.hero}>
      <span className={styles.moon} aria-hidden="true">☾</span>
      <p className="eyebrow">{copy.subtitle}</p>
      <h1>{copy.title}</h1>
      <p>{copy.method} · 1356–1500 {copy.suffix}</p>
    </header>
    <div className={styles.controls}>
      <label>{copy.civil}<input type="date" aria-label={copy.civil} value={day?.civil_date ?? ""}
        min="1937-03-16" max="2077-11-14" onChange={(event) => {
          if (event.target.value) setQuery({date: event.target.value});
        }} /></label>
      <label>{copy.adjustment}<select value={adjustment} onChange={(event) => changeAdjustment(Number(event.target.value))}>
        {[-2, -1, 0, 1, 2].map((value) => <option key={value} value={value}>{value > 0 ? "+" : ""}{number(value)}</option>)}
      </select></label>
      <button className="btn btn-secondary" onClick={() => setQuery({date: civilToday()})}>{copy.today}</button>
    </div>
    <p className={styles.note}>{copy.adjustmentHint}</p>
    <div role="status" aria-live="polite">
      {loading && <p>{copy.loading}</p>}
      {failed && <p>{copy.error} <button className="btn btn-secondary" onClick={() => setRefresh((n) => n + 1)}>{copy.retry}</button></p>}
    </div>
    {data && <div className={styles.columns} aria-busy={loading}>
      <section className={styles.panel} aria-label={copy.title}>
        <div className={styles.monthHeader}>
          <button className="btn btn-ghost" aria-label={copy.previous} disabled={loading || (data.year === 1356 && data.month === 1)} onClick={() => shift(-1)}>{locale === "ar" ? "→" : "←"}</button>
          <h2>{copy.months[data.month - 1]} {number(data.year)}</h2>
          <button className="btn btn-ghost" aria-label={copy.next} disabled={loading || (data.year === 1500 && data.month === 12)} onClick={() => shift(1)}>{locale === "ar" ? "←" : "→"}</button>
        </div>
        <div className={styles.legend} aria-label={copy.legend}>
          <span><i className={styles.occasionMarker} aria-hidden="true">◆</i>{copy.occasion}</span>
          <span><i className={styles.fastMarker} aria-hidden="true">☾</i>{copy.voluntaryFast}</span>
          <span><i className={styles.noFastMarker} aria-hidden="true">✦</i>{copy.noFast}</span>
        </div>
        <p className={styles.markerHint}>{copy.markerHint}</p>
        <div className={styles.grid}>
          {Array.from({length: 7}, (_, index) => <div className={styles.weekday} key={`weekday-${index}`}>
            {new Intl.DateTimeFormat(locale, {weekday: "short", timeZone: "UTC"}).format(new Date(Date.UTC(2026, 0, 5 + (firstWeekday - 1 + index) % 7)))}
          </div>)}
          {Array.from({length: skip}, (_, index) => <span key={`empty-${index}`} />)}
          {data.days.map((item) => {
            const itemEvents = calendarEventsForDay(data, item);
            const eventTitles = itemEvents.map((event) => event.titles[locale]).join(" · ");
            return <button key={item.day} className={`${styles.day} ${item.day === selected ? styles.selected : ""}`}
              aria-pressed={item.day === selected} disabled={loading}
              aria-label={`${number(item.day)} ${copy.months[data.month - 1]}, ${civilLabel(item.civil_date, true)}${eventTitles ? ` · ${eventTitles}` : ""}`}
              data-testid={`calendar-day-${item.day}`}
              onClick={() => setSelected(item.day)}>
              <strong>{number(item.day)}</strong><span>{civilLabel(item.civil_date)}</span>
              {itemEvents.length > 0 && <>
                <span className={styles.markers} aria-hidden="true">
                  {itemEvents.map((event) => <i
                    key={event.code}
                    className={event.kind === "voluntary_fast" ? styles.fastMarker : event.kind === "no_fast" ? styles.noFastMarker : styles.occasionMarker}
                    data-testid={`calendar-marker-${event.code}`}
                  >{eventIcon(event)}</i>)}
                </span>
                <span className={styles.dayTooltip} role="tooltip">{eventTitles}</span>
              </>}
            </button>;
          })}
        </div>
      </section>
      <aside className={styles.panel} aria-live="polite">
        <p className="eyebrow">{copy.method}</p>
        <h2>{number(selected)} {copy.months[data.month - 1]} {number(data.year)} {copy.suffix}</h2>
        {day && <p className={styles.note}>{civilLabel(day.civil_date, true)}</p>}
        {!events.length && <p>{copy.noEvents}</p>}
        {events.map((event) => <article className={styles.event} key={event.code}>
          <div className={styles.eventHeading}>
            <i className={event.kind === "voluntary_fast" ? styles.fastMarker : event.kind === "no_fast" ? styles.noFastMarker : styles.occasionMarker} aria-hidden="true">{eventIcon(event)}</i>
            <div><span>{event.kind === "voluntary_fast" ? copy.voluntaryFast : event.kind === "no_fast" ? copy.noFast : copy.occasion}</span><h3>{event.titles[locale]}</h3></div>
          </div>
          <p>{event.descriptions[locale]}</p>
          {sourceHref(event.source.url) && <a href={sourceHref(event.source.url)} target="_blank" rel="noopener noreferrer">{copy.source}: {event.source.label} ↗</a>}
        </article>)}
      </aside>
    </div>}
    <footer className={styles.disclaimer}><p>{copy.disclaimer}</p><p>{copy.hint}</p></footer>
  </div>;
}
