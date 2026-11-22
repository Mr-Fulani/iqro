"use client";

import Image from "next/image";
import { useI18n } from "../lib/i18n-context";
import { googlePlayBadge } from "../lib/store-badge";

/** The official "Get it on Google Play" badge; renders nothing until the store URL is set. */
export function GooglePlayBadge() {
  const { locale, t } = useI18n();
  const badge = googlePlayBadge(locale, process.env.NEXT_PUBLIC_ANDROID_PLAY_STORE_URL);
  if (!badge) return null;
  return (
    <a
      className="google-play-badge"
      href={badge.href}
      target="_blank"
      rel="noopener noreferrer"
      data-testid="google-play-badge"
    >
      <Image
        src={badge.src}
        alt={t("footer.googlePlayBadge")}
        width={badge.width}
        height={badge.height}
        loading="lazy"
        unoptimized
      />
    </a>
  );
}
