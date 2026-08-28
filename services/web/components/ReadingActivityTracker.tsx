"use client";

import { useCallback, useEffect, useRef } from "react";
import { api, ApiError, generateUuidV7 } from "../lib/api";
import { useAuth } from "../lib/auth-context";
import {
  AutomaticReadingPayload,
  enqueueReadingActivity,
  loadReadingActivityQueue,
  saveReadingActivityQueue,
} from "../lib/reading-activity-queue";

type ReadingActivityTrackerProps = {
  currentPage: number;
  viewMode: "text" | "mushaf";
  creditPageProgress?: boolean;
  timezoneName?: string;
  onActiveSecondsChange?: (seconds: number) => void;
};

const HEARTBEAT_SECONDS = 60;
const IDLE_AFTER_MS = 120_000;

function browserTimezone(): string {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
  } catch {
    return "UTC";
  }
}

export function ReadingActivityTracker({
  currentPage,
  viewMode,
  creditPageProgress = true,
  timezoneName,
  onActiveSecondsChange,
}: ReadingActivityTrackerProps) {
  const { session, isLoading: authLoading, loginGuest } = useAuth();
  const activeSeconds = useRef(0);
  const totalActiveSeconds = useRef(0);
  const segmentStartedAt = useRef<Date | null>(null);
  const lastInteractionAt = useRef(0);
  const previousPage = useRef(currentPage);
  const currentPageRef = useRef(currentPage);
  const viewModeRef = useRef(viewMode);
  const changedPages = useRef(new Set<number>());
  const creditedPages = useRef(new Set<number>());
  const sending = useRef(new Set<string>());
  const authLoadingRef = useRef(authLoading);
  const onActiveSecondsChangeRef = useRef(onActiveSecondsChange);

  useEffect(() => {
    authLoadingRef.current = authLoading;
  }, [authLoading]);

  useEffect(() => {
    onActiveSecondsChangeRef.current = onActiveSecondsChange;
  }, [onActiveSecondsChange]);

  const deliver = useCallback(async (payload: AutomaticReadingPayload) => {
    if (sending.current.has(payload.id)) return;
    sending.current.add(payload.id);
    try {
      if (!api.getSession() && authLoadingRef.current) {
        enqueueReadingActivity(payload);
        return;
      }
      if (!api.getSession() && !(await loginGuest())) {
        enqueueReadingActivity(payload);
        return;
      }
      await api.createAutomaticReadingSession(payload);
      const remaining = loadReadingActivityQueue().filter((item) => item.id !== payload.id);
      saveReadingActivityQueue(remaining);
      window.dispatchEvent(new Event("quran-reading-progress-changed"));
    } catch (error) {
      if (!(error instanceof ApiError) || error.status === 429 || error.status >= 500) {
        enqueueReadingActivity(payload);
      }
    } finally {
      sending.current.delete(payload.id);
    }
  }, [loginGuest]);

  const finalizeSegment = useCallback((allowPageOnly: boolean) => {
    const seconds = activeSeconds.current;
    if (
      seconds >= HEARTBEAT_SECONDS &&
      creditPageProgress &&
      viewModeRef.current === "mushaf" &&
      !creditedPages.current.has(currentPageRef.current)
    ) {
      changedPages.current.add(currentPageRef.current);
    }
    const pages = changedPages.current.size;
    if (seconds < HEARTBEAT_SECONDS && (!allowPageOnly || pages === 0)) return;

    const endedAt = new Date();
    const payload: AutomaticReadingPayload = {
      id: generateUuidV7(),
      timezone_name: timezoneName || browserTimezone(),
      started_at: (segmentStartedAt.current || endedAt).toISOString(),
      ended_at: endedAt.toISOString(),
      active_seconds: seconds,
      credited_pages: pages,
      credited_ayahs: 0,
      client_updated_at: endedAt.toISOString(),
    };
    activeSeconds.current = 0;
    for (const page of changedPages.current) creditedPages.current.add(page);
    changedPages.current = new Set();
    segmentStartedAt.current = endedAt;
    void deliver(payload);
  }, [creditPageProgress, deliver, timezoneName]);

  useEffect(() => {
    if (authLoading) return;
    const queue = loadReadingActivityQueue();
    for (const payload of queue) void deliver(payload);
  }, [authLoading, deliver, session?.user.id]);

  useEffect(() => {
    currentPageRef.current = currentPage;
    viewModeRef.current = viewMode;
    if (creditPageProgress && viewMode === "mushaf" && previousPage.current !== currentPage) {
      changedPages.current.add(currentPage);
      lastInteractionAt.current = Date.now();
    }
    previousPage.current = currentPage;
  }, [creditPageProgress, currentPage, viewMode]);

  useEffect(() => {
    segmentStartedAt.current ||= new Date();
    lastInteractionAt.current = Date.now();
    const markActive = () => {
      lastInteractionAt.current = Date.now();
    };
    const handleVisibility = () => {
      if (document.visibilityState === "hidden") finalizeSegment(true);
      else markActive();
    };
    const interval = window.setInterval(() => {
      const isActive =
        document.visibilityState === "visible" &&
        document.hasFocus() &&
        Date.now() - lastInteractionAt.current <= IDLE_AFTER_MS;
      if (!isActive) return;
      activeSeconds.current += 1;
      totalActiveSeconds.current += 1;
      onActiveSecondsChangeRef.current?.(totalActiveSeconds.current);
      if (activeSeconds.current >= HEARTBEAT_SECONDS) finalizeSegment(false);
    }, 1000);

    window.addEventListener("pointerdown", markActive, { passive: true });
    window.addEventListener("keydown", markActive);
    window.addEventListener("scroll", markActive, { passive: true });
    document.addEventListener("visibilitychange", handleVisibility);
    return () => {
      window.clearInterval(interval);
      window.removeEventListener("pointerdown", markActive);
      window.removeEventListener("keydown", markActive);
      window.removeEventListener("scroll", markActive);
      document.removeEventListener("visibilitychange", handleVisibility);
      finalizeSegment(true);
    };
  }, [finalizeSegment]);

  return null;
}
