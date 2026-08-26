"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";
import {
  api,
  Ayah,
  Reminder,
  ReminderTimezone,
  Surah,
  WebPushSubscriptionInput,
  WebPushStatus,
} from "../lib/api";
import { useAuth } from "../lib/auth-context";
import { useI18n } from "../lib/i18n-context";
import { MessageKey } from "../lib/i18n";

const WEEKDAYS = [
  [1, "reminder.weekday.mon"],
  [2, "reminder.weekday.tue"],
  [4, "reminder.weekday.wed"],
  [8, "reminder.weekday.thu"],
  [16, "reminder.weekday.fri"],
  [32, "reminder.weekday.sat"],
  [64, "reminder.weekday.sun"],
] as const;

const PRAYER_LABELS: Record<string, MessageKey> = {
  fajr: "prayer.fajr",
  dhuhr: "prayer.dhuhr",
  asr: "prayer.asr",
  maghrib: "prayer.maghrib",
  isha: "prayer.isha",
};

const REMINDER_TYPE_LABELS: Record<Reminder["reminder_type"], MessageKey> = {
  prayer: "reminder.type.prayer",
  quran_reading: "reminder.type.reading",
  quran_review: "reminder.type.review",
};

export function ReminderManager() {
  const { isLoggedIn } = useAuth();
  const { locale, t } = useI18n();
  const [reminders, setReminders] = useState<Reminder[]>([]);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [editing, setEditing] = useState<Reminder | null>(null);
  const [webPushStatus, setWebPushStatus] = useState<WebPushStatus | null>(null);
  const [webPushSupported, setWebPushSupported] = useState<boolean | null>(null);
  const [webPushSaving, setWebPushSaving] = useState(false);
  const [webPushNotice, setWebPushNotice] = useState<{
    kind: "error" | "success";
    message: string;
  } | null>(null);

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
    setWebPushSupported(
      "Notification" in window &&
        "serviceWorker" in navigator &&
        "PushManager" in window,
    );
  }, []);

  useEffect(() => {
    if (!isLoggedIn) {
      setReminders([]);
      setWebPushStatus(null);
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
    if (!isLoggedIn) return;
    let active = true;
    api
      .getWebPushStatus()
      .then((status) => {
        if (active) setWebPushStatus(status);
      })
      .catch((reason) => {
        if (active) {
          setWebPushNotice({ kind: "error", message: api.normalizeError(reason) });
        }
      });
    return () => {
      active = false;
    };
  }, [isLoggedIn]);

  useEffect(() => {
    if (!webPushStatus?.enabled || !webPushSupported) return;
    const timezoneName = browserTimezone();
    if (webPushStatus.timezone_name === timezoneName && webPushStatus.locale === locale) {
      return;
    }
    let active = true;
    navigator.serviceWorker
      .getRegistration("/")
      .then((registration) => registration?.pushManager.getSubscription())
      .then((subscription) => {
        if (!subscription) return undefined;
        return api.enableWebPush(
          serializePushSubscription(
            subscription,
            locale,
            t("reminder.webPushInvalidSubscription"),
          ),
        );
      })
      .then((status) => {
        if (active && status) setWebPushStatus(status);
      })
      .catch((reason) => {
        if (active) {
          setWebPushNotice({ kind: "error", message: api.normalizeError(reason) });
        }
      });
    return () => {
      active = false;
    };
  }, [locale, t, webPushStatus, webPushSupported]);

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
      setError(t("reminder.chooseWeekday"));
      return;
    }
    if (reminderType === "quran_review" && (!reviewStartId || !reviewEndId)) {
      setError(t("reminder.chooseRange"));
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
      setSuccess(editing ? t("reminder.updated") : t("reminder.created"));
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
      setSuccess(t("reminder.deleted"));
    } catch (reason) {
      setError(api.normalizeError(reason));
    }
  };

  const toggleWeekday = (bit: number) => {
    setWeekdaysMask((current) => (current & bit ? current & ~bit : current | bit));
  };

  const enableWebPush = async () => {
    if (!webPushStatus?.available || !webPushStatus.vapid_public_key) {
      setWebPushNotice({ kind: "error", message: t("reminder.webPushUnavailable") });
      return;
    }
    if (!webPushSupported) {
      setWebPushNotice({ kind: "error", message: t("reminder.webPushUnsupported") });
      return;
    }

    setWebPushSaving(true);
    setWebPushNotice(null);
    let createdSubscription: PushSubscription | null = null;
    try {
      const permission = await Notification.requestPermission();
      if (permission !== "granted") {
        setWebPushNotice({ kind: "error", message: t("reminder.webPushBlocked") });
        return;
      }

      const installingRegistration = await navigator.serviceWorker.register("/push-sw.js", {
        scope: "/",
      });
      const registration = installingRegistration.active
        ? installingRegistration
        : await navigator.serviceWorker.ready;
      let subscription = await registration.pushManager.getSubscription();
      if (!subscription) {
        subscription = await registration.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: urlBase64ToUint8Array(webPushStatus.vapid_public_key),
        });
        createdSubscription = subscription;
      }
      const status = await api.enableWebPush(
        serializePushSubscription(
          subscription,
          locale,
          t("reminder.webPushInvalidSubscription"),
        ),
      );
      setWebPushStatus(status);
      setWebPushNotice({ kind: "success", message: t("reminder.webPushEnabled") });
    } catch (reason) {
      if (createdSubscription) await createdSubscription.unsubscribe().catch(() => false);
      setWebPushNotice({
        kind: "error",
        message:
          reason instanceof DOMException && reason.name === "NotAllowedError"
            ? t("reminder.webPushBlocked")
            : api.normalizeError(reason),
      });
    } finally {
      setWebPushSaving(false);
    }
  };

  const disableWebPush = async () => {
    setWebPushSaving(true);
    setWebPushNotice(null);
    try {
      await api.disableWebPush();
      setWebPushStatus((current) =>
        current
          ? { ...current, enabled: false, timezone_name: null, locale: null }
          : current,
      );
      const registration = await navigator.serviceWorker.getRegistration("/");
      const subscription = await registration?.pushManager.getSubscription();
      await subscription?.unsubscribe().catch(() => false);
      setWebPushNotice({ kind: "success", message: t("reminder.webPushDisabled") });
    } catch (reason) {
      setWebPushNotice({ kind: "error", message: api.normalizeError(reason) });
    } finally {
      setWebPushSaving(false);
    }
  };

  const testWebPush = async () => {
    if (!webPushSupported || Notification.permission !== "granted") {
      setWebPushNotice({ kind: "error", message: t("reminder.webPushBlocked") });
      return;
    }
    setWebPushSaving(true);
    setWebPushNotice(null);
    try {
      const registration = await navigator.serviceWorker.ready;
      const tag = `iqro-notification-test-${Date.now()}`;
      await registration.showNotification(t("reminder.webPushTestTitle"), {
        body: t("reminder.webPushTestBody"),
        tag,
        requireInteraction: true,
        data: { url: `/${locale}/profile` },
      });
      const displayed = await registration.getNotifications({ tag });
      if (!displayed.some((notification) => notification.tag === tag)) {
        setWebPushNotice({ kind: "error", message: t("reminder.webPushTestDiscarded") });
        return;
      }
      const directResult = await verifyDirectNotification(
        t("reminder.webPushTestTitle"),
        t("reminder.webPushTestBody"),
      );
      if (directResult === "shown") {
        setWebPushNotice({ kind: "success", message: t("reminder.webPushTestShown") });
        return;
      }
      if (directResult === "error") {
        setWebPushNotice({ kind: "error", message: t("reminder.webPushTestDisplayError") });
        return;
      }
      if (directResult === "timeout") {
        setWebPushNotice({ kind: "error", message: t("reminder.webPushTestNotShown") });
        return;
      }
      setWebPushNotice({ kind: "success", message: t("reminder.webPushTestVerified") });
    } catch (reason) {
      setWebPushNotice({ kind: "error", message: api.normalizeError(reason) });
    } finally {
      setWebPushSaving(false);
    }
  };

  if (!isLoggedIn) return null;

  return (
    <section className="surface">
      <div className="surface-head">
        <div>
          <h3 className="surface-title">{t("reminder.title")}</h3>
          <p className="surface-subtitle">{t("reminder.description")}</p>
        </div>
        <span className="status-chip">{t("reminder.activeCount", { count: activeReminders.length })}</span>
      </div>

      {error && <div className="alert alert-error" style={{ marginBottom: 12 }}>{error}</div>}
      {success && <div className="alert alert-success" style={{ marginBottom: 12 }}>{success}</div>}

      <div
        style={{
          padding: 16,
          background: "var(--bg-subtle)",
          borderRadius: "var(--radius-md)",
          marginBottom: 18,
        }}
      >
        <div className="surface-head" style={{ marginBottom: 8 }}>
          <div>
            <h4 className="surface-title">{t("reminder.webPushTitle")}</h4>
            <p className="surface-subtitle">{t("reminder.webPushDescription")}</p>
          </div>
          <span className={`status-chip ${webPushStatus?.enabled ? "ok" : ""}`}>
            {webPushStatus?.enabled
              ? t("reminder.webPushOn")
              : t("reminder.webPushOff")}
          </span>
        </div>
        <p className="kpi-desc" style={{ marginBottom: 10 }}>
          {t("reminder.webPushPrayerLimit")}
        </p>
        {webPushNotice && (
          <div
            className={`alert ${
              webPushNotice.kind === "error" ? "alert-error" : "alert-success"
            }`}
            style={{ marginBottom: 10 }}
          >
            {webPushNotice.message}
          </div>
        )}
        {webPushSupported === false ? (
          <p className="kpi-desc">{t("reminder.webPushUnsupported")}</p>
        ) : webPushStatus?.available === false ? (
          <p className="kpi-desc">{t("reminder.webPushUnavailable")}</p>
        ) : webPushStatus?.enabled ? (
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            <button
              className="btn btn-primary btn-sm"
              type="button"
              disabled={webPushSaving}
              onClick={() => void testWebPush()}
            >
              {webPushSaving ? t("common.saving") : t("reminder.webPushTest")}
            </button>
            <button
              className="btn btn-secondary btn-sm"
              type="button"
              disabled={webPushSaving}
              onClick={() => void disableWebPush()}
            >
              {t("reminder.webPushDisable")}
            </button>
          </div>
        ) : (
          <button
            className="btn btn-primary btn-sm"
            type="button"
            disabled={webPushSaving || webPushStatus === null}
            onClick={() => void enableWebPush()}
          >
            {webPushSaving ? t("common.saving") : t("reminder.webPushEnable")}
          </button>
        )}
      </div>

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
            <label className="form-label" htmlFor="reminder-type">{t("reminder.type")}</label>
            <select
              id="reminder-type"
              value={reminderType}
              onChange={(event) =>
                setReminderType(event.target.value as Reminder["reminder_type"])
              }
            >
              <option value="prayer">{t("reminder.type.prayer")}</option>
              <option value="quran_reading">{t("reminder.type.reading")}</option>
              <option value="quran_review">{t("reminder.type.review")}</option>
            </select>
          </div>

          {reminderType === "prayer" ? (
            <>
              <div className="form-group">
                <label className="form-label" htmlFor="reminder-prayer">{t("reminder.prayerEvent")}</label>
                <select
                  id="reminder-prayer"
                  value={prayerEvent}
                  onChange={(event) =>
                    setPrayerEvent(event.target.value as typeof prayerEvent)
                  }
                >
                  {Object.entries(PRAYER_LABELS).map(([value, label]) => (
                    <option key={value} value={value}>{t(label)}</option>
                  ))}
                </select>
              </div>
              <div className="form-group">
                <label className="form-label" htmlFor="reminder-offset">{t("reminder.offset")}</label>
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
              <label className="form-label" htmlFor="reminder-time">{t("reminder.localTime")}</label>
              <input
                id="reminder-time"
                type="time"
                value={localTime}
                onChange={(event) => setLocalTime(event.target.value)}
              />
            </div>
          )}

          <div className="form-group">
            <label className="form-label" htmlFor="reminder-signal">{t("reminder.signal")}</label>
            <select
              id="reminder-signal"
              value={signal}
              onChange={(event) => setSignal(event.target.value as Reminder["signal"])}
            >
              <option value="sound">{t("reminder.sound")}</option>
              <option value="vibration">{t("reminder.vibration")}</option>
              <option value="silent">{t("reminder.silent")}</option>
            </select>
          </div>
        </div>

        {reminderType === "quran_review" && (
          <div className="form-row">
            <div className="form-group">
              <label className="form-label" htmlFor="review-surah">{t("reminder.surah")}</label>
              <select
                id="review-surah"
                value={reviewSurah}
                onChange={(event) => setReviewSurah(Number(event.target.value))}
              >
                {surahs.map((surah) => (
                  <option key={surah.id} value={surah.number}>
                    {surah.number}. {locale === "ar" ? surah.name_ar : locale === "ru" ? surah.name_ru : surah.name_en}
                  </option>
                ))}
              </select>
            </div>
            <div className="form-group">
              <label className="form-label" htmlFor="review-start">{t("reminder.startAyah")}</label>
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
              <label className="form-label" htmlFor="review-end">{t("reminder.endAyah")}</label>
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
          <p className="form-label" style={{ marginBottom: 8 }}>{t("reminder.weekdays")}</p>
          <div style={{ display: "flex", gap: 10, flexWrap: "wrap" }}>
            {WEEKDAYS.map(([bit, label]) => (
              <label key={bit} style={{ display: "flex", gap: 5, alignItems: "center" }}>
                <input
                  type="checkbox"
                  checked={Boolean(weekdaysMask & bit)}
                  onChange={() => toggleWeekday(bit)}
                />
                {t(label)}
              </label>
            ))}
          </div>
        </div>

        <div className="form-row">
          <div className="form-group">
            <label className="form-label" htmlFor="reminder-timezone-mode">{t("reminder.timezone")}</label>
            <select
              id="reminder-timezone-mode"
              value={timezoneMode}
              onChange={(event) =>
                setTimezoneMode(event.target.value as ReminderTimezone["mode"])
              }
            >
              <option value="device_local">{t("reminder.deviceTimezone")}</option>
              <option value="fixed">{t("reminder.fixed")}</option>
            </select>
          </div>
          {timezoneMode === "fixed" && (
            <div className="form-group">
              <label className="form-label" htmlFor="reminder-fixed-timezone">{t("reminder.ianaTimezone")}</label>
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
            {t("reminder.enabled")}
          </label>
        </div>

        <div style={{ display: "flex", gap: 8 }}>
          <button className="btn btn-primary btn-sm" disabled={saving}>
            {saving ? t("common.saving") : editing ? t("reminder.saveChanges") : t("reminder.create")}
          </button>
          {editing && (
            <button className="btn btn-secondary btn-sm" type="button" onClick={resetForm}>
              {t("common.cancel")}
            </button>
          )}
        </div>
      </form>

      {loading ? (
        <p className="kpi-desc">{t("reminder.loading")}</p>
      ) : activeReminders.length === 0 ? (
        <p className="kpi-desc">{t("reminder.none")}</p>
      ) : (
        <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
          {activeReminders.map((reminder) => (
            <div className="track-row" key={reminder.id}>
              <div>
                <strong>{t(REMINDER_TYPE_LABELS[reminder.reminder_type])}</strong>
                <p className="kpi-desc">{formatSchedule(reminder, t)}</p>
              </div>
              <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
                <span className={`status-chip ${reminder.is_enabled ? "ok" : ""}`}>
                  {reminder.is_enabled ? t("reminder.enabled") : t("reminder.disabled")}
                </span>
                <button
                  className="btn btn-secondary btn-sm"
                  type="button"
                  onClick={() => void toggleReminder(reminder)}
                >
                  {reminder.is_enabled ? t("reminder.disable") : t("reminder.enable")}
                </button>
                <button className="btn btn-secondary btn-sm" type="button" onClick={() => beginEdit(reminder)}>
                  {t("common.edit")}
                </button>
                <button className="btn btn-danger btn-sm" type="button" onClick={() => void removeReminder(reminder)}>
                  {t("common.delete")}
                </button>
              </div>
            </div>
          ))}
        </div>
      )}
    </section>
  );
}

type DirectNotificationResult = "shown" | "error" | "timeout" | "unsupported";

function verifyDirectNotification(
  title: string,
  body: string,
): Promise<DirectNotificationResult> {
  return new Promise((resolve) => {
    let notification: Notification;
    try {
      notification = new Notification(title, {
        body,
        tag: `iqro-direct-notification-test-${Date.now()}`,
        requireInteraction: true,
      });
    } catch {
      resolve("unsupported");
      return;
    }

    let settled = false;
    const finish = (result: DirectNotificationResult) => {
      if (settled) return;
      settled = true;
      window.clearTimeout(timeoutId);
      resolve(result);
    };
    const timeoutId = window.setTimeout(() => finish("timeout"), 3_000);
    notification.addEventListener("show", () => finish("shown"), { once: true });
    notification.addEventListener("error", () => finish("error"), { once: true });
  });
}

type Translate = ReturnType<typeof useI18n>["t"];

function formatSchedule(reminder: Reminder, t: Translate): string {
  if (!reminder.schedule) return t("reminder.removed");
  const schedule =
    reminder.schedule.kind === "prayer"
      ? `${t(PRAYER_LABELS[reminder.schedule.prayer_event])} ${formatOffset(reminder.schedule.prayer_offset_minutes, t)}`
      : reminder.schedule.local_time.slice(0, 5);
  const timezone =
    reminder.timezone.mode === "fixed" ? reminder.timezone.name : t("reminder.deviceTimezone");
  const review = reminder.review_target
    ? ` · ${reminder.review_target.start.surah_number}:${reminder.review_target.start.ayah_number}–${reminder.review_target.end.surah_number}:${reminder.review_target.end.ayah_number}`
    : "";
  return `${schedule}${review} · ${timezone}`;
}

function formatOffset(minutes: number, t: Translate): string {
  if (minutes === 0) return t("reminder.exact");
  return minutes > 0
    ? t("reminder.after", { minutes })
    : t("reminder.before", { minutes: Math.abs(minutes) });
}

function urlBase64ToUint8Array(value: string): Uint8Array<ArrayBuffer> {
  const padding = "=".repeat((4 - (value.length % 4)) % 4);
  const base64 = (value + padding).replace(/-/g, "+").replace(/_/g, "/");
  const decoded = window.atob(base64);
  const bytes = new Uint8Array(new ArrayBuffer(decoded.length));
  for (let index = 0; index < decoded.length; index += 1) {
    bytes[index] = decoded.charCodeAt(index);
  }
  return bytes;
}

function browserTimezone(): string {
  return Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
}

function serializePushSubscription(
  subscription: PushSubscription,
  locale: WebPushSubscriptionInput["locale"],
  invalidMessage: string,
): WebPushSubscriptionInput {
  const serialized = subscription.toJSON();
  if (!serialized.keys?.p256dh || !serialized.keys.auth) {
    throw new Error(invalidMessage);
  }
  return {
    endpoint: subscription.endpoint,
    keys: {
      p256dh: serialized.keys.p256dh,
      auth: serialized.keys.auth,
    },
    expiration_time:
      subscription.expirationTime === null
        ? null
        : new Date(subscription.expirationTime).toISOString(),
    timezone_name: browserTimezone(),
    locale,
  };
}
