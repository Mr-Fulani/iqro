"use client";

import React, { createContext, useContext, useEffect, useState, useCallback } from "react";
import { usePathname } from "next/navigation";
import {
  ACCOUNT_LIFECYCLE_NOTICE_KEY,
  api,
  clearLegacyStoredAuth,
  EmailChallenge,
  EmailVerificationResponse,
  GuestBootstrapResponse,
  loadLegacyStoredIdentity,
} from "./api";
import { clearSyncState } from "./sync-state";
import { clearPrayerLocationPreference } from "./prayer-location";
import { useI18n } from "./i18n-context";
import { rememberPostAuthReturnPath } from "./auth-navigation";

type AuthContextType = {
  session: GuestBootstrapResponse | null;
  isLoading: boolean;
  error: string | null;
  loginGuest: () => Promise<GuestBootstrapResponse | null>;
  startEmailChallenge: (email: string) => Promise<EmailChallenge | null>;
  verifyEmailChallenge: (
    challengeId: string,
    code: string,
    idempotencyKey: string,
  ) => Promise<EmailVerificationResponse | null>;
  logout: () => Promise<void>;
  logoutAll: () => Promise<boolean>;
  requestAccountDeletion: (challengeId: string) => Promise<boolean>;
  cancelAccountDeletion: (challengeId: string) => Promise<boolean>;
  isLoggedIn: boolean;
};

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const { locale, t } = useI18n();
  const pathname = usePathname();
  const [session, setSession] = useState<GuestBootstrapResponse | null>(null);
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    rememberPostAuthReturnPath(
      `${window.location.pathname}${window.location.search}${window.location.hash}`,
    );
  }, [pathname]);

  useEffect(() => {
    // Initialize base URL if set in environment or default to relative/localhost
    const apiBase = process.env.NEXT_PUBLIC_API_BASE_URL || "";
    api.setBase(apiBase);

    let active = true;
    void (async () => {
      const restored = await api.restoreSession();
      const legacyIdentity = loadLegacyStoredIdentity();
      if (restored) {
        // A valid HttpOnly session is authoritative. Do not replace its
        // installation cookies with a stale localStorage identity.
        clearLegacyStoredAuth();
      } else if (legacyIdentity) {
        try {
          await api.adoptLegacyInstallation(legacyIdentity);
          clearLegacyStoredAuth();
        } catch {
          // Keep the legacy identity for a later migration attempt.
        }
      } else {
        clearLegacyStoredAuth();
      }
      if (active) {
        setSession(restored);
        setIsLoading(false);
      }
    })();
    return () => {
      active = false;
    };
  }, []);

  const loginGuest = useCallback(async (): Promise<GuestBootstrapResponse | null> => {
    setIsLoading(true);
    setError(null);
    try {
      const res = await api.bootstrapGuest(locale);
      setSession(res);
      return res;
    } catch (err) {
      const msg = api.normalizeError(err);
      setError(msg);
      return null;
    } finally {
      setIsLoading(false);
    }
  }, [locale]);

  const startEmailChallenge = useCallback(
    async (email: string): Promise<EmailChallenge | null> => {
      setIsLoading(true);
      setError(null);
      try {
        let currentSession = api.getSession();
        if (!currentSession || currentSession.user.status === "guest") {
          // Re-bootstrap guests from the HttpOnly installation identity before
          // binding a challenge. This keeps the access token and installation
          // credential on the same device even after a legacy-cookie migration.
          currentSession = await api.bootstrapGuest(locale);
          setSession(currentSession);
        }
        if (!currentSession) return null;
        return await api.startEmailChallenge(email);
      } catch (err) {
        setError(api.normalizeError(err));
        return null;
      } finally {
        setIsLoading(false);
      }
    },
    [locale],
  );

  const verifyEmailChallenge = useCallback(
    async (
      challengeId: string,
      code: string,
      idempotencyKey: string,
    ): Promise<EmailVerificationResponse | null> => {
      setIsLoading(true);
      setError(null);
      try {
        const currentSession = api.getSession();
        const guestUserId = currentSession?.user.status === "guest" ? currentSession.user.id : null;
        if (guestUserId && api.getPendingSyncCount() > 0) {
          await api.syncNow();
        }
        const result = await api.verifyEmailChallenge({
          challenge_id: challengeId,
          code,
          idempotency_key: idempotencyKey,
        });
        if (result.merged_guest && guestUserId && guestUserId !== result.user.id) {
          clearSyncState(guestUserId);
        }
        setSession(result);
        return result;
      } catch (err) {
        setError(api.normalizeError(err));
        return null;
      } finally {
        setIsLoading(false);
      }
    },
    [],
  );

  const logout = useCallback(async (): Promise<void> => {
    const userId = api.getSession()?.user.id;
    setIsLoading(true);
    setError(null);
    try {
      await api.logout();
    } catch {
      // Ignore network errors on logout
    } finally {
      clearPrayerLocationPreference(userId);
      setSession(null);
      setIsLoading(false);
    }
  }, []);

  const logoutAll = useCallback(async (): Promise<boolean> => {
    const userId = api.getSession()?.user.id;
    setIsLoading(true);
    setError(null);
    try {
      await api.logoutAll();
      clearPrayerLocationPreference(userId);
      setSession(null);
      return true;
    } catch (err) {
      setError(api.normalizeError(err));
      return false;
    } finally {
      setIsLoading(false);
    }
  }, []);

  const requestAccountDeletion = useCallback(async (challengeId: string): Promise<boolean> => {
    setIsLoading(true);
    setError(null);
    try {
      const next = await api.requestAccountDeletion(challengeId);
      sessionStorage.setItem(
        ACCOUNT_LIFECYCLE_NOTICE_KEY,
        t("auth.deletionScheduledNotice"),
      );
      setSession(next);
      return true;
    } catch (err) {
      setError(api.normalizeError(err));
      return false;
    } finally {
      setIsLoading(false);
    }
  }, [t]);

  const cancelAccountDeletion = useCallback(async (challengeId: string): Promise<boolean> => {
    setIsLoading(true);
    setError(null);
    try {
      const next = await api.cancelAccountDeletion(challengeId);
      sessionStorage.setItem(ACCOUNT_LIFECYCLE_NOTICE_KEY, t("auth.deletionCancelledNotice"));
      setSession(next);
      return true;
    } catch (err) {
      setError(api.normalizeError(err));
      return false;
    } finally {
      setIsLoading(false);
    }
  }, [t]);

  return (
    <AuthContext.Provider
      value={{
        session,
        isLoading,
        error,
        loginGuest,
        startEmailChallenge,
        verifyEmailChallenge,
        logout,
        logoutAll,
        requestAccountDeletion,
        cancelAccountDeletion,
        isLoggedIn: Boolean(session?.access_token),
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth(): AuthContextType {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error("useAuth must be used within an AuthProvider");
  }
  return context;
}
