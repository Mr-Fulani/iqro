"use client";

import { useEffect, useRef, useState } from "react";
import { api, EmailVerificationResponse } from "../lib/api";
import { useAuth } from "../lib/auth-context";
import { loadGoogleIdentity, prepareGoogleIdentity } from "../lib/google-identity";
import { useI18n } from "../lib/i18n-context";

/**
 * "Sign in with Google": the official button and, with [oneTap], Google's
 * One Tap prompt for the account already signed in to the browser. Renders
 * nothing until the backend reports configured OAuth client IDs.
 */
export function GoogleSignIn({
  oneTap = false,
  onSignedIn,
}: {
  oneTap?: boolean;
  onSignedIn?: (result: EmailVerificationResponse) => void;
}) {
  const { locale, t } = useI18n();
  const { signInWithGoogle } = useAuth();
  const buttonRef = useRef<HTMLDivElement>(null);
  const [clientId, setClientId] = useState<string | null>(null);
  const onCredential = useRef<(idToken: string) => void>(() => undefined);

  useEffect(() => {
    onCredential.current = (idToken: string) => {
      void signInWithGoogle(idToken).then((result) => {
        if (result) onSignedIn?.(result);
      });
    };
  }, [signInWithGoogle, onSignedIn]);

  useEffect(() => {
    let active = true;
    api
      .getGoogleSignInConfig()
      .then((config) => {
        if (active) setClientId(config.enabled ? config.client_id : null);
      })
      .catch(() => {
        // Without the config the email code stays the only way in.
      });
    return () => {
      active = false;
    };
  }, []);

  useEffect(() => {
    const container = buttonRef.current;
    if (!clientId || !container) return;
    let active = true;
    loadGoogleIdentity()
      .then((google) => {
        if (!active) return;
        prepareGoogleIdentity(google, clientId, (idToken) => onCredential.current(idToken));
        google.renderButton(container, {
          type: "standard",
          theme: "outline",
          size: "large",
          shape: "pill",
          text: "continue_with",
          logo_alignment: "left",
          locale,
          width: Math.max(200, Math.min(400, Math.round(container.clientWidth))),
        });
        if (oneTap) google.prompt();
      })
      .catch(() => {
        // Blocked by an extension or offline: the email form still works.
      });
    return () => {
      active = false;
      if (oneTap) {
        void loadGoogleIdentity().then((google) => google.cancel()).catch(() => undefined);
      }
    };
  }, [clientId, locale, oneTap]);

  if (!clientId) return null;
  return (
    <div className="google-sign-in">
      <div ref={buttonRef} className="google-sign-in-button" />
      <div className="google-sign-in-divider" role="separator">
        <span>{t("authForm.orEmail")}</span>
      </div>
    </div>
  );
}
