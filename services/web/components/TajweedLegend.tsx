"use client";

import { useEffect, useRef, useState } from "react";
import type { TajweedReference } from "../lib/api";
import { useI18n } from "../lib/i18n-context";
import { localizedText, presentRules } from "../lib/tajweed";

type TajweedLegendProps = {
  reference: TajweedReference;
  codes: readonly string[];
  title: string;
  onSelectRule: (code: string) => void;
};

/**
 * Chips of the tajweed rules found on a page or in an ayah. Where they scroll
 * in one row (the phone reader), `data-overflow` marks the edges with more
 * chips behind them, and the row fades there instead of cutting a chip off.
 */
export function TajweedLegend({ reference, codes, title, onSelectRule }: TajweedLegendProps) {
  const { direction, locale } = useI18n();
  const rules = presentRules(reference, codes);
  const list = useRef<HTMLUListElement | null>(null);
  const [overflow, setOverflow] = useState("");

  useEffect(() => {
    const element = list.current;
    if (!element) return;
    const update = () => {
      const hidden = element.scrollWidth - element.clientWidth;
      // In RTL scrollLeft runs from 0 to a negative value.
      const scrolled = Math.abs(element.scrollLeft);
      setOverflow(hidden <= 1 ? "" : [scrolled > 1 ? "start" : "", scrolled < hidden - 1 ? "end" : ""]
        .filter(Boolean).join(" "));
    };
    update();
    element.addEventListener("scroll", update, { passive: true });
    const observer = new ResizeObserver(update);
    observer.observe(element);
    return () => {
      element.removeEventListener("scroll", update);
      observer.disconnect();
    };
  }, [rules.length]);

  if (!rules.length) return null;
  return (
    <section className="tajweed-legend" aria-label={title} lang={locale} dir={direction} data-testid="tajweed-legend">
      <p className="tajweed-legend-title">{title}</p>
      <ul className="tajweed-legend-list" ref={list} data-overflow={overflow || undefined}>
        {rules.map((rule) => (
          <li key={rule.code}>
            <button
              type="button"
              className="tajweed-chip"
              onClick={() => onSelectRule(rule.code)}
              aria-haspopup="dialog"
              data-rule={rule.code}
            >
              <span className="tajweed-dot" style={{ background: rule.color }} aria-hidden="true" />
              {localizedText(rule.name, locale)}
            </button>
          </li>
        ))}
      </ul>
    </section>
  );
}
