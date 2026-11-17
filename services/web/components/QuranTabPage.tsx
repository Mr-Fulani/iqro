"use client";

import { useRouter } from "next/navigation";
import { FormEvent, useEffect, useState } from "react";
import { api, QuranDivision, Surah } from "../lib/api";
import { useAuth } from "../lib/auth-context";
import { useI18n } from "../lib/i18n-context";
import { surahName } from "../lib/quran-content";
import { readLocalReadingPosition } from "../lib/reading-position-storage";
import { localizedPath } from "../lib/routing";
import { useHydrated } from "../lib/use-hydrated";
import { IntentPrefetchLink } from "./IntentPrefetchLink";
import { SurahNameArt } from "./SurahNameArt";

type ReaderView = "text" | "mushaf";

// The phone's choice between the text and the Mushaf, kept on this device like the app's.
const VIEW_KEY = "iqro_quran_tab_view_v1";

function storedView(): ReaderView {
  try {
    return window.localStorage.getItem(VIEW_KEY) === "text" ? "text" : "mushaf";
  } catch {
    return "mushaf";
  }
}

/**
 * The phone's Quran tab, like the app's
 * (clients/iqro_mobile/lib/features/quran/quran_screen.dart): the reading
 * mode, the saved place, a surah and ayah picker, the quick jump and the list
 * of surahs. Everything opens the reader at /quran.
 */
export default function QuranTabPage({ edition, initialSurahs }: { edition: string; initialSurahs: Surah[] }) {
  const { locale, t, formatNumber } = useI18n();
  const { session } = useAuth();
  const router = useRouter();
  const hydrated = useHydrated();
  const [surahs, setSurahs] = useState(initialSurahs);
  const [view, setView] = useState<ReaderView>("mushaf");
  const [place, setPlace] = useState<{ surah: number; ayah: number } | null>(null);
  const [pickedSurah, setPickedSurah] = useState(1);
  const [pickedAyah, setPickedAyah] = useState(1);
  const [divisions, setDivisions] = useState<Record<"juz" | "hizb" | "rub", QuranDivision[]> | null>(null);
  const [page, setPage] = useState("");

  useEffect(() => {
    setView(storedView());
    if (initialSurahs.length) return;
    api.getSurahs(edition).then(setSurahs).catch(() => {});
  }, [edition, initialSurahs.length]);

  // The saved place: the account's, else this device's.
  const sessionUserId = session?.user.id;
  useEffect(() => {
    const local = readLocalReadingPosition(edition);
    setPlace(local?.surahNumber ? { surah: local.surahNumber, ayah: local.ayahNumber ?? 1 } : null);
    if (!sessionUserId) return;
    let active = true;
    api.getReadingPosition(edition).then((position) => {
      if (active && position.ayah) setPlace({ surah: position.ayah.surah_number, ayah: position.ayah.ayah_number });
    }).catch(() => {});
    return () => {
      active = false;
    };
  }, [edition, sessionUserId]);

  const chooseView = (next: ReaderView) => {
    setView(next);
    try {
      window.localStorage.setItem(VIEW_KEY, next);
    } catch {
      // The choice then lasts for this visit only.
    }
  };

  const readerHref = (query: string) =>
    localizedPath(locale, `/quran?${query}${view === "text" ? "&view=text" : ""}`);
  const ayahHref = (surah: number, ayah: number) => readerHref(`surah=${surah}&ayah=${ayah}`);

  const loadDivisions = () => {
    if (divisions) return;
    Promise.all([api.getJuzList(edition), api.getHizbList(edition), api.getRubElHizbList(edition)])
      .then(([juz, hizb, rub]) => setDivisions({ juz, hizb, rub }))
      .catch(() => {});
  };
  const openPage = (event: FormEvent) => {
    event.preventDefault();
    const number = Number(page);
    if (Number.isInteger(number) && number >= 1 && number <= 604) router.push(readerHref(`page=${number}`));
  };

  const placeSurah = surahs.find((surah) => surah.number === (place?.surah ?? 1));
  const picked = surahs.find((surah) => surah.number === pickedSurah);

  return (
    <div className="more-page surahs-page">
      <header className="more-head">
        <h1>{t("nav.quran")}</h1>
        <p>{t("surahs.subtitle")}</p>
      </header>

      <div className="surahs-view" role="group" aria-label={`${t("surahs.textMode")} / ${t("surahs.mushafMode")}`}>
        {(["text", "mushaf"] as const).map((item) => (
          <button
            key={item}
            type="button"
            aria-pressed={view === item}
            onClick={() => chooseView(item)}
            data-testid={`surahs-view-${item}`}
          >
            {t(item === "text" ? "surahs.textMode" : "surahs.mushafMode")}
          </button>
        ))}
      </div>

      <IntentPrefetchLink
        href={ayahHref(place?.surah ?? 1, place?.ayah ?? 1)}
        className="surahs-continue"
        data-testid="surahs-continue"
      >
        <span className="surahs-continue-copy">
          <small>{t("surahs.continue")}</small>
          <strong>
            {placeSurah ? surahName(placeSurah, locale) : t("common.surah", { surah: formatNumber(place?.surah ?? 1) })}
            {" · "}
            {t("common.ayah", { ayah: formatNumber(place?.ayah ?? 1) })}
          </strong>
        </span>
        <span className="more-row-chevron" aria-hidden="true">›</span>
      </IntentPrefetchLink>

      <form
        className="surahs-picker"
        onSubmit={(event) => {
          event.preventDefault();
          router.push(ayahHref(pickedSurah, pickedAyah));
        }}
      >
        <label>
          <span>{t("surahs.surah")}</span>
          <select
            value={pickedSurah}
            onChange={(event) => {
              setPickedSurah(Number(event.target.value));
              setPickedAyah(1);
            }}
          >
            {surahs.map((surah) => (
              <option key={surah.number} value={surah.number}>
                {formatNumber(surah.number)}. {surahName(surah, locale)}
              </option>
            ))}
          </select>
        </label>
        <label>
          <span>{t("surahs.ayah")}</span>
          <select value={pickedAyah} onChange={(event) => setPickedAyah(Number(event.target.value))}>
            {Array.from({ length: picked?.ayah_count ?? 1 }, (_, index) => (
              <option key={index + 1} value={index + 1}>{formatNumber(index + 1)}</option>
            ))}
          </select>
        </label>
        <button type="submit" className="btn btn-primary">{t("surahs.open")}</button>
      </form>

      <details className="more-card surahs-jump" onToggle={loadDivisions} data-testid="surahs-jump">
        <summary>{t("surahs.quickJump")}</summary>
        <div className="surahs-jump-body">
          <form onSubmit={openPage}>
            <label>
              <span>{t("surahs.page")}</span>
              <input
                type="number"
                inputMode="numeric"
                min={1}
                max={604}
                value={page}
                onChange={(event) => setPage(event.target.value)}
                placeholder="1–604"
              />
            </label>
            <button type="submit" className="btn btn-secondary">{t("surahs.open")}</button>
          </form>
          {(["juz", "hizb", "rub"] as const).map((kind) => (
            <label key={kind}>
              <span>{t(`surahs.${kind}`)}</span>
              <select
                value=""
                disabled={!divisions}
                onChange={(event) => {
                  const division = divisions?.[kind].find((item) => item.number === Number(event.target.value));
                  if (division) router.push(ayahHref(division.start_ayah.surah, division.start_ayah.number));
                }}
              >
                <option value="">—</option>
                {divisions?.[kind].map((division) => (
                  <option key={division.number} value={division.number}>
                    {formatNumber(division.number)} · {t("common.page", { page: formatNumber(division.start_page) })}
                  </option>
                ))}
              </select>
            </label>
          ))}
        </div>
      </details>

      <div className="more-card surahs-list" data-testid="surahs-list">
        {surahs.map((surah) => (
          <IntentPrefetchLink key={surah.number} href={ayahHref(surah.number, 1)} className="surahs-row">
            <span className="ayah-badge">{formatNumber(surah.number)}</span>
            <span className="surahs-row-copy">
              <strong>{surahName(surah, locale)}</strong>
              <small>
                {t("home.ayahCount", { count: surah.ayah_count })} · {surah.revelation_type === "meccan" ? t("home.meccan") : t("home.medinan")}
              </small>
            </span>
            {hydrated && (
              <SurahNameArt surah={surah.number} fallback={surah.name_ar} className="quran-arabic-text home-surah-name" />
            )}
          </IntentPrefetchLink>
        ))}
      </div>
    </div>
  );
}
