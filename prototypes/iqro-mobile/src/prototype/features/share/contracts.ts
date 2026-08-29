import type { Locale } from "../../types";

export type ShareAction = "open-system-share" | "copy-link" | "copy-code";
export type ShareResult = "shared" | "copied" | "dismissed" | "unavailable";

export interface ShareExperience {
  schemaVersion: 1;
  campaignId: string;
  source: "local-default" | "remote-config";
  locale: Locale;
  title: string;
  message: string;
  downloadUrl: string;
  referral: {
    status: "not-connected" | "available";
    code: string | null;
    shortUrl: string | null;
    rewardText: string | null;
  };
  configVersion: string;
}

export interface ReferralSummary {
  invited: number;
  qualified: number;
  rewardBalance: number;
}

export interface ShareEvent {
  eventId: string;
  campaignId: string;
  action: ShareAction;
  result: ShareResult;
  occurredAt: string;
  accountMode: "guest" | "verified";
}

export interface ShareGateway {
  getExperience(input: { locale: Locale; accountMode: "guest" | "verified" }): Promise<ShareExperience>;
  createReferralLink(): Promise<ShareExperience["referral"]>;
  getReferralSummary(): Promise<ReferralSummary | null>;
  trackEvent(event: ShareEvent): Promise<void>;
}
