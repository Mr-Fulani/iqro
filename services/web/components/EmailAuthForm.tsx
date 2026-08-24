"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { FormEvent, useState } from "react";
import { generateUuidV7 } from "../lib/api";
import { useAuth } from "../lib/auth-context";
import { useI18n } from "../lib/i18n-context";

export function EmailAuthForm({ mode }: { mode: "login" | "register" }) {
  const router = useRouter();
  const { t } = useI18n();
  const {
    session,
    isLoggedIn,
    isLoading,
    error,
    loginGuest,
    logout,
    startEmailChallenge,
    verifyEmailChallenge,
  } = useAuth();
  const [email, setEmail] = useState("");
  const [code, setCode] = useState("");
  const [challengeId, setChallengeId] = useState<string | null>(null);
  const [verificationKey, setVerificationKey] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  const isActiveAccount = session?.user.status === "active";
  const title = mode === "register" ? t("authForm.registerTitle") : t("authForm.loginTitle");

  async function handleStart(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSuccess(null);
    const challenge = await startEmailChallenge(email);
    if (!challenge) return;
    setChallengeId(challenge.challenge_id);
    setVerificationKey(generateUuidV7());
    setSuccess(t("authForm.codeSent", {
      email,
      minutes: Math.ceil(challenge.expires_in / 60),
    }));
  }

  async function handleVerify(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!challengeId || !verificationKey) return;
    setSuccess(null);
    const result = await verifyEmailChallenge(challengeId, code, verificationKey);
    if (!result) return;
    setSuccess(
      result.merged_guest
        ? t("authForm.merged")
        : t("authForm.activated"),
    );
  }

  return (
    <div className="surface" style={{ maxWidth: 540, margin: "24px auto" }}>
      <div className="surface-head" style={{ marginBottom: 16 }}>
        <div>
          <p className="eyebrow">Quran Platform Auth</p>
          <h2 className="surface-title">{title}</h2>
        </div>
      </div>

      <p className="kpi-desc" style={{ marginBottom: 20 }}>
        {t("authForm.description")}
      </p>

      {error && <div className="alert alert-error" style={{ marginBottom: 16 }}>{error}</div>}
      {success && <div className="alert alert-success" style={{ marginBottom: 16 }}>{success}</div>}

      {isActiveAccount ? (
        <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <div className="alert alert-info">
            {t("authForm.signedInAsLabel")} {session.user.email && <strong>{session.user.email}</strong>}
          </div>
          <div style={{ display: "flex", gap: 10 }}>
            <Link href="/profile" className="btn btn-primary" style={{ flex: 1 }}>
              {t("authForm.profile")}
            </Link>
            <button onClick={() => void logout()} className="btn btn-secondary">
              {t("auth.logout")}
            </button>
          </div>
        </div>
      ) : challengeId ? (
        <form onSubmit={(event) => void handleVerify(event)} style={{ display: "flex", flexDirection: "column", gap: 14 }}>
          <label className="form-label" htmlFor="email-code">{t("authForm.emailCode")}</label>
          <input
            id="email-code"
            type="text"
            inputMode="numeric"
            autoComplete="one-time-code"
            pattern="[0-9]{6}"
            minLength={6}
            maxLength={6}
            value={code}
            onChange={(event) => setCode(event.target.value.replace(/\D/g, "").slice(0, 6))}
            placeholder="000000"
            required
          />
          <button className="btn btn-primary btn-lg" disabled={isLoading || code.length !== 6}>
            {isLoading ? t("common.checking") : t("authForm.verify")}
          </button>
          <button
            type="button"
            className="btn btn-secondary"
            onClick={() => {
              setChallengeId(null);
              setVerificationKey(null);
              setCode("");
              setSuccess(null);
            }}
          >
            {t("authForm.changeEmail")}
          </button>
        </form>
      ) : (
        <form onSubmit={(event) => void handleStart(event)} style={{ display: "flex", flexDirection: "column", gap: 14 }}>
          <label className="form-label" htmlFor="auth-email">Email</label>
          <input
            id="auth-email"
            type="email"
            autoComplete="email"
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            placeholder="reader@example.com"
            maxLength={254}
            required
          />
          <button className="btn btn-primary btn-lg" disabled={isLoading}>
            {isLoading ? t("common.sending") : t("authForm.getCode")}
          </button>
          {!isLoggedIn && (
            <button
              type="button"
              className="btn btn-secondary"
              disabled={isLoading}
              onClick={() => void loginGuest().then((result) => result && router.push("/profile"))}
            >
              {t("authForm.continueWithoutEmail")}
            </button>
          )}
        </form>
      )}

      <div style={{ marginTop: 18, padding: 14, background: "var(--bg-subtle)", borderRadius: "var(--radius-md)" }}>
        <p className="kpi-desc">
          {t("authForm.cookieNotice")}
        </p>
      </div>

      <div style={{ display: "flex", justifyContent: "space-between", marginTop: 18 }}>
        <Link href={mode === "register" ? "/login" : "/register"} className="kpi-desc" style={{ color: "var(--primary)" }}>
          {mode === "register" ? t("authForm.hasAccount") : t("authForm.firstLogin")}
        </Link>
        <Link href="/" className="kpi-desc">{t("authForm.home")}</Link>
      </div>
    </div>
  );
}
