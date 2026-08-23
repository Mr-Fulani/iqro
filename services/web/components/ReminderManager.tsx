"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";
import {
  api,
  Ayah,
  Reminder,
  ReminderTimezone,
  Surah,
} from "../lib/api";
import { useAuth } from "../lib/auth-context";

const WEEKDAYS = [
  [1, "Пн"],
  [2, "Вт"],
  [4, "Ср"],
  [8, "Чт"],
  [16, "Пт"],
  [32, "Сб"],
  [64, "Вс"],
] as const;

const PRAYER_LABELS: Record<string, string> = {
  fajr: "Фаджр",
  dhuhr: "Зухр",
  asr: "Аср",
  maghrib: "Магриб",
  isha: "Иша",
};

const REMINDER_TYPE_LABELS: Record<Reminder["reminder_type"], string> = {
  prayer: "Намаз",
  quran_reading: "Чтение Корана",
  quran_review: "Повторение аятов",
};

export function ReminderManager() {
  const { isLoggedIn } = useAuth();
  const [reminders, setReminders] = useState<Reminder[]>([]);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [editing, setEditing] = useState<Reminder | null>(null);

  const [reminderType, setReminderType] = useState<Reminder["reminder_type"]>("prayer");
  const [prayerEvent, setPrayerEvent] = useState<"fajr" | "dhuhr" | "asr" | "maghrib" | "isha">("fajr");
  const [prayerOffset, setPrayerOffset] = useState(-10);
  const [localTime, setLocalTime] = useState("07:30");
  const [weekdaysMask, setWeekdaysMask] = useState(127);
  const [timezoneMode, setTimezoneMode] = useState<ReminderTimezone["mode"]>("device_local");
  const [fixedTimezone, setFixedTimezone] = useState("Europe/Istanbul");
  const [signal, setSignal] = useState<Reminder["signal"]>("sound");
  const [isEnabled, setIsEnabled] = useState(true);

  const [surahs, setSurahs] = useState<Surah[]>([]);
  const [reviewSurah, setReviewSurah] = useState(1);
  const [reviewAyahs, setReviewAyahs] = useState<Ayah[]>([]);
  const [reviewStartId, setReviewStartId] = useState("");
  const [reviewEndId, setReviewEndId] = useState("");

  const activeReminders = useMemo(
    () => reminders.filter((reminder) => reminder.deleted_at === null),
    [reminders],
  );

  useEffect(() => {
    if (!isLoggedIn) {
      setReminders([]);
      return;
    }
    let active = true;
    setLoading(true);
    api
      .getReminders()
      .then((snapshot) => {
        if (active) setReminders(snapshot.reminders);
      })
      .catch((reason) => {
        if (active) setError(api.normalizeError(reason));
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [isLoggedIn]);

  useEffect(() => {
    if (reminderType !== "quran_review" || surahs.length > 0) return;
    api.getSurahs("madani-hafs").then(setSurahs).catch((reason) => {
      setError(api.normalizeError(reason));
    });
  }, [reminderType, surahs.length]);

  useEffect(() => {
    if (reminderType !== "quran_review") return;
    let active = true;
    api
      .getAyahs("madani-hafs", reviewSurah)
      .then((ayahs) => {
        if (!active) return;
        setReviewAyahs(ayahs);
        setReviewStartId((current) =>
          ayahs.some((ayah) => ayah.id === current) ? current : ayahs[0]?.id || "",
        );
        setReviewEndId((current) =>
          ayahs.some((ayah) => ayah.id === current) ? current : ayahs.at(-1)?.id || "",
        );
      })
      .catch((reason) => {
        if (active) setError(api.normalizeError(reason));
      });
    return () => {
      active = false;
    };
  }, [reminderType, reviewSurah]);

  const resetForm = () => {
    setEditing(null);
    setReminderType("prayer");
    setPrayerEvent("fajr");
    setPrayerOffset(-10);
    setLocalTime("07:30");
    setWeekdaysMask(127);
    setTimezoneMode("device_local");
    setFixedTimezone("Europe/Istanbul");
    setSignal("sound");
    setIsEnabled(true);
    setReviewSurah(1);
    setReviewStartId("");
    setReviewEndId("");
  };

  const beginEdit = (reminder: Reminder) => {
    if (!reminder.schedule) return;
    setEditing(reminder);
    setReminderType(reminder.reminder_type);
    if (reminder.schedule.kind === "prayer") {
      setPrayerEvent(reminder.schedule.prayer_event);
      setPrayerOffset(reminder.schedule.prayer_offset_minutes);
    } else {
      setLocalTime(reminder.schedule.local_time.slice(0, 5));
    }
    setWeekdaysMask(reminder.weekdays_mask);
    setTimezoneMode(reminder.timezone.mode);
    if (reminder.timezone.mode === "fixed") setFixedTimezone(reminder.timezone.name);
    setSignal(reminder.signal);
    setIsEnabled(reminder.is_enabled);
    if (reminder.review_target) {
      setReviewSurah(reminder.review_target.start.surah_number);
      setReviewStartId(reminder.review_target.start.id);
      setReviewEndId(reminder.review_target.end.id);
    }
    setError(null);
    setSuccess(null);
  };

  const saveReminder = async (event: FormEvent) => {
    event.preventDefault();
    if (weekdaysMask === 0) {
      setError("Выберите хотя бы один день недели.");
      return;
    }
    if (reminderType === "quran_review" && (!reviewStartId || !reviewEndId)) {
      setError("Выберите начало и конец диапазона аятов.");
      return;
    }
    setSaving(true);
    setError(null);
    setSuccess(null);
    const schedule =
      reminderType === "prayer"
        ? ({ kind: "prayer", prayer_event: prayerEvent, prayer_offset_minutes: prayerOffset } as const)
        : ({ kind: "local_time", local_time: `${localTime}:00` } as const);
    const timezone: ReminderTimezone =
      timezoneMode === "fixed"
        ? { mode: "fixed", name: fixedTimezone }
        : { mode: "device_local" };
    const reviewTarget =
      reminderType === "quran_review"
        ? { start_ayah_id: reviewStartId, end_ayah_id: reviewEndId }
        : undefined;
    try {
      const saved = editing
        ? await api.updateReminder(editing.id, {
            base_revision: editing.revision,
            reminder_type: reminderType,
            schedule,
            review_target: reviewTarget || null,
            weekdays_mask: weekdaysMask,
            timezone,
            signal,
            is_enabled: isEnabled,
          })
        : await api.createReminder({
            reminder_type: reminderType,
            schedule,
            ...(reviewTarget ? { review_target: reviewTarget } : {}),
            weekdays_mask: weekdaysMask,
            timezone,
            signal,
            is_enabled: isEnabled,
          });
      setReminders((previous) => {
        const withoutSaved = previous.filter((item) => item.id !== saved.id);
        return [saved, ...withoutSaved];
      });
      setSuccess(editing ? "Напоминание обновлено." : "Напоминание создано.");
      resetForm();
    } catch (reason) {
      setError(api.normalizeError(reason));
    } finally {
      setSaving(false);
    }
  };

  const toggleReminder = async (reminder: Reminder) => {
    setError(null);
    try {
      const updated = await api.updateReminder(reminder.id, {
        base_revision: reminder.revision,
        is_enabled: !reminder.is_enabled,
      });
      setReminders((previous) =>
        previous.map((item) => (item.id === updated.id ? updated : item)),
      );
    } catch (reason) {
      setError(api.normalizeError(reason));
    }
  };

  const removeReminder = async (reminder: Reminder) => {
    setError(null);
    try {
      const deleted = await api.deleteReminder(reminder.id, reminder.revision);
      setReminders((previous) =>
        previous.map((item) => (item.id === deleted.id ? deleted : item)),
      );
      if (editing?.id === reminder.id) resetForm();
      setSuccess("Напоминание удалено.");
    } catch (reason) {
      setError(api.normalizeError(reason));
    }
  };

  const toggleWeekday = (bit: number) => {
    setWeekdaysMask((current) => (current & bit ? current & ~bit : current | bit));
  };

  if (!isLoggedIn) return null;

  return (
    <section className="surface">
      <div className="surface-head">
        <div>
          <h3 className="surface-title">Напоминания</h3>
          <p className="surface-subtitle">
            Правила синхронизируются между устройствами. В web они работают как настройки;
            системное расписание уведомлений будет исполнять мобильный клиент.
          </p>
        </div>
        <span className="status-chip">Активных: {activeReminders.length}</span>
      </div>

      {error && <div className="alert alert-error" style={{ marginBottom: 12 }}>{error}</div>}
      {success && <div className="alert alert-success" style={{ marginBottom: 12 }}>{success}</div>}

      <form
        onSubmit={(event) => void saveReminder(event)}
        style={{
          padding: 16,
          background: "var(--bg-subtle)",
          borderRadius: "var(--radius-md)",
          display: "flex",
          flexDirection: "column",
          gap: 12,
          marginBottom: 18,
        }}
      >
        <div className="form-row">
          <div className="form-group">
            <label className="form-label" htmlFor="reminder-type">Тип</label>
            <select
              id="reminder-type"
              value={reminderType}
              onChange={(event) =>
                setReminderType(event.target.value as Reminder["reminder_type"])
              }
            >
              <option value="prayer">Намаз</option>
              <option value="quran_reading">Чтение Корана</option>
              <option value="quran_review">Повторение аятов</option>
            </select>
          </div>

          {reminderType === "prayer" ? (
            <>
              <div className="form-group">
                <label className="form-label" htmlFor="reminder-prayer">Молитва</label>
                <select
                  id="reminder-prayer"
                  value={prayerEvent}
                  onChange={(event) =>
                    setPrayerEvent(event.target.value as typeof prayerEvent)
                  }
                >
                  {Object.entries(PRAYER_LABELS).map(([value, label]) => (
                    <option key={value} value={value}>{label}</option>
                  ))}
                </select>
              </div>
              <div className="form-group">
                <label className="form-label" htmlFor="reminder-offset">Смещение, минут</label>
                <input
                  id="reminder-offset"
                  type="number"
                  min={-120}
                  max={120}
                  value={prayerOffset}
                  onChange={(event) => setPrayerOffset(Number(event.target.value))}
                />
              </div>
            </>
          ) : (
            <div className="form-group">
              <label className="form-label" htmlFor="reminder-time">Локальное время</label>
              <input
                id="reminder-time"
                type="time"
                value={localTime}
                onChange={(event) => setLocalTime(event.target.value)}
              />
            </div>
          )}

          <div className="form-group">
            <label className="form-label" htmlFor="reminder-signal">Сигнал</label>
            <select
              id="reminder-signal"
              value={signal}
              onChange={(event) => setSignal(event.target.value as Reminder["signal"])}
            >
              <option value="sound">Короткий звук</option>
              <option value="vibration">Вибрация</option>
              <option value="silent">Без звука</option>
            </select>
          </div>
        </div>

        {reminderType === "quran_review" && (
          <div className="form-row">
            <div className="form-group">
              <label className="form-label" htmlFor="review-surah">Сура</label>
              <select
                id="review-surah"
                value={reviewSurah}
                onChange={(event) => setReviewSurah(Number(event.target.value))}
              >
                {surahs.map((surah) => (
                  <option key={surah.id} value={surah.number}>
                    {surah.number}. {surah.name_ru}
                  </option>
                ))}
              </select>
            </div>
            <div className="form-group">
              <label className="form-label" htmlFor="review-start">Начальный аят</label>
              <select
                id="review-start"
                value={reviewStartId}
                onChange={(event) => setReviewStartId(event.target.value)}
              >
                {reviewAyahs.map((ayah) => (
                  <option key={ayah.id} value={ayah.id}>{ayah.number}</option>
                ))}
              </select>
            </div>
            <div className="form-group">
              <label className="form-label" htmlFor="review-end">Конечный аят</label>
              <select
                id="review-end"
                value={reviewEndId}
                onChange={(event) => setReviewEndId(event.target.value)}
              >
                {reviewAyahs.map((ayah) => (
                  <option key={ayah.id} value={ayah.id}>{ayah.number}</option>
                ))}
              </select>
            </div>
          </div>
        )}

        <div>
          <p className="form-label" style={{ marginBottom: 8 }}>Дни недели</p>
          <div style={{ display: "flex", gap: 10, flexWrap: "wrap" }}>
            {WEEKDAYS.map(([bit, label]) => (
              <label key={bit} style={{ display: "flex", gap: 5, alignItems: "center" }}>
                <input
                  type="checkbox"
                  checked={Boolean(weekdaysMask & bit)}
                  onChange={() => toggleWeekday(bit)}
                />
                {label}
              </label>
            ))}
          </div>
        </div>

        <div className="form-row">
          <div className="form-group">
            <label className="form-label" htmlFor="reminder-timezone-mode">Timezone</label>
            <select
              id="reminder-timezone-mode"
              value={timezoneMode}
              onChange={(event) =>
                setTimezoneMode(event.target.value as ReminderTimezone["mode"])
              }
            >
              <option value="device_local">Timezone устройства</option>
              <option value="fixed">Фиксированный</option>
            </select>
          </div>
          {timezoneMode === "fixed" && (
            <div className="form-group">
              <label className="form-label" htmlFor="reminder-fixed-timezone">IANA timezone</label>
              <input
                id="reminder-fixed-timezone"
                value={fixedTimezone}
                onChange={(event) => setFixedTimezone(event.target.value)}
              />
            </div>
          )}
          <label style={{ display: "flex", gap: 8, alignItems: "center" }}>
            <input
              type="checkbox"
              checked={isEnabled}
              onChange={(event) => setIsEnabled(event.target.checked)}
            />
            Включено
          </label>
        </div>

        <div style={{ display: "flex", gap: 8 }}>
          <button className="btn btn-primary btn-sm" disabled={saving}>
            {saving ? "Сохранение..." : editing ? "Сохранить изменения" : "Создать напоминание"}
          </button>
          {editing && (
            <button className="btn btn-secondary btn-sm" type="button" onClick={resetForm}>
              Отмена
            </button>
          )}
        </div>
      </form>

      {loading ? (
        <p className="kpi-desc">Загрузка напоминаний...</p>
      ) : activeReminders.length === 0 ? (
        <p className="kpi-desc">Напоминаний пока нет.</p>
      ) : (
        <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
          {activeReminders.map((reminder) => (
            <div className="track-row" key={reminder.id}>
              <div>
                <strong>{REMINDER_TYPE_LABELS[reminder.reminder_type]}</strong>
                <p className="kpi-desc">{formatSchedule(reminder)}</p>
              </div>
              <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
                <span className={`status-chip ${reminder.is_enabled ? "ok" : ""}`}>
                  {reminder.is_enabled ? "Включено" : "Выключено"}
                </span>
                <button
                  className="btn btn-secondary btn-sm"
                  type="button"
                  onClick={() => void toggleReminder(reminder)}
                >
                  {reminder.is_enabled ? "Отключить" : "Включить"}
                </button>
                <button className="btn btn-secondary btn-sm" type="button" onClick={() => beginEdit(reminder)}>
                  Изменить
                </button>
                <button className="btn btn-danger btn-sm" type="button" onClick={() => void removeReminder(reminder)}>
                  Удалить
                </button>
              </div>
            </div>
          ))}
        </div>
      )}
    </section>
  );
}

function formatSchedule(reminder: Reminder): string {
  if (!reminder.schedule) return "Удалено";
  const schedule =
    reminder.schedule.kind === "prayer"
      ? `${PRAYER_LABELS[reminder.schedule.prayer_event]} ${formatOffset(reminder.schedule.prayer_offset_minutes)}`
      : reminder.schedule.local_time.slice(0, 5);
  const timezone =
    reminder.timezone.mode === "fixed" ? reminder.timezone.name : "timezone устройства";
  const review = reminder.review_target
    ? ` · ${reminder.review_target.start.surah_number}:${reminder.review_target.start.ayah_number}–${reminder.review_target.end.surah_number}:${reminder.review_target.end.ayah_number}`
    : "";
  return `${schedule}${review} · ${timezone}`;
}

function formatOffset(minutes: number): string {
  if (minutes === 0) return "точно по времени";
  return minutes > 0 ? `через ${minutes} мин.` : `за ${Math.abs(minutes)} мин.`;
}
