const READER_INPUT = ["wheel", "touchstart", "pointerdown", "keydown"] as const;

/**
 * Keeps `element` where it is on screen while the content above it changes
 * height — translations and tafsir arriving after a jump to an ayah — until
 * the reader scrolls on their own, the element leaves the page, or
 * `timeoutMs` passes. Returns a function that lets go of it.
 */
export function holdInView(element: HTMLElement, timeoutMs = 8000): () => void {
  let frame = 0;
  let stopped = false;
  const started = performance.now();
  const anchor = element.getBoundingClientRect().top;
  const stop = () => {
    if (stopped) return;
    stopped = true;
    window.cancelAnimationFrame(frame);
    for (const type of READER_INPUT) window.removeEventListener(type, stop, true);
  };
  for (const type of READER_INPUT) window.addEventListener(type, stop, { capture: true, passive: true });
  const keep = () => {
    if (stopped) return;
    if (!element.isConnected || performance.now() - started > timeoutMs) {
      stop();
      return;
    }
    const drift = element.getBoundingClientRect().top - anchor;
    if (Math.abs(drift) > 1) window.scrollBy({ top: drift, behavior: "instant" });
    frame = window.requestAnimationFrame(keep);
  };
  frame = window.requestAnimationFrame(keep);
  return stop;
}
