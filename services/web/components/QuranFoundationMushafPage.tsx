"use client";

import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import type {
  QuranFoundationMushaf,
  QuranFoundationMushafPage,
  QuranFoundationMushafWord,
  Surah,
} from "../lib/api";
import { useI18n } from "../lib/i18n-context";
import { isAllowedQuranWordImageUrl, isQuranFontReady, loadQuranFont, quranFontFamily, retainQuranFont } from "../lib/quran-font";
import { fitMushafLines, qulGridRow } from "../lib/mushaf-line-layout";

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

type QuranFoundationMushafPageProps = {
  mushaf: QuranFoundationMushaf;
  page: QuranFoundationMushafPage;
  surahs: SurahIdentity[];
  selectedAyahKey: string | null;
  playingAyahKey: string | null;
  onSelectAyah: (ayahKey: string) => void;
};

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
  if (page.words.every((word) => word.verse_key)) {
    return new Map(page.words.map((word) => [word.verse_id!, word.verse_key!]));
  }
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

function displayLineNumber(pageNumber: number, sourceLineNumber: number, firstLine: number): number {
  // Quran.Foundation preserves the printed source line numbers on the opening
  // spread: Al-Fatihah starts at 9 and Al-Baqarah at 10. On a responsive single
  // page these compact blocks should remain vertically centred, not inherit the
  // eight or nine empty source rows that separate the facing printed pages.
  if (pageNumber === 1 || pageNumber === 2) {
    return sourceLineNumber - Math.floor((firstLine - 1) / 2);
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
  const layout = page.layout?.version === 1 ? page.layout : null;
  const lineCount = Math.min(30, Math.max(1, layout?.lines_per_page ?? mushaf.lines_per_page));
  const imageMode = page.rendering.available && page.rendering.mode === "word-images";
  const pageFontUrl = page.rendering.available ? page.rendering.font_url : undefined;
  const fontFamily = quranFontFamily(mushaf.source_id, page);
  const [fontState, setFontState] = useState<FontState>(() => isQuranFontReady(fontFamily, pageFontUrl) ? "ready" : "loading");
  const lines = useMemo(() => wordsByLine(page.words, lineCount), [lineCount, page.words]);
  const firstLine = Math.min(...page.words.map((word) => word.line_number));
  const occupiedRows = Math.max(...(layout?.lines.map((row) => row.line_number) ?? [lineCount]));
  const displayLine = (line: number) => layout
    ? qulGridRow(line, page.page_number, lineCount, occupiedRows)
    : displayLineNumber(page.page_number, line, firstLine);
  const sheet = useRef<HTMLDivElement>(null);
  const [retry, setRetry] = useState(0);
  const verseKeys = useMemo(() => verseKeyById(page), [page]);
  const intros = useMemo(
    () => layout ? [] : chapterIntros(page, lines, verseKeys, surahs),
    [layout, lines, page, surahs, verseKeys],
  );

  useEffect(() => {
    let cancelled = false;
    const headingFamily = "qf-mushaf-headings";
    const headings = layout ? loadQuranFont(headingFamily, layout.decoration_font_url) : Promise.resolve();
    const releaseHeadings = layout ? retainQuranFont(headingFamily, layout.decoration_font_url) : () => {};
    if (imageMode) {
      setFontState("loading");
      const images = page.words.map((word) => new Promise<void>((resolve, reject) => {
        if (!isAllowedQuranWordImageUrl(word.image_url)) { reject(new Error("Invalid word image")); return; }
        const img = new Image();
        img.onload = () => resolve();
        img.onerror = () => reject(new Error("Word image unavailable"));
        img.src = word.image_url;
      }));
      void Promise.all([...images, headings]).then(() => { if (!cancelled) setFontState("ready"); })
        .catch(() => { if (!cancelled) setFontState("error"); });
      return () => { cancelled = true; releaseHeadings(); };
    }
    setFontState(isQuranFontReady(fontFamily, pageFontUrl) ? "ready" : "loading");
    const loaded = loadQuranFont(fontFamily, pageFontUrl);
    const release = retainQuranFont(fontFamily, pageFontUrl);
    void Promise.all([loaded, headings]).then(() => {
        if (cancelled) return;
        setFontState("ready");
      })
      .catch(() => {
        if (!cancelled) setFontState("error");
      });

    return () => {
      cancelled = true;
      release();
      releaseHeadings();
    };
  }, [fontFamily, pageFontUrl, imageMode, page.words, retry, layout]);

  useLayoutEffect(() => {
    const element = sheet.current;
    if (!element || fontState !== "ready") return;
    const fit = () => {
      if (layout) {
        const rows = [...element.querySelectorAll<HTMLElement>(".qf-mushaf-line")];
        if (!rows.length) return;
        const metrics = rows.map((row) => {
          const words = [...row.querySelectorAll<HTMLElement>(".qf-mushaf-word")];
          return {
            width: words.reduce((sum, word) => sum + parseFloat(getComputedStyle(word).width), 0),
            height: parseFloat(getComputedStyle(row.firstElementChild as HTMLElement).height),
            words: words.length,
            centered: row.dataset.centered === "true",
          };
        });
        // Page-turn animation transforms ancestors; measure untransformed CSS
        // dimensions so a frame of that animation cannot shrink the final page.
        const rowStyle = getComputedStyle(rows[0]);
        const fitted = fitMushafLines(metrics, parseFloat(rowStyle.width), parseFloat(rowStyle.height));
        element.style.setProperty("--qf-line-scale", String(fitted.scale));
        element.style.setProperty("--qf-title-size", `${element.clientWidth * .038}px`);
        element.style.setProperty("--qf-basmala-size", `${element.clientWidth * .045}px`);
        rows.forEach((row, index) => row.style.setProperty("--qf-word-gap", `${fitted.gaps[index]}px`));
        element.dataset.layoutReady = "true";
        return;
      }
      let scale = 1;
      for (const line of element.querySelectorAll<HTMLElement>(".qf-mushaf-line")) {
        const content = line.firstElementChild as HTMLElement | null;
        if (!content || !content.scrollWidth) continue;
        scale = Math.min(scale, line.clientWidth / content.scrollWidth, line.clientHeight / content.offsetHeight);
      }
      element.style.setProperty("--qf-line-scale", String(scale));
      element.dataset.layoutReady = "true";
    };
    fit();
    const observer = new ResizeObserver(fit);
    observer.observe(element);
    for (const content of element.querySelectorAll(".qf-mushaf-line-content")) observer.observe(content);
    element.addEventListener("load", fit, true);
    return () => { observer.disconnect(); element.removeEventListener("load", fit, true); };
  }, [fontState, page, imageMode, layout]);

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
        <div className="alert alert-error" role="alert">
          {t("quran.mushafFontError")}
          <button type="button" className="btn btn-secondary" onClick={() => setRetry((value) => value + 1)}>{t("errorPage.retry")}</button>
        </div>
      ) : (
        <div
          ref={sheet}
          className={`qf-mushaf-sheet${layout ? " has-qul-layout" : ""}${fontState === "loading" ? " is-font-loading" : ""}`}
          style={{ gridTemplateRows: `repeat(${lineCount * (layout ? 2 : 1)}, minmax(0, 1fr))` }}
          data-layout-source={layout?.source_url}
          dir="rtl"
          lang="ar"
          translate="no"
          aria-label={t("quran.qfPageAria", { name: mushaf.name, page: page.page_number })}
        >
          {fontState === "loading" && (
            <div className="qf-mushaf-font-loading">{t("quran.mushafFontLoading")}</div>
          )}
          {layout?.lines.filter((row) => row.line_type !== "ayah").map((row) => (
            <div
              className={`qf-mushaf-chapter-intro ${row.line_type === "surah_name" ? "has-title" : "has-bismillah"}`}
              key={`intro-${row.line_number}`}
              style={{ gridRow: `${displayLine(row.line_number)} / span 2` }}
              data-surah-number={row.surah_number ?? undefined}
              data-line-type={row.line_type}
            >
              {row.line_type === "basmallah" ? (
                <div className="qf-mushaf-bismillah">{BISMILLAH}</div>
              ) : (
                <div className="qf-mushaf-chapter-title">سُورَةُ {surahs.find((surah) => surah.number === row.surah_number)?.name_ar}</div>
              )}
            </div>
          ))}
          {intros.map((intro) => (
            <div
              className={[
                "qf-mushaf-chapter-intro",
                intro.compact ? "is-compact" : "",
                intro.showTitle ? "has-title" : "",
                intro.showBismillah ? "has-bismillah" : "",
              ].filter(Boolean).join(" ")}
              style={{
                gridRow: `${displayLine(intro.firstLine)} / ${displayLine(intro.endLine)}`,
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
                data-display-line-number={displayLine(sourceLineNumber)}
                data-centered={layout?.lines.find((row) => row.line_number === sourceLineNumber)?.is_centered}
                style={{ gridRow: layout ? `${displayLine(sourceLineNumber)} / span 2` : displayLine(sourceLineNumber) }}
                key={sourceLineNumber}
              >
              <div className="qf-mushaf-line-content">
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
                    style={word.css_class?.split(/\s+/).includes("bidi-override") ? { unicodeBidi: "bidi-override" } : undefined}
                    key={word.id}
                    data-position-in-page={word.position_in_page}
                  >
                    {imageMode && isAllowedQuranWordImageUrl(word.image_url) ? (
                      // Provider word images have intrinsic metrics, including the smaller verse markers.
                      // eslint-disable-next-line @next/next/no-img-element
                      <img src={word.image_url} alt="" draggable={false} />
                    ) : word.text_runs ? word.text_runs.map((run, index) => (
                      <span key={index} style={run.color ? { color: run.color } : undefined}>{run.text}</span>
                    )) : word.text}
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
                    aria-pressed={selectedAyahKey === ayahKey}
                    title={t("common.ayah", { ayah: ayahKey })}
                    data-ayah-key={ayahKey}
                  >
                    {content}
                  </button>
                );
              })}
              </div>
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
