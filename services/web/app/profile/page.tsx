"use client";

import { useEffect, useState } from "react";
import {
  api,
  Bookmark,
  FeedbackTicket,
  ReadingPosition,
  SyncPullResponse,
} from "../../lib/api";
import { useAuth } from "../../lib/auth-context";

export default function ProfilePage() {
  const { session, identity, isLoggedIn, loginGuest, logout, isLoading: authLoading } = useAuth();

  const [reading, setReading] = useState<ReadingPosition | null>(null);
  const [bookmarks, setBookmarks] = useState<Bookmark[]>([]);
  const [feedbackTickets, setFeedbackTickets] = useState<FeedbackTicket[]>([]);
  const [syncResult, setSyncResult] = useState<SyncPullResponse | null>(null);

  const [loadingReading, setLoadingReading] = useState<boolean>(false);
  const [loadingBookmarks, setLoadingBookmarks] = useState<boolean>(false);
  const [loadingSync, setLoadingSync] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);
  const [successMsg, setSuccessMsg] = useState<string | null>(null);

  // New Bookmark form state
  const [newBookmarkPage, setNewBookmarkPage] = useState<number>(1);
  const [newBookmarkLabel, setNewBookmarkLabel] = useState<string>("Любимый аят");
  const [newBookmarkColor, setNewBookmarkColor] = useState<string>("emerald");
  const [newBookmarkNote, setNewBookmarkNote] = useState<string>("");

  // New Feedback form state
  const [showFeedbackModal, setShowFeedbackModal] = useState<boolean>(false);
  const [feedbackCategory, setFeedbackCategory] = useState<string>("quran_content");
  const [feedbackSubject, setFeedbackSubject] = useState<string>("");
  const [feedbackMessage, setFeedbackMessage] = useState<string>("");
  const [sendingFeedback, setSendingFeedback] = useState<boolean>(false);

  // Load user data on mount / login
  useEffect(() => {
    if (isLoggedIn) {
      void loadReadingData();
      void loadBookmarksData();
      void loadTicketsData();
    }
  }, [isLoggedIn]);

  const loadReadingData = async () => {
    setLoadingReading(true);
    try {
      const pos = await api.getReadingPosition("madani-hafs");
      setReading(pos);
    } catch {
      // Position might not be set yet
      setReading(null);
    } finally {
      setLoadingReading(false);
    }
  };

  const loadBookmarksData = async () => {
    setLoadingBookmarks(true);
    try {
      const res = await api.getBookmarks();
      setBookmarks(res.results || []);
    } catch (err) {
      setError(api.normalizeError(err));
    } finally {
      setLoadingBookmarks(false);
    }
  };

  const loadTicketsData = async () => {
    try {
      const tickets = await api.getFeedbackTickets();
      setFeedbackTickets(tickets || []);
    } catch {
      // Feedback might be empty
    }
  };

  const handleCreateBookmark = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    try {
      await api.createBookmark({
        edition_code: "madani-hafs",
        page_number: Number(newBookmarkPage),
        label: newBookmarkLabel,
        color_key: newBookmarkColor,
        note: newBookmarkNote,
      });
      setSuccessMsg("Закладка успешно создана!");
      setNewBookmarkNote("");
      await loadBookmarksData();
      setTimeout(() => setSuccessMsg(null), 3000);
    } catch (err) {
      setError(api.normalizeError(err));
    }
  };

  const handleDeleteBookmark = async (id: string, revision: number) => {
    try {
      await api.deleteBookmark(id, revision);
      setBookmarks((prev) => prev.filter((b) => b.id !== id));
      setSuccessMsg("Закладка удалена.");
      setTimeout(() => setSuccessMsg(null), 3000);
    } catch (err) {
      setError(api.normalizeError(err));
    }
  };

  const handleSyncPull = async () => {
    setLoadingSync(true);
    setError(null);
    try {
      const syncData = await api.syncPull(20);
      setSyncResult(syncData);
      setSuccessMsg("Синхронизация успешно выполнена!");
      await loadBookmarksData();
      await loadReadingData();
      setTimeout(() => setSuccessMsg(null), 3000);
    } catch (err) {
      setError(api.normalizeError(err));
    } finally {
      setLoadingSync(false);
    }
  };

  const handleCreateFeedback = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!feedbackSubject || !feedbackMessage) return;
    setSendingFeedback(true);
    try {
      await api.createFeedbackTicket({
        category: feedbackCategory,
        subject: feedbackSubject,
        message: feedbackMessage,
      });
      setSuccessMsg("Обращение отправлено! Редакционная команда рассмотрит его.");
      setShowFeedbackModal(false);
      setFeedbackSubject("");
      setFeedbackMessage("");
      await loadTicketsData();
      setTimeout(() => setSuccessMsg(null), 4000);
    } catch (err) {
      setError(api.normalizeError(err));
    } finally {
      setSendingFeedback(false);
    }
  };

  if (!isLoggedIn) {
    return (
      <div className="surface" style={{ maxWidth: 640, margin: "24px auto", textAlign: "center" }}>
        <span className="brand-mark sm" style={{ margin: "0 auto 16px" }}>👤</span>
        <h2 className="surface-title" style={{ marginBottom: 8 }}>Личный кабинет читателя</h2>
        <p className="kpi-desc" style={{ marginBottom: 24 }}>
          Войдите с помощью защищенной гостевой сессии, чтобы просматривать закладки,
          историю чтения и синхронизировать данные между устройствами.
        </p>

        {error && <div className="alert alert-error" style={{ marginBottom: 16 }}>{error}</div>}

        <button
          onClick={() => void loginGuest()}
          className="btn btn-primary btn-lg"
          disabled={authLoading}
          style={{ width: "100%" }}
        >
          {authLoading ? "Создание гостевой сессии..." : "Войти как гость"}
        </button>
      </div>
    );
  }

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 20 }}>
      {/* Account Info Header */}
      <section className="surface">
        <div className="surface-head">
          <div>
            <p className="eyebrow">Персональный профиль</p>
            <h2 className="surface-title">Личный кабинет</h2>
            <p className="surface-subtitle">
              ID пользователя: <code>{session?.user.id}</code> · Устройство: <code>{session?.device.id}</code>
            </p>
          </div>

          <div style={{ display: "flex", gap: 10 }}>
            <button
              className="btn btn-outline-primary btn-sm"
              onClick={() => void handleSyncPull()}
              disabled={loadingSync}
            >
              {loadingSync ? "Синхронизация..." : "🔄 Офлайн-синхронизация"}
            </button>
            <button
              className="btn btn-danger btn-sm"
              onClick={() => void logout()}
            >
              Выйти
            </button>
          </div>
        </div>

        {error && <div className="alert alert-error" style={{ marginBottom: 14 }}>{error}</div>}
        {successMsg && <div className="alert alert-success" style={{ marginBottom: 14 }}>{successMsg}</div>}

        <div className="kpi-grid" style={{ marginTop: 8 }}>
          <div className="kpi-card">
            <span className="kpi-label">Статус профиля</span>
            <span className="kpi-value">{session?.user.status === "guest" ? "Гость" : "Активен"}</span>
            <span className="kpi-desc">Платформа: {session?.device.platform}</span>
          </div>

          <div className="kpi-card">
            <span className="kpi-label">Сохраненных закладок</span>
            <span className="kpi-value">{bookmarks.length}</span>
            <span className="kpi-desc">Издание: Мадинский Мусхаф</span>
          </div>

          <div className="kpi-card">
            <span className="kpi-label">Позиция чтения</span>
            <span className="kpi-value">
              {reading ? `Стр. ${reading.page_number}` : "Не сохранено"}
            </span>
            <span className="kpi-desc">
              {reading?.surah_number ? `Сура ${reading.surah_number}:${reading.ayah_number || 1}` : "Начните чтение"}
            </span>
          </div>

          <div className="kpi-card">
            <span className="kpi-label">Обращений в поддержку</span>
            <span className="kpi-value">{feedbackTickets.length}</span>
            <span className="kpi-desc">Редакционный аудит</span>
          </div>
        </div>
      </section>

      {/* Bookmarks Section */}
      <section className="surface">
        <div className="surface-head">
          <div>
            <h3 className="surface-title">Ваши закладки</h3>
            <p className="surface-subtitle">Быстрый переход к сохраненным аятам и страницам.</p>
          </div>
        </div>

        {/* Add Bookmark Form */}
        <form
          onSubmit={handleCreateBookmark}
          style={{
            padding: 16,
            background: "var(--bg-subtle)",
            borderRadius: "var(--radius-md)",
            marginBottom: 20,
            display: "flex",
            flexDirection: "column",
            gap: 12,
          }}
        >
          <div className="form-row">
            <div className="form-group">
              <label className="form-label">Страница (1-604)</label>
              <input
                type="number"
                min={1}
                max={604}
                value={newBookmarkPage}
                onChange={(e) => setNewBookmarkPage(Number(e.target.value))}
              />
            </div>

            <div className="form-group">
              <label className="form-label">Название закладки</label>
              <input
                type="text"
                value={newBookmarkLabel}
                onChange={(e) => setNewBookmarkLabel(e.target.value)}
                placeholder="Например: Утреннее чтение"
              />
            </div>

            <div className="form-group">
              <label className="form-label">Цветовая метка</label>
              <select
                value={newBookmarkColor}
                onChange={(e) => setNewBookmarkColor(e.target.value)}
              >
                <option value="emerald">Изумрудный (Emerald)</option>
                <option value="gold">Золотой (Gold)</option>
                <option value="sapphire">Сапфировый (Sapphire)</option>
                <option value="ruby">Рубиновый (Ruby)</option>
              </select>
            </div>
          </div>

          <div className="form-group">
            <label className="form-label">Заметка (необязательно)</label>
            <input
              type="text"
              value={newBookmarkNote}
              onChange={(e) => setNewBookmarkNote(e.target.value)}
              placeholder="Дополнительный комментарий или цель повторения"
            />
          </div>

          <div>
            <button type="submit" className="btn btn-primary btn-sm">
              ➕ Добавить закладку
            </button>
          </div>
        </form>

        {/* Bookmarks List */}
        {loadingBookmarks ? (
          <div style={{ padding: 24, textAlign: "center", color: "var(--text-muted)" }}>
            Загрузка закладок...
          </div>
        ) : bookmarks.length > 0 ? (
          <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
            {bookmarks.map((bm) => (
              <div key={bm.id} className="track-row">
                <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
                  <span className="ayah-badge" style={{ background: "var(--accent-gold-subtle)", color: "var(--accent-gold)" }}>
                    🔖
                  </span>
                  <div>
                    <strong>{bm.label}</strong>
                    <p className="kpi-desc">
                      {bm.page_number ? `Страница ${bm.page_number}` : ""}
                      {bm.surah_number ? ` · Сура ${bm.surah_number}:${bm.ayah_number || 1}` : ""}
                      {bm.note ? ` · «${bm.note}»` : ""}
                    </p>
                  </div>
                </div>

                <button
                  className="btn btn-danger btn-sm"
                  onClick={() => void handleDeleteBookmark(bm.id, bm.revision)}
                  title="Удалить закладку"
                >
                  Удалить
                </button>
              </div>
            ))}
          </div>
        ) : (
          <div style={{ padding: 24, textAlign: "center", color: "var(--text-muted)" }}>
            У вас пока нет закладок. Добавьте закладку во время чтения Корана.
          </div>
        )}
      </section>

      {/* Feedback & Support Section */}
      <section className="surface">
        <div className="surface-head">
          <div>
            <h3 className="surface-title">Обратная связь и религиозный аудит</h3>
            <p className="surface-subtitle">
              Сообщите о неточности в тексте, таймкодах или расчетах молитв напрямую религиозной редакции.
            </p>
          </div>

          <button
            className="btn btn-outline-primary btn-sm"
            onClick={() => setShowFeedbackModal(true)}
          >
            ✉️ Создать обращение
          </button>
        </div>

        {showFeedbackModal && (
          <form
            onSubmit={handleCreateFeedback}
            style={{
              padding: 16,
              background: "var(--bg-subtle)",
              borderRadius: "var(--radius-md)",
              marginBottom: 16,
              display: "flex",
              flexDirection: "column",
              gap: 12,
            }}
          >
            <div className="form-row">
              <div className="form-group">
                <label className="form-label">Категория обращения</label>
                <select
                  value={feedbackCategory}
                  onChange={(e) => setFeedbackCategory(e.target.value)}
                >
                  <option value="quran_content">Текст Корана и Мусхаф</option>
                  <option value="audio_timing">Таймкоды аудиозаписи</option>
                  <option value="prayer_calculation">Расчет времени намаза</option>
                  <option value="general">Общий вопрос или предложение</option>
                </select>
              </div>

              <div className="form-group">
                <label className="form-label">Тема</label>
                <input
                  type="text"
                  value={feedbackSubject}
                  onChange={(e) => setFeedbackSubject(e.target.value)}
                  placeholder="Краткое описание"
                  required
                />
              </div>
            </div>

            <div className="form-group">
              <label className="form-label">Сообщение</label>
              <textarea
                value={feedbackMessage}
                onChange={(e) => setFeedbackMessage(e.target.value)}
                rows={3}
                placeholder="Подробное описание вопроса или замечания..."
                required
              />
            </div>

            <div style={{ display: "flex", gap: 10 }}>
              <button
                type="submit"
                className="btn btn-primary btn-sm"
                disabled={sendingFeedback}
              >
                {sendingFeedback ? "Отправка..." : "Отправить обращение"}
              </button>
              <button
                type="button"
                className="btn btn-secondary btn-sm"
                onClick={() => setShowFeedbackModal(false)}
              >
                Отмена
              </button>
            </div>
          </form>
        )}

        {feedbackTickets.length > 0 ? (
          <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
            {feedbackTickets.map((t) => (
              <div key={t.public_id} className="track-row">
                <div>
                  <strong>{t.subject}</strong>
                  <p className="kpi-desc">
                    Номер: <code>{t.public_id}</code> · Категория: {t.category} · Сообщений: {t.messages_count}
                  </p>
                </div>
                <span className={`status-chip ${t.status === "resolved" ? "ok" : ""}`}>
                  {t.status === "open" ? "Открыто" : t.status === "in_review" ? "На рассмотрении" : t.status}
                </span>
              </div>
            ))}
          </div>
        ) : (
          <div className="kpi-desc" style={{ padding: 12 }}>
            Активных обращений нет.
          </div>
        )}
      </section>
    </div>
  );
}
