/**
 * The rub al-hizb mark (۞, which marks the quarters of a hizb in the Mushaf)
 * on the day's reading bar: on every opening of the home page it travels
 * from the start to `percent` with a quarter turn, as in the app. With
 * reduced motion it simply stands there.
 */
export function PlanMark({ percent }: { percent: number }) {
  return (
    <span className="plan-mark" style={{ insetInlineStart: `${percent}%` }} aria-hidden="true" data-testid="plan-mark">
      <svg viewBox="0 0 24 24" width="24" height="24">
        <rect className="plan-mark-square" x="5" y="5" width="14" height="14" rx="1" />
        <rect className="plan-mark-square" x="5" y="5" width="14" height="14" rx="1" transform="rotate(45 12 12)" />
        <circle className="plan-mark-ring" cx="12" cy="12" r="2.6" />
      </svg>
    </span>
  );
}
