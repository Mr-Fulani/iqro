/**
 * Quran Platform - Typed API Client
 * Compatible with Django backend specification and DRF serializers.
 */

import {
  discardEntityOperation,
  enqueueSyncOperation,
  getPendingSyncCount,
  getPendingSyncOperations,
  getReadingPositionId,
  getSyncCursor,
  rebaseOutboxFromSnapshot,
  rememberReadingPositionId,
  removeSyncOperations,
  replaceSyncOperation,
  setSyncCursor,
} from "./sync-state";

export type RequestState<T = unknown> = {
  loading?: boolean;
  data?: T;
  error?: string;
};

// ---------------------------------------------------------------------------
// Authentication Types
// ---------------------------------------------------------------------------
export type DevicePlatform = "web" | "ios" | "android" | "telegram";
export type SupportedLocale = "ar" | "en" | "ru";

export type GuestBootstrapRequest = {
  locale: SupportedLocale;
  app_version: string;
};

export type UserSummary = {
  id: string;
  status: "guest" | "active" | "pending_deletion" | "suspended" | "deleted";
  preferred_locale: SupportedLocale;
  email: string | null;
};

export type DeviceSummary = {
  id: string;
  platform: DevicePlatform;
  locale: SupportedLocale;
  app_version: string;
  bootstrap_generation: number;
};

export type AuthTokens = {
  token_type: string;
  access_token: string;
  expires_in: number;
  access_expires_at: string;
};

export type GuestBootstrapResponse = AuthTokens & {
  user: UserSummary;
  device: DeviceSummary;
};

export type InstallIdentity = {
  installation_id: string;
  installation_credential: string;
};

export type EmailChallenge = {
  challenge_id: string;
  expires_in: number;
  expires_at: string;
};

export type EmailVerificationResponse = GuestBootstrapResponse & {
  merged_guest: boolean;
  replayed: boolean;
};

// ---------------------------------------------------------------------------
// Quran Catalog & Mushaf Types
// ---------------------------------------------------------------------------
export type QuranEditionVersion = {
  id: string;
  version: string;
  checksum_sha256: string;
  page_count: number;
  surah_count: number;
  juz_count: number;
  hizb_count: number;
  rub_el_hizb_count: number;
  published_at: string;
};

export type QuranEdition = {
  id: string;
  code: string;
  name_ar: string;
  name_en: string;
  name_ru: string;
  riwayah: string;
  source_name: string;
  source_url: string;
  license_name: string;
  license_url: string;
  active_version?: QuranEditionVersion;
};

export type Surah = {
  id: string;
  number: number;
  name_ar: string;
  name_en: string;
  name_ru: string;
  revelation_type: "meccan" | "medinan" | string;
  ayah_count: number;
  first_page: number | null;
};

export type Ayah = {
  id: string;
  edition_code: string;
  content_version: string;
  surah_number: number;
  number: number;
  text_uthmani: string;
  juz_number: number;
  hizb_number: number | null;
  rub_el_hizb_number: number | null;
  pages: number[];
};

export type PageAssetVariant = {
  url: string;
  width: number;
  height: number;
  format: "webp" | "jpeg" | string;
  bytes: number;
};

export type AyahPageRegion = {
  id: string;
  ayah: { id: string; surah: number; number: number };
  reading_order: number;
  polygon: [number, number][];
  x: number;
  y: number;
  width: number;
  height: number;
};

export type MushafPage = {
  id: string;
  edition_code: string;
  content_version: string;
  number: number;
  image_width: number;
  image_height: number;
  checksum_sha256: string;
  assets: PageAssetVariant[];
  regions: AyahPageRegion[];
};

export type QuranDivision = {
  id: string;
  number: number;
  start_ayah: { id: string; surah: number; number: number };
  end_ayah: { id: string; surah: number; number: number };
  start_page: number;
  end_page: number;
};

export type Juz = QuranDivision;
export type Hizb = QuranDivision;
export type RubElHizb = QuranDivision & {
  hizb_number: number;
  quarter_number: number;
};

// ---------------------------------------------------------------------------
// Audio Types
// ---------------------------------------------------------------------------
export type Reciter = {
  id: string;
  slug: string;
  name_ar: string;
  name_en: string;
  name_ru: string;
  country_code: string;
  biography_ar?: string;
  biography_en?: string;
  biography_ru?: string;
  portrait_url?: string | null;
};

export type Recitation = {
  id: string;
  code: string;
  version: string;
  style: string;
  reciter: Reciter;
  quran_edition: {
    id: string;
    code: string;
    content_version: string;
    riwayah: string;
  };
  rights: { stream: boolean; offline_download: boolean };
  coverage: { track_count: number; surah_count: number; complete: boolean };
  timings: { available: boolean; segment_count: number };
};

export type AudioTrack = {
  id: string;
  recitation_id: string;
  scope: "surah" | "juz" | "ayah" | string;
  surah_number: number | null;
  juz_number: number | null;
  duration_ms: number;
  offline_download_allowed: boolean;
  asset: {
    url: string;
    content_type: string;
    codec: "mp3" | "opus" | "aac" | string;
    bitrate_kbps: number;
    bytes: number;
    sha256: string | null;
    etag: string | null;
    range_supported: boolean;
    immutable: boolean;
  };
};

export type AyahAudioSegment = {
  ayah_id: string;
  surah_number: number;
  ayah_number: number;
  start_ms: number;
  end_ms: number;
};

export type SurahPlayback = {
  track: AudioTrack;
  segments: AyahAudioSegment[];
};

// ---------------------------------------------------------------------------
// Prayer Times Types
// ---------------------------------------------------------------------------
export type PrayerMethod = {
  id: string;
  code: string;
  available: boolean;
  name: { ar: string; en: string; ru: string };
  description: { ar: string; en: string; ru: string };
  checksum_sha256: string;
};

export type PrayerMethodsResponse = {
  catalog_version: string;
  configuration_schema_version: number;
  checksum_sha256: string;
  methods: PrayerMethod[];
};

export type PrayerTimeEvent = {
  local: string;
  utc: string;
  utc_offset_seconds: number;
};

export type PrayerTimesResult = {
  fajr: PrayerTimeEvent;
  sunrise: PrayerTimeEvent;
  dhuhr: PrayerTimeEvent;
  asr: PrayerTimeEvent;
  maghrib: PrayerTimeEvent;
  isha: PrayerTimeEvent;
  qiyam?: PrayerTimeEvent;
};

export type PrayerCalculationRequest = {
  date: string;
  timezone: string;
  location: {
    latitude: string | number;
    longitude: string | number;
  };
  method_config_id: string;
  method_checksum_sha256?: string;
  asr_method?: "standard" | "hanafi";
  high_latitude_rule?: string;
  polar_resolution?: string;
  adjustments?: {
    fajr?: number;
    sunrise?: number;
    dhuhr?: number;
    asr?: number;
    maghrib?: number;
    isha?: number;
  };
};

export type PrayerCalculationResponse = {
  date: string;
  timezone: string;
  method: { id: string; code: string; catalog_version?: string; checksum_sha256?: string; name?: { ar: string; en: string; ru: string } };
  times?: PrayerTimesResult;
  prayer_times?: PrayerTimesResult;
};

export type PrayerAdjustments = {
  fajr: number;
  sunrise: number;
  dhuhr: number;
  asr: number;
  maghrib: number;
  isha: number;
};

export type PrayerProfile = {
  id: string;
  method_config: {
    id: string;
    code: string;
    catalog_version: string;
    checksum_sha256: string;
  };
  method_available: boolean;
  asr_method: "standard" | "hanafi";
  high_latitude_rule: "middle_of_night" | "seventh_of_night" | "twilight_angle";
  polar_resolution: "unresolved" | "aqrab_balad" | "aqrab_yaum";
  adjustments: PrayerAdjustments;
  timezone_mode: "device_local" | "fixed";
  fixed_timezone: string | null;
  revision: number;
  client_updated_at: string;
  device_id: string | null;
  created_at: string;
  updated_at: string;
};

// ---------------------------------------------------------------------------
// Reading, Bookmarks & Sync Types
// ---------------------------------------------------------------------------
export type ReadingPosition = {
  id?: string;
  edition_code: string;
  page_number: number;
  ayah: {
    id: string;
    surah_number: number;
    ayah_number: number;
  } | null;
  intra_page_anchor?: {
    line_number?: number;
    x_ratio?: number;
    y_ratio?: number;
  };
  progress_percent: string;
  revision: number;
  last_read_at: string;
  client_updated_at: string;
};

export type Bookmark = {
  id: string;
  edition_code: string;
  page_number: number | null;
  ayah: {
    id: string;
    surah_number: number;
    ayah_number: number;
  } | null;
  label: string;
  color_key: string;
  note?: string;
  revision: number;
  created_at?: string;
  updated_at?: string;
  deleted_at: string | null;
};

export type PaginatedResponse<T> = {
  next: string | null;
  previous: string | null;
  results: T[];
};

export type SyncEntityType = "reading_position" | "bookmark" | "reminder";
export type SyncAction = "upsert" | "delete";

export type SyncEntity =
  | (ReadingPosition & { id: string; entity_type: "reading_position" })
  | (Bookmark & { entity_type: "bookmark" })
  | (Reminder & { entity_type: "reminder" });

export type SyncOperation = {
  operation_id: string;
  entity_type: SyncEntityType;
  entity_id: string;
  action: SyncAction;
  base_revision: number;
  client_updated_at: string;
  payload: Record<string, unknown>;
};

export type SyncOperationResult = {
  operation_id: string;
  outcome: "accepted" | "conflict";
  replayed: boolean;
  conflict_reason?: string;
  entity: SyncEntity | null;
  cursor: number;
};

export type SyncPushResponse = {
  results: SyncOperationResult[];
  cursor: number;
};

export type SyncChange = {
  cursor: number;
  entity_type: SyncEntityType;
  entity_id: string;
  action: SyncAction;
  revision: number;
  entity: SyncEntity;
  server_updated_at: string;
};

export type SyncIncrementalResponse = {
  mode: "incremental";
  changes: SyncChange[];
  next_cursor: number;
  has_more: boolean;
};

export type SyncFullResyncResponse = {
  mode: "full_resync";
  entities: SyncEntity[];
  snapshot_cursor: number;
  next_page_token: string | null;
  has_more: boolean;
};

export type SyncPullResponse = SyncIncrementalResponse | SyncFullResyncResponse;

export type SyncRunResult = {
  pushed: number;
  conflicts: number;
  changes: number;
  full_resync: boolean;
  snapshot_entities: number;
  cursor: number;
  pending: number;
};

export type ReminderSchedule =
  | {
      kind: "prayer";
      prayer_event: "fajr" | "dhuhr" | "asr" | "maghrib" | "isha";
      prayer_offset_minutes: number;
    }
  | { kind: "local_time"; local_time: string };

export type ReminderTimezone =
  | { mode: "device_local" }
  | { mode: "fixed"; name: string };

export type Reminder = {
  id: string;
  reminder_type: "prayer" | "quran_reading" | "quran_review";
  schedule: ReminderSchedule | null;
  review_target: {
    start: { id: string; surah_number: number; ayah_number: number };
    end: { id: string; surah_number: number; ayah_number: number };
  } | null;
  weekdays_mask: number;
  timezone: ReminderTimezone;
  delivery_mode: "local";
  signal: "silent" | "vibration" | "sound";
  is_enabled: boolean;
  revision: number;
  client_updated_at: string;
  device_id: string | null;
  deleted_at: string | null;
  created_at: string;
  updated_at: string;
};

export type ReminderSnapshot = {
  mode: "full_snapshot";
  authoritative: boolean;
  generated_at: string;
  count: number;
  reminders: Reminder[];
};

export type FeedbackTicket = {
  public_id: string;
  category: string;
  status:
    | "new"
    | "triaged"
    | "in_progress"
    | "waiting_for_user"
    | "resolved"
    | "rejected"
    | "duplicate"
    | "closed";
  subject: string;
  priority: "normal" | "high" | "critical";
  locale: SupportedLocale;
  channel: DevicePlatform;
  sla_response_due_at: string | null;
  first_response_at: string | null;
  created_at: string;
  updated_at: string;
};

export type FeedbackMessage = {
  id: string;
  client_message_id: string;
  author_type: "reporter" | "operator" | "system";
  body: string;
  created_at: string;
};

export type FeedbackTicketDetail = FeedbackTicket & {
  client_request_id: string;
  contact_email: string | null;
  team: string;
  resolved_at: string | null;
  closed_at: string | null;
  reopened_at: string | null;
  reopen_count: number;
  context: {
    edition_code: string;
    content_version: string;
    surah_number: number | null;
    ayah_number: number | null;
    page_number: number | null;
    reciter_id: string;
    recitation_id: string;
    audio_track_id: string;
    playback_ms: number | null;
    ad_campaign_id: string;
    ad_creative_id: string;
    route: string;
    app_version: string;
    app_build: string;
    client_platform: string;
    os_version: string;
  };
  messages: FeedbackMessage[];
};

// ---------------------------------------------------------------------------
// UUIDv7 and Security Utilities
// ---------------------------------------------------------------------------
export function generateUuidV7(): string {
  const bytes = new Uint8Array(16);
  if (typeof crypto !== "undefined" && crypto.getRandomValues) {
    crypto.getRandomValues(bytes);
  } else {
    for (let i = 0; i < 16; i += 1) bytes[i] = Math.floor(Math.random() * 256);
  }

  const timestamp = Date.now();
  // 48-bit timestamp (ms) in big-endian
  bytes[0] = (timestamp / 0x10000000000) & 0xff;
  bytes[1] = (timestamp / 0x100000000) & 0xff;
  bytes[2] = (timestamp / 0x1000000) & 0xff;
  bytes[3] = (timestamp / 0x10000) & 0xff;
  bytes[4] = (timestamp / 0x100) & 0xff;
  bytes[5] = timestamp & 0xff;

  // Version 7 in top 4 bits of byte 6
  bytes[6] = 0x70 | (bytes[6] & 0x0f);
  // Variant 1 in top 2 bits of byte 8
  bytes[8] = 0x80 | (bytes[8] & 0x3f);

  const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20, 32)}`;
}

// ---------------------------------------------------------------------------
// Storage Keys
// ---------------------------------------------------------------------------
const STORAGE_IDENTITY = "quran_platform_identity_v1";
const STORAGE_SESSION = "quran_platform_session_v1";

const API_ERROR_MESSAGES: Record<string, string> = {
  email_challenge_invalid: "Код неверен или сессия изменилась. Запросите новый код.",
  email_challenge_expired: "Срок действия кода истёк. Запросите новый код.",
  email_delivery_failed: "Не удалось отправить код. Попробуйте ещё раз позже.",
  auth_rate_limited: "Слишком много попыток. Повторите позже.",
  installation_identity_missing: "Сессия устройства потеряна. Запросите новый код.",
  account_link_unavailable: "Этот вход нельзя завершить в текущей сессии.",
  identity_already_linked: "Этот email уже привязан к другому аккаунту.",
  sync_cursor_expired: "История синхронизации устарела. Выполняется полная сверка данных.",
};

export class ApiError extends Error {
  public readonly status: number;
  public readonly code: string | null;
  public readonly payload: unknown;

  constructor(message: string, status: number, payload: unknown) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.payload = payload;
    this.code =
      payload && typeof payload === "object" && typeof (payload as { code?: unknown }).code === "string"
        ? String((payload as { code: string }).code)
        : null;
  }
}

export class OfflineMutationQueuedError extends Error {
  constructor() {
    super("Сеть недоступна. Изменение сохранено на устройстве и будет отправлено при синхронизации.");
    this.name = "OfflineMutationQueuedError";
  }
}

export function loadLegacyStoredIdentity(): InstallIdentity | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = localStorage.getItem(STORAGE_IDENTITY);
    if (raw) {
      const parsed = JSON.parse(raw) as InstallIdentity;
      if (parsed.installation_id && parsed.installation_credential?.length >= 43) {
        return parsed;
      }
    }
  } catch {
    // Ignore storage parse errors
  }
  return null;
}

export function clearLegacyStoredAuth(): void {
  if (typeof window === "undefined") return;
  try {
    localStorage.removeItem(STORAGE_SESSION);
    localStorage.removeItem(STORAGE_IDENTITY);
  } catch {
    // Ignore storage errors
  }
}

// ---------------------------------------------------------------------------
// Core API Client Class
// ---------------------------------------------------------------------------
export class ApiClient {
  private base: string;
  private session: GuestBootstrapResponse | null = null;
  private refreshingPromise: Promise<string | null> | null = null;

  constructor() {
    this.base = "";
  }

  public setBase(url: string) {
    this.base = url.replace(/\/$/, "");
  }

  public getBase(): string {
    return this.base;
  }

  public setSession(session: GuestBootstrapResponse | null) {
    this.session = session;
  }

  public getSession(): GuestBootstrapResponse | null {
    return this.session;
  }

  private queueMutationAfterNetworkFailure(error: unknown, operation: SyncOperation): never {
    if (error instanceof ApiError) throw error;
    const userId = this.session?.user.id;
    if (!userId) throw error;
    enqueueSyncOperation(userId, operation);
    throw new OfflineMutationQueuedError();
  }

  private clearQueuedEntity(entityType: SyncEntityType, entityId: string): void {
    const userId = this.session?.user.id;
    if (userId) discardEntityOperation(userId, entityType, entityId);
  }

  public normalizeError(err: unknown): string {
    if (typeof err === "string") return err;
    if (err instanceof Error) return err.message;
    if (err && typeof err === "object") {
      const obj = err as Record<string, unknown>;
      if (typeof obj.detail === "string") return obj.detail;
      if (typeof obj.message === "string") return obj.message;
      if (Array.isArray(obj.non_field_errors)) return obj.non_field_errors.join(", ");
      const firstVal = Object.values(obj)[0];
      if (Array.isArray(firstVal)) return firstVal.join(", ");
      if (typeof firstVal === "string") return firstVal;
    }
    return "Неизвестная ошибка";
  }

  public async request<T>(path: string, options: RequestInit = {}): Promise<T> {
    const url = path.startsWith("http") ? path : `${this.base}${path.startsWith("/") ? "" : "/"}${path}`;
    const headers = new Headers();
    headers.set("Content-Type", "application/json");
    headers.set("X-Request-ID", generateUuidV7());

    if (options.headers) {
      new Headers(options.headers).forEach((value, key) => {
        headers.set(key, value);
      });
    }

    if (this.session?.access_token) {
      headers.set("Authorization", `Bearer ${this.session.access_token}`);
    }

    const method = (options.method || "GET").toUpperCase();
    const fetchOptions: RequestInit = {
      ...options,
      headers,
      ...(method === "GET" ? { cache: options.cache || "no-cache" } : {}),
    };
    let response = await fetch(url, fetchOptions);

    // Refresh is handled by the same-origin BFF; the refresh credential is HttpOnly.
    if (response.status === 401 && this.session?.access_token && !path.includes("/auth/")) {
      const newToken = await this.performTokenRefresh();
      if (newToken) {
        headers.set("Authorization", `Bearer ${newToken}`);
        response = await fetch(url, fetchOptions);
      }
    }

    return this.parseResponse<T>(response);
  }

  private async parseResponse<T>(response: Response): Promise<T> {
    if (response.status === 204) {
      return {} as T;
    }

    const text = await response.text();
    let payload: unknown = null;
    if (text) {
      try {
        payload = JSON.parse(text);
      } catch {
        payload = text;
      }
    }

    if (!response.ok) {
      let message = `HTTP ${response.status}`;
      if (payload && typeof payload === "object") {
        const p = payload as Record<string, unknown>;
        const localizedMessage =
          typeof p.code === "string" ? API_ERROR_MESSAGES[p.code] : undefined;
        if (localizedMessage) message = localizedMessage;
        else if (p.detail) message = String(p.detail);
        else if (p.non_field_errors && Array.isArray(p.non_field_errors)) {
          message = p.non_field_errors.join(", ");
        } else {
          const firstKey = Object.keys(p)[0];
          if (firstKey) {
            const val = p[firstKey];
            message = `${firstKey}: ${Array.isArray(val) ? val.join(", ") : String(val)}`;
          }
        }
      }
      throw new ApiError(message, response.status, payload);
    }

    return payload as T;
  }

  private async webAuthRequest<T>(path: string, options: RequestInit = {}): Promise<T> {
    const headers = new Headers(options.headers);
    headers.set("Content-Type", "application/json");
    headers.set("X-Request-ID", generateUuidV7());
    if (this.session?.access_token) {
      headers.set("Authorization", `Bearer ${this.session.access_token}`);
    }
    const response = await fetch(`/api/web-auth${path}`, {
      ...options,
      headers,
      cache: "no-store",
    });
    return this.parseResponse<T>(response);
  }

  private async performTokenRefresh(): Promise<string | null> {
    if (this.refreshingPromise) {
      return this.refreshingPromise;
    }
    this.refreshingPromise = (async () => {
      try {
        const session = await this.webAuthRequest<GuestBootstrapResponse>("/refresh", {
          method: "POST",
        });
        this.setSession(session);
        return session.access_token;
      } catch {
        this.setSession(null);
        return null;
      } finally {
        this.refreshingPromise = null;
      }
    })();
    return this.refreshingPromise;
  }

  // -------------------------------------------------------------------------
  // Health
  // -------------------------------------------------------------------------
  public async getHealthLive(): Promise<{ status: string }> {
    return this.request<{ status: string }>("/api/v1/health/live");
  }

  public async getHealthReady(): Promise<{ status: string; checks?: Record<string, unknown> }> {
    return this.request<{ status: string; checks?: Record<string, unknown> }>("/api/v1/health/ready");
  }

  // -------------------------------------------------------------------------
  // Auth
  // -------------------------------------------------------------------------
  public async restoreSession(): Promise<GuestBootstrapResponse | null> {
    const token = await this.performTokenRefresh();
    return token ? this.session : null;
  }

  public async adoptLegacyInstallation(identity: InstallIdentity): Promise<void> {
    await this.webAuthRequest<void>("/installation", {
      method: "POST",
      body: JSON.stringify(identity),
    });
  }

  public async bootstrapGuest(locale: SupportedLocale = "ru"): Promise<GuestBootstrapResponse> {
    const payload: GuestBootstrapRequest = {
      locale,
      app_version: "1.0.0",
    };
    const response = await this.webAuthRequest<GuestBootstrapResponse>("/guest", {
      method: "POST",
      body: JSON.stringify(payload),
    });
    this.setSession(response);
    return response;
  }

  public async logout(): Promise<void> {
    try {
      await this.webAuthRequest<void>("/logout", { method: "POST" });
    } finally {
      this.setSession(null);
    }
  }

  public async startEmailChallenge(email: string): Promise<EmailChallenge> {
    return this.webAuthRequest<EmailChallenge>("/email/start", {
      method: "POST",
      body: JSON.stringify({ email }),
    });
  }

  public async verifyEmailChallenge(input: {
    challenge_id: string;
    code: string;
    idempotency_key: string;
  }): Promise<EmailVerificationResponse> {
    const session = await this.webAuthRequest<EmailVerificationResponse>("/email/verify", {
      method: "POST",
      body: JSON.stringify(input),
    });
    this.setSession(session);
    return session;
  }

  // -------------------------------------------------------------------------
  // Quran Catalog
  // -------------------------------------------------------------------------
  public async getEditions(): Promise<QuranEdition[]> {
    return this.request<QuranEdition[]>("/api/v1/quran/editions");
  }

  public async getEdition(edition: string): Promise<QuranEdition> {
    return this.request<QuranEdition>(`/api/v1/quran/editions/${edition}`);
  }

  public async getSurahs(edition: string): Promise<Surah[]> {
    return this.request<Surah[]>(`/api/v1/quran/editions/${edition}/surahs`);
  }

  public async getSurah(edition: string, surahNumber: number): Promise<Surah> {
    return this.request<Surah>(`/api/v1/quran/editions/${edition}/surahs/${surahNumber}`);
  }

  public async getAyahs(edition: string, surahNumber: number): Promise<Ayah[]> {
    return this.request<Ayah[]>(`/api/v1/quran/editions/${edition}/surahs/${surahNumber}/ayahs`);
  }

  public async getAyah(edition: string, surahNumber: number, ayahNumber: number): Promise<Ayah> {
    return this.request<Ayah>(`/api/v1/quran/editions/${edition}/ayahs/${surahNumber}/${ayahNumber}`);
  }

  public async getPage(edition: string, pageNumber: number): Promise<MushafPage> {
    return this.request<MushafPage>(`/api/v1/quran/editions/${edition}/pages/${pageNumber}`);
  }

  public async getJuzList(edition: string): Promise<Juz[]> {
    return this.request<Juz[]>(`/api/v1/quran/editions/${edition}/juz`);
  }

  public async getHizbList(edition: string): Promise<Hizb[]> {
    return this.request<Hizb[]>(`/api/v1/quran/editions/${edition}/hizb`);
  }

  public async getRubElHizbList(edition: string): Promise<RubElHizb[]> {
    return this.request<RubElHizb[]>(`/api/v1/quran/editions/${edition}/rub-el-hizb`);
  }

  // -------------------------------------------------------------------------
  // Audio Catalog & Playback
  // -------------------------------------------------------------------------
  public async getReciters(cursor?: string): Promise<PaginatedResponse<Reciter>> {
    const params = new URLSearchParams();
    if (cursor) params.set("cursor", cursor);
    const qs = params.toString() ? `?${params.toString()}` : "";
    return this.request<PaginatedResponse<Reciter>>(`/api/v1/reciters${qs}`);
  }

  public async getReciter(reciterId: string): Promise<Reciter> {
    return this.request<Reciter>(`/api/v1/reciters/${reciterId}`);
  }

  public async getRecitations(params: { reciter_id?: string; quran_edition?: string; style?: string; cursor?: string } = {}): Promise<PaginatedResponse<Recitation>> {
    const query = new URLSearchParams();
    if (params.reciter_id) query.set("reciter_id", params.reciter_id);
    if (params.quran_edition) query.set("quran_edition", params.quran_edition);
    if (params.style) query.set("style", params.style);
    if (params.cursor) query.set("cursor", params.cursor);
    const qs = query.toString() ? `?${query.toString()}` : "";
    return this.request<PaginatedResponse<Recitation>>(`/api/v1/recitations${qs}`);
  }

  public async getTracks(recitationId: string, params: { scope?: string; cursor?: string; page_size?: number } = {}): Promise<PaginatedResponse<AudioTrack>> {
    const query = new URLSearchParams();
    if (params.scope) query.set("scope", params.scope);
    if (params.cursor) query.set("cursor", params.cursor);
    if (params.page_size) query.set("page_size", String(params.page_size));
    const qs = query.toString() ? `?${query.toString()}` : "";
    return this.request<PaginatedResponse<AudioTrack>>(`/api/v1/recitations/${recitationId}/tracks${qs}`);
  }

  public async getSurahPlayback(recitationId: string, surahNumber: number): Promise<SurahPlayback> {
    return this.request<SurahPlayback>(`/api/v1/recitations/${recitationId}/surahs/${surahNumber}`);
  }

  public async getAyahPlayback(recitationId: string, surahNumber: number, ayahNumber: number): Promise<{ track: AudioTrack; segment: AyahAudioSegment }> {
    return this.request<{ track: AudioTrack; segment: AyahAudioSegment }>(`/api/v1/recitations/${recitationId}/ayahs/${surahNumber}/${ayahNumber}`);
  }

  // -------------------------------------------------------------------------
  // Prayer Times
  // -------------------------------------------------------------------------
  public async getPrayerMethods(): Promise<PrayerMethodsResponse> {
    return this.request<PrayerMethodsResponse>("/api/v1/prayer/methods");
  }

  public async calculatePrayer(payload: PrayerCalculationRequest): Promise<PrayerCalculationResponse> {
    return this.request<PrayerCalculationResponse>("/api/v1/prayer/calculate", {
      method: "POST",
      body: JSON.stringify(payload),
    });
  }

  public async getPrayerProfile(): Promise<PrayerProfile> {
    return this.request<PrayerProfile>("/api/v1/me/prayer-profile");
  }

  public async savePrayerProfile(data: {
    base_revision: number;
    method_config_id: string;
    method_checksum_sha256: string;
    asr_method: "standard" | "hanafi";
    high_latitude_rule: PrayerProfile["high_latitude_rule"];
    polar_resolution: PrayerProfile["polar_resolution"];
    adjustments: PrayerAdjustments;
    timezone_mode: PrayerProfile["timezone_mode"];
    fixed_timezone?: string;
  }): Promise<PrayerProfile> {
    return this.request<PrayerProfile>("/api/v1/me/prayer-profile", {
      method: "PUT",
      body: JSON.stringify({ ...data, client_updated_at: new Date().toISOString() }),
    });
  }

  // -------------------------------------------------------------------------
  // Reading Position, Bookmarks & Sync
  // -------------------------------------------------------------------------
  public async getReadingPosition(edition: string): Promise<ReadingPosition> {
    const position = await this.request<ReadingPosition>(`/api/v1/me/reading-position/${edition}`);
    const userId = this.session?.user.id;
    if (userId && position.id) rememberReadingPositionId(userId, edition, position.id);
    return position;
  }

  public async saveReadingPosition(
    edition: string,
    data: {
      page_number: number;
      surah_number?: number;
      ayah_number?: number;
      intra_page_anchor?: { line_number?: number; x_ratio?: number; y_ratio?: number };
      progress_percent?: number | string;
      base_revision: number;
    },
  ): Promise<ReadingPosition> {
    const now = new Date().toISOString();
    const progressVal =
      typeof data.progress_percent === "number"
        ? data.progress_percent.toFixed(2)
        : data.progress_percent || "0.00";

    const body: Record<string, unknown> = {
      edition_code: edition,
      page_number: data.page_number,
      progress_percent: progressVal,
      last_read_at: now,
      client_updated_at: now,
      base_revision: data.base_revision,
    };

    if (data.surah_number && data.ayah_number) {
      body.surah_number = data.surah_number;
      body.ayah_number = data.ayah_number;
    }

    if (data.intra_page_anchor) {
      body.intra_page_anchor = data.intra_page_anchor;
    }

    const userId = this.session?.user.id;
    let entityId = userId ? getReadingPositionId(userId, edition) : null;
    let baseRevision = data.base_revision;
    if (!entityId) {
      try {
        const current = await this.getReadingPosition(edition);
        entityId = current.id || null;
        baseRevision = current.revision;
        body.base_revision = current.revision;
      } catch (error) {
        if (error instanceof ApiError && error.status !== 404) throw error;
      }
    }
    entityId ||= generateUuidV7();
    const operation: SyncOperation = {
      operation_id: generateUuidV7(),
      entity_type: "reading_position",
      entity_id: entityId,
      action: "upsert",
      base_revision: baseRevision,
      client_updated_at: now,
      payload: Object.fromEntries(
        Object.entries(body).filter(([key]) => key !== "base_revision" && key !== "client_updated_at"),
      ),
    };

    try {
      const saved = await this.request<ReadingPosition>(`/api/v1/me/reading-position/${edition}`, {
        method: "PUT",
        body: JSON.stringify(body),
      });
      this.clearQueuedEntity("reading_position", entityId);
      if (userId && saved.id) rememberReadingPositionId(userId, edition, saved.id);
      return saved;
    } catch (error) {
      return this.queueMutationAfterNetworkFailure(error, operation);
    }
  }

  public async getBookmarks(cursor?: string): Promise<PaginatedResponse<Bookmark>> {
    const params = new URLSearchParams({ page_size: "50" });
    if (cursor) params.set("cursor", cursor);
    return this.request<PaginatedResponse<Bookmark>>(`/api/v1/me/bookmarks?${params.toString()}`);
  }

  public async getBookmark(bookmarkId: string): Promise<Bookmark> {
    return this.request<Bookmark>(`/api/v1/me/bookmarks/${bookmarkId}`);
  }

  public async createBookmark(data: {
    edition_code: string;
    page_number?: number;
    surah_number?: number;
    ayah_number?: number;
    label?: string;
    color_key?: string;
    note?: string;
  }): Promise<Bookmark> {
    const now = new Date().toISOString();
    const entityId = generateUuidV7();
    const body: Record<string, unknown> = {
      id: entityId,
      edition_code: data.edition_code,
      label: data.label || "Закладка",
      color_key: data.color_key || "teal",
      client_updated_at: now,
    };

    if (data.page_number) body.page_number = data.page_number;
    if (data.surah_number && data.ayah_number) {
      body.surah_number = data.surah_number;
      body.ayah_number = data.ayah_number;
    }
    if (data.note) body.note = data.note;

    const operation: SyncOperation = {
      operation_id: generateUuidV7(),
      entity_type: "bookmark",
      entity_id: entityId,
      action: "upsert",
      base_revision: 0,
      client_updated_at: now,
      payload: Object.fromEntries(
        Object.entries(body).filter(([key]) => key !== "id" && key !== "client_updated_at"),
      ),
    };
    try {
      const bookmark = await this.request<Bookmark>("/api/v1/me/bookmarks", {
        method: "POST",
        body: JSON.stringify(body),
      });
      this.clearQueuedEntity("bookmark", entityId);
      return bookmark;
    } catch (error) {
      return this.queueMutationAfterNetworkFailure(error, operation);
    }
  }

  public async updateBookmark(
    bookmarkId: string,
    data: {
      label?: string;
      color_key?: string;
      note?: string;
      base_revision: number;
    },
  ): Promise<Bookmark> {
    const now = new Date().toISOString();
    const { base_revision: baseRevision, ...payload } = data;
    const operation: SyncOperation = {
      operation_id: generateUuidV7(),
      entity_type: "bookmark",
      entity_id: bookmarkId,
      action: "upsert",
      base_revision: baseRevision,
      client_updated_at: now,
      payload,
    };
    try {
      const bookmark = await this.request<Bookmark>(`/api/v1/me/bookmarks/${bookmarkId}`, {
        method: "PATCH",
        body: JSON.stringify({ ...data, client_updated_at: now }),
      });
      this.clearQueuedEntity("bookmark", bookmarkId);
      return bookmark;
    } catch (error) {
      return this.queueMutationAfterNetworkFailure(error, operation);
    }
  }

  public async deleteBookmark(bookmarkId: string, baseRevision = 1): Promise<Bookmark> {
    const now = new Date().toISOString();
    const params = new URLSearchParams({
      base_revision: String(baseRevision),
      client_updated_at: now,
    });
    const operation: SyncOperation = {
      operation_id: generateUuidV7(),
      entity_type: "bookmark",
      entity_id: bookmarkId,
      action: "delete",
      base_revision: baseRevision,
      client_updated_at: now,
      payload: {},
    };
    try {
      const bookmark = await this.request<Bookmark>(`/api/v1/me/bookmarks/${bookmarkId}?${params}`, {
        method: "DELETE",
      });
      this.clearQueuedEntity("bookmark", bookmarkId);
      return bookmark;
    } catch (error) {
      return this.queueMutationAfterNetworkFailure(error, operation);
    }
  }

  public async syncPush(operations: SyncOperation[]): Promise<SyncPushResponse> {
    return this.request<SyncPushResponse>("/api/v1/sync/push", {
      method: "POST",
      body: JSON.stringify({ operations }),
    });
  }

  public async syncPull(options: {
    cursor?: number;
    limit?: number;
    full_resync?: boolean;
    page_token?: string;
  } = {}): Promise<SyncPullResponse> {
    const params = new URLSearchParams({ limit: String(options.limit || 100) });
    if (options.full_resync) params.set("full_resync", "true");
    else if (options.cursor !== undefined) params.set("cursor", String(options.cursor));
    if (options.page_token) params.set("page_token", options.page_token);
    return this.request<SyncPullResponse>(`/api/v1/sync/pull?${params.toString()}`);
  }

  public getPendingSyncCount(): number {
    const userId = this.session?.user.id;
    return userId ? getPendingSyncCount(userId) : 0;
  }

  public async syncNow(limit = 100): Promise<SyncRunResult> {
    const userId = this.session?.user.id;
    if (!userId) throw new Error("Для синхронизации требуется активная сессия.");

    let pushed = 0;
    let conflicts = 0;
    let changes = 0;
    let fullResync = false;
    let snapshotEntities = 0;

    const flushOutbox = async () => {
      const attempts = new Map<string, number>();
      for (let cycle = 0; cycle < 20; cycle += 1) {
        const operations = getPendingSyncOperations(userId).slice(0, 100);
        if (operations.length === 0) return;
        const response = await this.syncPush(operations);
        const terminalIds: string[] = [];
        let rebased = false;

        for (const result of response.results) {
          const operation = operations.find(
            (candidate) => candidate.operation_id === result.operation_id,
          );
          if (!operation) continue;
          if (result.outcome === "accepted") {
            terminalIds.push(operation.operation_id);
            pushed += 1;
            if (result.entity?.entity_type === "reading_position") {
              rememberReadingPositionId(
                userId,
                result.entity.edition_code,
                result.entity.id,
              );
            }
            continue;
          }

          const attempt = (attempts.get(operation.operation_id) || 0) + 1;
          const current = result.entity;
          const canRebase =
            attempt <= 3 &&
            Boolean(current) &&
            ["revision_mismatch", "entity_identity_mismatch"].includes(
              result.conflict_reason || "",
            );
          const canRemap =
            attempt <= 3 &&
            operation.base_revision === 0 &&
            ["entity_id_unavailable", "entity_id_not_reusable"].includes(
              result.conflict_reason || "",
            );

          if (canRebase && current) {
            const replacement: SyncOperation = {
              ...operation,
              operation_id: generateUuidV7(),
              entity_id: current.id,
              base_revision: current.revision,
              client_updated_at: new Date().toISOString(),
            };
            replaceSyncOperation(userId, operation.operation_id, replacement);
            attempts.set(replacement.operation_id, attempt);
            rebased = true;
          } else if (canRemap) {
            const replacement: SyncOperation = {
              ...operation,
              operation_id: generateUuidV7(),
              entity_id: generateUuidV7(),
              client_updated_at: new Date().toISOString(),
            };
            replaceSyncOperation(userId, operation.operation_id, replacement);
            attempts.set(replacement.operation_id, attempt);
            rebased = true;
          } else {
            terminalIds.push(operation.operation_id);
            conflicts += 1;
          }
        }

        removeSyncOperations(userId, terminalIds);
        if (!rebased && terminalIds.length === 0) return;
      }
      throw new Error("Очередь синхронизации не сошлась после повторных попыток.");
    };

    const pullIncremental = async () => {
      let cursor = getSyncCursor(userId);
      while (true) {
        const response = await this.syncPull({ cursor, limit });
        if (response.mode !== "incremental") {
          throw new Error("Сервер вернул неожиданный режим синхронизации.");
        }
        changes += response.changes.length;
        cursor = response.next_cursor;
        setSyncCursor(userId, cursor);
        if (!response.has_more) return cursor;
      }
    };

    const collectFullSnapshot = async () => {
      for (let restart = 0; restart < 2; restart += 1) {
        let pageToken: string | undefined;
        let snapshotCursor = 0;
        const entities: SyncEntity[] = [];
        try {
          for (let page = 0; page < 1000; page += 1) {
            const response = await this.syncPull({
              full_resync: true,
              limit,
              ...(pageToken ? { page_token: pageToken } : {}),
            });
            if (response.mode !== "full_resync") {
              throw new Error("Сервер не вернул полный снимок синхронизации.");
            }
            if (page === 0) snapshotCursor = response.snapshot_cursor;
            else if (snapshotCursor !== response.snapshot_cursor) {
              throw new Error("Курсор полного снимка изменился во время загрузки.");
            }
            entities.push(...response.entities);
            pageToken = response.next_page_token || undefined;
            if (!response.has_more) {
              rebaseOutboxFromSnapshot(userId, entities);
              setSyncCursor(userId, snapshotCursor);
              snapshotEntities = entities.length;
              return;
            }
            if (!pageToken) {
              throw new Error("Сервер не вернул токен следующей страницы снимка.");
            }
          }
        } catch (error) {
          const tokenInvalid =
            error instanceof ApiError && error.code === "full_resync_token_invalid";
          if (tokenInvalid && restart === 0) continue;
          throw error;
        }
      }
      throw new Error("Полный снимок превысил допустимое число страниц.");
    };

    await flushOutbox();
    try {
      await pullIncremental();
    } catch (error) {
      if (!(error instanceof ApiError) || error.status !== 410 || error.code !== "sync_cursor_expired") {
        throw error;
      }
      fullResync = true;
      await collectFullSnapshot();
      await flushOutbox();
      await pullIncremental();
    }

    return {
      pushed,
      conflicts,
      changes,
      full_resync: fullResync,
      snapshot_entities: snapshotEntities,
      cursor: getSyncCursor(userId),
      pending: getPendingSyncCount(userId),
    };
  }

  // -------------------------------------------------------------------------
  // Local reminder rules
  // -------------------------------------------------------------------------
  public async getReminders(): Promise<ReminderSnapshot> {
    return this.request<ReminderSnapshot>("/api/v1/me/reminders");
  }

  public async getReminder(reminderId: string): Promise<Reminder> {
    return this.request<Reminder>(`/api/v1/me/reminders/${reminderId}`);
  }

  public async createReminder(data: {
    reminder_type: Reminder["reminder_type"];
    schedule: ReminderSchedule;
    review_target?: { start_ayah_id: string; end_ayah_id: string };
    weekdays_mask: number;
    timezone: ReminderTimezone;
    signal: Reminder["signal"];
    is_enabled: boolean;
  }): Promise<Reminder> {
    const entityId = generateUuidV7();
    const now = new Date().toISOString();
    const operation: SyncOperation = {
      operation_id: generateUuidV7(),
      entity_type: "reminder",
      entity_id: entityId,
      action: "upsert",
      base_revision: 0,
      client_updated_at: now,
      payload: { ...data },
    };
    try {
      const reminder = await this.request<Reminder>("/api/v1/me/reminders", {
        method: "POST",
        body: JSON.stringify({
          ...data,
          id: entityId,
          base_revision: 0,
          client_updated_at: now,
        }),
      });
      this.clearQueuedEntity("reminder", entityId);
      return reminder;
    } catch (error) {
      return this.queueMutationAfterNetworkFailure(error, operation);
    }
  }

  public async updateReminder(
    reminderId: string,
    data: Partial<{
      reminder_type: Reminder["reminder_type"];
      schedule: ReminderSchedule;
      review_target: { start_ayah_id: string; end_ayah_id: string } | null;
      weekdays_mask: number;
      timezone: ReminderTimezone;
      signal: Reminder["signal"];
      is_enabled: boolean;
    }> & { base_revision: number },
  ): Promise<Reminder> {
    const now = new Date().toISOString();
    const { base_revision: baseRevision, ...payload } = data;
    const operation: SyncOperation = {
      operation_id: generateUuidV7(),
      entity_type: "reminder",
      entity_id: reminderId,
      action: "upsert",
      base_revision: baseRevision,
      client_updated_at: now,
      payload,
    };
    try {
      const reminder = await this.request<Reminder>(`/api/v1/me/reminders/${reminderId}`, {
        method: "PATCH",
        body: JSON.stringify({ ...data, client_updated_at: now }),
      });
      this.clearQueuedEntity("reminder", reminderId);
      return reminder;
    } catch (error) {
      return this.queueMutationAfterNetworkFailure(error, operation);
    }
  }

  public async deleteReminder(reminderId: string, baseRevision: number): Promise<Reminder> {
    const now = new Date().toISOString();
    const operation: SyncOperation = {
      operation_id: generateUuidV7(),
      entity_type: "reminder",
      entity_id: reminderId,
      action: "delete",
      base_revision: baseRevision,
      client_updated_at: now,
      payload: {},
    };
    try {
      const reminder = await this.request<Reminder>(`/api/v1/me/reminders/${reminderId}`, {
        method: "DELETE",
        body: JSON.stringify({
          base_revision: baseRevision,
          client_updated_at: now,
        }),
      });
      this.clearQueuedEntity("reminder", reminderId);
      return reminder;
    } catch (error) {
      return this.queueMutationAfterNetworkFailure(error, operation);
    }
  }

  // -------------------------------------------------------------------------
  // Feedback
  // -------------------------------------------------------------------------
  public async getFeedbackTickets(cursor?: string): Promise<PaginatedResponse<FeedbackTicket>> {
    const params = new URLSearchParams({ page_size: "25" });
    if (cursor) params.set("cursor", cursor);
    return this.request<PaginatedResponse<FeedbackTicket>>(
      `/api/v1/feedback/tickets?${params}`,
    );
  }

  public async createFeedbackTicket(payload: {
    category: string;
    subject: string;
    message: string;
    context?: {
      route?: string;
      app_version?: string;
      client_platform?: DevicePlatform;
    };
  }): Promise<FeedbackTicketDetail> {
    return this.request<FeedbackTicketDetail>("/api/v1/feedback/tickets", {
      method: "POST",
      body: JSON.stringify({
        ...payload,
        client_request_id: generateUuidV7(),
        client_message_id: generateUuidV7(),
        locale: "ru",
        context: {
          route: payload.context?.route || "/profile",
          app_version: payload.context?.app_version || "1.0.0",
          client_platform: payload.context?.client_platform || "web",
        },
      }),
    });
  }

  public async getFeedbackTicket(publicId: string): Promise<FeedbackTicketDetail> {
    return this.request<FeedbackTicketDetail>(`/api/v1/feedback/tickets/${publicId}`);
  }

  public async sendFeedbackMessage(
    publicId: string,
    message: string,
  ): Promise<FeedbackTicketDetail> {
    return this.request<FeedbackTicketDetail>(`/api/v1/feedback/tickets/${publicId}/messages`, {
      method: "POST",
      body: JSON.stringify({ client_message_id: generateUuidV7(), body: message }),
    });
  }

  public async closeFeedbackTicket(
    publicId: string,
    reason = "Закрыто пользователем",
  ): Promise<FeedbackTicketDetail> {
    return this.request<FeedbackTicketDetail>(`/api/v1/feedback/tickets/${publicId}/close`, {
      method: "POST",
      body: JSON.stringify({ reason }),
    });
  }

  public async reopenFeedbackTicket(
    publicId: string,
    reason = "Повторно открыто пользователем",
  ): Promise<FeedbackTicketDetail> {
    return this.request<FeedbackTicketDetail>(`/api/v1/feedback/tickets/${publicId}/reopen`, {
      method: "POST",
      body: JSON.stringify({ reason }),
    });
  }
}

export const api = new ApiClient();
