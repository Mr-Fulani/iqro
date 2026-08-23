"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import {
  api,
  Bookmark,
  FeedbackTicket,
  FeedbackTicketDetail,
  ReadingPosition,
} from "../../lib/api";
import { useAuth } from "../../lib/auth-context";
import { ReminderManager } from "../../components/ReminderManager";

const FEEDBACK_CATEGORIES = [
  ["religious_content", "Религиозное содержание"],
  ["page_layout", "Страница Мусхафа или область аята"],
  ["audio", "Аудио, таймкод или чтец"],
  ["advertisement", "Жалоба на рекламу"],
  ["technical", "Техническая проблема"],
  ["account_sync", "Аккаунт или синхронизация"],
  ["donation_link", "Ссылка на пожертвование"],
  ["accessibility_localization", "Доступность или локализация"],
  ["general", "Общий вопрос или предложение"],
  ["other", "Другое"],
] as const;

const FEEDBACK_STATUS_LABELS: Record<string, string> = {
  new: "Новое",
  triaged: "Распределено",
  in_progress: "В работе",
  waiting_for_user: "Ожидает ответа",
  resolved: "Решено",
  rejected: "Отклонено",
  duplicate: "Дубликат",
  closed: "Закрыто",
};

const FEEDBACK_CATEGORY_LABELS = Object.fromEntries(FEEDBACK_CATEGORIES);

export default function ProfilePage() {
  const { session, isLoggedIn, loginGuest, logout, isLoading: authLoading } = useAuth();

  const [reading, setReading] = useState<ReadingPosition | null>(null);
  const [bookmarks, setBookmarks] = useState<Bookmark[]>([]);
  const [feedbackTickets, setFeedbackTickets] = useState<FeedbackTicket[]>([]);
  const [loadingBookmarks, setLoadingBookmarks] = useState<boolean>(false);
  const [loadingSync, setLoadingSync] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);
  const [successMsg, setSuccessMsg] = useState<string | null>(null);

  // New Bookmark form state
  const [newBookmarkPage, setNewBookmarkPage] = useState<number>(1);
  const [newBookmarkLabel, setNewBookmarkLabel] = useState<string>("Любимый аят");
  const [newBookmarkColor, setNewBookmarkColor] = useState<string>("emerald");
  const [newBookmarkNote, setNewBookmarkNote] = useState<string>("");
  const [bookmarkDraft, setBookmarkDraft] = useState<{
    id: string;
    label: string;
    color_key: string;
    note: string;
    revision: number;
  } | null>(null);

  // New Feedback form state
  const [showFeedbackModal, setShowFeedbackModal] = useState<boolean>(false);
  const [feedbackCategory, setFeedbackCategory] = useState<string>("religious_content");
  const [feedbackSubject, setFeedbackSubject] = useState<string>("");
  const [feedbackMessage, setFeedbackMessage] = useState<string>("");
  const [sendingFeedback, setSendingFeedback] = useState<boolean>(false);
  const [selectedFeedback, setSelectedFeedback] = useState<FeedbackTicketDetail | null>(null);
  const [feedbackReply, setFeedbackReply] = useState<string>("");
  const [feedbackActionLoading, setFeedbackActionLoading] = useState<boolean>(false);

  // Load user data on mount / login
  useEffect(() => {
    if (isLoggedIn) {
      void loadReadingData();
      void loadBookmarksData();
      void loadTicketsData();
    }
  }, [isLoggedIn]);

  const loadReadingData = async () => {
    try {
      const pos = await api.getReadingPosition("madani-hafs");
      setReading(pos);
    } catch {
      // Position might not be set yet
      setReading(null);
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
      setFeedbackTickets(tickets.results || []);
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

  const handleUpdateBookmark = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!bookmarkDraft) return;
    setError(null);
    try {
      const updated = await api.updateBookmark(bookmarkDraft.id, {
        label: bookmarkDraft.label,
        color_key: bookmarkDraft.color_key,
        note: bookmarkDraft.note,
        base_revision: bookmarkDraft.revision,
      });
      setBookmarks((previous) =>
        previous.map((bookmark) => (bookmark.id === updated.id ? updated : bookmark)),
      );
      setBookmarkDraft(null);
      setSuccessMsg("Закладка обновлена.");
      setTimeout(() => setSuccessMsg(null), 3000);
    } catch (err) {
      setError(api.normalizeError(err));
    }
  };

  const handleSyncPull = async () => {
    setLoadingSync(true);
    setError(null);
    try {
      await api.syncPull(20);
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
      const created = await api.createFeedbackTicket({
        category: feedbackCategory,
        subject: feedbackSubject,
        message: feedbackMessage,
      });
      setSuccessMsg("Обращение отправлено! Редакционная команда рассмотрит его.");
      setShowFeedbackModal(false);
      setFeedbackSubject("");
      setFeedbackMessage("");
      setSelectedFeedback(created);
      await loadTicketsData();
      setTimeout(() => setSuccessMsg(null), 4000);
    } catch (err) {
      setError(api.normalizeError(err));
    } finally {
      setSendingFeedback(false);
    }
  };

  const openFeedbackTicket = async (publicId: string) => {
    setFeedbackActionLoading(true);
    setError(null);
    try {
      setSelectedFeedback(await api.getFeedbackTicket(publicId));
      setFeedbackReply("");
    } catch (err) {
      setError(api.normalizeError(err));
    } finally {
      setFeedbackActionLoading(false);
    }
  };

  const handleFeedbackReply = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedFeedback || !feedbackReply.trim()) return;
    setFeedbackActionLoading(true);
    setError(null);
    try {
      const updated = await api.sendFeedbackMessage(selectedFeedback.public_id, feedbackReply);
      setSelectedFeedback(updated);
      setFeedbackReply("");
      setFeedbackTickets((previous) =>
        previous.map((ticket) => (ticket.public_id === updated.public_id ? updated : ticket)),
      );
    } catch (err) {
      setError(api.normalizeError(err));
    } finally {
      setFeedbackActionLoading(false);
    }
  };

  const transitionFeedbackTicket = async (action: "close" | "reopen") => {
    if (!selectedFeedback) return;
    setFeedbackActionLoading(true);
    setError(null);
    try {
      const updated =
        action === "close"
          ? await api.closeFeedbackTicket(selectedFeedback.public_id)
          : await api.reopenFeedbackTicket(selectedFeedback.public_id);
      setSelectedFeedback(updated);
      setFeedbackTickets((previous) =>
        previous.map((ticket) => (ticket.public_id === updated.public_id ? updated : ticket)),
      );
      setSuccessMsg(action === "close" ? "Обращение закрыто." : "Обращение открыто повторно.");
      setTimeout(() => setSuccessMsg(null), 3000);
    } catch (err) {
      setError(api.normalizeError(err));
    } finally {
      setFeedbackActionLoading(false);
    }
  };

  if (!isLoggedIn) {
    return (
      <div className="surface" style={{ maxWidth: 640, margin: "24px auto", textAlign: "center" }}>
        <span className="brand-mark sm" style={{ margin: "0 auto 16px" }}>👤</span>
        <h2 className="surface-title" style={{ marginBottom: 8 }}>Личный кабинет читателя</h2>
        <p className="kpi-desc" style={{ marginBottom: 24 }}>
          Войдите по одноразовому коду из email либо продолжите как гость, чтобы просматривать
          закладки, историю чтения и синхронизировать данные между устройствами.
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

  const isGuest = session?.user.status === "guest";

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 20 }}>
      {/* Account Info Header */}
      <section className="surface">
        <div className="surface-head">
          <div>
            <p className="eyebrow">Персональный профиль</p>
            <h2 className="surface-title">Личный кабинет</h2>
            <p className="surface-subtitle">
              {session?.user.email ? `${session.user.email} · ` : ""}ID пользователя: {" "}
              <code>{session?.user.id}</code> · Устройство: <code>{session?.device.id}</code>
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
            {isGuest ? (
              <Link href="/login" className="btn btn-primary btn-sm">
                Войти по email
              </Link>
            ) : (
              <button
                className="btn btn-danger btn-sm"
                onClick={() => void logout()}
              >
                Выйти
              </button>
            )}
          </div>
        </div>

        {error && <div className="alert alert-error" style={{ marginBottom: 14 }}>{error}</div>}
        {successMsg && <div className="alert alert-success" style={{ marginBottom: 14 }}>{successMsg}</div>}
        {isGuest && (
          <div className="alert alert-info" style={{ marginBottom: 14 }}>
            Сейчас данные привязаны только к этому устройству. Войдите по email, чтобы сохранить
            их в аккаунте и синхронизировать между устройствами.
          </div>
        )}

        <div className="kpi-grid" style={{ marginTop: 8 }}>
          <div className="kpi-card">
            <span className="kpi-label">Статус профиля</span>
            <span className="kpi-value">{session?.user.status === "guest" ? "Гость" : "Активен"}</span>
            <span className="kpi-desc">
              {session?.user.email || `Платформа: ${session?.device.platform}`}
            </span>
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
              {reading?.ayah
                ? `Сура ${reading.ayah.surah_number}:${reading.ayah.ayah_number}`
                : "Начните чтение"}
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
              <div key={bm.id} className="track-row" style={{ alignItems: "stretch" }}>
                {bookmarkDraft?.id === bm.id ? (
                  <form
                    onSubmit={(event) => void handleUpdateBookmark(event)}
                    style={{ display: "flex", flexDirection: "column", gap: 10, width: "100%" }}
                  >
                    <div className="form-row">
                      <div className="form-group">
                        <label className="form-label" htmlFor={`bookmark-label-${bm.id}`}>
                          Название
                        </label>
                        <input
                          id={`bookmark-label-${bm.id}`}
                          value={bookmarkDraft.label}
                          maxLength={120}
                          onChange={(event) =>
                            setBookmarkDraft({ ...bookmarkDraft, label: event.target.value })
                          }
                        />
                      </div>
                      <div className="form-group">
                        <label className="form-label" htmlFor={`bookmark-color-${bm.id}`}>
                          Цвет
                        </label>
                        <select
                          id={`bookmark-color-${bm.id}`}
                          value={bookmarkDraft.color_key}
                          onChange={(event) =>
                            setBookmarkDraft({ ...bookmarkDraft, color_key: event.target.value })
                          }
                        >
                          <option value="emerald">Изумрудный</option>
                          <option value="gold">Золотой</option>
                          <option value="sapphire">Сапфировый</option>
                          <option value="ruby">Рубиновый</option>
                        </select>
                      </div>
                    </div>
                    <div className="form-group">
                      <label className="form-label" htmlFor={`bookmark-note-${bm.id}`}>
                        Заметка
                      </label>
                      <textarea
                        id={`bookmark-note-${bm.id}`}
                        value={bookmarkDraft.note}
                        maxLength={2000}
                        rows={2}
                        onChange={(event) =>
                          setBookmarkDraft({ ...bookmarkDraft, note: event.target.value })
                        }
                      />
                    </div>
                    <div style={{ display: "flex", gap: 8 }}>
                      <button className="btn btn-primary btn-sm" type="submit">
                        Сохранить
                      </button>
                      <button
                        className="btn btn-secondary btn-sm"
                        type="button"
                        onClick={() => setBookmarkDraft(null)}
                      >
                        Отмена
                      </button>
                    </div>
                  </form>
                ) : (
                  <>
                    <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
                      <span className="ayah-badge" style={{ background: "var(--accent-gold-subtle)", color: "var(--accent-gold)" }}>
                        🔖
                      </span>
                      <div>
                        <strong>{bm.label}</strong>
                        <p className="kpi-desc">
                          {bm.page_number ? `Страница ${bm.page_number}` : ""}
                          {bm.ayah
                            ? ` · Сура ${bm.ayah.surah_number}:${bm.ayah.ayah_number}`
                            : ""}
                          {bm.note ? ` · «${bm.note}»` : ""}
                        </p>
                      </div>
                    </div>

                    <div style={{ display: "flex", gap: 8 }}>
                      <button
                        className="btn btn-secondary btn-sm"
                        onClick={() =>
                          setBookmarkDraft({
                            id: bm.id,
                            label: bm.label,
                            color_key: bm.color_key,
                            note: bm.note || "",
                            revision: bm.revision,
                          })
                        }
                      >
                        Изменить
                      </button>
                      <button
                        className="btn btn-danger btn-sm"
                        onClick={() => void handleDeleteBookmark(bm.id, bm.revision)}
                        title="Удалить закладку"
                      >
                        Удалить
                      </button>
                    </div>
                  </>
                )}
              </div>
            ))}
          </div>
        ) : (
          <div style={{ padding: 24, textAlign: "center", color: "var(--text-muted)" }}>
            У вас пока нет закладок. Добавьте закладку во время чтения Корана.
          </div>
        )}
      </section>

      <ReminderManager />

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
                <label className="form-label" htmlFor="feedback-category">
                  Категория обращения
                </label>
                <select
                  id="feedback-category"
                  value={feedbackCategory}
                  onChange={(e) => setFeedbackCategory(e.target.value)}
                >
                  {FEEDBACK_CATEGORIES.map(([value, label]) => (
                    <option key={value} value={value}>
                      {label}
                    </option>
                  ))}
                </select>
              </div>

              <div className="form-group">
                <label className="form-label" htmlFor="feedback-subject">Тема</label>
                <input
                  id="feedback-subject"
                  type="text"
                  value={feedbackSubject}
                  onChange={(e) => setFeedbackSubject(e.target.value)}
                  placeholder="Краткое описание"
                  required
                />
              </div>
            </div>

            <div className="form-group">
              <label className="form-label" htmlFor="feedback-message">Сообщение</label>
              <textarea
                id="feedback-message"
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
                    Номер: <code>{t.public_id}</code> · Категория:{" "}
                    {FEEDBACK_CATEGORY_LABELS[t.category] || t.category}
                  </p>
                </div>
                <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
                  <span className={`status-chip ${t.status === "resolved" ? "ok" : ""}`}>
                    {FEEDBACK_STATUS_LABELS[t.status] || t.status}
                  </span>
                  <button
                    className="btn btn-secondary btn-sm"
                    type="button"
                    disabled={feedbackActionLoading}
                    onClick={() => void openFeedbackTicket(t.public_id)}
                  >
                    Открыть
                  </button>
                </div>
              </div>
            ))}
          </div>
        ) : (
          <div className="kpi-desc" style={{ padding: 12 }}>
            Активных обращений нет.
          </div>
        )}

        {selectedFeedback && (
          <div
            style={{
              marginTop: 18,
              padding: 16,
              border: "1px solid var(--border)",
              borderRadius: "var(--radius-md)",
              display: "flex",
              flexDirection: "column",
              gap: 14,
            }}
          >
            <div className="surface-head" style={{ marginBottom: 0 }}>
              <div>
                <p className="eyebrow">Обращение {selectedFeedback.public_id}</p>
                <h4 className="surface-title">{selectedFeedback.subject}</h4>
                <p className="surface-subtitle">
                  {FEEDBACK_CATEGORY_LABELS[selectedFeedback.category] || selectedFeedback.category}
                  {selectedFeedback.team ? ` · Команда: ${selectedFeedback.team}` : ""}
                </p>
              </div>
              <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
                <span
                  className={`status-chip ${selectedFeedback.status === "resolved" ? "ok" : ""}`}
                >
                  {FEEDBACK_STATUS_LABELS[selectedFeedback.status] || selectedFeedback.status}
                </span>
                <button
                  className="btn btn-secondary btn-sm"
                  type="button"
                  onClick={() => setSelectedFeedback(null)}
                >
                  Скрыть
                </button>
              </div>
            </div>

            <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
              {selectedFeedback.messages.map((message) => (
                <div
                  key={message.id}
                  className={`alert ${message.author_type === "operator" ? "alert-info" : ""}`}
                >
                  <strong>
                    {message.author_type === "operator"
                      ? "Поддержка"
                      : message.author_type === "system"
                        ? "Система"
                        : "Вы"}
                  </strong>
                  <p style={{ marginTop: 4, whiteSpace: "pre-wrap" }}>{message.body}</p>
                </div>
              ))}
            </div>

            {!(["rejected", "duplicate"] as string[]).includes(selectedFeedback.status) && (
              <form
                onSubmit={(event) => void handleFeedbackReply(event)}
                style={{ display: "flex", flexDirection: "column", gap: 8 }}
              >
                <label className="form-label" htmlFor="feedback-reply">
                  Добавить сообщение
                </label>
                <textarea
                  id="feedback-reply"
                  rows={3}
                  maxLength={4000}
                  value={feedbackReply}
                  onChange={(event) => setFeedbackReply(event.target.value)}
                  placeholder="Ваш ответ редакции или поддержке"
                />
                <div style={{ display: "flex", gap: 8 }}>
                  <button
                    className="btn btn-primary btn-sm"
                    disabled={feedbackActionLoading || !feedbackReply.trim()}
                  >
                    Отправить сообщение
                  </button>
                  {selectedFeedback.status === "closed" || selectedFeedback.status === "resolved" ? (
                    <button
                      className="btn btn-secondary btn-sm"
                      type="button"
                      disabled={feedbackActionLoading}
                      onClick={() => void transitionFeedbackTicket("reopen")}
                    >
                      Открыть повторно
                    </button>
                  ) : (
                    <button
                      className="btn btn-danger btn-sm"
                      type="button"
                      disabled={feedbackActionLoading}
                      onClick={() => void transitionFeedbackTicket("close")}
                    >
                      Закрыть обращение
                    </button>
                  )}
                </div>
              </form>
            )}
          </div>
        )}
      </section>
    </div>
  );
}
