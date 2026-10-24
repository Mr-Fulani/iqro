"use client";

import { useRef, useState, type CSSProperties, type KeyboardEvent, type PointerEvent } from "react";

import { useI18n } from "../../lib/i18n-context";
import { LESSON_MEDIA_SIZES, lessonImageSrcSet, type CourseSlide } from "../../lib/thematic-courses";
import { usePageLoaded } from "../../lib/use-page-loaded";

/** The tallest slide sets the frame, but not above 1.25 of its width; the others fit inside, centred. */
const MAX_HEIGHT_RATIO = 1.25;
/** A swipe over this share of the frame's width turns the slide. */
const SWIPE_SHARE = 0.15;

/**
 * Lesson slides, one at a time: arrows, dots, swipe and ←/→ while the focus is inside.
 * Only the current slide and its neighbours have a picture; the others mount as the visitor
 * gets near them. The neighbour waits for the page's load, so the first slide, often the
 * largest paint on a phone, has the network to itself. In Arabic the order and the arrows are mirrored.
 */
export function LessonSlides({ slides, priority = false }: { slides: CourseSlide[]; priority?: boolean }) {
  const { direction, formatNumber, t } = useI18n();
  const [index, setIndex] = useState(0);
  // The slides with a picture: the current one, its neighbours and those already shown.
  const [seen, setSeen] = useState<ReadonlySet<number>>(() => new Set([0, 1]));
  const [moved, setMoved] = useState(false);
  const loaded = usePageLoaded();
  const track = useRef<HTMLDivElement>(null);
  const dots = useRef<(HTMLButtonElement | null)[]>([]);
  const drag = useRef<{ pointer: number; x: number; dx: number } | null>(null);
  const total = slides.length;
  const ratio = Math.min(
    MAX_HEIGHT_RATIO,
    Math.max(...slides.map(({ image }) => (image.width ? image.height / image.width : 0))) || 9 / 16,
  );
  const of = (number: number) => t("courses.slideOf", { number: formatNumber(number), total: formatNumber(total) });

  function go(next: number): number {
    if (next < 0 || next >= total || next === index) return index;
    setIndex(next);
    setMoved(true);
    setSeen((previous) => new Set(previous).add(next - 1).add(next).add(next + 1));
    return next;
  }

  function onKeyDown(event: KeyboardEvent<HTMLElement>) {
    if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;
    if (event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return;
    event.preventDefault();
    // → moves forward in a left-to-right page and back in a right-to-left one.
    const next = go(index + ((event.key === "ArrowRight") === (direction === "rtl") ? -1 : 1));
    if (dots.current.includes(event.target as HTMLButtonElement)) dots.current[next]?.focus();
  }

  function onPointerDown(event: PointerEvent<HTMLDivElement>) {
    if (total < 2 || !event.isPrimary || event.button !== 0) return;
    drag.current = { pointer: event.pointerId, x: event.clientX, dx: 0 };
    event.currentTarget.setPointerCapture(event.pointerId);
  }

  function onPointerMove(event: PointerEvent<HTMLDivElement>) {
    const current = drag.current;
    if (!current || current.pointer !== event.pointerId) return;
    current.dx = event.clientX - current.x;
    track.current?.style.setProperty("--drag", `${current.dx}px`);
    track.current?.setAttribute("data-dragging", "");
  }

  function onPointerEnd(event: PointerEvent<HTMLDivElement>) {
    const current = drag.current;
    if (!current || current.pointer !== event.pointerId) return;
    drag.current = null;
    track.current?.style.removeProperty("--drag");
    track.current?.removeAttribute("data-dragging");
    if (event.type === "pointercancel" || Math.abs(current.dx) < event.currentTarget.clientWidth * SWIPE_SHARE) return;
    // A swipe towards the start of the line brings the next slide: leftwards here, rightwards in Arabic.
    go(index + ((current.dx < 0) === (direction === "rtl") ? -1 : 1));
  }

  const counter = t("courses.slideCounter", { number: formatNumber(index + 1), total: formatNumber(total) });
  return (
    <div
      className="lesson-slides"
      data-testid="lesson-slides"
      data-index={index}
      role="region"
      aria-roledescription={t("courses.carousel")}
      aria-label={t("courses.slides")}
      onKeyDown={onKeyDown}
    >
      <div
        className="lesson-slides-frame"
        style={{ aspectRatio: `1 / ${ratio}` }}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerEnd}
        onPointerCancel={onPointerEnd}
      >
        <div ref={track} className="lesson-slides-track" style={{ "--slide": index } as CSSProperties}>
          {slides.map((slide, item) => {
            const current = item === index;
            return (
              <div
                key={item}
                className="lesson-slides-slide"
                role="group"
                aria-roledescription={t("courses.slide")}
                aria-label={of(item + 1)}
                aria-hidden={current ? undefined : true}
                inert={!current}
              >
                {item === index || (loaded && seen.has(item)) ? (
                  // eslint-disable-next-line @next/next/no-img-element -- ready WebP sizes from the media host
                  <img
                    src={slide.image.small_url}
                    srcSet={lessonImageSrcSet(slide.image)}
                    sizes={LESSON_MEDIA_SIZES}
                    width={slide.image.width}
                    height={slide.image.height}
                    alt={slide.alt}
                    draggable={false}
                    decoding="async"
                    fetchPriority={priority && item === 0 ? "high" : undefined}
                  />
                ) : null}
              </div>
            );
          })}
        </div>
      </div>

      <div className="lesson-slides-info">
        {/* Every caption takes the same cell, so the tallest one sets the height and nothing below jumps. */}
        <div className="lesson-slides-captions">
          {slides.map((slide, item) => (
            <p key={item} dir={slide.dir} data-current={item === index ? "" : undefined}>{slide.caption}</p>
          ))}
        </div>
        {total > 1 ? <span className="lesson-slides-counter" aria-hidden="true">{counter}</span> : null}
      </div>

      {total > 1 ? (
        <div className="lesson-slides-nav">
          <button
            type="button"
            className="lesson-slides-arrow"
            aria-label={t("courses.slidePrevious")}
            aria-disabled={index === 0 ? true : undefined}
            onClick={() => go(index - 1)}
          >
            <Chevron back />
          </button>
          <div className="lesson-slides-dots">
            {slides.map((_, item) => (
              <button
                key={item}
                ref={(element) => {
                  dots.current[item] = element;
                }}
                type="button"
                className="lesson-slides-dot"
                aria-label={of(item + 1)}
                aria-current={item === index ? "true" : undefined}
                onClick={() => go(item)}
              />
            ))}
          </div>
          <button
            type="button"
            className="lesson-slides-arrow"
            aria-label={t("courses.slideNext")}
            aria-disabled={index === total - 1 ? true : undefined}
            onClick={() => go(index + 1)}
          >
            <Chevron />
          </button>
        </div>
      ) : null}

      <p className="sr-only" aria-live="polite" aria-atomic="true">{moved ? of(index + 1) : ""}</p>
    </div>
  );
}

function Chevron({ back = false }: { back?: boolean }) {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"
      strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d={back ? "M15 5l-7 7 7 7" : "M9 5l7 7-7 7"} />
    </svg>
  );
}
