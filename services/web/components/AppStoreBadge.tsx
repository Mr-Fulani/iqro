"use client";

import Image from "next/image";
import { useI18n } from "../lib/i18n-context";
import { appStoreBadge } from "../lib/store-badge";

/** Apple's "Download on the App Store" badge; renders nothing until the store URL is set. */
export function AppStoreBadge() {
  const { locale, t } = useI18n();
  const badge = appStoreBadge(locale, process.env.NEXT_PUBLIC_IOS_APP_STORE_URL);
  if (!badge) return null;
  return (
    <a
      className="app-store-badge"
      href={badge.href}
      target="_blank"
      rel="noopener noreferrer"
      data-testid="app-store-badge"
    >
      <Image
        src={badge.src}
        alt={t("footer.appStoreBadge")}
        width={badge.width}
        height={badge.height}
        loading="lazy"
        unoptimized
      />
    </a>
  );
}
