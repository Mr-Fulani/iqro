/**
 * The traveller with a book who walks along the day's reading bar on every
 * opening of the home page, as in the app. CSS moves him from the start to
 * `percent`; with reduced motion he simply stands there.
 */
export function PlanWalker({ percent }: { percent: number }) {
  return (
    <span className="plan-walker" style={{ insetInlineStart: `${percent}%` }} aria-hidden="true" data-testid="plan-walker">
      <svg viewBox="0 0 26 34" width="26" height="34">
        <g className="plan-walker-leg plan-walker-leg-a">
          <path d="M12 23 L10.5 32" />
        </g>
        <g className="plan-walker-leg plan-walker-leg-b">
          <path d="M14 23 L15.5 32" />
        </g>
        <path className="plan-walker-robe" d="M8.5 11.5 Q13 9.5 17.5 11.5 L18.5 25 L7.5 25 Z" />
        <path className="plan-walker-arm" d="M15 13.5 L18.5 17.5" />
        <rect x="17" y="14.5" width="7" height="8" rx="1.2" fill="#D5A34C" transform="rotate(-12 20.5 18.5)" />
        <rect x="17.3" y="17.6" width="6.4" height="1.2" fill="#FFFDF8" opacity=".7" transform="rotate(-12 20.5 18.5)" />
        <circle cx="13" cy="6.6" r="3.6" fill="#D9B48C" />
        <path d="M9.4 6 Q13 1.4 16.6 6 Z" fill="#FFFDF8" stroke="#DCD8CE" strokeWidth=".6" />
      </svg>
    </span>
  );
}
