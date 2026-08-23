"use client";

import React, { createContext, useContext, useEffect, useState, useCallback } from "react";
import {
  api,
  clearLegacyStoredAuth,
  EmailChallenge,
  EmailVerificationResponse,
  GuestBootstrapResponse,
  loadLegacyStoredIdentity,
} from "./api";

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
  isLoggedIn: boolean;
};

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [session, setSession] = useState<GuestBootstrapResponse | null>(null);
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    // Initialize base URL if set in environment or default to relative/localhost
    const apiBase = process.env.NEXT_PUBLIC_API_BASE_URL || "";
    api.setBase(apiBase);

    let active = true;
    void (async () => {
      const legacyIdentity = loadLegacyStoredIdentity();
      if (legacyIdentity) {
        try {
          await api.adoptLegacyInstallation(legacyIdentity);
          clearLegacyStoredAuth();
        } catch {
          // Keep the legacy identity for a later migration attempt.
        }
      } else {
        clearLegacyStoredAuth();
      }
      const restored = await api.restoreSession();
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
      const res = await api.bootstrapGuest("ru");
      setSession(res);
      return res;
    } catch (err) {
      const msg = api.normalizeError(err);
      setError(msg);
      return null;
    } finally {
      setIsLoading(false);
    }
  }, []);

  const startEmailChallenge = useCallback(
    async (email: string): Promise<EmailChallenge | null> => {
      setIsLoading(true);
      setError(null);
      try {
        let currentSession = api.getSession();
        if (!currentSession) {
          currentSession = await loginGuest();
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
    [loginGuest],
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
        const result = await api.verifyEmailChallenge({
          challenge_id: challengeId,
          code,
          idempotency_key: idempotencyKey,
        });
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
    setIsLoading(true);
    setError(null);
    try {
      await api.logout();
    } catch {
      // Ignore network errors on logout
    } finally {
      setSession(null);
      setIsLoading(false);
    }
  }, []);

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
