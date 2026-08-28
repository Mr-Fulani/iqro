"use client";

import { FormEvent, useCallback, useEffect, useState } from "react";
import {
  api,
  DuaCategory,
  DuaCollection,
  DuaEntry,
  PaginatedResponse,
} from "../../lib/api";
import { useI18n } from "../../lib/i18n-context";
import type { PublishedDuaInitialData } from "../../lib/public-content";

function cursorFromUrl(url: string | null): string | undefined {
  if (!url) return undefined;
  try {
    return new URL(url, "http://iqro.local").searchParams.get("cursor") || undefined;
  } catch {
    return undefined;
  }
}

export default function DuaPage({
  initialData,
}: {
  initialData?: PublishedDuaInitialData;
}) {
  const { formatNumber, locale, t } = useI18n();
  const [collections, setCollections] = useState<DuaCollection[]>(initialData?.collections ?? []);
  const [categories, setCategories] = useState<DuaCategory[]>(initialData?.categories ?? []);
  const [entries, setEntries] = useState<DuaEntry[]>(initialData?.entries.results ?? []);
  const [nextCursor, setNextCursor] = useState<string | undefined>(() =>
    cursorFromUrl(initialData?.entries.next ?? null),
  );
  const [selectedCategory, setSelectedCategory] = useState("");
  const [query, setQuery] = useState("");
  const [appliedQuery, setAppliedQuery] = useState("");
  const [catalogLoading, setCatalogLoading] = useState(!initialData);
  const [entriesLoading, setEntriesLoading] = useState(!initialData);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    let active = true;
    setCatalogLoading(true);
    Promise.all([api.getDuaCollections(locale), api.getDuaCategories(locale)])
      .then(([nextCollections, nextCategories]) => {
        if (!active) return;
        setCollections(nextCollections);
        setCategories(nextCategories);
        setError("");
      })
      .catch(() => {
        if (active) setError(t("dua.unavailable"));
      })
      .finally(() => {
        if (active) setCatalogLoading(false);
      });
    return () => {
      active = false;
    };
  }, [locale, t]);

  const loadEntries = useCallback(async () => {
    setEntriesLoading(true);
    try {
      const page = await api.getDuaEntries({
        language: locale,
        category: selectedCategory || undefined,
        q: appliedQuery || undefined,
      });
      setEntries(page.results);
      setNextCursor(cursorFromUrl(page.next));
      setError("");
    } catch {
      setError(t("dua.unavailable"));
    } finally {
      setEntriesLoading(false);
    }
  }, [appliedQuery, locale, selectedCategory, t]);

  useEffect(() => {
    void loadEntries();
  }, [loadEntries]);

  const handleSearch = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setAppliedQuery(query.trim());
  };

  const resetFilters = () => {
    setQuery("");
    setAppliedQuery("");
    setSelectedCategory("");
  };

  const loadMore = async () => {
    if (!nextCursor || loadingMore) return;
    setLoadingMore(true);
    try {
      const page: PaginatedResponse<DuaEntry> = await api.getDuaEntries({
        language: locale,
        category: selectedCategory || undefined,
        q: appliedQuery || undefined,
        cursor: nextCursor,
      });
      setEntries((current) => [...current, ...page.results]);
      setNextCursor(cursorFromUrl(page.next));
    } catch {
      setError(t("dua.unavailable"));
    } finally {
      setLoadingMore(false);
    }
  };

  const collection = collections[0];

  return (
    <div className="dua-page">
      <section className="surface dua-hero">
        <div className="surface-head">
          <div>
            <p className="eyebrow">{t("dua.eyebrow")}</p>
            <h1 className="surface-title">{t("dua.title")}</h1>
            <p className="surface-subtitle">{t("dua.description")}</p>
          </div>
          <span className="dua-hero-icon" aria-hidden="true">🤲</span>
        </div>

        <div className="dua-catalog-summary">
          <div>
            <strong>{formatNumber(collection?.entry_count ?? 10)}</strong>
            <span>{t("dua.entriesAvailable")}</span>
          </div>
          <div>
            <strong>{formatNumber(collection?.category_count ?? 10)}</strong>
            <span>{t("dua.categoriesAvailable")}</span>
          </div>
          <p>{t("dua.starterNotice")}</p>
        </div>

        {collection?.source ? (
          <p className="dua-source-lead">
            {t("dua.sourceEdition")}: {collection.source.title} · {collection.source.author}.{" "}
            <a href={collection.source.source_url} target="_blank" rel="noreferrer">
              IslamHouse ↗
            </a>
          </p>
        ) : null}
      </section>

      <section className="surface dua-browser" aria-busy={catalogLoading || entriesLoading}>
        <form className="dua-search" onSubmit={handleSearch}>
          <label className="sr-only" htmlFor="dua-search-input">{t("dua.searchLabel")}</label>
          <input
            id="dua-search-input"
            type="search"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder={t("dua.searchPlaceholder")}
            maxLength={120}
          />
          <button className="btn btn-primary" type="submit">{t("dua.searchButton")}</button>
          {(selectedCategory || appliedQuery) ? (
            <button className="btn btn-secondary" type="button" onClick={resetFilters}>
              {t("dua.resetFilters")}
            </button>
          ) : null}
        </form>

        <div className="dua-category-list" aria-label={t("dua.categoryFilter")}>
          <button
            type="button"
            className={`dua-category-chip${selectedCategory === "" ? " is-active" : ""}`}
            aria-pressed={selectedCategory === ""}
            onClick={() => setSelectedCategory("")}
          >
            {t("dua.allCategories")}
          </button>
          {categories.map((category) => (
            <button
              key={category.id}
              type="button"
              className={`dua-category-chip${selectedCategory === category.slug ? " is-active" : ""}`}
              aria-pressed={selectedCategory === category.slug}
              onClick={() => setSelectedCategory(category.slug)}
            >
              {category.title}
            </button>
          ))}
        </div>

        {error ? (
          <div className="alert alert-error" role="alert">
            <span>{error}</span>
            <button className="btn btn-sm btn-secondary" type="button" onClick={() => void loadEntries()}>
              {t("dua.retry")}
            </button>
          </div>
        ) : null}

        {entriesLoading ? (
          <div className="alert alert-info">{t("common.loading")}</div>
        ) : entries.length === 0 ? (
          <div className="dua-empty">
            <span aria-hidden="true">🤲</span>
            <p>{t("dua.empty")}</p>
          </div>
        ) : (
          <div className="dua-entry-list">
            {entries.map((entry) => (
              <article className="dua-entry-card" key={entry.id}>
                <header className="dua-entry-head">
                  <div>
                    <span className="dua-entry-number">#{formatNumber(entry.source_number)}</span>
                    <h2>{entry.category.title}</h2>
                  </div>
                  <span className="status-chip">
                    {entry.repetitions === 1
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
        )}

        {nextCursor ? (
          <button
            className="btn btn-secondary dua-load-more"
            type="button"
            disabled={loadingMore}
            onClick={() => void loadMore()}
          >
            {loadingMore ? t("common.loading") : t("dua.loadMore")}
          </button>
        ) : null}
      </section>
    </div>
  );
}
