"use client";

import Link from "next/link";
import { FormEvent, useEffect, useMemo, useState } from "react";
import { DuaTopicIcon } from "./DuaTopicIcon";
import {
  api,
  DuaCategory,
  DuaCollection,
} from "../lib/api";
import { useI18n } from "../lib/i18n-context";
import type { PublishedDuaInitialData } from "../lib/public-content";
import { localizedPath } from "../lib/routing";

export default function DuaPage({
  initialData,
}: {
  initialData?: PublishedDuaInitialData;
}) {
  const { formatNumber, locale, t } = useI18n();
  const [collections, setCollections] = useState<DuaCollection[]>(initialData?.collections ?? []);
  const [categories, setCategories] = useState<DuaCategory[]>(initialData?.categories ?? []);
  const [query, setQuery] = useState("");
  const [appliedQuery, setAppliedQuery] = useState("");
  const [selectedCollection, setSelectedCollection] = useState("");
  const [catalogLoading, setCatalogLoading] = useState(!initialData);
  const [catalogReloadKey, setCatalogReloadKey] = useState(0);
  const [error, setError] = useState("");

  useEffect(() => {
    let active = true;
    setCatalogLoading(true);
    Promise.all([api.getDuaCollections(locale), api.getDuaCategories(locale)])
      .then(([nextCollections, nextCategories]) => {
        if (!active) return;
        setCollections(nextCollections);
        setCategories(nextCategories);
        setSelectedCollection((current) =>
          current && nextCollections.some((item) => item.slug === current)
            ? current
            : "",
        );
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
  }, [catalogReloadKey, locale, t]);

  const visibleCategories = useMemo(() => {
    const normalizedQuery = appliedQuery.toLocaleLowerCase(locale).trim();
    return categories.filter((category) => {
      if (selectedCollection && category.collection !== selectedCollection) return false;
      if (!normalizedQuery) return true;
      return category.title.toLocaleLowerCase(locale).includes(normalizedQuery)
        || String(category.source_number) === normalizedQuery;
    });
  }, [appliedQuery, categories, locale, selectedCollection]);

  const summaryCollections = useMemo(
    () => selectedCollection
      ? collections.filter((item) => item.slug === selectedCollection)
      : collections,
    [collections, selectedCollection],
  );
  const summaryEntryCount = summaryCollections.reduce(
    (total, item) => total + item.entry_count,
    0,
  );
  const summaryCategoryCount = summaryCollections.reduce(
    (total, item) => total + item.category_count,
    0,
  );

  const handleSearch = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setAppliedQuery(query.trim());
  };

  const resetFilters = () => {
    setQuery("");
    setAppliedQuery("");
  };

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
            <strong>{formatNumber(summaryEntryCount)}</strong>
            <span>{t("dua.entriesAvailable")}</span>
          </div>
          <div>
            <strong>{formatNumber(summaryCategoryCount)}</strong>
            <span>{t("dua.categoriesAvailable")}</span>
          </div>
          <p>{t("dua.starterNotice")}</p>
        </div>

        {summaryCollections.map((collection) => collection.source ? (
          <p className="dua-source-lead" key={collection.slug}>
            {t("dua.sourceEdition")}: {collection.source.title} · {collection.source.author}.{" "}
            <a href={collection.source.source_url} target="_blank" rel="noreferrer">
              {t("dua.openSource")} ↗
            </a>
          </p>
        ) : null)}
      </section>

      <section className="surface dua-browser" aria-busy={catalogLoading}>
        <form className="dua-search" onSubmit={handleSearch}>
          <label className="sr-only" htmlFor="dua-collection-filter">
            {t("dua.collectionFilter")}
          </label>
          <select
            id="dua-collection-filter"
            value={selectedCollection}
            onChange={(event) => setSelectedCollection(event.target.value)}
            aria-label={t("dua.collectionFilter")}
          >
            <option value="">{t("dua.allCollections")}</option>
            {collections.map((collection) => (
              <option key={collection.slug} value={collection.slug}>
                {collection.source?.title || collection.slug}
              </option>
            ))}
          </select>
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
            {visibleCategories.map((category) => (
              <Link
                key={category.id}
                href={localizedPath(
                  locale,
                  `/dua/${category.collection}/categories/${category.slug}`,
                )}
                className="dua-category-chip"
                aria-label={t("dua.openTopic", { topic: category.title })}
              >
                <span className="dua-category-card-head">
                  <DuaTopicIcon sourceNumber={category.source_number} slug={category.slug} />
                  <span className="dua-category-number">{formatNumber(category.source_number)}</span>
                </span>
                <span className="dua-category-title">{category.title}</span>
                {!selectedCollection && collections.length > 1 ? (
                  <span className="dua-category-collection">
                    {category.collection_title || category.collection}
                  </span>
                ) : null}
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
          {!catalogLoading && visibleCategories.length === 0 ? (
            <div className="dua-empty">
              <span aria-hidden="true">⌕</span>
              <p>{t("dua.noTopics")}</p>
            </div>
          ) : null}
        </div>

        {error ? (
          <div className="alert alert-error" role="alert">
            <span>{error}</span>
            <button
              className="btn btn-sm btn-secondary"
              type="button"
              onClick={() => setCatalogReloadKey((current) => current + 1)}
            >
              {t("dua.retry")}
            </button>
          </div>
        ) : null}
      </section>
    </div>
  );
}
