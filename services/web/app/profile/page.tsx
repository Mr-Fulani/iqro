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
import { AccountSecurityPanel } from "../../components/AccountSecurityPanel";
import { SYNC_STATE_EVENT } from "../../lib/sync-state";
import { useI18n } from "../../lib/i18n-context";
import { MessageKey } from "../../lib/i18n";
import { localizedPath } from "../../lib/routing";

const FEEDBACK_CATEGORIES = [
  ["religious_content", "feedback.category.religious"],
  ["page_layout", "feedback.category.layout"],
  ["audio", "feedback.category.audio"],
  ["advertisement", "feedback.category.ad"],
  ["technical", "feedback.category.technical"],
  ["account_sync", "feedback.category.account"],
  ["donation_link", "feedback.category.donation"],
  ["accessibility_localization", "feedback.category.accessibility"],
  ["general", "feedback.category.general"],
  ["other", "feedback.category.other"],
] as const;

const FEEDBACK_STATUS_LABELS: Record<string, MessageKey> = {
  new: "feedback.status.new",
  triaged: "feedback.status.triaged",
  in_progress: "feedback.status.progress",
  waiting_for_user: "feedback.status.waiting",
  resolved: "feedback.status.resolved",
  rejected: "feedback.status.rejected",
  duplicate: "feedback.status.duplicate",
  closed: "feedback.status.closed",
};

const FEEDBACK_CATEGORY_LABELS = Object.fromEntries(FEEDBACK_CATEGORIES) as Record<string, MessageKey>;

export default function ProfilePage() {
  const {
    session,
    isLoggedIn,
    logout,
    logoutAll,
    isLoading: authLoading,
  } = useAuth();
  const { locale, t } = useI18n();

  const [reading, setReading] = useState<ReadingPosition | null>(null);
  const [bookmarks, setBookmarks] = useState<Bookmark[]>([]);
  const [feedbackTickets, setFeedbackTickets] = useState<FeedbackTicket[]>([]);
  const [loadingBookmarks, setLoadingBookmarks] = useState<boolean>(false);
  const [loadingSync, setLoadingSync] = useState<boolean>(false);
  const [pendingSync, setPendingSync] = useState<number>(0);
  const [syncVersion, setSyncVersion] = useState<number>(0);
  const [confirmLogoutAll, setConfirmLogoutAll] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);
  const [successMsg, setSuccessMsg] = useState<string | null>(null);

  // New Bookmark form state
  const [newBookmarkPage, setNewBookmarkPage] = useState<number>(1);
  const [newBookmarkLabel, setNewBookmarkLabel] = useState<string>(() => t("profile.defaultBookmark"));
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
    if (isLoggedIn && session?.user.status !== "pending_deletion") {
      void loadReadingData();
      void loadBookmarksData();
      void loadTicketsData();
    }
  }, [isLoggedIn, session?.user.status]);

  useEffect(() => {
    if (!session?.user.id) {
      setPendingSync(0);
      return;
    }
    const refreshPending = () => setPendingSync(api.getPendingSyncCount());
    refreshPending();
    window.addEventListener(SYNC_STATE_EVENT, refreshPending);
    return () => window.removeEventListener(SYNC_STATE_EVENT, refreshPending);
  }, [session?.user.id]);

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
      setSuccessMsg(t("profile.bookmarkCreated"));
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
      setSuccessMsg(t("profile.bookmarkDeleted"));
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
      setSuccessMsg(t("profile.bookmarkUpdated"));
      setTimeout(() => setSuccessMsg(null), 3000);
    } catch (err) {
      setError(api.normalizeError(err));
    }
  };

  const handleSyncPull = async () => {
    setLoadingSync(true);
    setError(null);
    try {
      const result = await api.syncNow();
      const details = [
        result.pushed ? t("profile.syncPushed", { count: result.pushed }) : null,
        result.changes ? t("profile.syncChanges", { count: result.changes }) : null,
        result.full_resync ? t("profile.syncFull", { count: result.snapshot_entities }) : null,
        result.conflicts ? t("profile.syncConflicts", { count: result.conflicts }) : null,
      ].filter(Boolean);
      setSuccessMsg(
        details.length
          ? t("profile.syncComplete", { details: details.join(", ") })
          : t("profile.syncCurrent"),
      );
      await loadBookmarksData();
      await loadReadingData();
      setPendingSync(result.pending);
      setSyncVersion((current) => current + 1);
      setTimeout(() => setSuccessMsg(null), 5000);
    } catch (err) {
      setError(api.normalizeError(err));
    } finally {
      setLoadingSync(false);
    }
  };

  const handleLogoutAll = async () => {
    setError(null);
    const succeeded = await logoutAll();
    if (!succeeded) {
      setError(t("profile.logoutAllError"));
      setConfirmLogoutAll(false);
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
      setSuccessMsg(t("profile.feedbackSent"));
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
      setSuccessMsg(action === "close" ? t("profile.feedbackClosed") : t("profile.feedbackReopened"));
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
        <h1 className="surface-title" style={{ marginBottom: 8 }}>{t("profile.readerProfile")}</h1>
        <p className="kpi-desc" style={{ marginBottom: 24 }}>
          {t("profile.loginDescription")}
        </p>

        {error && <div className="alert alert-error" style={{ marginBottom: 16 }}>{error}</div>}

        <Link
          href={localizedPath(locale, "/login")}
          className="btn btn-primary btn-lg"
          style={{ width: "100%" }}
        >
          {t("auth.emailLogin")}
        </Link>
      </div>
    );
  }

  if (session?.user.status === "pending_deletion") {
    return <AccountSecurityPanel />;
  }

  const isGuest = session?.user.status === "guest";

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 20 }}>
      {/* Account Info Header */}
      <section className="surface">
        <div className="surface-head">
          <div>
            <p className="eyebrow">{t("profile.eyebrow")}</p>
            <h1 className="surface-title">{t("profile.title")}</h1>
            <p className="surface-subtitle">
              {session?.user.email ? `${session.user.email} · ` : ""}
              {t("profile.identity", {
                userId: session?.user.id || "—",
                deviceId: session?.device.id || "—",
              })}
            </p>
          </div>

          <div className="responsive-actions">
            <button
              className="btn btn-outline-primary btn-sm"
              onClick={() => void handleSyncPull()}
              disabled={loadingSync}
            >
              {loadingSync ? t("profile.syncing") : t("profile.offlineSync")}
              {!loadingSync && pendingSync > 0 ? ` (${pendingSync})` : ""}
            </button>
            {isGuest ? (
              <Link href={localizedPath(locale, "/login")} className="btn btn-primary btn-sm">
                {t("auth.emailLogin")}
              </Link>
            ) : (
              <>
                <button
                  className="btn btn-secondary btn-sm"
                  onClick={() => void logout()}
                >
                  {t("auth.logout")}
                </button>
                <button
                  className="btn btn-danger btn-sm"
                  onClick={() => setConfirmLogoutAll(true)}
                >
                  {t("profile.logoutAll")}
                </button>
              </>
            )}
          </div>
        </div>

        {error && <div className="alert alert-error" style={{ marginBottom: 14 }}>{error}</div>}
        {successMsg && <div className="alert alert-success" style={{ marginBottom: 14 }}>{successMsg}</div>}
        {confirmLogoutAll && (
          <div className="alert alert-error" style={{ marginBottom: 14 }}>
            <strong>{t("profile.logoutAllTitle")}</strong>
            <p style={{ marginTop: 6 }}>{t("profile.logoutAllDescription")}</p>
            <div className="responsive-actions" style={{ marginTop: 10 }}>
              <button
                className="btn btn-danger btn-sm"
                type="button"
                disabled={authLoading}
                onClick={() => void handleLogoutAll()}
              >
                {authLoading ? t("profile.endingSessions") : t("profile.confirmLogoutAll")}
              </button>
              <button
                className="btn btn-secondary btn-sm"
                type="button"
                disabled={authLoading}
                onClick={() => setConfirmLogoutAll(false)}
              >
                {t("common.cancel")}
              </button>
            </div>
          </div>
        )}
        {isGuest && (
          <div className="alert alert-info" style={{ marginBottom: 14 }}>
            {t("profile.guestNotice")}
          </div>
        )}

        <div className="kpi-grid" style={{ marginTop: 8 }}>
          <div className="kpi-card">
            <span className="kpi-label">{t("profile.status")}</span>
            <span className="kpi-value">{session?.user.status === "guest" ? t("profile.guest") : t("profile.active")}</span>
            <span className="kpi-desc">
              {session?.user.email || t("profile.platform", { platform: session?.device.platform || "web" })}
            </span>
          </div>

          <div className="kpi-card">
            <span className="kpi-label">{t("profile.syncQueue")}</span>
            <span className="kpi-value">{pendingSync}</span>
            <span className="kpi-desc">
              {pendingSync ? t("profile.pendingChanges") : t("profile.noLocalChanges")}
            </span>
          </div>

          <div className="kpi-card">
            <span className="kpi-label">{t("profile.savedBookmarks")}</span>
            <span className="kpi-value">{bookmarks.length}</span>
            <span className="kpi-desc">{t("profile.editionMadani")}</span>
          </div>

          <div className="kpi-card">
            <span className="kpi-label">{t("profile.readingPosition")}</span>
            <span className="kpi-value">
              {reading ? t("common.page", { page: reading.page_number }) : t("profile.notSaved")}
            </span>
            <span className="kpi-desc">
              {reading?.ayah
                ? t("common.surah", { surah: `${reading.ayah.surah_number}:${reading.ayah.ayah_number}` })
                : t("profile.startReading")}
            </span>
          </div>

          <div className="kpi-card">
            <span className="kpi-label">{t("profile.supportRequests")}</span>
            <span className="kpi-value">{feedbackTickets.length}</span>
            <span className="kpi-desc">{t("profile.editorialAudit")}</span>
          </div>
        </div>
      </section>

      <AccountSecurityPanel />

      {/* Bookmarks Section */}
      <section className="surface">
        <div className="surface-head">
          <div>
            <h3 className="surface-title">{t("profile.bookmarksTitle")}</h3>
            <p className="surface-subtitle">{t("profile.bookmarksDescription")}</p>
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
              <label className="form-label">{t("profile.pageInput")}</label>
              <input
                type="number"
                min={1}
                max={604}
                value={newBookmarkPage}
                onChange={(e) => setNewBookmarkPage(Number(e.target.value))}
              />
            </div>

            <div className="form-group">
              <label className="form-label">{t("profile.bookmarkName")}</label>
              <input
                type="text"
                value={newBookmarkLabel}
                onChange={(e) => setNewBookmarkLabel(e.target.value)}
                placeholder={t("profile.bookmarkExample")}
              />
            </div>

            <div className="form-group">
              <label className="form-label">{t("profile.colorLabel")}</label>
              <select
                value={newBookmarkColor}
                onChange={(e) => setNewBookmarkColor(e.target.value)}
              >
                <option value="emerald">{t("profile.color.emerald")}</option>
                <option value="gold">{t("profile.color.gold")}</option>
                <option value="sapphire">{t("profile.color.sapphire")}</option>
                <option value="ruby">{t("profile.color.ruby")}</option>
              </select>
            </div>
          </div>

          <div className="form-group">
            <label className="form-label">{t("profile.noteOptional")}</label>
            <input
              type="text"
              value={newBookmarkNote}
              onChange={(e) => setNewBookmarkNote(e.target.value)}
              placeholder={t("profile.notePlaceholder")}
            />
          </div>

          <div>
            <button type="submit" className="btn btn-primary btn-sm">
              {t("profile.addBookmark")}
            </button>
          </div>
        </form>

        {/* Bookmarks List */}
        {loadingBookmarks ? (
          <div style={{ padding: 24, textAlign: "center", color: "var(--text-muted)" }}>
            {t("profile.loadingBookmarks")}
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
                          {t("profile.name")}
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
                          {t("profile.color")}
                        </label>
                        <select
                          id={`bookmark-color-${bm.id}`}
                          value={bookmarkDraft.color_key}
                          onChange={(event) =>
                            setBookmarkDraft({ ...bookmarkDraft, color_key: event.target.value })
                          }
                        >
                          <option value="emerald">{t("profile.color.emerald")}</option>
                          <option value="gold">{t("profile.color.gold")}</option>
                          <option value="sapphire">{t("profile.color.sapphire")}</option>
                          <option value="ruby">{t("profile.color.ruby")}</option>
                        </select>
                      </div>
                    </div>
                    <div className="form-group">
                      <label className="form-label" htmlFor={`bookmark-note-${bm.id}`}>
                        {t("profile.note")}
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
                    <div className="responsive-actions">
                      <button className="btn btn-primary btn-sm" type="submit">
                        {t("common.save")}
                      </button>
                      <button
                        className="btn btn-secondary btn-sm"
                        type="button"
                        onClick={() => setBookmarkDraft(null)}
                      >
                        {t("common.cancel")}
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
                          {bm.page_number ? t("common.page", { page: bm.page_number }) : ""}
                          {bm.ayah
                            ? ` · ${t("common.surah", { surah: `${bm.ayah.surah_number}:${bm.ayah.ayah_number}` })}`
                            : ""}
                          {bm.note ? ` · «${bm.note}»` : ""}
                        </p>
                      </div>
                    </div>

                    <div className="responsive-actions">
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
                        {t("common.edit")}
                      </button>
                      <button
                        className="btn btn-danger btn-sm"
                        onClick={() => void handleDeleteBookmark(bm.id, bm.revision)}
                        title={t("profile.deleteBookmarkTitle")}
                      >
                        {t("common.delete")}
                      </button>
                    </div>
                  </>
                )}
              </div>
            ))}
          </div>
        ) : (
          <div style={{ padding: 24, textAlign: "center", color: "var(--text-muted)" }}>
            {t("profile.noBookmarks")}
          </div>
        )}
      </section>

      <ReminderManager key={syncVersion} />

      {/* Feedback & Support Section */}
      <section className="surface" id="feedback">
        <div className="surface-head">
          <div>
            <h3 className="surface-title">{t("feedback.title")}</h3>
            <p className="surface-subtitle">{t("feedback.description")}</p>
          </div>

          <button
            className="btn btn-outline-primary btn-sm"
            onClick={() => setShowFeedbackModal(true)}
          >
            {t("feedback.create")}
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
                  {t("feedback.category")}
                </label>
                <select
                  id="feedback-category"
                  value={feedbackCategory}
                  onChange={(e) => setFeedbackCategory(e.target.value)}
                >
                  {FEEDBACK_CATEGORIES.map(([value, label]) => (
                    <option key={value} value={value}>
                      {t(label)}
                    </option>
                  ))}
                </select>
              </div>

              <div className="form-group">
                <label className="form-label" htmlFor="feedback-subject">{t("feedback.subject")}</label>
                <input
                  id="feedback-subject"
                  type="text"
                  value={feedbackSubject}
                  onChange={(e) => setFeedbackSubject(e.target.value)}
                  placeholder={t("feedback.subjectPlaceholder")}
                  required
                />
              </div>
            </div>

            <div className="form-group">
              <label className="form-label" htmlFor="feedback-message">{t("feedback.message")}</label>
              <textarea
                id="feedback-message"
                value={feedbackMessage}
                onChange={(e) => setFeedbackMessage(e.target.value)}
                rows={3}
                placeholder={t("feedback.messagePlaceholder")}
                required
              />
            </div>

            <div className="responsive-actions">
              <button
                type="submit"
                className="btn btn-primary btn-sm"
                disabled={sendingFeedback}
              >
                {sendingFeedback ? t("common.sending") : t("feedback.send")}
              </button>
              <button
                type="button"
                className="btn btn-secondary btn-sm"
                onClick={() => setShowFeedbackModal(false)}
              >
                {t("common.cancel")}
              </button>
            </div>
          </form>
        )}

        {feedbackTickets.length > 0 ? (
          <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
            {feedbackTickets.map((ticket) => (
              <div key={ticket.public_id} className="track-row">
                <div>
                  <strong>{ticket.subject}</strong>
                  <p className="kpi-desc">
                    {t("feedback.numberCategory", {
                      id: ticket.public_id,
                      category: FEEDBACK_CATEGORY_LABELS[ticket.category]
                        ? t(FEEDBACK_CATEGORY_LABELS[ticket.category])
                        : ticket.category,
                    })}
                  </p>
                </div>
                <div className="responsive-actions">
                  <span className={`status-chip ${ticket.status === "resolved" ? "ok" : ""}`}>
                    {FEEDBACK_STATUS_LABELS[ticket.status] ? t(FEEDBACK_STATUS_LABELS[ticket.status]) : ticket.status}
                  </span>
                  <button
                    className="btn btn-secondary btn-sm"
                    type="button"
                    disabled={feedbackActionLoading}
                    onClick={() => void openFeedbackTicket(ticket.public_id)}
                  >
                    {t("common.open")}
                  </button>
                </div>
              </div>
            ))}
          </div>
        ) : (
          <div className="kpi-desc" style={{ padding: 12 }}>
            {t("feedback.none")}
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
                <p className="eyebrow">{t("feedback.ticket", { id: selectedFeedback.public_id })}</p>
                <h4 className="surface-title">{selectedFeedback.subject}</h4>
                <p className="surface-subtitle">
                  {FEEDBACK_CATEGORY_LABELS[selectedFeedback.category]
                    ? t(FEEDBACK_CATEGORY_LABELS[selectedFeedback.category])
                    : selectedFeedback.category}
                  {selectedFeedback.team ? ` · ${t("feedback.team", { team: selectedFeedback.team })}` : ""}
                </p>
              </div>
              <div className="responsive-actions">
                <span
                  className={`status-chip ${selectedFeedback.status === "resolved" ? "ok" : ""}`}
                >
                  {FEEDBACK_STATUS_LABELS[selectedFeedback.status]
                    ? t(FEEDBACK_STATUS_LABELS[selectedFeedback.status])
                    : selectedFeedback.status}
                </span>
                <button
                  className="btn btn-secondary btn-sm"
                  type="button"
                  onClick={() => setSelectedFeedback(null)}
                >
                  {t("feedback.hide")}
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
                      ? t("feedback.support")
                      : message.author_type === "system"
                        ? t("feedback.system")
                        : t("feedback.you")}
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
                  {t("feedback.addMessage")}
                </label>
                <textarea
                  id="feedback-reply"
                  rows={3}
                  maxLength={4000}
                  value={feedbackReply}
                  onChange={(event) => setFeedbackReply(event.target.value)}
                  placeholder={t("feedback.replyPlaceholder")}
                />
                <div className="responsive-actions">
                  <button
                    className="btn btn-primary btn-sm"
                    disabled={feedbackActionLoading || !feedbackReply.trim()}
                  >
                    {t("feedback.sendMessage")}
                  </button>
                  {selectedFeedback.status === "closed" || selectedFeedback.status === "resolved" ? (
                    <button
                      className="btn btn-secondary btn-sm"
                      type="button"
                      disabled={feedbackActionLoading}
                      onClick={() => void transitionFeedbackTicket("reopen")}
                    >
                      {t("feedback.reopen")}
                    </button>
                  ) : (
                    <button
                      className="btn btn-danger btn-sm"
                      type="button"
                      disabled={feedbackActionLoading}
                      onClick={() => void transitionFeedbackTicket("close")}
                    >
                      {t("feedback.closeTicket")}
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
