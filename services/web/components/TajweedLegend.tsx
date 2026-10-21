"use client";

import type { TajweedReference } from "../lib/api";
import { useI18n } from "../lib/i18n-context";
import { localizedText, presentRules } from "../lib/tajweed";

type TajweedLegendProps = {
  reference: TajweedReference;
  codes: readonly string[];
  title: string;
  onSelectRule: (code: string) => void;
};

/** Chips of the tajweed rules found on a page or in an ayah. */
export function TajweedLegend({ reference, codes, title, onSelectRule }: TajweedLegendProps) {
  const { direction, locale } = useI18n();
  const rules = presentRules(reference, codes);
  if (!rules.length) return null;
  return (
    <section className="tajweed-legend" aria-label={title} lang={locale} dir={direction} data-testid="tajweed-legend">
      <p className="tajweed-legend-title">{title}</p>
      <ul className="tajweed-legend-list">
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
