"use client";

import { useState, type FormEvent } from "react";

import { api } from "../../lib/api";
import { useAuth } from "../../lib/auth-context";
import { MAX_RATING_COMMENT, parseRating, ratingStorageKey, writeRating } from "../../lib/course-feedback";
import { useI18n } from "../../lib/i18n-context";
import { withGuestSession } from "./guestSession";
import { useThematicProgress } from "./CourseProgress";
import { announceStoredValue, useStoredValue } from "./useStoredValue";

const STARS = [1, 2, 3, 4, 5] as const;

/**
 * «Насколько курс был полезен?». Only the admin sees ratings: the student sees
 * their own one, never an average. Shown once a lesson is learned, or, with
 * `afterLesson`, once that (last) lesson is.
 */
export function CourseRating({
  courseSlug,
  language,
  lessonSlugs,
  afterLesson,
}: {
  courseSlug: string;
  language: string;
  lessonSlugs: string[];
  afterLesson?: string;
}) {
  const { formatNumber, t } = useI18n();
  const { loginGuest } = useAuth();
  const progress = useThematicProgress(courseSlug);
  const raw = useStoredValue(ratingStorageKey(courseSlug));
  const saved = raw ? parseRating(raw) : null;
  const [editing, setEditing] = useState(false);
  const [stars, setStars] = useState(0);
  const [comment, setComment] = useState("");
  const [state, setState] = useState<"idle" | "sending" | "error">("idle");

  const learned = (slug: string) => progress?.lessons[slug]?.status === "completed";
  const visible = afterLesson ? learned(afterLesson) : lessonSlugs.some(learned);
  if (!progress || raw === null || !visible) return null;

  function edit() {
    setStars(saved?.stars ?? 0);
    setComment(saved?.comment ?? "");
    setState("idle");
    setEditing(true);
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!stars || state === "sending") return;
    setState("sending");
    try {
      const result = await withGuestSession(loginGuest, () =>
        api.rateCourse(courseSlug, { stars, comment: comment.trim(), language }),
      );
      writeRating(courseSlug, result);
      announceStoredValue();
      setEditing(false);
      setState("idle");
    } catch {
      setState("error");
    }
  }

  const titleId = `course-rating-${courseSlug}`;
  if (saved && !editing) {
    return (
      <section className="surface course-rating" aria-labelledby={titleId} data-testid="course-rating">
        <h2 id={titleId}>{t("courses.ratingTitle")}</h2>
        <p className="course-rating-saved" role="status">
          <span className="course-rating-stars" aria-hidden="true">
            {STARS.map((value) => (value <= saved.stars ? "★" : "☆")).join("")}
          </span>{" "}
          {t("courses.ratingSaved", { stars: formatNumber(saved.stars) })}
        </p>
        <button type="button" className="btn btn-secondary" onClick={edit}>{t("courses.ratingEdit")}</button>
      </section>
    );
  }

  return (
    <section className="surface course-rating" aria-labelledby={titleId} data-testid="course-rating">
      <form onSubmit={(event) => void submit(event)}>
        <fieldset className="course-rating-fieldset">
          <legend id={titleId}><h2>{t("courses.ratingTitle")}</h2></legend>
          <div className="course-rating-choice">
            {STARS.map((value) => (
              <label key={value} className={value <= stars ? "is-on" : undefined}>
                <input
                  type="radio"
                  name={`${titleId}-stars`}
                  value={value}
                  checked={stars === value}
                  onChange={() => setStars(value)}
                />
                <span aria-hidden="true">★</span>
                <span className="sr-only">{t("courses.ratingStar", { count: formatNumber(value) })}</span>
              </label>
            ))}
          </div>
        </fieldset>
        <label className="course-rating-comment">
          <span>{t("courses.ratingComment")}</span>
          <textarea
            value={comment}
            onChange={(event) => setComment(event.target.value)}
            maxLength={MAX_RATING_COMMENT}
            rows={3}
          />
          <small>{t("courses.ratingCounter", { count: formatNumber(comment.length) })}</small>
        </label>
        {state === "error" ? <p className="course-report-error" role="alert">{t("courses.ratingError")}</p> : null}
        <button type="submit" className="btn btn-primary" disabled={!stars || state === "sending"}>
          {state === "sending" ? t("common.sending") : t("courses.ratingSend")}
        </button>
      </form>
    </section>
  );
}
