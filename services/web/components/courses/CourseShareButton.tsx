"use client";

import { useEffect, useRef, useState, useSyncExternalStore } from "react";

import { useI18n } from "../../lib/i18n-context";

function subscribeNothing() {
  return () => undefined;
}

/** A phone opens the system share menu; a computer copies the link. */
function canShareNatively(): boolean {
  return typeof navigator.share === "function" && window.matchMedia?.("(pointer: coarse)").matches === true;
}

/** «Поделиться» on a phone, «Скопировать ссылку» on a computer (docs/courses/README.md). */
export function CourseShareButton({ title, text, url }: { title: string; text: string; url: string }) {
  const { t } = useI18n();
  const native = useSyncExternalStore(subscribeNothing, canShareNatively, () => false);
  const [status, setStatus] = useState<"" | "copied" | "failed">("");
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => () => {
    if (timer.current) clearTimeout(timer.current);
  }, []);

  async function share() {
    if (native) {
      try {
        await navigator.share({ title, text, url });
      } catch {
        // Closing the menu is not an error.
      }
      return;
    }
    try {
      await navigator.clipboard.writeText(url);
      setStatus("copied");
    } catch {
      setStatus("failed");
    }
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(() => setStatus(""), 4_000);
  }

  return (
    <div className="course-share">
      <button type="button" className="btn btn-secondary course-share-button" onClick={() => void share()} data-testid="course-share">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8"
          strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          {native ? (
            <path d="M12 3v12m0-12-4 4m4-4 4 4M5 12v7a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-7" />
          ) : (
            <path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1" />
          )}
        </svg>
        {native ? t("courses.share") : t("courses.copyLink")}
      </button>
      <span className="course-share-status" role="status">
        {status === "copied" ? t("courses.linkCopied") : status === "failed" ? t("courses.copyError") : ""}
      </span>
    </div>
  );
}
