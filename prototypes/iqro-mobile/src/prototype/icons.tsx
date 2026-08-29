import type { ReactNode, SVGProps } from "react";

type IconName =
  | "home" | "book" | "target" | "headphones" | "grid" | "arrow" | "chevron"
  | "search" | "bookmark" | "play" | "pause" | "clock" | "moon" | "sun"
  | "settings" | "bell" | "map" | "repeat" | "timer" | "user" | "plus"
  | "check" | "refresh" | "trash" | "globe" | "volume" | "skipBack"
  | "skipForward" | "list" | "shield" | "info" | "flame" | "calendar"
  | "spark" | "arch" | "droplet" | "sunrise" | "download" | "close"
  | "more" | "layers" | "edit" | "logout" | "mail" | "device" | "wifiOff"
  | "share" | "gift" | "link" | "copy";

const paths: Record<IconName, ReactNode> = {
  home: <><path d="m3 11 9-8 9 8"/><path d="M5 10v10h14V10M9 20v-6h6v6"/></>,
  book: <><path d="M4 5.5A3.5 3.5 0 0 1 7.5 2H11v17H7.5A3.5 3.5 0 0 0 4 22Z"/><path d="M20 5.5A3.5 3.5 0 0 0 16.5 2H13v17h3.5A3.5 3.5 0 0 1 20 22Z"/></>,
  target: <><circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1.5"/></>,
  headphones: <><path d="M4 14v-2a8 8 0 0 1 16 0v2"/><path d="M4 14h3v7H5a1 1 0 0 1-1-1Zm16 0h-3v7h2a1 1 0 0 0 1-1Z"/></>,
  grid: <><rect x="3" y="3" width="7" height="7" rx="2"/><rect x="14" y="3" width="7" height="7" rx="2"/><rect x="3" y="14" width="7" height="7" rx="2"/><rect x="14" y="14" width="7" height="7" rx="2"/></>,
  arrow: <><path d="m15 18-6-6 6-6"/></>,
  chevron: <path d="m9 18 6-6-6-6"/>,
  search: <><circle cx="11" cy="11" r="7"/><path d="m20 20-4-4"/></>,
  bookmark: <path d="M6 3h12v18l-6-4-6 4Z"/>,
  play: <path d="m8 5 11 7-11 7Z"/>,
  pause: <><path d="M8 5v14M16 5v14"/></>,
  clock: <><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></>,
  moon: <path d="M20 15.5A8.5 8.5 0 0 1 8.5 4 8.5 8.5 0 1 0 20 15.5Z"/>,
  sun: <><circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M4.9 4.9l1.4 1.4m11.4 11.4 1.4 1.4M2 12h2m16 0h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></>,
  settings: <><circle cx="12" cy="12" r="3"/><path d="M19 13.5v-3l2-1.5-2-3.4-2.4 1A8 8 0 0 0 14 5l-.3-2.6h-4L9.4 5a8 8 0 0 0-2.6 1.6l-2.4-1L2.5 9l2 1.5v3L2.5 15l2 3.4 2.4-1A8 8 0 0 0 9.4 19l.3 2.6h4L14 19a8 8 0 0 0 2.6-1.6l2.4 1 2-3.4Z"/></>,
  bell: <><path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9"/><path d="M10 21h4"/></>,
  map: <><path d="m3 6 6-3 6 3 6-3v15l-6 3-6-3-6 3Z"/><path d="M9 3v15m6-12v15"/></>,
  repeat: <><path d="m17 2 4 4-4 4"/><path d="M3 11V9a3 3 0 0 1 3-3h15M7 22l-4-4 4-4"/><path d="M21 13v2a3 3 0 0 1-3 3H3"/></>,
  timer: <><circle cx="12" cy="13" r="8"/><path d="M12 9v4l3 2M9 2h6"/></>,
  user: <><circle cx="12" cy="8" r="4"/><path d="M4 22a8 8 0 0 1 16 0"/></>,
  plus: <path d="M12 5v14M5 12h14"/>,
  check: <path d="m5 12 4 4L19 6"/>,
  refresh: <><path d="M20 7v5h-5"/><path d="M4 17v-5h5M6 8a7 7 0 0 1 12-2l2 2M18 16a7 7 0 0 1-12 2l-2-2"/></>,
  trash: <><path d="M4 7h16M9 7V4h6v3M7 7l1 14h8l1-14"/></>,
  globe: <><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/></>,
  volume: <><path d="M4 10v4h4l5 4V6l-5 4Z"/><path d="M16 9a4 4 0 0 1 0 6M19 6a8 8 0 0 1 0 12"/></>,
  skipBack: <><path d="M6 5v14M18 6l-9 6 9 6Z"/></>,
  skipForward: <><path d="M18 5v14M6 6l9 6-9 6Z"/></>,
  list: <><path d="M8 6h13M8 12h13M8 18h13"/><circle cx="3.5" cy="6" r=".5"/><circle cx="3.5" cy="12" r=".5"/><circle cx="3.5" cy="18" r=".5"/></>,
  shield: <path d="M12 2 4 5v6c0 5 3.5 9 8 11 4.5-2 8-6 8-11V5Z"/>,
  info: <><circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7h.01"/></>,
  flame: <path d="M13 2s1 4-2 6c-2-2-5 0-5 4a6 6 0 0 0 12 0c0-5-5-7-5-10Z"/>,
  calendar: <><rect x="3" y="5" width="18" height="16" rx="3"/><path d="M8 3v4m8-4v4M3 10h18"/></>,
  spark: <><path d="m12 3 1.5 4.5L18 9l-4.5 1.5L12 15l-1.5-4.5L6 9l4.5-1.5Z"/><path d="m19 15 .7 2.3L22 18l-2.3.7L19 21l-.7-2.3L16 18l2.3-.7Z"/></>,
  arch: <><path d="M5 21V11a7 7 0 0 1 14 0v10M9 21V11a3 3 0 0 1 6 0v10"/><path d="M3 21h18"/></>,
  droplet: <path d="M12 2s6 6.3 6 12a6 6 0 0 1-12 0c0-5.7 6-12 6-12Z"/>,
  sunrise: <><path d="M4 18h16M6 14a6 6 0 0 1 12 0M12 3v3M4.2 7.2l2.1 2.1m11.4 0 2.1-2.1"/></>,
  download: <><path d="M12 3v12m-5-5 5 5 5-5M5 21h14"/></>,
  close: <path d="m6 6 12 12M18 6 6 18"/>,
  more: <><circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/></>,
  layers: <><path d="m12 2 9 5-9 5-9-5Z"/><path d="m3 12 9 5 9-5M3 17l9 5 9-5"/></>,
  edit: <><path d="M12 20H4v-8L15 1l8 8Z"/><path d="m14 3 7 7"/></>,
  logout: <><path d="M10 4H4v16h6M14 8l4 4-4 4m-6-4h10"/></>,
  mail: <><rect x="3" y="5" width="18" height="14" rx="2"/><path d="m3 7 9 6 9-6"/></>,
  device: <><rect x="6" y="2" width="12" height="20" rx="3"/><path d="M10 18h4"/></>,
  wifiOff: <><path d="m3 3 18 18M5 12a11 11 0 0 1 2.5-1.7M9.5 8.2A11 11 0 0 1 19 12M8.5 16a5 5 0 0 1 7 0M12 20h.01"/></>,
  share: <><circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><path d="m8.6 10.5 6.8-4M8.6 13.5l6.8 4"/></>,
  gift: <><rect x="3" y="9" width="18" height="12" rx="2"/><path d="M12 9v12M3 13h18M8.5 9C6 9 5 7.7 5 6.4 5 5.1 6 4 7.4 4 9.3 4 12 9 12 9m3.5 0C18 9 19 7.7 19 6.4 19 5.1 18 4 16.6 4 14.7 4 12 9 12 9"/></>,
  link: <><path d="M10 13a5 5 0 0 0 7.5.5l2-2a5 5 0 0 0-7-7l-1.1 1.1"/><path d="M14 11a5 5 0 0 0-7.5-.5l-2 2a5 5 0 0 0 7 7l1.1-1.1"/></>,
  copy: <><rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h3"/></>,
};

export function Icon({ name, size = 22, filled = false, ...props }: SVGProps<SVGSVGElement> & { name: IconName; size?: number; filled?: boolean }) {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24" width={size} height={size} fill={filled ? "currentColor" : "none"} stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" {...props}>
      {paths[name]}
    </svg>
  );
}
