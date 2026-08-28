export type AutomaticReadingPayload = {
  id: string;
  timezone_name: string;
  started_at: string;
  ended_at: string;
  active_seconds: number;
  credited_pages: number;
  credited_ayahs: number;
  client_updated_at: string;
};

const STORAGE_KEY = "quran_platform_reading_sessions_v1";
const MAX_QUEUED_SESSIONS = 100;

export function loadReadingActivityQueue(): AutomaticReadingPayload[] {
  try {
    const value = JSON.parse(localStorage.getItem(STORAGE_KEY) || "[]") as unknown;
    return Array.isArray(value) ? (value as AutomaticReadingPayload[]) : [];
  } catch {
    return [];
  }
}

export function saveReadingActivityQueue(queue: AutomaticReadingPayload[]): void {
  try {
    if (queue.length === 0) localStorage.removeItem(STORAGE_KEY);
    else localStorage.setItem(STORAGE_KEY, JSON.stringify(queue.slice(-MAX_QUEUED_SESSIONS)));
  } catch {
    // Reading stays available when browser storage is restricted.
  }
}

export function enqueueReadingActivity(payload: AutomaticReadingPayload): void {
  const queue = loadReadingActivityQueue();
  if (!queue.some((item) => item.id === payload.id)) queue.push(payload);
  saveReadingActivityQueue(queue);
}

export function clearReadingActivityQueue(): void {
  try {
    localStorage.removeItem(STORAGE_KEY);
  } catch {
    // Logout still succeeds when browser storage is restricted.
  }
}
