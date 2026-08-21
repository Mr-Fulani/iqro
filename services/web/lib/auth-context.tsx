"use client";

import React, { createContext, useContext, useEffect, useState, useCallback } from "react";
import {
  api,
  GuestBootstrapResponse,
  InstallIdentity,
  loadStoredIdentity,
  loadStoredSession,
  saveStoredSession,
} from "./api";

type AuthContextType = {
  session: GuestBootstrapResponse | null;
  identity: InstallIdentity;
  isLoading: boolean;
  error: string | null;
  loginGuest: () => Promise<GuestBootstrapResponse | null>;
  logout: () => Promise<void>;
  isLoggedIn: boolean;
};

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [session, setSession] = useState<GuestBootstrapResponse | null>(null);
  const [identity, setIdentity] = useState<InstallIdentity>({
    installation_id: "",
    installation_credential: "",
  });
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    // Initialize base URL if set in environment or default to relative/localhost
    const apiBase = process.env.NEXT_PUBLIC_API_BASE_URL || "";
    api.setBase(apiBase);

    const storedIdentity = loadStoredIdentity();
    setIdentity(storedIdentity);

    const storedSession = loadStoredSession();
    if (storedSession) {
      setSession(storedSession);
      api.setSession(storedSession);
    }
    setIsLoading(false);
  }, []);

  const loginGuest = useCallback(async (): Promise<GuestBootstrapResponse | null> => {
    setIsLoading(true);
    setError(null);
    try {
      const currentIdentity = loadStoredIdentity();
      setIdentity(currentIdentity);
      const res = await api.bootstrapGuest(currentIdentity, "ru");
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

  const logout = useCallback(async (): Promise<void> => {
    setIsLoading(true);
    setError(null);
    try {
      await api.logout();
    } catch {
      // Ignore network errors on logout
    } finally {
      setSession(null);
      saveStoredSession(null);
      setIsLoading(false);
    }
  }, []);

  return (
    <AuthContext.Provider
      value={{
        session,
        identity,
        isLoading,
        error,
        loginGuest,
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
