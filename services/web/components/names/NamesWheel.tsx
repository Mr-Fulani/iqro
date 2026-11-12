"use client";

import { useCallback, useEffect, useRef, useState } from "react";

import { useI18n } from "@/lib/i18n-context";
import {
  isNameSlug,
  markNameSeen,
  nameLabel,
  NAMES_PROGRESS_EVENT,
  namesProgressStorageKey,
  readNamesProgress,
  seenCount,
  stripHarakat,
  wheelIndex,
  wheelTarget,
  writeNamesProgress,
  type NamesDocument,
} from "@/lib/names";
import { NAME_ONLY } from "@/lib/names-audio";
import { useAccountProgressSync } from "@/lib/use-account-progress-sync";
import { useCourseProgress } from "@/lib/use-course-progress";
import { useReducedMotion } from "@/lib/use-reduced-motion";
import { NameCard } from "./NameCard";
import { useNameVoice } from "./use-name-voice";

const TAU = Math.PI * 2;

type Motion = "idle" | "drag" | "inertia" | "snap";

/** The site's colours and fonts, read once from the page for the canvas. */
function readTheme(element: HTMLElement) {
  const style = getComputedStyle(element);
  const value = (name: string, fallback: string) => style.getPropertyValue(name).trim() || fallback;
  return {
    face: value("--panel", "#fff"),
    faceEdge: value("--bg-subtle", "#f1f5f9"),
    rim: value("--border-strong", "#cbd5e1"),
    line: value("--border", "#e2e8f0"),
    accent: value("--primary", "#047857"),
    onAccent: value("--text-inverse", "#fff"),
    gold: value("--accent-gold", "#b45309"),
    text: value("--text-primary", "#0f172a"),
    muted: value("--text-secondary", "#475569"),
    sans: value("--font-sans", "sans-serif"),
    arabic: value("--font-arabic", "serif"),
  };
}

/**
 * The wheel of the Names (docs/names-of-allah/README.md): a dial of labels with
 * a magnifier at the needle and tasbih ticks every 11 and 33. A finger, the
 * mouse or the arrow keys turn it; a tap on the centre moves to the next name;
 * the block under the wheel opens the name's card.
 */
export function NamesWheel({ document: list }: { document: NamesDocument }) {
  const { t, locale } = useI18n();
  const names = list.names;
  const count = names.length;
  const reducedMotion = useReducedMotion();
  const progress = useCourseProgress(namesProgressStorageKey(), NAMES_PROGRESS_EVENT, isNameSlug);
  // A signed-in reader's marks go to the account: when the page opens, after «Выучено», when a card closes.
  const syncProgress = useAccountProgressSync("names", list.collection.slug, readNamesProgress, writeNamesProgress, isNameSlug);

  const [current, setCurrent] = useState(0);
  // The Arabic interface has one way to write a name.
  const [arabicChosen, setArabicChosen] = useState(false);
  const arabicLabels = arabicChosen || locale === "ar";
  const [soundOn, setSoundOn] = useState(true);
  const [card, setCard] = useState<number | null>(null);
  const voice = useNameVoice();

  const stage = useRef<HTMLDivElement | null>(null);
  const dial = useRef<HTMLDivElement | null>(null);
  const canvas = useRef<HTMLCanvasElement | null>(null);
  const wheel = useRef({
    position: 0,
    velocity: 0,
    target: 0,
    motion: "idle" as Motion,
    frame: 0,
    lastTime: 0,
    size: 0,
    index: 0,
    lastTick: 0,
    audio: null as AudioContext | null,
  });
  const live = useRef({ arabicLabels, soundOn, reducedMotion, names, version: list.collection.version, voice, locale });
  useEffect(() => {
    live.current = { arabicLabels, soundOn, reducedMotion, names, version: list.collection.version, voice, locale };
  });

  // Drawing -----------------------------------------------------------------

  const draw = useCallback(() => {
    const state = wheel.current;
    const element = canvas.current;
    const context = element?.getContext("2d");
    if (!element || !context || !state.size) return;
    const { arabicLabels: arabic, names: items } = live.current;
    const theme = readTheme(element);
    const total = items.length;
    const step = TAU / total;
    // Arabic labels run the other way round, as the script does.
    const direction = arabic ? -1 : 1;
    const angleOf = (index: number) => -Math.PI / 2 + direction * index * step;
    const size = state.size;
    const centre = size / 2;
    const radius = centre - 3;
    const ratio = Math.min(3, window.devicePixelRatio || 1);
    const coreRadius = size * 0.16;

    context.setTransform(ratio, 0, 0, ratio, 0, 0);
    context.clearRect(0, 0, size, size);

    const face = context.createRadialGradient(centre, centre - radius * 0.3, radius * 0.05, centre, centre, radius);
    face.addColorStop(0, theme.face);
    face.addColorStop(1, theme.faceEdge);
    context.beginPath();
    context.arc(centre, centre, radius, 0, TAU);
    context.fillStyle = face;
    context.fill();
    context.lineWidth = 5;
    context.strokeStyle = theme.rim;
    context.beginPath();
    context.arc(centre, centre, radius - 2.5, 0, TAU);
    context.stroke();
    context.lineWidth = 1;
    context.strokeStyle = theme.gold;
    context.globalAlpha = 0.55;
    context.beginPath();
    context.arc(centre, centre, radius - 6, 0, TAU);
    context.stroke();

    const tickRadius = radius - 9;
    const outer = radius - 19;
    const inner = radius * 0.43;
    context.globalAlpha = 1;
    context.strokeStyle = theme.line;
    context.beginPath();
    context.arc(centre, centre, inner - 8, 0, TAU);
    context.stroke();

    context.save();
    context.translate(centre, centre);

    // A tick for every name, a longer one every 11, a gold one every 33: the marks of a tasbih.
    for (let index = 0; index < total; index += 1) {
      const major = index % 33 === 0;
      const middle = index % 11 === 0;
      const length = major ? 9 : middle ? 6 : 3;
      context.save();
      context.rotate(angleOf(index));
      context.strokeStyle = major ? theme.gold : theme.muted;
      context.globalAlpha = major ? 0.95 : middle ? 0.7 : 0.4;
      context.lineWidth = major ? 1.6 : 1;
      context.beginPath();
      context.moveTo(tickRadius - length, 0);
      context.lineTo(tickRadius, 0);
      context.stroke();
      context.restore();
    }
    context.globalAlpha = 1;

    const at = ((state.position % total) + total) % total;
    const near = wheelIndex(state.position, total);
    const family = arabic ? theme.arabic : theme.sans;
    const baseSize = Math.max(6.5, size * 0.0205) * (arabic ? 1.5 : 1);
    const span = outer - inner;
    context.textBaseline = "middle";
    context.textAlign = "left";
    // Labels are placed by hand; Arabic still shapes right to left.
    context.direction = "ltr";

    // Latin and Cyrillic labels start at the inner radius; Arabic ones are short and end at the rim.
    const label = (index: number, measureOnly = false): number => {
      let distance = Math.abs(index - at);
      distance = Math.min(distance, total - distance);
      const zoom = Math.exp(-(distance * distance) / 0.6);
      const selected = index === near;
      let fontSize = baseSize * (1 + zoom);
      const text = arabic ? stripHarakat(items[index].arabic) : nameLabel(items[index]);
      const weight = selected ? 600 : zoom > 0.3 ? 500 : 400;
      context.font = `${weight} ${fontSize}px ${family}`;
      let width = context.measureText(text).width;
      const limit = selected ? span - 4 : span;
      if (width > limit) {
        fontSize = (fontSize * limit) / width;
        context.font = `${weight} ${fontSize}px ${family}`;
        width = context.measureText(text).width;
      }
      const pad = Math.max(4, fontSize * 0.45);
      const start = arabic ? outer - width : inner;
      if (measureOnly) return start - pad;
      const angle = angleOf(index);
      context.save();
      context.rotate(angle);
      const leftHalf = Math.cos(angle) < -1e-6;
      if (leftHalf) context.rotate(Math.PI);
      const x = leftHalf ? -(start + width) : start;
      if (selected) {
        const height = fontSize * 1.6;
        context.beginPath();
        context.roundRect(x - pad, -height / 2, width + pad * 2, height, height / 2);
        context.fillStyle = theme.accent;
        context.fill();
        context.fillStyle = theme.onAccent;
        context.globalAlpha = 1;
      } else {
        context.fillStyle = zoom > 0.08 ? theme.text : theme.muted;
        context.globalAlpha = 0.6 + 0.4 * zoom;
      }
      context.fillText(text, x, arabic ? fontSize * 0.08 : 0);
      context.restore();
      return start - pad;
    };
    for (let index = 0; index < total; index += 1) if (index !== near) label(index);
    context.globalAlpha = 1;

    // The needle goes under the chosen label, so the label stays on top.
    context.save();
    context.rotate(-Math.PI / 2 + direction * state.position * step);
    const from = coreRadius + 8;
    const to = arabic ? Math.max(inner - 12, label(near, true) - 9) : inner - 12;
    context.strokeStyle = theme.gold;
    context.lineWidth = 2.2;
    context.lineCap = "round";
    context.beginPath();
    context.moveTo(from, 0);
    context.lineTo(to, 0);
    context.stroke();
    context.fillStyle = theme.gold;
    context.beginPath();
    context.moveTo(to + 5, 0);
    context.lineTo(to - 2, -3.2);
    context.lineTo(to - 2, 3.2);
    context.closePath();
    context.fill();
    context.beginPath();
    context.arc(from, 0, 3.2, 0, TAU);
    context.fillStyle = theme.face;
    context.fill();
    context.lineWidth = 1.5;
    context.stroke();
    // The mark on the rim.
    context.lineWidth = 2.5;
    context.beginPath();
    context.moveTo(tickRadius - 12, 0);
    context.lineTo(radius - 4, 0);
    context.stroke();
    context.restore();

    label(near);
    context.restore();
  }, []);

  // Click, vibration and the reciter -----------------------------------------

  /** A short mechanical click and a light vibration for every name that passes the needle. */
  const tick = useCallback(() => {
    const state = wheel.current;
    try {
      if (navigator.userActivation?.hasBeenActive) navigator.vibrate?.(4);
    } catch {
      // No vibration on this device.
    }
    const now = performance.now();
    if (!live.current.soundOn || !state.audio || now - state.lastTick < 28) return;
    state.lastTick = now;
    try {
      const audio = state.audio;
      if (audio.state === "suspended") void audio.resume();
      const time = audio.currentTime;
      const oscillator = audio.createOscillator();
      const gain = audio.createGain();
      oscillator.type = "triangle";
      oscillator.frequency.setValueAtTime(2200, time);
      oscillator.frequency.exponentialRampToValueAtTime(900, time + 0.03);
      gain.gain.setValueAtTime(0.05, time);
      gain.gain.exponentialRampToValueAtTime(0.0001, time + 0.04);
      oscillator.connect(gain).connect(audio.destination);
      oscillator.start(time);
      oscillator.stop(time + 0.05);
    } catch {
      // The click is a nicety.
    }
  }, []);

  /** Browsers allow sound only after a gesture: the first touch of the wheel prepares it. */
  const unlockAudio = useCallback(() => {
    const state = wheel.current;
    if (state.audio) return;
    try {
      state.audio = new AudioContext();
    } catch {
      // No Web Audio: the wheel turns silently.
    }
  }, []);

  /** The needle has stopped on a name: it counts as seen and the reciter says it. */
  const settle = useCallback(() => {
    const { names: items, version, soundOn: sound, voice: reciter } = live.current;
    const name = items[wheel.current.index];
    const before = readNamesProgress();
    const after = markNameSeen(before, name.slug, version);
    if (after !== before) writeNamesProgress(after);
    // The labels' switch also picks the voice: the name with its meaning in the site's language,
    // or the name alone with Arabic labels.
    if (sound) void reciter.play(name, live.current.arabicLabels ? NAME_ONLY : live.current.locale);
  }, []);

  // Motion ------------------------------------------------------------------

  const moved = useCallback(() => {
    const state = wheel.current;
    const index = wheelIndex(state.position, live.current.names.length);
    if (index === state.index) return;
    state.index = index;
    tick();
    setCurrent(index);
  }, [tick]);

  const run = useCallback(function loop(time: number) {
    const state = wheel.current;
    state.frame = 0;
    if (!state.lastTime) state.lastTime = time;
    const elapsed = Math.min(40, time - state.lastTime);
    state.lastTime = time;
    if (state.motion === "inertia") {
      state.position += state.velocity * elapsed;
      state.velocity *= Math.exp(-elapsed / 450);
      if (Math.abs(state.velocity) < 0.0035) {
        state.motion = "snap";
        state.target = Math.round(state.position);
      }
    } else if (state.motion === "snap") {
      state.position += (state.target - state.position) * (1 - Math.exp(-elapsed / 70));
      if (Math.abs(state.target - state.position) < 0.003) {
        state.position = state.target;
        state.motion = "idle";
        state.lastTime = 0;
        moved();
        draw();
        settle();
        return;
      }
    }
    moved();
    draw();
    if (state.motion === "inertia" || state.motion === "snap") state.frame = requestAnimationFrame(loop);
    else state.lastTime = 0;
  }, [draw, moved, settle]);

  const start = useCallback(() => {
    const state = wheel.current;
    state.lastTime = 0;
    if (!state.frame) state.frame = requestAnimationFrame(run);
  }, [run]);

  /** Turns the wheel to a name the short way round. */
  const goTo = useCallback((index: number) => {
    const state = wheel.current;
    state.target = wheelTarget(state.position, index, live.current.names.length);
    if (live.current.reducedMotion) {
      state.position = state.target;
      state.motion = "idle";
      moved();
      draw();
      settle();
      return;
    }
    state.motion = "snap";
    start();
  }, [draw, moved, settle, start]);

  const next = useCallback(() => {
    unlockAudio();
    goTo(Math.round(wheel.current.position) + 1);
  }, [goTo, unlockAudio]);

  // Size and redraws ----------------------------------------------------------

  useEffect(() => {
    const element = stage.current;
    if (!element) return;
    const layout = () => {
      const box = element.getBoundingClientRect();
      const size = Math.max(200, Math.floor(Math.min(box.width, box.height)));
      const ratio = Math.min(3, window.devicePixelRatio || 1);
      wheel.current.size = size;
      if (dial.current) dial.current.style.width = dial.current.style.height = `${size}px`;
      if (canvas.current) {
        canvas.current.width = Math.round(size * ratio);
        canvas.current.height = Math.round(size * ratio);
      }
      draw();
    };
    const observer = new ResizeObserver(layout);
    observer.observe(element);
    layout();
    // Labels are measured with the page's fonts: draw again once they are in.
    void document.fonts?.ready.then(draw);
    const state = wheel.current;
    return () => {
      observer.disconnect();
      if (state.frame) cancelAnimationFrame(state.frame);
      state.frame = 0;
      void state.audio?.close();
      state.audio = null;
    };
  }, [draw]);

  useEffect(draw, [arabicLabels, draw, names]);

  // Gestures ----------------------------------------------------------------

  const gesture = useRef({
    active: false,
    inCore: false,
    travelled: 0,
    angle: 0,
    x: 0,
    y: 0,
    samples: [] as { time: number; position: number }[],
  });

  const local = (event: React.PointerEvent) => {
    const box = event.currentTarget.getBoundingClientRect();
    return { x: event.clientX - box.left - box.width / 2, y: event.clientY - box.top - box.height / 2 };
  };

  const onPointerDown = (event: React.PointerEvent<HTMLDivElement>) => {
    if (event.button > 0) return;
    unlockAudio();
    const state = wheel.current;
    const point = local(event);
    gesture.current = {
      active: true,
      inCore: Math.hypot(point.x, point.y) <= state.size * 0.16,
      travelled: 0,
      angle: Math.atan2(point.y, point.x),
      x: event.clientX,
      y: event.clientY,
      samples: [{ time: event.timeStamp, position: state.position }],
    };
    state.motion = "drag";
    state.velocity = 0;
    try {
      event.currentTarget.setPointerCapture(event.pointerId);
    } catch {
      // The drag works without capture while the pointer stays over the wheel.
    }
  };

  const onPointerMove = (event: React.PointerEvent<HTMLDivElement>) => {
    const drag = gesture.current;
    if (!drag.active) return;
    const state = wheel.current;
    const point = local(event);
    drag.travelled = Math.max(drag.travelled, Math.hypot(event.clientX - drag.x, event.clientY - drag.y));
    if (Math.hypot(point.x, point.y) < 12) return;
    const angle = Math.atan2(point.y, point.x);
    let delta = angle - drag.angle;
    if (delta > Math.PI) delta -= TAU;
    if (delta < -Math.PI) delta += TAU;
    drag.angle = angle;
    if (drag.travelled < 6 && drag.inCore) return;
    const total = live.current.names.length;
    state.position += ((live.current.arabicLabels ? -1 : 1) * delta) / (TAU / total);
    drag.samples.push({ time: event.timeStamp, position: state.position });
    while (drag.samples.length > 2 && event.timeStamp - drag.samples[0].time > 90) drag.samples.shift();
    moved();
    draw();
  };

  const onPointerEnd = (event: React.PointerEvent<HTMLDivElement>) => {
    const drag = gesture.current;
    if (!drag.active) return;
    drag.active = false;
    const state = wheel.current;
    // A tap on the centre: the next name.
    if (drag.inCore && drag.travelled < 8) {
      state.motion = "idle";
      next();
      return;
    }
    const first = drag.samples[0];
    const last = drag.samples[drag.samples.length - 1];
    let velocity = last.time > first.time ? (last.position - first.position) / (last.time - first.time) : 0;
    if (event.timeStamp - last.time > 80) velocity = 0;
    state.velocity = Math.max(-0.09, Math.min(0.09, velocity));
    if (live.current.reducedMotion || Math.abs(state.velocity) < 0.004) {
      state.motion = "snap";
      state.target = Math.round(state.position);
    } else {
      state.motion = "inertia";
    }
    start();
  };

  const onKeyDown = (event: React.KeyboardEvent<HTMLDivElement>) => {
    if (event.target !== event.currentTarget) return;
    if (event.key === "ArrowRight" || event.key === "ArrowDown") {
      event.preventDefault();
      next();
    } else if (event.key === "ArrowLeft" || event.key === "ArrowUp") {
      event.preventDefault();
      unlockAudio();
      goTo(Math.round(wheel.current.position) - 1);
    } else if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      setCard(wheel.current.index);
    }
  };

  // Page --------------------------------------------------------------------

  const name = names[current];
  const seen = seenCount(progress, names);

  return (
    <div className="names-wheel" data-testid="names-wheel">
      <div className="names-top">
        <div className="names-toggles">
          <button
            type="button"
            className="names-chip"
            aria-pressed={soundOn}
            onClick={() => {
              if (soundOn) voice.stop();
              setSoundOn(!soundOn);
            }}
            data-testid="names-sound"
          >
            <svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <path d="M2.5 6h2.5l3-2.5v9L5 10H2.5z" />
              {soundOn ? <path d="M10.5 5.5a3.5 3.5 0 0 1 0 5M12.5 3.5a6.3 6.3 0 0 1 0 9" /> : <path d="m10.5 6 4 4m0-4-4 4" />}
            </svg>
            <span>{t("names.sound")}</span>
          </button>
          {locale !== "ar" && (
            <div className="names-segment" role="group" aria-label={t("names.labelsGroup")}>
              <button type="button" aria-pressed={!arabicLabels} onClick={() => setArabicChosen(false)} data-testid="names-labels-locale">
                {t("names.labelsLocale")}
              </button>
              <button type="button" aria-pressed={arabicLabels} onClick={() => setArabicChosen(true)} lang="ar" data-testid="names-labels-arabic">
                عربي
              </button>
            </div>
          )}
        </div>
        <div className="names-meter">
          <div className="names-meter-label">
            <span>{t("names.seen")}</span>
            <span data-testid="names-seen">{t("names.seenCount", { seen, total: count })}</span>
          </div>
          <div className="names-bar" aria-hidden="true">
            <div className="names-bar-fill" style={{ width: `${(seen / count) * 100}%` }} />
          </div>
        </div>
      </div>

      <div className="names-stage" ref={stage}>
        <div
          ref={dial}
          className="names-dial"
          tabIndex={0}
          role="slider"
          aria-label={t("names.wheelLabel")}
          aria-valuemin={1}
          aria-valuemax={count}
          aria-valuenow={name.position}
          aria-valuetext={`${nameLabel(name)}, ${name.meaning}`}
          onPointerDown={onPointerDown}
          onPointerMove={onPointerMove}
          onPointerUp={onPointerEnd}
          onPointerCancel={onPointerEnd}
          onKeyDown={onKeyDown}
          data-testid="names-dial"
        >
          <canvas ref={canvas} />
          {/* Pointer taps reach the dial under it; the button itself serves the keyboard and screen readers. */}
          <button type="button" className="names-core" aria-label={t("names.next")} onClick={next} data-testid="names-next">
            <span className="names-core-number">{name.position}</span>
            <span className="names-core-total">{t("names.ofTotal", { total: count })}</span>
          </button>
        </div>
      </div>

      <button type="button" className="names-readout" onClick={() => setCard(current)} data-testid="names-readout">
        <span className="names-readout-arabic" lang="ar" dir="rtl">{name.arabic}</span>
        {name.transliteration && <span className="names-readout-name">{name.transliteration}</span>}
        <span className="names-readout-meaning">{name.meaning}</span>
        <span className="names-readout-open">{t("names.openCard")}</span>
      </button>
      <p className="names-hint">{t("names.hint")}</p>

      <audio ref={voice.attach} preload="none" onEnded={voice.stop} />
      {card !== null && (
        <NameCard
          document={list}
          index={card}
          progress={progress}
          voice={voice}
          onMarked={() => void syncProgress()}
          onStep={(index) => {
            setCard(index);
            goTo(index);
          }}
          onClose={() => {
            void syncProgress();
            setCard(null);
            dial.current?.focus({ preventScroll: true });
          }}
        />
      )}
    </div>
  );
}
