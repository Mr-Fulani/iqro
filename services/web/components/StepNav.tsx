"use client";

import { useI18n } from "../lib/i18n-context";

type StepNavProps = {
  className: string;
  backLabel: string;
  nextLabel: string;
  onBack: () => void;
  onNext: () => void;
  isFirst: boolean;
  /** The last step's button finishes the lesson and has no arrow. */
  isLast: boolean;
};

/** «Back» and «Next» of a step-by-step lesson; the arrows follow the reading direction. */
export function StepNav({ className, backLabel, nextLabel, onBack, onNext, isFirst, isLast }: StepNavProps) {
  const { direction } = useI18n();
  const backArrow = direction === "rtl" ? "→" : "←";
  const nextArrow = direction === "rtl" ? "←" : "→";
  return (
    <div className={className}>
      <button type="button" className="btn btn-secondary" onClick={onBack} disabled={isFirst}>
        <span aria-hidden="true">{backArrow}</span> {backLabel}
      </button>
      <button type="button" className="btn btn-primary" onClick={onNext}>
        {nextLabel}
        {isLast ? null : <> <span aria-hidden="true">{nextArrow}</span></>}
      </button>
    </div>
  );
}
