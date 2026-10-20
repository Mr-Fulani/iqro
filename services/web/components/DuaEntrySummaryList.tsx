import Link from "next/link";
import type { DuaEntry } from "../lib/api";
import { duaDisplayTitle } from "../lib/dua-share";
import { translate, type Locale } from "../lib/i18n";
import { localizedPath } from "../lib/routing";

export function DuaEntrySummaryList({ entries, locale }: { entries: DuaEntry[]; locale: Locale }) {
  const groups = new Map<string, { title: string; entries: DuaEntry[] }>();
  for (const entry of entries) {
    const key = `${entry.collection}:${entry.category.slug}`;
    const group = groups.get(key) ?? { title: duaDisplayTitle(entry.category.title, locale), entries: [] };
    group.entries.push(entry);
    groups.set(key, group);
  }
  const numbers = new Intl.NumberFormat(locale);
  if (!entries.length) return <p className="dua-empty">{translate(locale, "dua.empty")}</p>;
  return (
    <div className="dua-summary-groups">
      {[...groups].map(([key, group]) => (
        <section key={key} className="dua-summary-group">
          <h2>{group.title}</h2>
          <ul className="dua-summary-list">
            {group.entries.map((entry) => (
              <li key={entry.id}>
                <Link
                  href={localizedPath(locale, `/dua/${entry.collection}/${entry.source_number}`)}
                  className="dua-summary-row"
                  data-source-number={entry.source_number}
                  aria-label={translate(locale, "dua.openTopic", { topic: `${group.title} · #${numbers.format(entry.source_number)}` })}
                >
                  <span className="dua-summary-number">#{numbers.format(entry.source_number)}</span>
                  <span className="dua-summary-preview" dir={locale === "ar" || !entry.translation?.meaning_text ? "rtl" : undefined}>
                    {locale === "ar" ? entry.arabic_text : entry.translation?.meaning_text || entry.arabic_text}
                  </span>
                  <span aria-hidden="true">{locale === "ar" ? "←" : "→"}</span>
                </Link>
              </li>
            ))}
          </ul>
        </section>
      ))}
    </div>
  );
}
