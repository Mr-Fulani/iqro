"use client";

import { useEffect, useMemo, useState } from "react";
import type {
  QuranFoundationMushaf,
  QuranFoundationMushafPage,
  QuranFoundationMushafWord,
} from "../lib/api";
import { useI18n } from "../lib/i18n-context";

type FontState = "loading" | "ready" | "error";

type QuranFoundationMushafPageProps = {
  mushaf: QuranFoundationMushaf;
  page: QuranFoundationMushafPage;
  selectedAyahKey: string | null;
  playingAyahKey: string | null;
  onSelectAyah: (ayahKey: string) => void;
};

function isAllowedQuranFontUrl(value: string | undefined): value is string {
  if (!value) return false;
  try {
    const url = new URL(value);
    return (
      url.protocol === "https:" &&
      url.hostname === "verses.quran.foundation" &&
      url.port === "" &&
      url.username === "" &&
      url.password === "" &&
      url.search === "" &&
      url.hash === "" &&
      url.pathname.startsWith("/fonts/quran/") &&
      url.pathname.endsWith(".woff2")
    );
  } catch {
    return false;
  }
}

function verseKeysFromMapping(mapping: Record<string, string>): string[] {
  const keys: string[] = [];
  for (const [surahValue, rangeValue] of Object.entries(mapping).sort(
    ([left], [right]) => Number(left) - Number(right),
  )) {
    const surah = Number(surahValue);
    const match = /^(\d+)(?:-(\d+))?$/.exec(rangeValue.trim());
    if (!Number.isInteger(surah) || surah < 1 || surah > 114 || !match) continue;
    const start = Number(match[1]);
    const end = Number(match[2] || match[1]);
    if (start < 1 || end < start || end > 286) continue;
    for (let ayah = start; ayah <= end; ayah += 1) keys.push(`${surah}:${ayah}`);
  }
  return keys;
}

function verseKeyById(page: QuranFoundationMushafPage): Map<number, string> {
  const verseIds: number[] = [];
  const seen = new Set<number>();
  for (const word of [...page.words].sort(
    (left, right) => left.position_in_page - right.position_in_page,
  )) {
    if (word.verse_id === null || seen.has(word.verse_id)) continue;
    seen.add(word.verse_id);
    verseIds.push(word.verse_id);
  }
  const verseKeys = verseKeysFromMapping(page.verse_mapping);
  return new Map(
    verseIds.slice(0, verseKeys.length).map((verseId, index) => [verseId, verseKeys[index]]),
  );
}

function wordsByLine(
  words: QuranFoundationMushafWord[],
  lineCount: number,
): QuranFoundationMushafWord[][] {
  const lines = Array.from({ length: lineCount }, () => [] as QuranFoundationMushafWord[]);
  for (const word of words) {
    if (word.line_number < 1 || word.line_number > lineCount) continue;
    lines[word.line_number - 1].push(word);
  }
  for (const line of lines) {
    line.sort(
      (left, right) =>
        left.position_in_line - right.position_in_line ||
        left.position_in_page - right.position_in_page,
    );
  }
  return lines;
}

export function QuranFoundationMushafPageView({
  mushaf,
  page,
  selectedAyahKey,
  playingAyahKey,
  onSelectAyah,
}: QuranFoundationMushafPageProps) {
  const { t } = useI18n();
  const lineCount = Math.min(30, Math.max(1, mushaf.lines_per_page));
  const pageFontUrl = page.rendering.available ? page.rendering.font_url : undefined;
  const fontFamily = page.rendering.available && page.rendering.mode === "page-font"
    ? `qf-mushaf-${mushaf.source_id}-page-${page.page_number}`
    : `qf-mushaf-${mushaf.source_id}`;
  const [fontState, setFontState] = useState<FontState>("loading");
  const lines = useMemo(() => wordsByLine(page.words, lineCount), [lineCount, page.words]);
  const verseKeys = useMemo(() => verseKeyById(page), [page]);

  useEffect(() => {
    setFontState("loading");
    if (!isAllowedQuranFontUrl(pageFontUrl)) {
      setFontState("error");
      return;
    }

    let cancelled = false;
    let loadedFont: FontFace | null = null;
    const fontFace = new FontFace(fontFamily, `url("${pageFontUrl}") format("woff2")`);
    fontFace.display = "block";
    void fontFace
      .load()
      .then((font) => {
        if (cancelled) return;
        loadedFont = font;
        document.fonts.add(font);
        setFontState("ready");
      })
      .catch(() => {
        if (!cancelled) setFontState("error");
      });

    return () => {
      cancelled = true;
      if (loadedFont) document.fonts.delete(loadedFont);
    };
  }, [fontFamily, pageFontUrl]);

  return (
    <div
      className="qf-mushaf-view"
      data-mushaf-id={mushaf.source_id}
      data-page-number={page.page_number}
      data-font-status={fontState}
    >
      <div className="qf-mushaf-meta">
        <div>
          <strong>{mushaf.name}</strong>
          <span>{mushaf.qirat_name} · {mushaf.lines_per_page} {t("quran.mushafLines")}</span>
        </div>
        <span>Quran.Foundation</span>
      </div>

      {fontState === "error" ? (
        <div className="alert alert-error">{t("quran.mushafFontError")}</div>
      ) : (
        <div
          className={`qf-mushaf-sheet${fontState === "loading" ? " is-font-loading" : ""}`}
          style={{ gridTemplateRows: `repeat(${lineCount}, minmax(0, 1fr))` }}
          dir="rtl"
          lang="ar"
          translate="no"
          aria-label={t("quran.qfPageAria", { name: mushaf.name, page: page.page_number })}
        >
          {fontState === "loading" && (
            <div className="qf-mushaf-font-loading">{t("quran.mushafFontLoading")}</div>
          )}
          {lines.map((line, lineIndex) => (
            <div
              className="qf-mushaf-line"
              data-line-number={lineIndex + 1}
              key={lineIndex + 1}
              aria-hidden={line.length === 0 ? "true" : undefined}
            >
              {line.map((word) => {
                const ayahKey = word.verse_id === null ? undefined : verseKeys.get(word.verse_id);
                const className = [
                  "qf-mushaf-word",
                  word.char_type_name === "end" ? "is-ayah-end" : "",
                  ayahKey && selectedAyahKey === ayahKey ? "is-selected" : "",
                  ayahKey && playingAyahKey === ayahKey ? "is-playing" : "",
                ].filter(Boolean).join(" ");
                const style = { fontFamily: `"${fontFamily}", serif` };
                if (!ayahKey) {
                  return (
                    <span className={className} style={style} key={word.id}>
                      {word.text}
                    </span>
                  );
                }
                return (
                  <button
                    className={className}
                    style={style}
                    type="button"
                    key={word.id}
                    onClick={() => onSelectAyah(ayahKey)}
                    aria-label={t("common.ayah", { ayah: ayahKey })}
                    title={t("common.ayah", { ayah: ayahKey })}
                  >
                    {word.text}
                  </button>
                );
              })}
            </div>
          ))}
          <span className="qf-mushaf-page-number" aria-hidden="true">
            {page.page_number}
          </span>
        </div>
      )}

      <p className="qf-mushaf-attribution">
        {mushaf.source.attribution}{" "}
        <a href={mushaf.source.url} target="_blank" rel="noreferrer">
          {mushaf.source.name}
        </a>
      </p>
    </div>
  );
}
