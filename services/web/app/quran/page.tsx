"use client";

import { Suspense, useCallback, useEffect, useMemo, useState } from "react";
import { useSearchParams } from "next/navigation";
import { MushafAudioPlayer } from "../../components/MushafAudioPlayer";
import {
  api,
  Ayah,
  MushafPage,
  QuranEdition,
  Surah,
} from "../../lib/api";
import { useAuth } from "../../lib/auth-context";

function QuranContent() {
  const searchParams = useSearchParams();
  const initialSurahParam = searchParams.get("surah");

  const { isLoggedIn, loginGuest } = useAuth();
  const [editions, setEditions] = useState<QuranEdition[]>([]);
  const [selectedEdition, setSelectedEdition] = useState<string>("madani-hafs");
  const [surahs, setSurahs] = useState<Surah[]>([]);
  const [selectedSurah, setSelectedSurah] = useState<number>(initialSurahParam ? Number(initialSurahParam) : 1);
  const [ayahs, setAyahs] = useState<Ayah[]>([]);
  const [currentPage, setCurrentPage] = useState<number>(1);
  const [mushafPage, setMushafPage] = useState<MushafPage | null>(null);
  const [selectedMushafAyah, setSelectedMushafAyah] = useState<string | null>(null);
  const [playingMushafAyah, setPlayingMushafAyah] = useState<string | null>(null);

  const [viewMode, setViewMode] = useState<"text" | "mushaf">("text");
  const [loading, setLoading] = useState<boolean>(true);
  const [feedbackMessage, setFeedbackMessage] = useState<{ text: string; type: "ok" | "err" } | null>(null);

  // Load Editions
  useEffect(() => {
    api
      .getEditions()
      .then((res) => {
        setEditions(res);
        if (res.length > 0) {
          const defaultEd = res.find((e) => e.code === "madani-hafs") || res[0];
          setSelectedEdition(defaultEd.code);
        }
      })
      .catch((err) => {
        setFeedbackMessage({ text: api.normalizeError(err), type: "err" });
      });
  }, []);

  // Load Surahs when edition changes
  useEffect(() => {
    if (!selectedEdition) return;
    setLoading(true);
    api
      .getSurahs(selectedEdition)
      .then((res) => {
        setSurahs(res);
        setLoading(false);
      })
      .catch((err) => {
        setLoading(false);
        setFeedbackMessage({ text: api.normalizeError(err), type: "err" });
      });
  }, [selectedEdition]);

  // Load Ayahs when surah changes
  useEffect(() => {
    if (!selectedEdition || !selectedSurah) return;
    setLoading(true);
    api
      .getAyahs(selectedEdition, selectedSurah)
      .then((res) => {
        setAyahs(res);
        setLoading(false);
        if (res.length > 0 && res[0].pages?.length > 0) {
          setCurrentPage(res[0].pages[0]);
        }
      })
      .catch((err) => {
        setLoading(false);
        setFeedbackMessage({ text: api.normalizeError(err), type: "err" });
      });
  }, [selectedEdition, selectedSurah]);

  // Load Mushaf page when page changes and in mushaf mode
  useEffect(() => {
    if (viewMode !== "mushaf" || !selectedEdition || !currentPage) return;
    api
      .getPage(selectedEdition, currentPage)
      .then((pageData) => {
        setMushafPage(pageData);
        setSelectedMushafAyah(null);
      })
      .catch(() => {
        setMushafPage(null);
      });
  }, [selectedEdition, currentPage, viewMode]);

  const currentSurahObj = surahs.find((s) => s.number === selectedSurah);
  const mushafRegions = useMemo(() => {
    const unique = new Map<string, MushafPage["regions"][number]>();
    for (const region of mushafPage?.regions || []) {
      const key = `${region.ayah.surah}:${region.ayah.number}:${JSON.stringify(region.polygon)}`;
      if (!unique.has(key)) unique.set(key, region);
    }
    return [...unique.values()];
  }, [mushafPage]);

  const handleActiveAyahChange = useCallback((ayahKey: string | null) => {
    setPlayingMushafAyah(ayahKey);
    if (!ayahKey) return;
    const [surahNumber, ayahNumber] = ayahKey.split(":").map(Number);
    if (surahNumber !== selectedSurah) return;
    const activeAyah = ayahs.find((ayah) => ayah.number === ayahNumber);
    const nextPage = activeAyah?.pages[0];
    if (viewMode === "mushaf" && nextPage) {
      setCurrentPage((page) => nextPage === page ? page : nextPage);
    }
  }, [ayahs, selectedSurah, viewMode]);

  const handleSavePosition = async (ayahNumber?: number) => {
    if (!isLoggedIn) {
      const res = await loginGuest();
      if (!res) {
        setFeedbackMessage({ text: "Не удалось войти для сохранения позиции.", type: "err" });
        return;
      }
    }

    try {
      const progress = ((currentPage / 604) * 100).toFixed(2);
      await api.saveReadingPosition(selectedEdition, {
        page_number: currentPage,
        surah_number: selectedSurah,
        ayah_number: ayahNumber || 1,
        progress_percent: progress,
        base_revision: 0,
      });
      setFeedbackMessage({
        text: `Позиция чтения сохранена: Сура ${selectedSurah}, страница ${currentPage}`,
        type: "ok",
      });
      setTimeout(() => setFeedbackMessage(null), 4000);
    } catch (err) {
      setFeedbackMessage({ text: api.normalizeError(err), type: "err" });
    }
  };

  const handleAddBookmark = async (ayahNumber?: number) => {
    if (!isLoggedIn) {
      const res = await loginGuest();
      if (!res) {
        setFeedbackMessage({ text: "Не удалось войти для добавления закладки.", type: "err" });
        return;
      }
    }

    try {
      await api.createBookmark({
        edition_code: selectedEdition,
        page_number: currentPage,
        surah_number: selectedSurah,
        ayah_number: ayahNumber || undefined,
        label: `Сура ${selectedSurah}:${ayahNumber || 1} (стр. ${currentPage})`,
        color_key: "emerald",
      });
      setFeedbackMessage({ text: "Закладка успешно добавлена в личный кабинет!", type: "ok" });
      setTimeout(() => setFeedbackMessage(null), 4000);
    } catch (err) {
      setFeedbackMessage({ text: api.normalizeError(err), type: "err" });
    }
  };

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 20 }}>
      {/* Control Bar */}
      <section className="surface">
        <div className="surface-head" style={{ marginBottom: 16 }}>
          <div>
            <p className="eyebrow">Чтение Священного Писания</p>
            <h2 className="surface-title">
              {currentSurahObj ? `${currentSurahObj.number}. ${currentSurahObj.name_ru} (${currentSurahObj.name_ar})` : "Коран"}
            </h2>
            {currentSurahObj && (
              <p className="surface-subtitle">
                {currentSurahObj.ayah_count} аятов · {currentSurahObj.revelation_type === "meccan" ? "Мекканская" : "Мединская"} · Страница {currentPage}
              </p>
            )}
          </div>

          <div style={{ display: "flex", gap: 10, flexWrap: "wrap" }}>
            <button
              className={`btn ${viewMode === "text" ? "btn-primary" : "btn-secondary"}`}
              onClick={() => setViewMode("text")}
            >
              📜 Текст
            </button>
            <button
              className={`btn ${viewMode === "mushaf" ? "btn-primary" : "btn-secondary"}`}
              onClick={() => setViewMode("mushaf")}
            >
              📖 Мусхаф (стр. {currentPage})
            </button>
            <button
              className="btn btn-outline-primary"
              onClick={() => void handleSavePosition(1)}
              title="Сохранить текущую позицию"
            >
              📍 Сохранить позицию
            </button>
          </div>
        </div>

        {feedbackMessage && (
          <div className={`alert ${feedbackMessage.type === "ok" ? "alert-success" : "alert-error"}`} style={{ marginBottom: 16 }}>
            {feedbackMessage.text}
          </div>
        )}

        <div className="form-row">
          <div className="form-group">
            <label className="form-label">Издание Корана</label>
            <select
              value={selectedEdition}
              onChange={(e) => setSelectedEdition(e.target.value)}
              disabled={editions.length === 0}
            >
              {editions.map((ed) => (
                <option key={ed.id} value={ed.code}>
                  {ed.name_ru} ({ed.riwayah})
                </option>
              ))}
            </select>
          </div>

          <div className="form-group">
            <label className="form-label">Выбор суры (1-114)</label>
            <select
              value={selectedSurah}
              onChange={(e) => setSelectedSurah(Number(e.target.value))}
              disabled={surahs.length === 0}
            >
              {surahs.map((s) => (
                <option key={s.id} value={s.number}>
                  {s.number}. {s.name_ru} — {s.name_ar} ({s.ayah_count} аят.)
                </option>
              ))}
            </select>
          </div>

          <div className="form-group">
            <label className="form-label">Страница Мусхафа (1-604)</label>
            <div style={{ display: "flex", gap: 8 }}>
              <button
                className="btn btn-secondary btn-sm"
                onClick={() => setCurrentPage((p) => Math.max(1, p - 1))}
                disabled={currentPage <= 1}
              >
                ◀ Назад
              </button>
              <input
                type="number"
                min={1}
                max={604}
                value={currentPage}
                onChange={(e) => setCurrentPage(Number(e.target.value))}
                style={{ textAlign: "center", fontWeight: 700 }}
              />
              <button
                className="btn btn-secondary btn-sm"
                onClick={() => setCurrentPage((p) => Math.min(604, p + 1))}
                disabled={currentPage >= 604}
              >
                Вперед ▶
              </button>
            </div>
          </div>
        </div>
      </section>

      {/* Content Area */}
      {viewMode === "text" ? (
        <section className="surface">
          {/* Bismillah Header */}
          {selectedSurah !== 1 && selectedSurah !== 9 && (
            <div style={{ textAlign: "center", padding: "16px 0 24px", borderBottom: "1px solid var(--border)" }}>
              <span className="quran-arabic-text" style={{ fontSize: 32, color: "var(--primary)" }}>
                بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ
              </span>
            </div>
          )}

          {loading ? (
            <div style={{ padding: 32, textAlign: "center", color: "var(--text-muted)" }}>
              Загрузка аятов суры...
            </div>
          ) : ayahs.length > 0 ? (
            <div style={{ display: "flex", flexDirection: "column", gap: 16, marginTop: 16 }}>
              {ayahs.map((ayah) => (
                <article key={ayah.id} className="ayah-card">
                  <div className="ayah-header">
                    <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                      <span className="ayah-badge">{ayah.number}</span>
                      <span className="kpi-desc">
                        Аят {ayah.number} · Джуз {ayah.juz_number}
                      </span>
                    </div>

                    <div style={{ display: "flex", gap: 8 }}>
                      <button
                        className="btn btn-secondary btn-sm"
                        onClick={() => void handleSavePosition(ayah.number)}
                        title="Отметить как прочитанное"
                      >
                        📍 Отметка
                      </button>
                      <button
                        className="btn btn-secondary btn-sm"
                        onClick={() => void handleAddBookmark(ayah.number)}
                        title="Добавить в закладки"
                      >
                        🔖 Закладка
                      </button>
                    </div>
                  </div>

                  <p className="quran-arabic-text">{ayah.text_uthmani}</p>
                </article>
              ))}
            </div>
          ) : (
            <div style={{ padding: 32, textAlign: "center", color: "var(--text-muted)" }}>
              Аяты для выбранной суры не найдены в каталоге.
            </div>
          )}
        </section>
      ) : (
        /* Mushaf Page View */
        <section className="surface">
          <MushafAudioPlayer
            editionCode={selectedEdition}
            selectedSurah={selectedSurah}
            selectedAyahKey={selectedMushafAyah}
            onActiveAyahChange={handleActiveAyahChange}
          />
          <div className="mushaf-page-container">
            {mushafPage && mushafPage.assets && mushafPage.assets.length > 0 ? (
              <div className="mushaf-page-frame">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={mushafPage.assets[0].url}
                  alt={`Страница Мусхафа ${currentPage}`}
                  className="mushaf-image"
                />
                <svg
                  className="mushaf-regions"
                  viewBox="0 0 1 1"
                  preserveAspectRatio="none"
                  aria-label={`Интерактивные области аятов страницы ${currentPage}`}
                >
                  {mushafRegions.map((region) => {
                    const key = `${region.ayah.surah}:${region.ayah.number}`;
                    return (
                      <polygon
                        key={region.id}
                        points={region.polygon.map(([x, y]) => `${x},${y}`).join(" ")}
                        className={`mushaf-region${selectedMushafAyah === key ? " is-selected" : ""}${playingMushafAyah === key ? " is-playing" : ""}`}
                        role="button"
                        tabIndex={0}
                        aria-label={`Аят ${key}`}
                        onClick={() => setSelectedMushafAyah(key)}
                        onKeyDown={(event) => {
                          if (event.key === "Enter" || event.key === " ") {
                            event.preventDefault();
                            setSelectedMushafAyah(key);
                          }
                        }}
                      >
                        <title>Аят {key}</title>
                      </polygon>
                    );
                  })}
                </svg>
                {selectedMushafAyah && (
                  <div className="mushaf-selection-label">
                    {playingMushafAyah === selectedMushafAyah ? "Звучит" : "Выбран"} аят {selectedMushafAyah}
                  </div>
                )}
              </div>
            ) : (
              <div style={{ textAlign: "center", padding: 40 }}>
                <p className="eyebrow" style={{ marginBottom: 12 }}>
                  Мадинский Мусхаф · Страница {currentPage}
                </p>
                <div
                  style={{
                    maxWidth: 540,
                    margin: "0 auto",
                    padding: 32,
                    background: "#fff",
                    borderRadius: 12,
                    border: "1px solid var(--border)",
                  }}
                >
                  <p className="quran-arabic-text" style={{ fontSize: 24, textAlign: "center" }}>
                    {ayahs.slice(0, 5).map((a) => a.text_uthmani).join(" ۝ ")}
                  </p>
                </div>
              </div>
            )}
          </div>

          <div style={{ display: "flex", justifyContent: "space-between", marginTop: 16 }}>
            <button
              className="btn btn-secondary"
              onClick={() => setCurrentPage((p) => Math.max(1, p - 1))}
              disabled={currentPage <= 1}
            >
              ◀ Предыдущая страница ({currentPage - 1})
            </button>
            <span style={{ fontWeight: 600, alignSelf: "center" }}>
              Страница {currentPage} из 604
            </span>
            <button
              className="btn btn-secondary"
              onClick={() => setCurrentPage((p) => Math.min(604, p + 1))}
              disabled={currentPage >= 604}
            >
              Следующая страница ({currentPage + 1}) ▶
            </button>
          </div>
        </section>
      )}
    </div>
  );
}

export default function QuranPage() {
  return (
    <Suspense fallback={<div style={{ padding: 32, textAlign: "center" }}>Загрузка Корана...</div>}>
      <QuranContent />
    </Suspense>
  );
}
