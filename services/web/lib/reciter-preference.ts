import type { Recitation, Reciter } from "./api";
import { reciterPersonKey } from "./reciter-catalog";

const STORAGE_KEY = "quran_reciter_preference_v1";
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SAFE_KEY_PATTERN = /^[a-z0-9][a-z0-9-]{0,127}$/;

export type ReciterPreference = {
  personKey: string;
  reciterId: string;
  recitationId: string | null;
  style: string | null;
};

function isSafePreference(value: unknown): value is ReciterPreference {
  if (!value || typeof value !== "object") return false;
  const item = value as Record<string, unknown>;
  return (
    typeof item.personKey === "string" &&
    SAFE_KEY_PATTERN.test(item.personKey) &&
    typeof item.reciterId === "string" &&
    UUID_PATTERN.test(item.reciterId) &&
    (item.recitationId === null ||
      (typeof item.recitationId === "string" && UUID_PATTERN.test(item.recitationId))) &&
    (item.style === null ||
      (typeof item.style === "string" && item.style.length > 0 && item.style.length <= 32))
  );
}

export function loadReciterPreference(): ReciterPreference | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const parsed: unknown = JSON.parse(raw);
    if (isSafePreference(parsed)) return parsed;
    window.localStorage.removeItem(STORAGE_KEY);
  } catch {
    // Storage can be unavailable in privacy-restricted browser contexts.
  }
  return null;
}

export function rememberReciterPreference(
  reciter: Pick<Reciter, "id" | "slug">,
  recitation?: Pick<Recitation, "id" | "style"> | null,
): void {
  if (typeof window === "undefined") return;
  const personKey = reciterPersonKey(reciter);
  const current = loadReciterPreference();
  const samePerson = current?.personKey === personKey;
  const preference: ReciterPreference = {
    personKey,
    reciterId: reciter.id,
    recitationId: recitation?.id ?? (samePerson ? current.recitationId : null),
    style: recitation?.style ?? (samePerson ? current.style : null),
  };
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(preference));
  } catch {
    // The selection still works for the current page when storage is unavailable.
  }
}

export function preferredReciter(
  reciters: Reciter[],
  preference = loadReciterPreference(),
): Reciter | undefined {
  if (!preference) return undefined;
  return reciters.find((item) => reciterPersonKey(item) === preference.personKey);
}

export function preferredRecitation(
  recitations: Recitation[],
  preference = loadReciterPreference(),
): Recitation | undefined {
  if (!preference) return undefined;
  const exact = recitations.find((item) => item.id === preference.recitationId);
  if (exact) return exact;
  const samePerson = recitations.filter(
    (item) => reciterPersonKey(item.reciter) === preference.personKey,
  );
  return samePerson.find((item) => item.style === preference.style) || samePerson[0];
}
