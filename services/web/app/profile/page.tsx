"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import {
  api,
  Bookmark,
  DuaEntry,
  DuaFavorite,
  FeedbackTicket,
  FeedbackTicketDetail,
  ReadingPosition,
  ReferralLink,
  ReferralSummary,
  ShareConfigResponse,
} from "../../lib/api";
import { useAuth } from "../../lib/auth-context";
import { AccountSecurityPanel } from "../../components/AccountSecurityPanel";
import { SYNC_STATE_EVENT } from "../../lib/sync-state";
import { useI18n } from "../../lib/i18n-context";
import { MessageKey } from "../../lib/i18n";
import { localizedPath } from "../../lib/routing";
import { DuaEntryList } from "../../components/DuaEntryList";
import { FavoriteBookmarkIcon } from "../../components/FavoriteBookmarkIcon";

type FavoriteFilter = "all" | "dua" | "quran";

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
  const { formatNumber, locale, t } = useI18n();
  const userStatus = session?.user.status;

  const [reading, setReading] = useState<ReadingPosition | null>(null);
  const [bookmarks, setBookmarks] = useState<Bookmark[]>([]);
  const [duaFavorites, setDuaFavorites] = useState<DuaFavorite[]>([]);
  const [feedbackTickets, setFeedbackTickets] = useState<FeedbackTicket[]>([]);
  const [loadingBookmarks, setLoadingBookmarks] = useState<boolean>(false);
  const [loadingDuaFavorites, setLoadingDuaFavorites] = useState<boolean>(false);
  const [favoriteFilter, setFavoriteFilter] = useState<FavoriteFilter>("all");
  const [loadingSync, setLoadingSync] = useState<boolean>(false);
  const [pendingSync, setPendingSync] = useState<number>(0);
  const [confirmLogoutAll, setConfirmLogoutAll] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);
  const [successMsg, setSuccessMsg] = useState<string | null>(null);
  const [shareConfig, setShareConfig] = useState<ShareConfigResponse | null>(null);
  const [referralLink, setReferralLink] = useState<ReferralLink | null>(null);
  const [referralSummary, setReferralSummary] = useState<ReferralSummary | null>(null);
  const [loadingShare, setLoadingShare] = useState<boolean>(false);
  const [creatingReferralLink, setCreatingReferralLink] = useState<boolean>(false);
  const [shareNotice, setShareNotice] = useState<string | null>(null);

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

  const loadDuaFavoritesData = useCallback(async () => {
    setLoadingDuaFavorites(true);
    try {
      const snapshot = await api.getDuaFavorites(locale, true);
      setDuaFavorites(
        snapshot.results.filter((favorite) => favorite.is_favorite && favorite.entry),
      );
    } catch (err) {
      setError(api.normalizeError(err));
    } finally {
      setLoadingDuaFavorites(false);
    }
  }, [locale]);

  const loadShareData = useCallback(async () => {
    setLoadingShare(true);
    setShareNotice(null);
    setReferralLink(null);
    setReferralSummary(null);
    try {
      const config = await api.getShareConfig(locale);
      setShareConfig(config);
      if (
        userStatus === "active" &&
        config.available &&
        config.campaign?.referral_enabled
      ) {
        try {
          setReferralSummary(await api.getReferralSummary(config.campaign.key));
        } catch {
          // General sharing remains available when referral statistics cannot be loaded.
        }
      }
    } catch {
      setShareConfig(null);
    } finally {
      setLoadingShare(false);
    }
  }, [locale, userStatus]);

  // Load user data on mount / login
  useEffect(() => {
    if (isLoggedIn && userStatus !== "pending_deletion") {
      void loadReadingData();
      void loadBookmarksData();
      void loadDuaFavoritesData();
      void loadTicketsData();
      void loadShareData();
    }
  }, [isLoggedIn, loadDuaFavoritesData, loadShareData, userStatus]);

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

  const handleDuaFavoriteChange = (entry: DuaEntry, isFavorite: boolean) => {
    if (isFavorite) return;
    setDuaFavorites((current) =>
      current.filter(
        (favorite) =>
          !(
            favorite.collection === entry.collection &&
            favorite.source_number === entry.source_number
          ),
      ),
    );
    setSuccessMsg(t("profile.duaFavoriteRemoved"));
    setTimeout(() => setSuccessMsg(null), 3000);
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
      await loadDuaFavoritesData();
      await loadReadingData();
      setPendingSync(result.pending);
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

  const trackShare = (
    action: "open-system-share" | "copy-link" | "copy-code",
    result: "shared" | "copied" | "dismissed" | "unavailable",
  ) => {
    const campaign = shareConfig?.campaign;
    if (!campaign) return;
    void api.trackShareEvent({
      campaignKey: campaign.key,
      referralCode: referralLink?.code,
      action,
      result,
    }).catch(() => undefined);
  };

  const shareDestination = (): string =>
    referralLink?.short_url ||
    shareConfig?.campaign?.canonical_download_url ||
    window.location.origin;

  const copyShareLink = async () => {
    try {
      await navigator.clipboard.writeText(shareDestination());
      setShareNotice(t("profile.shareCopied"));
      trackShare("copy-link", "copied");
    } catch {
      setShareNotice(t("profile.shareCopyError"));
      trackShare("copy-link", "unavailable");
    }
  };

  const openShareMenu = async () => {
    const campaign = shareConfig?.campaign;
    if (!navigator.share) {
      trackShare("open-system-share", "unavailable");
      await copyShareLink();
      return;
    }
    try {
      await navigator.share({
        title: campaign?.title || t("profile.shareFallbackTitle"),
        text: campaign?.message || t("profile.shareFallbackMessage"),
        url: shareDestination(),
      });
      setShareNotice(t("profile.shareSent"));
      trackShare("open-system-share", "shared");
    } catch (shareError) {
      const dismissed = shareError instanceof DOMException && shareError.name === "AbortError";
      trackShare("open-system-share", dismissed ? "dismissed" : "unavailable");
      if (!dismissed) setShareNotice(t("profile.shareCopyError"));
    }
  };

  const createReferralLink = async () => {
    const campaign = shareConfig?.campaign;
    if (!campaign) return;
    setCreatingReferralLink(true);
    setShareNotice(null);
    try {
      const link = await api.getOrCreateReferralLink(campaign.key);
      setReferralLink(link);
      setShareNotice(t("profile.shareLinkReady"));
      try {
        setReferralSummary(await api.getReferralSummary(campaign.key));
      } catch {
        // The link is ready even if statistics are temporarily unavailable.
      }
    } catch {
      setShareNotice(t("profile.shareLinkError"));
    } finally {
      setCreatingReferralLink(false);
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
  const shareCampaign = shareConfig?.available ? shareConfig.campaign : null;
  const canUseReferrals = !isGuest && Boolean(shareCampaign?.referral_enabled);
  const duaFavoriteEntries = duaFavorites.flatMap((favorite) =>
    favorite.entry ? [favorite.entry] : [],
  );
  const savedItemCount = bookmarks.length + duaFavoriteEntries.length;
  const bookmarkSurahName = (bookmark: Bookmark): string => {
    const ayah = bookmark.ayah;
    if (!ayah) return "";
    if (locale === "ar") return ayah.surah_name_ar || String(ayah.surah_number);
    if (locale === "ru") return ayah.surah_name_ru || ayah.surah_name_en || String(ayah.surah_number);
    return ayah.surah_name_en || String(ayah.surah_number);
  };
  const bookmarkHref = (bookmark: Bookmark): string => {
    if (bookmark.ayah) {
      return localizedPath(
        locale,
        `/quran?surah=${bookmark.ayah.surah_number}&ayah=${bookmark.ayah.ayah_number}`,
      );
    }
    return localizedPath(locale, `/quran?page=${bookmark.page_number || 1}`);
  };
  const bookmarkTitle = (bookmark: Bookmark): string =>
    bookmark.ayah
      ? t("profile.quranAyahTitle", {
          surah: bookmarkSurahName(bookmark),
          ayah: formatNumber(bookmark.ayah.ayah_number),
        })
      : t("profile.quranPageTitle", { page: formatNumber(bookmark.page_number || 1) });

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 20 }}>
      {/* Account Info Header */}
      <section className="surface profile-account-overview">
        <div className="profile-account-heading">
          <span className="profile-account-avatar" aria-hidden="true">👤</span>
          <div>
            <p className="eyebrow">{t("profile.eyebrow")}</p>
            <h1 className="surface-title">{t("profile.title")}</h1>
            <p className="surface-subtitle">
              {session?.user.email || t("profile.guestAccountSummary")}
            </p>
          </div>
        </div>

        {error && <div className="alert alert-error" style={{ marginBottom: 14 }}>{error}</div>}
        {successMsg && <div className="alert alert-success" style={{ marginBottom: 14 }}>{successMsg}</div>}
        {isGuest && (
          <div className="alert alert-info" style={{ marginBottom: 14 }}>
            {t("profile.guestNotice")}
          </div>
        )}

        <div className="profile-account-action-grid">
          <article className="profile-account-action-card">
            <div className="profile-account-action-copy">
              <h2>{t("profile.syncTitle")}</h2>
              <p id="profile-sync-description">{t("profile.syncDescription")}</p>
            </div>
            <div>
              <button
                className="btn btn-outline-primary btn-sm"
                onClick={() => void handleSyncPull()}
                disabled={loadingSync}
                aria-describedby="profile-sync-description"
              >
                {loadingSync ? t("profile.syncing") : t("profile.syncData")}
                {!loadingSync && pendingSync > 0 ? ` (${pendingSync})` : ""}
              </button>
            </div>
          </article>

          <article className="profile-account-action-card">
            <div className="profile-account-action-copy">
              <h2>{isGuest ? t("profile.secureAccountTitle") : t("profile.sessionTitle")}</h2>
              <p>
                {isGuest
                  ? t("profile.secureAccountDescription")
                  : t("profile.sessionDescription")}
              </p>
            </div>
            <div className="responsive-actions">
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
          </article>
        </div>

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
            <span className="kpi-label">{t("profile.savedItems")}</span>
            <span className="kpi-value">{formatNumber(savedItemCount)}</span>
            <span className="kpi-desc">
              {t("profile.savedItemsBreakdown", {
                dua: formatNumber(duaFavoriteEntries.length),
                quran: formatNumber(bookmarks.length),
              })}
            </span>
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

      <section className="surface profile-share-section" id="share-app">
        <div className="profile-share-heading">
          <div className="profile-share-icon" aria-hidden="true">↗</div>
          <div>
            <p className="eyebrow">{t("profile.shareEyebrow")}</p>
            <h2 className="surface-title">
              {shareCampaign?.title || t("profile.shareTitle")}
            </h2>
            <p className="surface-subtitle">
              {shareCampaign?.message || t("profile.shareDescription")}
            </p>
          </div>
        </div>

        {shareNotice && <div className="alert alert-info">{shareNotice}</div>}

        {!loadingShare && !shareCampaign && (
          <p className="profile-share-note">{t("profile.shareProgramUnavailable")}</p>
        )}

        {isGuest && (
          <div className="profile-share-guest">
            <p>{t("profile.shareGuestHint")}</p>
            <Link href={localizedPath(locale, "/login")} className="btn btn-secondary btn-sm">
              {t("profile.shareLogin")}
            </Link>
          </div>
        )}

        {canUseReferrals && !referralLink && (
          <div className="profile-share-referral-callout">
            <div>
              <strong>{t("profile.sharePersonalTitle")}</strong>
              <p>{t("profile.sharePersonalDescription")}</p>
            </div>
            <button
              type="button"
              className="btn btn-primary"
              disabled={creatingReferralLink || loadingShare}
              onClick={() => void createReferralLink()}
            >
              {creatingReferralLink
                ? t("profile.shareCreating")
                : t("profile.shareCreateLink")}
            </button>
          </div>
        )}

        {referralLink && (
          <div className="profile-share-link-card">
            <div className="profile-share-link-copy">
              <label htmlFor="profile-referral-link">{t("profile.sharePersonalLink")}</label>
              <div className="profile-share-link-row">
                <input
                  id="profile-referral-link"
                  value={referralLink.short_url}
                  readOnly
                  onFocus={(event) => event.currentTarget.select()}
                />
                <button type="button" className="btn btn-secondary" onClick={() => void copyShareLink()}>
                  {t("profile.shareCopy")}
                </button>
              </div>
            </div>
            <div className="profile-share-code">
              <span>{t("profile.sharePromoCode")}</span>
              <strong>{referralLink.code}</strong>
            </div>
          </div>
        )}

        {canUseReferrals && referralSummary && (
          <div className="profile-share-stats" aria-label={t("profile.shareStatsTitle")}>
            <div>
              <span>{t("profile.shareInvited")}</span>
              <strong>{formatNumber(referralSummary.invited)}</strong>
            </div>
            <div>
              <span>{t("profile.shareQualified")}</span>
              <strong>{formatNumber(referralSummary.qualified)}</strong>
            </div>
            <div>
              <span>{t("profile.shareBalance")}</span>
              <strong>{formatNumber(referralSummary.reward_balance)}</strong>
            </div>
            <div>
              <span>{t("profile.sharePending")}</span>
              <strong>{formatNumber(referralSummary.pending_reward)}</strong>
            </div>
          </div>
        )}

        <div className="profile-share-actions">
          <button type="button" className="btn btn-primary" onClick={() => void openShareMenu()}>
            {shareCampaign?.cta_label || t("profile.shareAction")}
          </button>
          <button type="button" className="btn btn-secondary" onClick={() => void copyShareLink()}>
            {t("profile.shareCopyLink")}
          </button>
        </div>
      </section>

      {/* Saved content */}
      <section className="surface profile-favorites" id="favorites">
        <div className="surface-head">
          <div>
            <h3 className="surface-title">{t("profile.favoritesTitle")}</h3>
            <p className="surface-subtitle">{t("profile.favoritesDescription")}</p>
          </div>
        </div>

        <div className="profile-favorite-filters" aria-label={t("profile.favoriteFiltersLabel")}>
          {(["all", "dua", "quran"] as const).map((filter) => {
            const count =
              filter === "all"
                ? savedItemCount
                : filter === "dua"
                  ? duaFavoriteEntries.length
                  : bookmarks.length;
            return (
              <button
                key={filter}
                type="button"
                className={`profile-favorite-filter ${favoriteFilter === filter ? "is-active" : ""}`}
                aria-pressed={favoriteFilter === filter}
                onClick={() => setFavoriteFilter(filter)}
              >
                {t(`profile.favoriteFilter.${filter}` as MessageKey)}
                <span>{formatNumber(count)}</span>
              </button>
            );
          })}
        </div>

        {favoriteFilter !== "quran" ? (
          <div className="profile-favorite-group">
            <div className="profile-favorite-group-head">
              <div>
                <h4>{t("profile.duaFavoritesTitle")}</h4>
                <p>{t("profile.duaFavoritesDescription")}</p>
              </div>
              <span className="status-chip">{formatNumber(duaFavoriteEntries.length)}</span>
            </div>
            {loadingDuaFavorites ? (
              <div className="profile-favorite-empty">{t("profile.loadingDuaFavorites")}</div>
            ) : duaFavoriteEntries.length > 0 ? (
              <DuaEntryList
                entries={duaFavoriteEntries}
                headingLevel={3}
                compact
                onFavoriteChange={handleDuaFavoriteChange}
              />
            ) : (
              <div className="profile-favorite-empty">
                <span aria-hidden="true">♡</span>
                <p>{t("profile.noDuaFavorites")}</p>
                <Link href={localizedPath(locale, "/dua")} className="btn btn-secondary btn-sm">
                  {t("profile.openDuaCatalog")}
                </Link>
              </div>
            )}
          </div>
        ) : null}

        {favoriteFilter !== "dua" ? (
          <div className="profile-favorite-group profile-quran-favorites">
            {loadingBookmarks ? (
              <div className="profile-favorite-empty">{t("profile.loadingBookmarks")}</div>
            ) : bookmarks.length > 0 ? (
              <div className="profile-bookmark-list">
                {bookmarks.map((bm) => (
                  <div key={bm.id} className="track-row profile-bookmark-row">
                    {bookmarkDraft?.id === bm.id ? (
                      <form
                        onSubmit={(event) => void handleUpdateBookmark(event)}
                        className="profile-bookmark-edit"
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
                        <Link
                          href={bookmarkHref(bm)}
                          className="profile-bookmark-link"
                          aria-label={t("profile.openSavedQuran", { title: bookmarkTitle(bm) })}
                        >
                          <span className="ayah-badge profile-saved-icon" aria-hidden="true">
                            <FavoriteBookmarkIcon active />
                          </span>
                          <span className="profile-bookmark-copy">
                            <strong>{bookmarkTitle(bm)}</strong>
                            <span>
                              {bm.label || ""}
                              {bm.ayah && bm.page_number
                                ? ` · ${t("common.page", { page: formatNumber(bm.page_number) })}`
                                : ""}
                              {bm.note ? ` · «${bm.note}»` : ""}
                            </span>
                          </span>
                          <span className="profile-bookmark-arrow" aria-hidden="true">→</span>
                        </Link>

                        <div className="responsive-actions profile-bookmark-actions">
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
              <div className="profile-favorite-empty">{t("profile.noBookmarks")}</div>
            )}
          </div>
        ) : null}
      </section>

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
