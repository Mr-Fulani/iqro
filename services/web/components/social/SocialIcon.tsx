import type { SocialPlatformCode } from "../../lib/api";

type SocialIconProps = {
  platform: SocialPlatformCode;
};

const MONOGRAMS: Partial<Record<SocialPlatformCode, string>> = {
  vk: "VK",
  threads: "@",
  discord: "D",
  pinterest: "P",
  odnoklassniki: "OK",
  rutube: "R",
  reddit: "r/",
  twitch: "T",
};

export function SocialIcon({ platform }: SocialIconProps) {
  const common = {
    className: "social-platform-icon",
    viewBox: "0 0 24 24",
    "aria-hidden": true,
    focusable: false,
  } as const;

  if (platform === "telegram") {
    return <svg {...common}><path d="M3 11.2 20.4 4.5c.8-.3 1.5.2 1.2 1.7l-3 14.1c-.2 1-1 1.3-1.8.8l-4.6-3.4-2.2 2.1c-.2.2-.5.5-1 .5l.3-4.7 8.6-7.8c.4-.3-.1-.5-.6-.2L6.7 14.3l-4.5-1.4c-1-.3-1-1 .8-1.7Z" fill="currentColor" /></svg>;
  }
  if (platform === "youtube") {
    return <svg {...common}><rect x="2" y="5" width="20" height="14" rx="4" fill="currentColor" /><path d="m10 9 6 3-6 3V9Z" fill="white" /></svg>;
  }
  if (platform === "instagram") {
    return <svg {...common}><rect x="3" y="3" width="18" height="18" rx="5" fill="none" stroke="currentColor" strokeWidth="2" /><circle cx="12" cy="12" r="4" fill="none" stroke="currentColor" strokeWidth="2" /><circle cx="17.4" cy="6.7" r="1.2" fill="currentColor" /></svg>;
  }
  if (platform === "tiktok") {
    return <svg {...common}><path d="M14.5 3v10.2a4.5 4.5 0 1 1-3.8-4.4v3a1.7 1.7 0 1 0 1 1.6V3h2.8Zm0 2.2c1.1 1.6 2.5 2.5 4.5 2.7v3a8 8 0 0 1-4.5-1.7v-4Z" fill="currentColor" /></svg>;
  }
  if (platform === "x") {
    return <svg {...common}><path d="M4 3h4.7l4.2 5.7L17.8 3H20l-6.1 7.4L20.5 21h-4.7l-4.7-6.4L5.8 21H3.5l6.6-8L4 3Zm3.6 1.8 9.1 14.4h1.8L9.4 4.8H7.6Z" fill="currentColor" /></svg>;
  }
  if (platform === "facebook") {
    return <svg {...common}><path d="M14 21v-8h2.8l.4-3H14V8.1c0-.9.3-1.6 1.7-1.6h1.8V3.8c-.3 0-1.4-.1-2.6-.1-2.6 0-4.4 1.6-4.4 4.5V10H7.6v3h2.9v8H14Z" fill="currentColor" /></svg>;
  }
  if (platform === "whatsapp") {
    return <svg {...common}><path d="M12 3a8.5 8.5 0 0 0-7.4 12.7L3.3 21l5.4-1.4A8.5 8.5 0 1 0 12 3Z" fill="none" stroke="currentColor" strokeWidth="2" /><path d="M8.3 7.7c.3-.3.8-.2 1 .2l1 2c.1.3.1.6-.1.8l-.8.9c.7 1.4 1.7 2.4 3.1 3.1l.9-.8c.2-.2.5-.2.8-.1l2 1c.4.2.5.7.2 1-1 1.2-2.4 1.5-4 .8a11.1 11.1 0 0 1-5-5c-.7-1.6-.3-3 .9-4Z" fill="currentColor" /></svg>;
  }
  if (platform === "linkedin") {
    return <svg {...common}><rect x="3" y="9" width="4" height="12" fill="currentColor" /><circle cx="5" cy="5" r="2.2" fill="currentColor" /><path d="M10 9h4v1.7c.8-1.2 2-2 3.7-2 3.2 0 3.8 2.1 3.8 5V21h-4v-6.4c0-1.5 0-3-1.8-3s-2.1 1.4-2.1 2.9V21H10V9Z" fill="currentColor" /></svg>;
  }
  if (platform === "github") {
    return <svg {...common}><path d="M12 2.8a9.4 9.4 0 0 0-3 18.3c.5.1.7-.2.7-.5v-1.8c-2.8.6-3.4-1.2-3.4-1.2-.5-1.2-1.1-1.5-1.1-1.5-.9-.6.1-.6.1-.6 1 0 1.6 1.1 1.6 1.1.9 1.6 2.4 1.1 3 .9.1-.7.4-1.1.7-1.3-2.3-.3-4.7-1.1-4.7-5A4 4 0 0 1 7 8.4c-.1-.3-.5-1.3.1-2.7 0 0 .9-.3 2.9 1.1a10 10 0 0 1 5.2 0c2-1.4 2.9-1.1 2.9-1.1.6 1.4.2 2.4.1 2.7a4 4 0 0 1 1.1 2.8c0 3.9-2.4 4.7-4.7 5 .4.3.7 1 .7 1.9v2.5c0 .3.2.6.7.5A9.4 9.4 0 0 0 12 2.8Z" fill="currentColor" /></svg>;
  }
  if (platform === "dzen") {
    return <svg {...common}><path d="M4 4c4 0 6.2 1.1 8 4 1.8-2.9 4-4 8-4 0 4-1.1 6.2-4 8 2.9 1.8 4 4 4 8-4 0-6.2-1.1-8-4-1.8 2.9-4 4-8 4 0-4 1.1-6.2 4-8-2.9-1.8-4-4-4-8Z" fill="currentColor" /></svg>;
  }
  if (platform === "snapchat") {
    return <svg {...common}><path d="M12 3.5c-3 0-4.3 2.5-4.3 5.1 0 1-.2 1.7-.7 2.3-.5.5-1.3.7-2 .9-.6.2-.6 1 .1 1.3.9.4 1.5.8 1.8 1.4.5 1.1.3 1.8 1.2 2 .7.2 1.2-.1 1.8.4.6.5 1.1 1.6 2.1 1.6s1.5-1.1 2.1-1.6c.6-.5 1.1-.2 1.8-.4.9-.2.7-.9 1.2-2 .3-.6.9-1 1.8-1.4.7-.3.7-1.1.1-1.3-.7-.2-1.5-.4-2-.9-.5-.6-.7-1.3-.7-2.3 0-2.6-1.3-5.1-4.3-5.1Z" fill="none" stroke="currentColor" strokeWidth="1.8" /></svg>;
  }
  if (platform === "bluesky") {
    return <svg {...common}><path d="M12 11c-1-2.6-3.8-6.1-6.4-8C3.1 1.2 2.2 1.5 1.6 1.8.9 2.2.8 3.6.8 4.4c0 .8.4 6.3.7 7.2.9 3 4 4 6.8 3.5-4.8.8-6 3.4-3.4 6 4.9 5 7.1-1.1 7.1-1.1s2.2 6.1 7.1 1.1c2.6-2.6 1.4-5.2-3.4-6 2.8.5 5.9-.5 6.8-3.5.3-.9.7-6.4.7-7.2 0-.8-.1-2.2-.8-2.6-.6-.3-1.5-.6-4 1.2-2.6 1.9-5.4 5.4-6.4 8Z" fill="currentColor" /></svg>;
  }

  return (
    <svg {...common}>
      <circle cx="12" cy="12" r="10" fill="currentColor" opacity="0.12" />
      <text
        x="12"
        y="12.5"
        dominantBaseline="middle"
        textAnchor="middle"
        fontSize={MONOGRAMS[platform]?.length === 1 ? 12 : 8.5}
        fontWeight="800"
        fill="currentColor"
      >
        {MONOGRAMS[platform] ?? platform.slice(0, 2).toUpperCase()}
      </text>
    </svg>
  );
}
