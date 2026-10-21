import Link from "next/link";
import type { DuaEntry } from "../lib/api";
import { duaPreview } from "../lib/dua-presentation";
import { duaDisplayTitle } from "../lib/dua-share";
import type { Locale } from "../lib/i18n";
import { localizedPath } from "../lib/routing";
import { DuaChevronIcon } from "./DuaIcons";

/** Du'a a search found, under the title of each chapter (_AsyncDuaEntries). */
export function DuaEntrySummaryList({ entries, locale }: { entries: DuaEntry[]; locale: Locale }) {
  const groups = new Map<string, { title: string; entries: DuaEntry[] }>();
  for (const entry of entries) {
    const key = `${entry.collection}:${entry.category.slug}`;
    const group = groups.get(key) ?? { title: duaDisplayTitle(entry.category.title, locale), entries: [] };
    group.entries.push(entry);
    groups.set(key, group);
  }
  return (
    <div className="dua-summary-groups">
      {[...groups].map(([key, group]) => (
        <section key={key} className="dua-summary-group">
          <h2>{group.title}</h2>
          <ul className="dua-summary-list">
            {group.entries.map((entry) => {
              const preview = duaPreview(entry, locale);
              return (
                <li key={entry.id}>
                  <Link
                    href={localizedPath(locale, `/dua/${entry.collection}/${entry.source_number}`)}
                    className="dua-summary-row"
                    data-source-number={entry.source_number}
                  >
                    <span className="dua-summary-number">#{entry.source_number}</span>
                    <span className="dua-summary-preview" dir={preview.arabic ? "rtl" : undefined}>
                      {preview.text}
                    </span>
                    <DuaChevronIcon />
                  </Link>
                </li>
              );
            })}
          </ul>
        </section>
      ))}
    </div>
  );
}
