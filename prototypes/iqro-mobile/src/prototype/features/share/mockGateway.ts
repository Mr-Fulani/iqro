import type { Locale } from "../../types";
import type { ShareEvent, ShareExperience, ShareGateway } from "./contracts";

const EVENT_OUTBOX_KEY = "iqro-share-event-outbox-v1";

const copy: Record<Locale, { title: string; message: string }> = {
  ru: { title: "IQRO — ежедневное чтение Корана", message: "Попробуйте IQRO — спокойный ежедневный ритм чтения, слушания и заучивания Корана." },
  en: { title: "IQRO — daily Quran practice", message: "Try IQRO for a calm daily rhythm of Quran reading, listening and memorization." },
  ar: { title: "إقرأ — وردك اليومي من القرآن", message: "جرّب إقرأ لقراءة القرآن والاستماع والحفظ بهدوء كل يوم." },
  tr: { title: "IQRO — günlük Kur'an pratiği", message: "Kur'an okuma, dinleme ve ezber için sakin bir günlük ritim sunan IQRO'yu deneyin." },
};

export const mockShareGateway: ShareGateway = {
  async getExperience({ locale }) {
    return {
      schemaVersion: 1,
      campaignId: "evergreen-share-v1",
      source: "local-default",
      locale,
      ...copy[locale],
      // Reserved example domain: replace through remote config before release.
      downloadUrl: "https://iqro.example/download",
      referral: { status: "not-connected", code: null, shortUrl: null, rewardText: null },
      configVersion: "local-default-1",
    } satisfies ShareExperience;
  },

  async createReferralLink() {
    return { status: "not-connected", code: null, shortUrl: null, rewardText: null };
  },

  async getReferralSummary() {
    return null;
  },

  async trackEvent(event: ShareEvent) {
    try {
      const existing = JSON.parse(window.localStorage.getItem(EVENT_OUTBOX_KEY) || "[]") as ShareEvent[];
      window.localStorage.setItem(EVENT_OUTBOX_KEY, JSON.stringify([...existing.slice(-49), event]));
    } catch {
      // Analytics must never block sharing; the production adapter retries its outbox later.
    }
  },
};
