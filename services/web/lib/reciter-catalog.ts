import type { Recitation, Reciter } from "./api";

const CANONICAL_RECITER_SLUGS: Readonly<Record<string, string>> = {
  "qf-1-abdulbaset-abdulsamad-mujawwad": "qf-2-abdul-baset-abdul-samad",
  "qf-12-mahmoud-khaleel-al-husary": "qf-6-mahmoud-khaleel-al-husary",
};

export const HOME_POPULAR_RECITER_SLUGS = [
  "qf-7-mishari-rashid-al-afasy",
  "qf-3-abdur-rahman-as-sudais",
  "qf-2-abdul-baset-abdul-samad",
  "qf-9-muhammad-siddiq-al-minshawi",
  "qf-6-mahmoud-khaleel-al-husary",
  "qf-159-maher-al-muaiqly",
  "qf-13-saad-al-ghamdi",
  "qf-10-saud-ash-shuraym",
] as const;

export type RecitationRole = "listen" | "ayah_playback" | "memorization";

export function reciterPersonKey(reciter: Pick<Reciter, "slug"> | string): string {
  const slug = typeof reciter === "string" ? reciter : reciter.slug;
  return CANONICAL_RECITER_SLUGS[slug] || slug;
}

export function groupRecitersByPerson(reciters: Reciter[]): Reciter[] {
  const people = new Map<string, Reciter>();
  for (const reciter of reciters) {
    const personKey = reciterPersonKey(reciter);
    const current = people.get(personKey);
    if (!current) {
      people.set(personKey, reciter);
      continue;
    }

    const representative = reciter.slug === personKey ? reciter : current;
    const portraitUrl =
      representative.portrait_url || current.portrait_url || reciter.portrait_url || null;
    people.set(
      personKey,
      portraitUrl === representative.portrait_url
        ? representative
        : { ...representative, portrait_url: portraitUrl },
    );
  }
  return [...people.values()];
}

export function selectHomePopularReciters(reciters: Reciter[]): Reciter[] {
  const people = groupRecitersByPerson(reciters);
  const bySlug = new Map(people.map((reciter) => [reciterPersonKey(reciter), reciter]));
  const ranked = HOME_POPULAR_RECITER_SLUGS.flatMap((slug) => {
    const reciter = bySlug.get(slug);
    return reciter ? [reciter] : [];
  });
  const rankedKeys = new Set(ranked.map(reciterPersonKey));

  return [...ranked, ...people.filter((reciter) => !rankedKeys.has(reciterPersonKey(reciter)))]
    .slice(0, HOME_POPULAR_RECITER_SLUGS.length);
}

export function reciterSourcesForPerson(reciters: Reciter[], selected: Reciter): Reciter[] {
  const personKey = reciterPersonKey(selected);
  return reciters.filter((reciter) => reciterPersonKey(reciter) === personKey);
}

export function supportsRecitationRole(
  recitation: Recitation,
  role: RecitationRole,
): boolean {
  const capability = recitation.capabilities?.[role];
  if (typeof capability === "boolean") return capability;

  // Keep old cached/API responses readable during the additive contract rollout.
  if (role === "listen") return recitation.rights.stream && recitation.coverage.surah_count > 0;
  return recitation.timings.available && recitation.timings.complete === true;
}

export function recitationsForRole(
  recitations: Recitation[],
  role: RecitationRole,
): Recitation[] {
  return recitations.filter((recitation) => supportsRecitationRole(recitation, role));
}

function publishedTimestamp(recitation: Recitation): number {
  const timestamp = Date.parse(recitation.published_at);
  return Number.isFinite(timestamp) ? timestamp : 0;
}

export function latestRecitationsByVariant(
  recitations: Recitation[],
  role?: RecitationRole,
): Recitation[] {
  const variants = new Map<string, Recitation>();
  const eligible = role ? recitationsForRole(recitations, role) : recitations;
  for (const recitation of eligible) {
    const key = [
      reciterPersonKey(recitation.reciter),
      recitation.style,
      recitation.quran_edition.code,
    ].join(":");
    const current = variants.get(key);
    if (!current || publishedTimestamp(recitation) > publishedTimestamp(current)) {
      variants.set(key, recitation);
    }
  }
  return [...variants.values()].sort((left, right) =>
    left.style.localeCompare(right.style) ||
    left.quran_edition.riwayah.localeCompare(right.quran_edition.riwayah),
  );
}
