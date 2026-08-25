import type { Recitation, Reciter } from "./api";

const CANONICAL_RECITER_SLUGS: Readonly<Record<string, string>> = {
  "qf-1-abdulbaset-abdulsamad-mujawwad": "qf-2-abdul-baset-abdul-samad",
  "qf-12-mahmoud-khaleel-al-husary": "qf-6-mahmoud-khaleel-al-husary",
};

export function reciterPersonKey(reciter: Pick<Reciter, "slug"> | string): string {
  const slug = typeof reciter === "string" ? reciter : reciter.slug;
  return CANONICAL_RECITER_SLUGS[slug] || slug;
}

export function groupRecitersByPerson(reciters: Reciter[]): Reciter[] {
  const people = new Map<string, Reciter>();
  for (const reciter of reciters) {
    const personKey = reciterPersonKey(reciter);
    const current = people.get(personKey);
    if (!current || reciter.slug === personKey) people.set(personKey, reciter);
  }
  return [...people.values()];
}

export function reciterSourcesForPerson(reciters: Reciter[], selected: Reciter): Reciter[] {
  const personKey = reciterPersonKey(selected);
  return reciters.filter((reciter) => reciterPersonKey(reciter) === personKey);
}

function publishedTimestamp(recitation: Recitation): number {
  const timestamp = Date.parse(recitation.published_at);
  return Number.isFinite(timestamp) ? timestamp : 0;
}

export function latestRecitationsByVariant(recitations: Recitation[]): Recitation[] {
  const variants = new Map<string, Recitation>();
  for (const recitation of recitations) {
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
