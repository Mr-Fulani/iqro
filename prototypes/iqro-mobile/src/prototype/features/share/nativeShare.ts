import type { ShareExperience, ShareResult } from "./contracts";

async function copyText(value: string): Promise<ShareResult> {
  try {
    await navigator.clipboard.writeText(value);
    return "copied";
  } catch {
    return "unavailable";
  }
}

export async function openNativeShare(experience: ShareExperience): Promise<ShareResult> {
  if (navigator.share) {
    try {
      await navigator.share({ title: experience.title, text: experience.message, url: experience.referral.shortUrl || experience.downloadUrl });
      return "shared";
    } catch (error) {
      return error instanceof DOMException && error.name === "AbortError" ? "dismissed" : "unavailable";
    }
  }
  return copyText(experience.referral.shortUrl || experience.downloadUrl);
}

export { copyText };
