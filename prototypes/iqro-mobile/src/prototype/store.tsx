"use client";

import {
  createContext,
  type Dispatch,
  type ReactNode,
  type SetStateAction,
  useContext,
  useEffect,
  useMemo,
  useState,
} from "react";
import { initialState } from "./initialState";
import type { Locale, PrototypeState, Route } from "./types";

const STORAGE_KEY = "iqro-mobile-prototype-v2";

interface PrototypeContextValue {
  state: PrototypeState;
  setState: Dispatch<SetStateAction<PrototypeState>>;
  navigate: (route: Route) => void;
  goBack: () => void;
  notify: (message: string) => void;
}

const PrototypeContext = createContext<PrototypeContextValue | null>(null);

function isLocale(value: string | null): value is Locale {
  return value === "ru" || value === "en" || value === "ar" || value === "tr";
}

const routes: Route[] = [
  "onboarding-language", "onboarding-goal", "onboarding-norm", "home", "quran", "reader",
  "mushaf", "audio", "player", "plan", "prayer-reading", "prayer", "memorization", "dua",
  "dua-topic", "dua-entry", "favorites", "more", "account", "share", "settings",
];

function isRoute(value: string | null): value is Route {
  return value !== null && routes.includes(value as Route);
}

export function PrototypeProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<PrototypeState>(initialState);

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const reset = params.get("reset") === "1";
    const stored = reset ? null : window.localStorage.getItem(STORAGE_KEY);
    let next = initialState;
    if (stored) {
      try {
        next = { ...initialState, ...(JSON.parse(stored) as Partial<PrototypeState>) };
      } catch {
        window.localStorage.removeItem(STORAGE_KEY);
      }
    }
    const screen = params.get("screen");
    const locale = params.get("locale");
    const theme = params.get("theme");
    next = {
      ...next,
      ...(isRoute(screen) ? { route: screen, onboarded: !screen.startsWith("onboarding") } : {}),
      ...(isLocale(locale) ? { locale } : {}),
      ...(theme === "dark" || theme === "light" ? { theme } : {}),
    };
    const timeout = window.setTimeout(() => setState(next), 0);
    return () => window.clearTimeout(timeout);
  }, []);

  useEffect(() => {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify({ ...state, toast: "", modal: "" }));
    document.documentElement.lang = state.locale;
    document.documentElement.dir = state.locale === "ar" ? "rtl" : "ltr";
    document.documentElement.dataset.theme = state.theme;
  }, [state]);

  useEffect(() => {
    if (!state.toast) return;
    const timeout = window.setTimeout(() => {
      setState((current) => ({ ...current, toast: "" }));
    }, 2600);
    return () => window.clearTimeout(timeout);
  }, [state.toast]);

  const value = useMemo<PrototypeContextValue>(() => ({
    state,
    setState,
    navigate: (route) => setState((current) => ({
      ...current,
      previousRoute: current.route,
      route,
      modal: "",
    })),
    goBack: () => setState((current) => {
      const parent: Partial<Record<Route, Route>> = {
        "onboarding-goal": "onboarding-language",
        "onboarding-norm": "onboarding-goal",
        reader: "quran",
        mushaf: "quran",
        "prayer-reading": "plan",
        prayer: "more",
        memorization: "more",
        dua: "more",
        "dua-topic": "dua",
        "dua-entry": "dua-topic",
        favorites: "more",
        account: "more",
        share: "settings",
      };
      return {
        ...current,
        route: parent[current.route] || current.previousRoute,
        previousRoute: current.route,
        modal: "",
      };
    }),
    notify: (toast) => setState((current) => ({ ...current, toast })),
  }), [state]);

  return <PrototypeContext.Provider value={value}>{children}</PrototypeContext.Provider>;
}

export function usePrototype(): PrototypeContextValue {
  const context = useContext(PrototypeContext);
  if (!context) throw new Error("usePrototype must be used inside PrototypeProvider");
  return context;
}
