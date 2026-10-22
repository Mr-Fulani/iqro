"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";

import { api, type DuaCategory, type DuaEntry } from "../lib/api";
import { useAuth } from "../lib/auth-context";
import { collectCursorPages } from "../lib/cursor-pagination";
import { duaChaptersMatching } from "../lib/dua-search";
import { duaDisplayTitle } from "../lib/dua-share";
import { duaTopics, topicCategories, topicEntryCount, type DuaTopic } from "../lib/dua-topics";
import { useI18n } from "../lib/i18n-context";
import type { PublishedDuaInitialData } from "../lib/public-content";
import { localizedPath } from "../lib/routing";
import { DuaChapterRow, DuaEmpty, DuaError, DuaLoading, DuaTopBar } from "./DuaChrome";
import { DuaEntrySummaryList } from "./DuaEntrySummaryList";
import { DuaChevronIcon, DuaSearchIcon } from "./DuaIcons";
import { DuaThematicIcon } from "./DuaThematicIcon";

const SEARCH_DELAY_MS = 350;

type SearchState =
  | { status: "idle" }
  | { status: "loading"; query: string }
  | { status: "error"; query: string }
  | { status: "done"; query: string; entries: DuaEntry[] };

/** _DuaTopicCard and _DuaFavoritesCard: icon, title, description, count. */
function DuaTopicCard({
  href,
  icon,
  title,
  description,
  count,
}: {
  href: string;
  icon: string;
  title: string;
  description: string;
  count: string;
}) {
  return (
    <Link className="dua-topic-card" href={href}>
      <DuaThematicIcon topic={icon} />
      <span className="dua-topic-card-title">{title}</span>
      <span className="dua-topic-card-description">{description}</span>
      <span className="dua-topic-card-count">{count}</span>
    </Link>
  );
}

/** _DuaTopicTile: a topic a search found, as a row. */
function DuaTopicTile({ topic, count }: { topic: DuaTopic; count: string }) {
  const { locale } = useI18n();
  return (
    <Link className="dua-topic-tile" href={localizedPath(locale, `/dua/topics/${topic.id}`)}>
      <DuaThematicIcon topic={topic.id} />
      <span className="dua-topic-tile-text">
        <span className="dua-topic-card-title">{topic.title[locale]}</span>
        <span className="dua-topic-card-count">{count}</span>
      </span>
      <DuaChevronIcon />
    </Link>
  );
}

/**
 * The app's du'a catalog (_DuaCatalog): a search field over a grid of topics,
 * the favourites first. Typing searches chapters, topics and the du'a
 * themselves, as the app does.
 */
export default function DuaPage({ initialData }: { initialData?: PublishedDuaInitialData }) {
  const { locale, t } = useI18n();
  const { isLoading: authLoading, session } = useAuth();
  const [categories, setCategories] = useState<DuaCategory[] | null>(initialData?.categories ?? null);
  const [catalogFailed, setCatalogFailed] = useState(false);
  // A server render brings the catalog; without one it loads here.
  const [catalogAttempt, setCatalogAttempt] = useState(initialData ? 0 : 1);
  const [favoritesCount, setFavoritesCount] = useState(0);
  const [query, setQuery] = useState("");
  const [submittedQuery, setSubmittedQuery] = useState("");
  const [searchAttempt, setSearchAttempt] = useState(0);
  const [search, setSearch] = useState<SearchState>({ status: "idle" });

  // The query lives in the address, so «Back» from a du'a returns to it.
  useEffect(() => {
    const initial = new URLSearchParams(window.location.search).get("q")?.trim() ?? "";
    if (!initial) return;
    setQuery(initial);
    if (initial.length >= 2) setSubmittedQuery(initial);
  }, []);

  useEffect(() => {
    if (catalogAttempt === 0) return;
    let active = true;
    setCatalogFailed(false);
    api.getDuaCategories(locale)
      .then((items) => {
        if (active) setCategories(items);
      })
      .catch(() => {
        if (active) setCatalogFailed(true);
      });
    return () => {
      active = false;
    };
  }, [catalogAttempt, locale]);

  useEffect(() => {
    if (authLoading || !session) {
      setFavoritesCount(0);
      return;
    }
    let active = true;
    api.getDuaFavorites()
      .then((snapshot) => {
        if (active) setFavoritesCount(snapshot.results.filter((item) => item.is_favorite).length);
      })
      .catch(() => {
        // The catalog stays usable without personal state.
      });
    return () => {
      active = false;
    };
  }, [authLoading, session]);

  useEffect(() => {
    if (submittedQuery.length < 2) {
      setSearch({ status: "idle" });
      return;
    }
    let active = true;
    setSearch({ status: "loading", query: submittedQuery });
    collectCursorPages((cursor) => api.getDuaEntries({
      language: locale,
      q: submittedQuery,
      cursor,
      page_size: 100,
    }), 10)
      .then((entries) => {
        if (active) setSearch({ status: "done", query: submittedQuery, entries });
      })
      .catch(() => {
        if (active) setSearch({ status: "error", query: submittedQuery });
      });
    return () => {
      active = false;
    };
  }, [locale, searchAttempt, submittedQuery]);

  const onQueryChange = (value: string) => {
    setQuery(value);
    const next = value.trim();
    const url = new URL(window.location.href);
    if (next) url.searchParams.set("q", next);
    else url.searchParams.delete("q");
    window.history.replaceState(window.history.state, "", url);
    if (next.length < 2) setSubmittedQuery("");
  };

  useEffect(() => {
    const next = query.trim();
    if (next.length < 2 || next === submittedQuery) return;
    const timer = window.setTimeout(() => setSubmittedQuery(next), SEARCH_DELAY_MS);
    return () => window.clearTimeout(timer);
  }, [query, submittedQuery]);

  const items = useMemo(() => categories ?? [], [categories]);
  const count = (value: number) => t("dua.count", { count: value });
  const trimmed = query.trim();

  let body;
  if (trimmed) {
    if (trimmed.length < 2) {
      body = <DuaEmpty message={t("dua.searchMinCharacters")} />;
    } else {
      // The server matches the words of each du'a, so a query such as «сон»
      // misses «сна». Chapters and topics whose names match come first.
      const needle = trimmed.toLowerCase();
      const chapters = duaChaptersMatching(trimmed, items);
      const topics = duaTopics.filter((topic) => topicCategories(topic, items).length > 0
        && (topic.title[locale].toLowerCase().includes(needle)
          || topic.description[locale].toLowerCase().includes(needle)));
      const pending = trimmed !== submittedQuery || search.status === "loading" || search.status === "idle";
      const leading = chapters.length + topics.length;
      body = (
        <div className="dua-search-results">
          {chapters.map((chapter) => <DuaChapterRow key={chapter.id} chapter={chapter} locale={locale} t={t} />)}
          {topics.map((topic) => (
            <DuaTopicTile key={topic.id} topic={topic} count={count(topicEntryCount(topic, items))} />
          ))}
          {pending ? (
            <DuaLoading t={t} />
          ) : search.status === "error" ? (
            <DuaError t={t} onRetry={() => setSearchAttempt((value) => value + 1)} />
          ) : search.status === "done" && search.entries.length > 0 ? (
            <DuaEntrySummaryList entries={search.entries} locale={locale} />
          ) : leading === 0 ? (
            <DuaEmpty message={t("dua.notFound")} />
          ) : null}
        </div>
      );
    }
  } else if (categories === null) {
    body = catalogFailed
      ? <DuaError t={t} onRetry={() => setCatalogAttempt((value) => value + 1)} />
      : <DuaLoading t={t} />;
  } else if (items.length === 0) {
    body = <DuaEmpty message={t("dua.noCategories")} />;
  } else {
    const topics = duaTopics.filter((topic) => topicCategories(topic, items).length > 0);
    const other = items.filter((category) =>
      !duaTopics.some((topic) => topicCategories(topic, [category]).length > 0));
    body = (
      <>
        <div className="dua-topic-grid">
          {favoritesCount > 0 ? (
            <DuaTopicCard
              href={localizedPath(locale, "/dua/favorites")}
              icon="favorites"
              title={t("dua.favorites")}
              description={t("dua.favoritesSubtitle")}
              count={count(favoritesCount)}
            />
          ) : null}
          {topics.map((topic) => (
            <DuaTopicCard
              key={topic.id}
              href={localizedPath(locale, `/dua/topics/${topic.id}`)}
              icon={topic.id}
              title={topic.title[locale]}
              description={topic.description[locale]}
              count={count(topicEntryCount(topic, items))}
            />
          ))}
        </div>
        {other.map((category) => (
          <Link
            key={category.id}
            className="dua-plain-card"
            href={localizedPath(locale, `/dua/${category.collection}/categories/${category.slug}`)}
          >
            {duaDisplayTitle(category.title, locale)}
          </Link>
        ))}
      </>
    );
  }

  return (
    <div className="dua-page">
      <DuaTopBar locale={locale} t={t} title={t("dua.title")} subtitle={t("dua.subtitle")} />
      <label className="dua-search">
        <DuaSearchIcon />
        <span className="sr-only">{t("dua.search")}</span>
        <input
          className="dua-search-input"
          type="search"
          value={query}
          onChange={(event) => onQueryChange(event.target.value)}
          placeholder={t("dua.search")}
          maxLength={120}
          enterKeyHint="search"
        />
      </label>
      {body}
    </div>
  );
}
