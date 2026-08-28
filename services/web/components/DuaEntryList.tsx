"use client";

import type { DuaEntry } from "../lib/api";
import { useI18n } from "../lib/i18n-context";

export function DuaEntryList({
  entries,
  headingLevel = 2,
}: {
  entries: DuaEntry[];
  headingLevel?: 2 | 3;
}) {
  const { formatNumber, locale, t } = useI18n();
  const EntryHeading = headingLevel === 3 ? "h3" : "h2";

  if (entries.length === 0) {
    return (
      <div className="dua-empty">
        <span aria-hidden="true">🤲</span>
        <p>{t("dua.empty")}</p>
      </div>
    );
  }

  return (
    <div className="dua-entry-list">
      {entries.map((entry) => (
        <article className="dua-entry-card" key={entry.id}>
          <header className="dua-entry-head">
            <div>
              <span className="dua-entry-number">#{formatNumber(entry.source_number)}</span>
              <EntryHeading>{entry.category.title}</EntryHeading>
            </div>
            <span className="status-chip">
              {entry.repetition_label
                ? t("dua.repeatSequence", {
                    count: entry.repetition_label
                      .split(" · ")
                      .map((value) => formatNumber(Number(value)))
                      .join(" · "),
                  })
                : entry.repetitions === 1
                  ? t("dua.repeatOnce")
                  : t("dua.repeatCount", { count: formatNumber(entry.repetitions) })}
            </span>
          </header>

          <p className="dua-arabic" lang="ar" dir="rtl">{entry.arabic_text}</p>

          {entry.translation?.transliteration ? (
            <div className="dua-translation-block">
              <span>{t("dua.transliteration")}</span>
              <p>{entry.translation.transliteration}</p>
            </div>
          ) : null}

          {locale !== "ar" && entry.translation ? (
            <div className="dua-translation-block dua-meaning">
              <span>{t("dua.meaning")}</span>
              <p>{entry.translation.meaning_text}</p>
            </div>
          ) : null}

          <details className="dua-provenance">
            <summary>{t("dua.sourceAndEvidence")}</summary>
            <div className="dua-provenance-body">
              {entry.evidence.map((evidence, index) => (
                <div key={`${evidence.source_reference}-${index}`}>
                  <strong>{evidence.source_reference}</strong>
                  <span>
                    {evidence.verification_status === "editorially_verified"
                      ? t("dua.editoriallyVerified")
                      : t("dua.sourceOnly")}
                  </span>
                </div>
              ))}
              {entry.source ? (
                <p>
                  {t("dua.sourceEdition")}: {entry.source.title}.{" "}
                  <a href={entry.source.source_url} target="_blank" rel="noreferrer">
                    {t("dua.openSource")} ↗
                  </a>
                </p>
              ) : null}
            </div>
          </details>
        </article>
      ))}
    </div>
  );
}
