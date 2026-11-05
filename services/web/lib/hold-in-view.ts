const READER_INPUT = ["wheel", "touchstart", "pointerdown", "keydown"] as const;

/**
 * Keeps `element` where it is on screen while the content above it changes
 * height — translations and tafsir arriving after a jump to an ayah — until
 * the reader scrolls on their own, anything else scrolls the page, the
 * element leaves the page, or `timeoutMs` passes. Returns a function that
 * lets go of it.
 */
export function holdInView(element: HTMLElement, timeoutMs = 8000): () => void {
  let frame = 0;
  let stopped = false;
  const started = performance.now();
  const anchor = element.getBoundingClientRect().top;
  // The hold does the browser's scroll anchoring itself, the same in every
  // browser (Safari has none): with the browser's own off, only the hold and
  // a scroll it did not make move the page.
  const root = document.documentElement;
  const overflowAnchor = root.style.overflowAnchor;
  root.style.overflowAnchor = "none";
  // Where the page was left after the last frame.
  let scrollY = window.scrollY;
  const stop = () => {
    if (stopped) return;
    stopped = true;
    window.cancelAnimationFrame(frame);
    root.style.overflowAnchor = overflowAnchor;
    for (const type of READER_INPUT) window.removeEventListener(type, stop, true);
  };
  for (const type of READER_INPUT) window.addEventListener(type, stop, { capture: true, passive: true });
  const keep = () => {
    if (stopped) return;
    if (!element.isConnected || performance.now() - started > timeoutMs) {
      stop();
      return;
    }
    // Another scroll — the page going to a word or a playing ayah, the
    // scrollbar — means the hold is no longer wanted: pulling the page back
    // would undo it, under a finger that is about to select a word.
    if (Math.abs(window.scrollY - scrollY) > 1) {
      stop();
      return;
    }
    const drift = element.getBoundingClientRect().top - anchor;
    if (Math.abs(drift) > 1) window.scrollBy({ top: drift, behavior: "instant" });
    scrollY = window.scrollY;
    frame = window.requestAnimationFrame(keep);
  };
  frame = window.requestAnimationFrame(keep);
  return stop;
}
