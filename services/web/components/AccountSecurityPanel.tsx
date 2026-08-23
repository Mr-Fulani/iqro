"use client";

import { FormEvent, useCallback, useEffect, useState } from "react";
import {
  ACCOUNT_LIFECYCLE_NOTICE_KEY,
  api,
  DeviceInventory,
  generateUuidV7,
} from "../lib/api";
import { useAuth } from "../lib/auth-context";

const PLATFORM_LABELS: Record<DeviceInventory["platform"], string> = {
  web: "Web-браузер",
  ios: "iPhone / iPad",
  android: "Android",
  telegram: "Telegram",
};

type LifecycleAction = "request" | "cancel";

function formatDate(value: string | null | undefined): string {
  if (!value) return "—";
  return new Intl.DateTimeFormat("ru-RU", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(value));
}

export function AccountSecurityPanel() {
  const {
    session,
    error: authError,
    isLoading: authLoading,
    startEmailChallenge,
    verifyEmailChallenge,
    requestAccountDeletion,
    cancelAccountDeletion,
    logout,
  } = useAuth();
  const [devices, setDevices] = useState<DeviceInventory[]>([]);
  const [loadingDevices, setLoadingDevices] = useState(false);
  const [confirmDeviceId, setConfirmDeviceId] = useState<string | null>(null);
  const [revokingDeviceId, setRevokingDeviceId] = useState<string | null>(null);
  const [action, setAction] = useState<LifecycleAction | null>(null);
  const [challengeId, setChallengeId] = useState<string | null>(null);
  const [code, setCode] = useState("");
  const [localError, setLocalError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  const isPendingDeletion = session?.user.status === "pending_deletion";
  const isActiveAccount = session?.user.status === "active";

  const loadDevices = useCallback(async () => {
    if (!isActiveAccount) return;
    setLoadingDevices(true);
    setLocalError(null);
    try {
      setDevices(await api.getDevices());
    } catch (error) {
      setLocalError(api.normalizeError(error));
    } finally {
      setLoadingDevices(false);
    }
  }, [isActiveAccount]);

  useEffect(() => {
    void loadDevices();
  }, [loadDevices]);

  useEffect(() => {
    const notice = sessionStorage.getItem(ACCOUNT_LIFECYCLE_NOTICE_KEY);
    if (notice) {
      setSuccess(notice);
      sessionStorage.removeItem(ACCOUNT_LIFECYCLE_NOTICE_KEY);
    }
  }, []);

  const revokeDevice = async (deviceId: string) => {
    setRevokingDeviceId(deviceId);
    setLocalError(null);
    try {
      await api.revokeDevice(deviceId);
      setDevices((current) => current.filter((device) => device.id !== deviceId));
      setConfirmDeviceId(null);
      setSuccess("Сессии выбранного устройства завершены.");
    } catch (error) {
      setLocalError(api.normalizeError(error));
    } finally {
      setRevokingDeviceId(null);
    }
  };

  const beginLifecycleAction = (nextAction: LifecycleAction) => {
    setAction(nextAction);
    setChallengeId(null);
    setCode("");
    setLocalError(null);
    setSuccess(null);
  };

  const sendLifecycleCode = async () => {
    if (!session?.user.email || !action) return;
    setLocalError(null);
    const challenge = await startEmailChallenge(session.user.email);
    if (!challenge) {
      setLocalError("Не удалось отправить код. Повторите попытку.");
      return;
    }
    setChallengeId(challenge.challenge_id);
  };

  const submitLifecycleAction = async (event: FormEvent) => {
    event.preventDefault();
    if (!challengeId || !action || code.length !== 6) return;
    setLocalError(null);
    const verified = await verifyEmailChallenge(challengeId, code, generateUuidV7());
    if (!verified) {
      setLocalError("Не удалось подтвердить код.");
      return;
    }
    const completed =
      action === "request"
        ? await requestAccountDeletion(challengeId)
        : await cancelAccountDeletion(challengeId);
    if (!completed) {
      setLocalError("Не удалось завершить действие с аккаунтом.");
      return;
    }
    setAction(null);
    setChallengeId(null);
    setCode("");
    setSuccess(
      action === "request"
        ? "Удаление аккаунта запланировано. До указанной даты его можно отменить."
        : "Удаление аккаунта отменено.",
    );
  };

  const lifecycleForm = action ? (
    <div className={action === "request" ? "alert alert-error" : "alert alert-info"}>
      <strong>
        {action === "request" ? "Запланировать удаление аккаунта?" : "Отменить удаление?"}
      </strong>
      <p style={{ marginTop: 6 }}>
        {action === "request"
          ? "Обычный доступ будет заблокирован сразу. Через 7 дней синхронизируемые данные будут удалены, а аккаунт — анонимизирован."
          : "Для восстановления аккаунта подтвердите владение email новым одноразовым кодом."}
      </p>
      {!challengeId ? (
        <div style={{ display: "flex", gap: 8, marginTop: 10, flexWrap: "wrap" }}>
          <button
            className={action === "request" ? "btn btn-danger btn-sm" : "btn btn-primary btn-sm"}
            type="button"
            disabled={authLoading}
            onClick={() => void sendLifecycleCode()}
          >
            {authLoading ? "Отправка..." : `Получить код на ${session?.user.email}`}
          </button>
          <button
            className="btn btn-secondary btn-sm"
            type="button"
            disabled={authLoading}
            onClick={() => setAction(null)}
          >
            Назад
          </button>
        </div>
      ) : (
        <form onSubmit={(event) => void submitLifecycleAction(event)} style={{ marginTop: 12 }}>
          <div className="form-group" style={{ maxWidth: 320 }}>
            <label className="form-label" htmlFor="account-lifecycle-code">
              Код из письма
            </label>
            <input
              id="account-lifecycle-code"
              inputMode="numeric"
              autoComplete="one-time-code"
              pattern="[0-9]{6}"
              maxLength={6}
              value={code}
              onChange={(event) => setCode(event.target.value.replace(/\D/g, ""))}
              required
            />
          </div>
          <div style={{ display: "flex", gap: 8, marginTop: 10, flexWrap: "wrap" }}>
            <button
              className={action === "request" ? "btn btn-danger btn-sm" : "btn btn-primary btn-sm"}
              disabled={authLoading || code.length !== 6}
            >
              {authLoading
                ? "Проверка..."
                : action === "request"
                  ? "Подтвердить удаление"
                  : "Восстановить аккаунт"}
            </button>
            <button
              className="btn btn-secondary btn-sm"
              type="button"
              disabled={authLoading}
              onClick={() => beginLifecycleAction(action)}
            >
              Запросить новый код
            </button>
          </div>
        </form>
      )}
    </div>
  ) : null;

  if (isPendingDeletion) {
    return (
      <section className="surface" aria-labelledby="pending-deletion-title">
        <p className="eyebrow">Безопасность аккаунта</p>
        <h2 className="surface-title" id="pending-deletion-title">
          Удаление аккаунта запланировано
        </h2>
        <p className="surface-subtitle" style={{ marginBottom: 16 }}>
          Аккаунт и синхронизируемые данные будут удалены после {" "}
          <strong>{formatDate(session.user.deletion_scheduled_for)}</strong>. До этого момента
          удаление можно отменить после повторной проверки email.
        </p>
        {(localError || authError) && (
          <div className="alert alert-error" style={{ marginBottom: 14 }}>
            {localError || authError}
          </div>
        )}
        {success && <div className="alert alert-success" style={{ marginBottom: 14 }}>{success}</div>}
        {lifecycleForm}
        {!action && (
          <div style={{ display: "flex", gap: 10, flexWrap: "wrap" }}>
            <button
              className="btn btn-primary"
              type="button"
              onClick={() => beginLifecycleAction("cancel")}
            >
              Отменить удаление
            </button>
            <button className="btn btn-secondary" type="button" onClick={() => void logout()}>
              Выйти
            </button>
          </div>
        )}
      </section>
    );
  }

  if (!isActiveAccount) return null;

  return (
    <>
      <section className="surface" aria-labelledby="devices-title">
        <div className="surface-head">
          <div>
            <p className="eyebrow">Безопасность аккаунта</p>
            <h3 className="surface-title" id="devices-title">Устройства и сессии</h3>
            <p className="surface-subtitle">
              Завершайте доступ на устройствах, которыми больше не пользуетесь.
            </p>
          </div>
          <button
            className="btn btn-secondary btn-sm"
            type="button"
            disabled={loadingDevices}
            onClick={() => void loadDevices()}
          >
            {loadingDevices ? "Обновление..." : "Обновить"}
          </button>
        </div>
        {localError && <div className="alert alert-error" style={{ marginBottom: 14 }}>{localError}</div>}
        {success && <div className="alert alert-success" style={{ marginBottom: 14 }}>{success}</div>}
        <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
          {devices.map((device) => (
            <div className="track-row" key={device.id}>
              <div>
                <strong>{PLATFORM_LABELS[device.platform]}</strong>
                {device.is_current && <span className="status-chip ok" style={{ marginLeft: 8 }}>Текущее</span>}
                <p className="kpi-desc">
                  Версия {device.app_version || "не указана"} · язык {device.locale.toUpperCase()} ·
                  последний доступ {formatDate(device.last_seen_at)}
                </p>
              </div>
              {!device.is_current && (
                confirmDeviceId === device.id ? (
                  <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
                    <button
                      className="btn btn-danger btn-sm"
                      type="button"
                      disabled={revokingDeviceId === device.id}
                      onClick={() => void revokeDevice(device.id)}
                    >
                      {revokingDeviceId === device.id ? "Отключение..." : "Подтвердить отключение"}
                    </button>
                    <button
                      className="btn btn-secondary btn-sm"
                      type="button"
                      disabled={revokingDeviceId === device.id}
                      onClick={() => setConfirmDeviceId(null)}
                    >
                      Отмена
                    </button>
                  </div>
                ) : (
                  <button
                    className="btn btn-danger btn-sm"
                    type="button"
                    onClick={() => setConfirmDeviceId(device.id)}
                  >
                    Завершить сессии
                  </button>
                )
              )}
            </div>
          ))}
          {!loadingDevices && devices.length === 0 && (
            <p className="kpi-desc">Активные устройства не найдены.</p>
          )}
        </div>
      </section>

      <section className="surface" aria-labelledby="danger-zone-title">
        <p className="eyebrow">Опасная зона</p>
        <h3 className="surface-title" id="danger-zone-title">Удаление аккаунта</h3>
        <p className="surface-subtitle" style={{ marginBottom: 16 }}>
          После повторной проверки email начнётся 7-дневный период отмены. До его окончания
          безвозвратное удаление не выполняется.
        </p>
        {(localError || authError) && (
          <div className="alert alert-error" style={{ marginBottom: 14 }}>
            {localError || authError}
          </div>
        )}
        {lifecycleForm}
        {!action && (
          <button
            className="btn btn-danger"
            type="button"
            onClick={() => beginLifecycleAction("request")}
          >
            Удалить аккаунт
          </button>
        )}
      </section>
    </>
  );
}
