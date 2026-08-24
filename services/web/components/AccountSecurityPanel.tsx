"use client";

import { FormEvent, useCallback, useEffect, useState } from "react";
import {
  ACCOUNT_LIFECYCLE_NOTICE_KEY,
  api,
  DeviceInventory,
  generateUuidV7,
} from "../lib/api";
import { useAuth } from "../lib/auth-context";
import { useI18n } from "../lib/i18n-context";
import { MessageKey } from "../lib/i18n";

const PLATFORM_LABELS: Record<DeviceInventory["platform"], MessageKey> = {
  web: "account.platform.web",
  ios: "account.platform.ios",
  android: "account.platform.android",
  telegram: "account.platform.telegram",
};

type LifecycleAction = "request" | "cancel";

export function AccountSecurityPanel() {
  const { t, formatDate: formatLocalizedDate } = useI18n();
  const formatDate = (value: string | null | undefined) => value
    ? formatLocalizedDate(value, { dateStyle: "medium", timeStyle: "short" })
    : "—";
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
      setSuccess(t("account.deviceRevoked"));
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
      setLocalError(t("account.codeSendError"));
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
      setLocalError(t("account.codeVerifyError"));
      return;
    }
    const completed =
      action === "request"
        ? await requestAccountDeletion(challengeId)
        : await cancelAccountDeletion(challengeId);
    if (!completed) {
      setLocalError(t("account.actionError"));
      return;
    }
    setAction(null);
    setChallengeId(null);
    setCode("");
    setSuccess(
      action === "request"
        ? t("auth.deletionScheduledNotice")
        : t("auth.deletionCancelledNotice"),
    );
  };

  const lifecycleForm = action ? (
    <div className={action === "request" ? "alert alert-error" : "alert alert-info"}>
      <strong>
        {action === "request" ? t("account.requestTitle") : t("account.cancelTitle")}
      </strong>
      <p style={{ marginTop: 6 }}>
        {action === "request"
          ? t("account.requestDescription")
          : t("account.cancelDescription")}
      </p>
      {!challengeId ? (
        <div style={{ display: "flex", gap: 8, marginTop: 10, flexWrap: "wrap" }}>
          <button
            className={action === "request" ? "btn btn-danger btn-sm" : "btn btn-primary btn-sm"}
            type="button"
            disabled={authLoading}
            onClick={() => void sendLifecycleCode()}
          >
            {authLoading ? t("common.sending") : t("account.getCode", { email: session?.user.email || "" })}
          </button>
          <button
            className="btn btn-secondary btn-sm"
            type="button"
            disabled={authLoading}
            onClick={() => setAction(null)}
          >
            {t("common.back")}
          </button>
        </div>
      ) : (
        <form onSubmit={(event) => void submitLifecycleAction(event)} style={{ marginTop: 12 }}>
          <div className="form-group" style={{ maxWidth: 320 }}>
            <label className="form-label" htmlFor="account-lifecycle-code">
              {t("authForm.emailCode")}
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
                ? t("common.checking")
                : action === "request"
                  ? t("account.confirmDeletion")
                  : t("account.restore")}
            </button>
            <button
              className="btn btn-secondary btn-sm"
              type="button"
              disabled={authLoading}
              onClick={() => beginLifecycleAction(action)}
            >
              {t("account.newCode")}
            </button>
          </div>
        </form>
      )}
    </div>
  ) : null;

  if (isPendingDeletion) {
    return (
      <section className="surface" aria-labelledby="pending-deletion-title">
        <p className="eyebrow">{t("account.security")}</p>
        <h2 className="surface-title" id="pending-deletion-title">
          {t("account.pendingTitle")}
        </h2>
        <p className="surface-subtitle" style={{ marginBottom: 16 }}>
          {t("account.pendingDescription", { date: formatDate(session.user.deletion_scheduled_for) })}
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
              {t("account.cancelDeletion")}
            </button>
            <button className="btn btn-secondary" type="button" onClick={() => void logout()}>
              {t("auth.logout")}
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
            <p className="eyebrow">{t("account.security")}</p>
            <h3 className="surface-title" id="devices-title">{t("account.devicesTitle")}</h3>
            <p className="surface-subtitle">{t("account.devicesDescription")}</p>
          </div>
          <button
            className="btn btn-secondary btn-sm"
            type="button"
            disabled={loadingDevices}
            onClick={() => void loadDevices()}
          >
            {loadingDevices ? t("account.refreshing") : t("common.refresh")}
          </button>
        </div>
        {localError && <div className="alert alert-error" style={{ marginBottom: 14 }}>{localError}</div>}
        {success && <div className="alert alert-success" style={{ marginBottom: 14 }}>{success}</div>}
        <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
          {devices.map((device) => (
            <div className="track-row" key={device.id}>
              <div>
                <strong>{t(PLATFORM_LABELS[device.platform])}</strong>
                {device.is_current && <span className="status-chip ok" style={{ marginInlineStart: 8 }}>{t("account.current")}</span>}
                <p className="kpi-desc">
                  {t("account.deviceMeta", {
                    version: device.app_version || t("common.notSpecified"),
                    locale: device.locale.toUpperCase(),
                    date: formatDate(device.last_seen_at),
                  })}
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
                      {revokingDeviceId === device.id ? t("account.disconnecting") : t("account.confirmDisconnect")}
                    </button>
                    <button
                      className="btn btn-secondary btn-sm"
                      type="button"
                      disabled={revokingDeviceId === device.id}
                      onClick={() => setConfirmDeviceId(null)}
                    >
                      {t("common.cancel")}
                    </button>
                  </div>
                ) : (
                  <button
                    className="btn btn-danger btn-sm"
                    type="button"
                    onClick={() => setConfirmDeviceId(device.id)}
                  >
                    {t("account.endSessions")}
                  </button>
                )
              )}
            </div>
          ))}
          {!loadingDevices && devices.length === 0 && (
            <p className="kpi-desc">{t("account.noDevices")}</p>
          )}
        </div>
      </section>

      <section className="surface" aria-labelledby="danger-zone-title">
        <p className="eyebrow">{t("account.dangerZone")}</p>
        <h3 className="surface-title" id="danger-zone-title">{t("account.deletionTitle")}</h3>
        <p className="surface-subtitle" style={{ marginBottom: 16 }}>{t("account.deletionDescription")}</p>
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
            {t("account.delete")}
          </button>
        )}
      </section>
    </>
  );
}
