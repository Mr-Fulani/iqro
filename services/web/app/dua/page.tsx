"use client";

import Link from "next/link";
import { FormEvent, useCallback, useEffect, useState } from "react";
import { DuaEntryList } from "../../components/DuaEntryList";
import { DuaTopicIcon } from "../../components/DuaTopicIcon";
import {
  api,
  DuaCategory,
  DuaCollection,
  DuaEntry,
  PaginatedResponse,
} from "../../lib/api";
import { useI18n } from "../../lib/i18n-context";
import type { PublishedDuaInitialData } from "../../lib/public-content";
import { localizedPath } from "../../lib/routing";

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
  }, [appliedQuery, locale, t]);

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
  };

  const loadMore = async () => {
    if (!nextCursor || loadingMore) return;
    setLoadingMore(true);
    try {
      const page: PaginatedResponse<DuaEntry> = await api.getDuaEntries({
        language: locale,
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
            <strong>{formatNumber(collection?.entry_count ?? 267)}</strong>
            <span>{t("dua.entriesAvailable")}</span>
          </div>
          <div>
            <strong>{formatNumber(collection?.category_count ?? 132)}</strong>
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
          {appliedQuery ? (
            <button className="btn btn-secondary" type="button" onClick={resetFilters}>
              {t("dua.resetFilters")}
            </button>
          ) : null}
        </form>

        <div className="dua-category-section">
          <header>
            <h2>{t("dua.topicsTitle")}</h2>
            <p>{t("dua.categoryFilter")}</p>
          </header>
          <div className="dua-category-list" aria-label={t("dua.categoryFilter")}>
            {categories.map((category) => (
              <Link
                key={category.id}
                href={localizedPath(locale, `/dua/${category.slug}`)}
                className="dua-category-chip"
                aria-label={t("dua.openTopic", { topic: category.title })}
              >
                <span className="dua-category-card-head">
                  <DuaTopicIcon sourceNumber={category.source_number} slug={category.slug} />
                  <span className="dua-category-number">{formatNumber(category.source_number)}</span>
                </span>
                <span className="dua-category-title">{category.title}</span>
                <span className="dua-category-meta">
                  <small>
                    {t("dua.categoryEntryCount", { count: formatNumber(category.entry_count) })}
                  </small>
                  <span className="dua-category-arrow" aria-hidden="true">
                    {locale === "ar" ? "←" : "→"}
                  </span>
                </span>
              </Link>
            ))}
          </div>
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
        ) : (
          <DuaEntryList entries={entries} />
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
