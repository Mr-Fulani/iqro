"use client";

import { useEffect, useId, useRef, useState, type FormEvent } from "react";

import { formatClock } from "../../lib/audio-content";
import { api } from "../../lib/api";
import { useAuth } from "../../lib/auth-context";
import {
  MAX_REPORT_MESSAGE,
  REPORT_CATEGORIES,
  reportContext,
  reportSubject,
  videoTimeOf,
  type ReportCategory,
} from "../../lib/course-feedback";
import { isLocale } from "../../lib/i18n";
import { useI18n } from "../../lib/i18n-context";
import { withGuestSession } from "./guestSession";
import type { ReportedLesson } from "./LessonFeedback";

/** «Сообщить об ошибке»: a support ticket that knows the course, lesson, release and video moment. */
export default function LessonReportDialog({ lesson, onClose }: { lesson: ReportedLesson; onClose: () => void }) {
  const { formatNumber, t } = useI18n();
  const { loginGuest } = useAuth();
  const dialog = useRef<HTMLDialogElement | null>(null);
  const titleId = useId();
  const [category, setCategory] = useState<ReportCategory>("religious_content");
  const [message, setMessage] = useState("");
  const [email, setEmail] = useState("");
  const [state, setState] = useState<"editing" | "sending" | "error">("editing");
  const [sentId, setSentId] = useState("");
  // The moment is taken when the form opens: the student describes what was on screen then.
  const [playbackMs] = useState(() => videoTimeOf(lesson.courseSlug, lesson.lessonSlug));

  useEffect(() => {
    const element = dialog.current;
    if (element && !element.open) element.showModal();
  }, []);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!message.trim() || state === "sending") return;
    setState("sending");
    try {
      const ticket = await withGuestSession(loginGuest, () =>
        api.createFeedbackTicket({
          category,
          subject: reportSubject(lesson.courseTitle, lesson.lessonNumber, lesson.lessonTitle),
          message: message.trim(),
          locale: isLocale(lesson.language) ? lesson.language : undefined,
          contact_email: email.trim() || undefined,
          context: reportContext(lesson.courseSlug, lesson.lessonSlug, lesson.courseVersion, playbackMs),
        }),
      );
      setSentId(ticket.public_id);
      setState("editing");
    } catch {
      setState("error");
    }
  }

  return (
    <dialog
      ref={dialog}
      className="course-report-dialog"
      aria-labelledby={titleId}
      onClose={onClose}
      onClick={(event) => {
        if (event.target === event.currentTarget) dialog.current?.close();
      }}
      data-testid="lesson-report-dialog"
    >
      <div className="course-report-head">
        <h2 id={titleId}>{t("courses.report")}</h2>
        <button type="button" className="course-report-close" onClick={() => dialog.current?.close()} aria-label={t("courses.reportClose")}>
          ×
        </button>
      </div>
      {sentId ? (
        <div className="course-report-sent" role="status">
          <p><strong>{t("courses.reportSent", { id: sentId })}</strong></p>
          <p>{t("courses.reportReply", { section: t("feedback.title") })}</p>
          <button type="button" className="btn btn-primary" onClick={() => dialog.current?.close()}>{t("courses.reportClose")}</button>
        </div>
      ) : (
        <form className="course-report-form" onSubmit={(event) => void submit(event)}>
          <p className="course-report-intro">{t("courses.reportIntro", { lesson: lesson.lessonTitle })}</p>
          <label>
            <span>{t("courses.reportCategory")}</span>
            <select value={category} onChange={(event) => setCategory(event.target.value as ReportCategory)}>
              {REPORT_CATEGORIES.map((item) => (
                <option key={item} value={item}>{t(`courses.reportCategory.${item}`)}</option>
              ))}
            </select>
          </label>
          <label>
            <span>{t("courses.reportMessage")}</span>
            <textarea
              value={message}
              onChange={(event) => setMessage(event.target.value)}
              maxLength={MAX_REPORT_MESSAGE}
              rows={5}
              required
            />
          </label>
          <label>
            <span>{t("courses.reportEmail")}</span>
            <input type="email" value={email} onChange={(event) => setEmail(event.target.value)} autoComplete="email" maxLength={254} />
          </label>
          {playbackMs !== undefined ? (
            <p className="course-report-note">
              {t("courses.reportVideoAt", { position: formatClock(playbackMs, (value) => formatNumber(value)) })}
            </p>
          ) : null}
          {state === "error" ? <p className="course-report-error" role="alert">{t("courses.reportError")}</p> : null}
          <button type="submit" className="btn btn-primary" disabled={!message.trim() || state === "sending"}>
            {state === "sending" ? t("common.sending") : t("courses.reportSend")}
          </button>
        </form>
      )}
    </dialog>
  );
}
