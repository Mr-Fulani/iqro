/**
 * Quran Platform - Typed API Client
 * Compatible with Django backend specification and DRF serializers.
 */

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
  installation_id: string;
  installation_credential: string;
  platform: DevicePlatform;
  locale: SupportedLocale;
  app_version: string;
};

export type UserSummary = {
  id: string;
  status: "guest" | "active" | "pending_deletion" | "suspended" | "deleted";
  preferred_locale: SupportedLocale;
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
  refresh_token: string;
  refresh_expires_in: number;
  refresh_expires_at: string;
};

export type GuestBootstrapResponse = AuthTokens & {
  user: UserSummary;
  device: DeviceSummary;
};

export type InstallIdentity = {
  installation_id: string;
  installation_credential: string;
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

// ---------------------------------------------------------------------------
// Reading, Bookmarks & Sync Types
// ---------------------------------------------------------------------------
export type ReadingPosition = {
  id?: string;
  edition_code: string;
  page_number: number;
  surah_number?: number | null;
  ayah_number?: number | null;
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
  surah_number?: number | null;
  ayah_number?: number | null;
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

export type SyncPullResponse = {
  mode: "incremental" | "full_resync";
  has_more: boolean;
  next_cursor?: number;
  next_page_token?: string | null;
  changes?: unknown[];
  entities?: unknown[];
  snapshot_cursor?: number;
};

export type Reminder = {
  id: string;
  type: string;
  title: string;
  time_of_day: string;
  days_of_week: number[];
  is_active: boolean;
  revision: number;
  created_at: string;
  updated_at: string;
};

export type FeedbackTicket = {
  public_id: string;
  category: "quran_content" | "audio_timing" | "prayer_calculation" | "general" | string;
  status: "open" | "in_review" | "resolved" | "closed";
  subject: string;
  created_at: string;
  updated_at: string;
  messages_count: number;
};

export type FeedbackMessage = {
  id: string;
  author_type: "user" | "support" | "system";
  content: string;
  created_at: string;
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

export function generateInstallationCredential(): string {
  const bytes = new Uint8Array(32);
  if (typeof crypto !== "undefined" && crypto.getRandomValues) {
    crypto.getRandomValues(bytes);
  } else {
    for (let i = 0; i < 32; i += 1) bytes[i] = Math.floor(Math.random() * 256);
  }

  let binary = "";
  for (let i = 0; i < bytes.length; i += 1) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/g, "");
}

// ---------------------------------------------------------------------------
// Storage Keys
// ---------------------------------------------------------------------------
const STORAGE_IDENTITY = "quran_platform_identity_v1";
const STORAGE_SESSION = "quran_platform_session_v1";

export function loadStoredIdentity(): InstallIdentity {
  if (typeof window === "undefined") {
    return { installation_id: generateUuidV7(), installation_credential: generateInstallationCredential() };
  }
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
  const created: InstallIdentity = {
    installation_id: generateUuidV7(),
    installation_credential: generateInstallationCredential(),
  };
  try {
    localStorage.setItem(STORAGE_IDENTITY, JSON.stringify(created));
  } catch {
    // Ignore storage write errors
  }
  return created;
}

export function loadStoredSession(): GuestBootstrapResponse | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = localStorage.getItem(STORAGE_SESSION);
    if (raw) {
      return JSON.parse(raw) as GuestBootstrapResponse;
    }
  } catch {
    // Ignore storage parse errors
  }
  return null;
}

export function saveStoredSession(session: GuestBootstrapResponse | null): void {
  if (typeof window === "undefined") return;
  try {
    if (session) {
      localStorage.setItem(STORAGE_SESSION, JSON.stringify(session));
    } else {
      localStorage.removeItem(STORAGE_SESSION);
    }
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
    if (typeof window !== "undefined") {
      this.session = loadStoredSession();
    }
  }

  public setBase(url: string) {
    this.base = url.replace(/\/$/, "");
  }

  public getBase(): string {
    return this.base;
  }

  public setSession(session: GuestBootstrapResponse | null) {
    this.session = session;
    saveStoredSession(session);
  }

  public getSession(): GuestBootstrapResponse | null {
    return this.session;
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

    // Handle 401 token refresh if refresh_token is present
    if (response.status === 401 && this.session?.refresh_token && !path.includes("/auth/")) {
      const newToken = await this.performTokenRefresh();
      if (newToken) {
        headers.set("Authorization", `Bearer ${newToken}`);
        response = await fetch(url, fetchOptions);
      }
    }

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
        if (p.detail) message = String(p.detail);
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
      throw new Error(message);
    }

    return payload as T;
  }

  private async performTokenRefresh(): Promise<string | null> {
    if (this.refreshingPromise) {
      return this.refreshingPromise;
    }
    this.refreshingPromise = (async () => {
      if (!this.session?.refresh_token) return null;
      try {
        const result = await fetch(`${this.base}/api/v1/auth/token/refresh`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ refresh_token: this.session.refresh_token }),
        });
        if (!result.ok) {
          this.setSession(null);
          return null;
        }
        const data = (await result.json()) as AuthTokens;
        if (this.session) {
          const updated: GuestBootstrapResponse = {
            ...this.session,
            access_token: data.access_token,
            expires_in: data.expires_in,
            access_expires_at: data.access_expires_at,
            refresh_token: data.refresh_token,
            refresh_expires_in: data.refresh_expires_in,
            refresh_expires_at: data.refresh_expires_at,
          };
          this.setSession(updated);
          return data.access_token;
        }
        return null;
      } catch {
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
  public async bootstrapGuest(identity?: InstallIdentity, locale: SupportedLocale = "ru"): Promise<GuestBootstrapResponse> {
    const id = identity || loadStoredIdentity();
    const payload: GuestBootstrapRequest = {
      installation_id: id.installation_id,
      installation_credential: id.installation_credential,
      platform: "web",
      locale,
      app_version: "1.0.0",
    };
    const response = await this.request<GuestBootstrapResponse>("/api/v1/auth/guest", {
      method: "POST",
      body: JSON.stringify(payload),
    });
    this.setSession(response);
    return response;
  }

  public async logout(): Promise<void> {
    try {
      await this.request<void>("/api/v1/auth/logout", { method: "POST" });
    } finally {
      this.setSession(null);
    }
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

  // -------------------------------------------------------------------------
  // Reading Position, Bookmarks & Sync
  // -------------------------------------------------------------------------
  public async getReadingPosition(edition: string): Promise<ReadingPosition> {
    return this.request<ReadingPosition>(`/api/v1/me/reading-position/${edition}`);
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

    return this.request<ReadingPosition>(`/api/v1/me/reading-position/${edition}`, {
      method: "PUT",
      body: JSON.stringify(body),
    });
  }

  public async getBookmarks(cursor?: string): Promise<PaginatedResponse<Bookmark>> {
    const params = new URLSearchParams({ page_size: "50" });
    if (cursor) params.set("cursor", cursor);
    return this.request<PaginatedResponse<Bookmark>>(`/api/v1/me/bookmarks?${params.toString()}`);
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
    const body: Record<string, unknown> = {
      id: generateUuidV7(),
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

    return this.request<Bookmark>("/api/v1/me/bookmarks", {
      method: "POST",
      body: JSON.stringify(body),
    });
  }

  public async deleteBookmark(bookmarkId: string, baseRevision = 1): Promise<void> {
    const now = new Date().toISOString();
    return this.request<void>(`/api/v1/me/bookmarks/${bookmarkId}`, {
      method: "DELETE",
      body: JSON.stringify({
        base_revision: baseRevision,
        client_updated_at: now,
      }),
    });
  }

  public async syncPull(limit = 20): Promise<SyncPullResponse> {
    return this.request<SyncPullResponse>(`/api/v1/sync/pull?limit=${limit}`);
  }

  // -------------------------------------------------------------------------
  // Feedback
  // -------------------------------------------------------------------------
  public async getFeedbackTickets(): Promise<FeedbackTicket[]> {
    return this.request<FeedbackTicket[]>("/api/v1/feedback/tickets");
  }

  public async createFeedbackTicket(payload: {
    category: string;
    subject: string;
    message: string;
  }): Promise<FeedbackTicket> {
    return this.request<FeedbackTicket>("/api/v1/feedback/tickets", {
      method: "POST",
      body: JSON.stringify(payload),
    });
  }

  public async getFeedbackTicket(publicId: string): Promise<FeedbackTicket & { messages: FeedbackMessage[] }> {
    return this.request<FeedbackTicket & { messages: FeedbackMessage[] }>(`/api/v1/feedback/tickets/${publicId}`);
  }

  public async sendFeedbackMessage(publicId: string, message: string): Promise<FeedbackMessage> {
    return this.request<FeedbackMessage>(`/api/v1/feedback/tickets/${publicId}/messages`, {
      method: "POST",
      body: JSON.stringify({ content: message }),
    });
  }
}

export const api = new ApiClient();
