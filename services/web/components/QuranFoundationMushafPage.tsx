"use client";

import { useEffect, useMemo, useState } from "react";
import type {
  QuranFoundationMushaf,
  QuranFoundationMushafPage,
  QuranFoundationMushafWord,
  Surah,
} from "../lib/api";
import { useI18n } from "../lib/i18n-context";

type FontState = "loading" | "ready" | "error";
type SurahIdentity = Pick<Surah, "number" | "name_ar">;

type AyahFragment = {
  key: string;
  ayahKey?: string;
  words: QuranFoundationMushafWord[];
};

type ChapterIntro = {
  surah: SurahIdentity;
  firstLine: number;
  endLine: number;
  compact: boolean;
  showTitle: boolean;
  showBismillah: boolean;
};

const BISMILLAH = "بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ";
const OPENING_PAGE_ROW_OFFSET = -4;

type QuranFoundationMushafPageProps = {
  mushaf: QuranFoundationMushaf;
  page: QuranFoundationMushafPage;
  surahs: SurahIdentity[];
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
  // position_in_line can wrap when an ayah continues on the next physical line.
  // The snapshot's position_in_page is the canonical reading and display order.
  for (const word of [...words].sort(
    (left, right) => left.position_in_page - right.position_in_page || left.id - right.id,
  )) {
    if (word.line_number < 1 || word.line_number > lineCount) continue;
    lines[word.line_number - 1].push(word);
  }
  return lines;
}

function fragmentsForLine(
  words: QuranFoundationMushafWord[],
  verseKeys: Map<number, string>,
): AyahFragment[] {
  const fragments: AyahFragment[] = [];
  for (const word of words) {
    const ayahKey = word.verse_id === null ? undefined : verseKeys.get(word.verse_id);
    const previous = fragments.at(-1);
    if (previous && previous.ayahKey === ayahKey) {
      previous.words.push(word);
      continue;
    }
    fragments.push({
      key: `${ayahKey || "unmapped"}-${word.id}`,
      ayahKey,
      words: [word],
    });
  }
  return fragments;
}

function displayLineNumber(pageNumber: number, sourceLineNumber: number): number {
  // Quran.Foundation preserves the printed source line numbers on the opening
  // spread: Al-Fatihah starts at 9 and Al-Baqarah at 10. On a responsive single
  // page these compact blocks should remain vertically centred, not inherit the
  // eight or nine empty source rows that separate the facing printed pages.
  if (pageNumber === 1 || pageNumber === 2) {
    return sourceLineNumber + OPENING_PAGE_ROW_OFFSET;
  }
  return sourceLineNumber;
}

function chapterIntros(
  page: QuranFoundationMushafPage,
  lines: QuranFoundationMushafWord[][],
  verseKeys: Map<number, string>,
  surahs: SurahIdentity[],
): ChapterIntro[] {
  const surahByNumber = new Map(surahs.map((surah) => [surah.number, surah]));
  const occupiedLines = new Set(
    lines.flatMap((line, index) => line.length > 0 ? [index + 1] : []),
  );
  const intros: ChapterIntro[] = [];

  for (const [surahValue, rangeValue] of Object.entries(page.verse_mapping).sort(
    ([left], [right]) => Number(left) - Number(right),
  )) {
    const match = /^(\d+)(?:-(\d+))?$/.exec(rangeValue.trim());
    const surahNumber = Number(surahValue);
    if (!match || Number(match[1]) !== 1) continue;
    const surah = surahByNumber.get(surahNumber);
    if (!surah) continue;

    const firstVerseId = [...verseKeys.entries()].find(
      ([, ayahKey]) => ayahKey === `${surahNumber}:1`,
    )?.[0];
    if (firstVerseId === undefined) continue;
    const firstVerseLine = Math.min(
      ...page.words
        .filter((word) => word.verse_id === firstVerseId)
        .map((word) => word.line_number),
    );
    if (!Number.isFinite(firstVerseLine) || firstVerseLine <= 1) continue;

    let previousOccupiedLine = firstVerseLine - 1;
    while (previousOccupiedLine > 0 && !occupiedLines.has(previousOccupiedLine)) {
      previousOccupiedLine -= 1;
    }
    const availableRows = firstVerseLine - previousOccupiedLine - 1;
    if (availableRows < 1) continue;
    const showTitle = surahNumber > 2;
    const showBismillah = surahNumber !== 1 && surahNumber !== 9;
    const requiredRows = Number(showTitle) + Number(showBismillah);
    if (requiredRows === 0) continue;
    const usedRows = Math.min(requiredRows, availableRows);
    const firstIntroLine = firstVerseLine - usedRows;
    intros.push({
      surah,
      firstLine: firstIntroLine,
      endLine: firstVerseLine,
      compact: requiredRows > usedRows,
      showTitle,
      showBismillah,
    });
  }

  return intros;
}

export function QuranFoundationMushafPageView({
  mushaf,
  page,
  surahs,
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
  const intros = useMemo(
    () => chapterIntros(page, lines, verseKeys, surahs),
    [lines, page, surahs, verseKeys],
  );

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
          {intros.map((intro) => (
            <div
              className={[
                "qf-mushaf-chapter-intro",
                intro.compact ? "is-compact" : "",
                intro.showTitle ? "has-title" : "",
                intro.showBismillah ? "has-bismillah" : "",
              ].filter(Boolean).join(" ")}
              style={{
                gridRow: `${displayLineNumber(page.page_number, intro.firstLine)} / ${displayLineNumber(page.page_number, intro.endLine)}`,
              }}
              key={intro.surah.number}
              data-surah-number={intro.surah.number}
            >
              {intro.showTitle && (
                <div className="qf-mushaf-chapter-title">
                  سُورَةُ {intro.surah.name_ar}
                </div>
              )}
              {intro.showBismillah && (
                <div className="qf-mushaf-bismillah">{BISMILLAH}</div>
              )}
            </div>
          ))}
          {lines.map((line, lineIndex) => {
            if (line.length === 0) return null;
            const sourceLineNumber = lineIndex + 1;
            return (
              <div
                className="qf-mushaf-line"
                data-line-number={sourceLineNumber}
                data-display-line-number={displayLineNumber(page.page_number, sourceLineNumber)}
                style={{ gridRow: displayLineNumber(page.page_number, sourceLineNumber) }}
                key={sourceLineNumber}
              >
              {fragmentsForLine(line, verseKeys).map((fragment) => {
                const { ayahKey } = fragment;
                const fragmentClassName = [
                  "qf-mushaf-ayah-fragment",
                  ayahKey && selectedAyahKey === ayahKey ? "is-selected" : "",
                  ayahKey && playingAyahKey === ayahKey ? "is-playing" : "",
                ].filter(Boolean).join(" ");
                const style = { fontFamily: `"${fontFamily}", serif` };
                const content = fragment.words.map((word) => (
                  <span
                    className={`qf-mushaf-word${word.char_type_name === "end" ? " is-ayah-end" : ""}`}
                    key={word.id}
                    data-position-in-page={word.position_in_page}
                  >
                    {word.text}
                  </span>
                ));
                if (!ayahKey) {
                  return (
                    <span className={fragmentClassName} style={style} key={fragment.key}>
                      {content}
                    </span>
                  );
                }
                return (
                  <button
                    className={fragmentClassName}
                    style={style}
                    type="button"
                    key={fragment.key}
                    onClick={() => onSelectAyah(ayahKey)}
                    aria-label={t("common.ayah", { ayah: ayahKey })}
                    title={t("common.ayah", { ayah: ayahKey })}
                    data-ayah-key={ayahKey}
                  >
                    {content}
                  </button>
                );
              })}
              </div>
            );
          })}
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
