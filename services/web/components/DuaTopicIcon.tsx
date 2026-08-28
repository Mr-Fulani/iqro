type DuaTopicIconName =
  | "sun"
  | "shirt"
  | "drop"
  | "home"
  | "mosque"
  | "moon"
  | "shield"
  | "heart"
  | "cloud"
  | "bowl"
  | "compass";

function iconName(sourceNumber: number, slug: string): DuaTopicIconName {
  if (/waking|morning|evening/.test(slug)) return "sun";
  if (/cloth|dress|undress/.test(slug)) return "shirt";
  if (/toilet|ablution/.test(slug)) return "drop";
  if (/home/.test(slug)) return "home";
  if (/mosque|prayer|athan|ruki|sujood|tashahhud|witr|istikharah/.test(slug)) return "mosque";
  if (/sleep|night|dream|moon/.test(slug)) return "moon";
  if (/enemy|harm|protection|devil|satan|oppression|adversary|fear|worry|anguish/.test(slug)) return "shield";
  if (/sick|ill|dead|death|funeral|grave|bereaved|tragedy|child|parent/.test(slug)) return "heart";
  if (/wind|thunder|rain/.test(slug)) return "cloud";
  if (/eat|food|drink|fast|dates|dinner|meal/.test(slug)) return "bowl";
  if (sourceNumber === 1 || sourceNumber === 27) return "sun";
  return "compass";
}

export function DuaTopicIcon({ sourceNumber, slug }: { sourceNumber: number; slug: string }) {
  const name = iconName(sourceNumber, slug);

  return (
    <span className="dua-topic-icon" aria-hidden="true">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
        {name === "sun" ? <><circle cx="12" cy="12" r="3.5" /><path d="M12 2.5v2M12 19.5v2M2.5 12h2M19.5 12h2M5.3 5.3l1.4 1.4M17.3 17.3l1.4 1.4M18.7 5.3l-1.4 1.4M6.7 17.3l-1.4 1.4" /></> : null}
        {name === "shirt" ? <path d="m8.2 4 3.8 2 3.8-2 4.2 3-2.3 3.4-2.2-1V21h-7V9.4l-2.2 1L4 7l4.2-3Z" /> : null}
        {name === "drop" ? <path d="M12 2.5S6.5 9 6.5 14a5.5 5.5 0 0 0 11 0c0-5-5.5-11.5-5.5-11.5Z" /> : null}
        {name === "home" ? <><path d="M3.5 10.5 12 3l8.5 7.5" /><path d="M5.5 9.3V21h13V9.3M9.5 21v-6h5v6" /></> : null}
        {name === "mosque" ? <><path d="M4 21h16M6 21v-9h12v9M9 12V9.5a3 3 0 0 1 6 0V12M8 7.5h8M12 3V1.8" /><path d="M9 16h6" /></> : null}
        {name === "moon" ? <path d="M20 15.2A8.5 8.5 0 0 1 8.8 4a8.5 8.5 0 1 0 11.2 11.2Z" /> : null}
        {name === "shield" ? <><path d="M12 2.5 20 6v5.5c0 5-3.4 8.4-8 10-4.6-1.6-8-5-8-10V6l8-3.5Z" /><path d="m8.8 12 2.1 2.1 4.5-4.5" /></> : null}
        {name === "heart" ? <path d="M20.8 5.8a5 5 0 0 0-7.1 0L12 7.5l-1.7-1.7a5 5 0 1 0-7.1 7.1L12 21l8.8-8.1a5 5 0 0 0 0-7.1Z" /> : null}
        {name === "cloud" ? <><path d="M6.5 16.5h11a4 4 0 0 0 .3-8 6 6 0 0 0-11.2 1.7 3.2 3.2 0 0 0-.1 6.3Z" /><path d="m9 19-1 2M13 19l-1 2M17 19l-1 2" /></> : null}
        {name === "bowl" ? <><path d="M4 11h16a8 8 0 0 1-16 0ZM7 21h10" /><path d="M9 3c0 1.5-1 2-1 3.5M13 3c0 1.5-1 2-1 3.5M17 3c0 1.5-1 2-1 3.5" /></> : null}
        {name === "compass" ? <><circle cx="12" cy="12" r="9" /><path d="m15.5 8.5-2 5-5 2 2-5 5-2Z" /></> : null}
      </svg>
    </span>
  );
}
