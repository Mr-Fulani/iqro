// Icons of the app's du'a screens: the mihrab is _DuaMihrabPainter
// (iqro_icon.dart), the rest follow the Material icons the app uses.
import type { ReactNode } from "react";

function Icon({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <svg className={className ? `dua-icon ${className}` : "dua-icon"} viewBox="0 0 24 24" aria-hidden="true">
      {children}
    </svg>
  );
}

/** Du'a: a mihrab with a hanging lamp. */
export function DuaMihrabIcon({ className }: { className?: string }) {
  return (
    <Icon className={className}>
      <g fill="none" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round">
        <path d="M4.5 21.5v-10Q4.5 5.5 12 2q7.5 3.5 7.5 9.5v10Z" strokeWidth="1.8" />
        <path d="M12 2v6M10.5 16.2h3" strokeWidth="1.5" />
      </g>
      <path d="M10.5 8.2h3l.9 1.4q1.2 2.7-.2 5.4H9.8q-1.4-2.7-.2-5.4Z" fill="currentColor" />
    </Icon>
  );
}

const stroke = {
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 2,
  strokeLinecap: "round" as const,
  strokeLinejoin: "round" as const,
};

export function DuaPlayIcon({ playing }: { playing: boolean }) {
  return (
    <Icon>
      {playing
        ? <path d="M7 5h3.2v14H7zM13.8 5H17v14h-3.2z" fill="currentColor" />
        : <path d="M8 5.2v13.6L18.6 12Z" fill="currentColor" />}
    </Icon>
  );
}

/** Repeat, or repeat-one when it is on. */
export function DuaRepeatIcon({ one }: { one: boolean }) {
  return (
    <Icon>
      <path d="M7 6.5h10.5V10M17 17.5H6.5V14M15 4.5l2.5 2-2.5 2M9 19.5l-2.5-2 2.5-2" {...stroke} />
      {one ? <path d="M11.3 10.6 12.5 10v4.2" {...stroke} strokeWidth={1.7} /> : null}
    </Icon>
  );
}

export function DuaRefreshIcon() {
  return (
    <Icon>
      <path d="M19 12a7 7 0 1 1-2.05-4.95M19 4.5V9h-4.5" {...stroke} />
    </Icon>
  );
}

/** Forward chevron; CSS mirrors it in right-to-left pages. */
export function DuaChevronIcon() {
  return (
    <Icon className="dua-flip">
      <path d="m9.5 6 6 6-6 6" {...stroke} />
    </Icon>
  );
}

export function DuaBackIcon() {
  return (
    <Icon className="dua-flip">
      <path d="M19.5 12h-15M11 5.5 4.5 12l6.5 6.5" {...stroke} />
    </Icon>
  );
}

export function DuaSearchIcon() {
  return (
    <Icon>
      <path d="M10.5 17a6.5 6.5 0 1 0 0-13 6.5 6.5 0 0 0 0 13ZM15.3 15.3 20 20" {...stroke} />
    </Icon>
  );
}

export function DuaCloudOffIcon() {
  return (
    <Icon>
      <path
        d="M3 3l18 18M8.6 6.4A6.5 6.5 0 0 1 18.4 10a4 4 0 0 1 1.9 7M16 18H7a4.5 4.5 0 0 1-1.6-8.7"
        {...stroke}
      />
    </Icon>
  );
}

export function DuaCheckIcon() {
  return (
    <Icon>
      <path d="m5 12.5 4.5 4.5L19 7.5" {...stroke} strokeWidth={2.6} />
    </Icon>
  );
}

export function DuaVerifiedIcon({ verified }: { verified: boolean }) {
  return (
    <Icon>
      {verified
        ? <path d="M12 3 14.3 5l3-.3.6 3 2.6 1.6-1.3 2.7 1.3 2.7-2.6 1.6-.6 3-3-.3L12 21l-2.3-2-3 .3-.6-3-2.6-1.6 1.3-2.7-1.3-2.7 2.6-1.6.6-3 3 .3Zm-3.2 9 2.2 2.2 4.4-4.4" {...stroke} strokeWidth={1.7} />
        : <path d="M4 5.5C6.5 4.3 9.2 4.3 12 6c2.8-1.7 5.5-1.7 8-.5V19c-2.5-1.2-5.2-1.2-8 .5-2.8-1.7-5.5-1.7-8-.5ZM12 6v13.5" {...stroke} strokeWidth={1.7} />}
    </Icon>
  );
}

export function DuaExpandIcon() {
  return (
    <Icon className="dua-expand-icon">
      <path d="m6 9.5 6 6 6-6" {...stroke} />
    </Icon>
  );
}
