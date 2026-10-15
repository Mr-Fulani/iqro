export function DuaTimeIcon({ evening }: { evening: boolean }) {
  return (
    <span className={`dua-topic-icon dua-time-icon${evening ? " is-evening" : ""}`} aria-hidden="true">
      <svg viewBox="0 0 64 64" fill="none">
        {evening ? <>
          <path d="M43 8C35 8 30 14 31 21C32 30 43 34 50 27C41 29 36 17 43 8Z" fill="#E7C27D" />
          <path d="m14 11 1.2 2.8L18 15l-2.8 1.2L14 19l-1.2-2.8L10 15l2.8-1.2Z" fill="#A99BC9" />
          <circle cx="23" cy="23" r="1.3" fill="#A99BC9" />
          <circle cx="32" cy="39" r="8" fill="#D99473" />
        </> : <>
          <circle cx="32" cy="28" r="10" fill="#D5A34C" />
          <path d="M32 8v5M16 15l3.5 3.5M48 15l-3.5 3.5M9 28h5M50 28h5" stroke="#D5A34C" strokeWidth="2" strokeLinecap="round" />
        </>}
        <path d="M8 40Q20 25 32 38Q44 26 56 40V52H8Z" fill={evening ? "#E1DCEB" : "#D6E5DA"} />
        <path d="M8 44Q21 36 33 44T56 43V52H8Z" fill={evening ? "#786EAD" : "#0B5D4A"} />
        <path d="M17 57h30" stroke={evening ? "#A99BC9" : "#91B4A5"} strokeWidth="2" strokeLinecap="round" />
      </svg>
    </span>
  );
}
