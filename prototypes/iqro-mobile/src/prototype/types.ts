export type Locale = "ru" | "en" | "ar" | "tr";
export type Theme = "light" | "dark";
export type ReaderMode = "text" | "mushaf";

export type Route =
  | "onboarding-language"
  | "onboarding-goal"
  | "onboarding-norm"
  | "home"
  | "quran"
  | "reader"
  | "mushaf"
  | "audio"
  | "player"
  | "plan"
  | "prayer-reading"
  | "prayer"
  | "memorization"
  | "dua"
  | "dua-topic"
  | "dua-entry"
  | "favorites"
  | "more"
  | "account"
  | "settings";

export type SystemState =
  | "online"
  | "loading"
  | "offline"
  | "api-error"
  | "session-expired"
  | "sync-conflict"
  | "notifications-denied"
  | "geolocation-denied"
  | "no-audio"
  | "offline-unavailable";

export type PrayerCode = "fajr" | "dhuhr" | "asr" | "maghrib" | "isha";

export interface PlayerState {
  active: boolean;
  playing: boolean;
  reciterId: string;
  surah: number;
  ayah: number;
  progress: number;
  repeat: "off" | "ayah" | "range" | "surah";
  speed: number;
  pauseSeconds: number;
}

export interface PrototypeState {
  route: Route;
  previousRoute: Route;
  onboarded: boolean;
  locale: Locale;
  theme: Theme;
  goal: "reading" | "memorization" | "prayer" | "dua";
  dailyUnit: "minutes" | "pages" | "ayahs";
  dailyTarget: number;
  dailyAchieved: number;
  readerMode: ReaderMode;
  mushafId: number;
  mushafZoom: number;
  selectedAyah: number;
  lastPosition: { surah: number; ayah: number; page: number };
  quranBookmarks: string[];
  duaFavorites: number[];
  selectedDua: number;
  selectedReciter: string;
  player: PlayerState;
  prayerPages: Record<PrayerCode, number>;
  prayerNotifications: Record<PrayerCode, boolean>;
  afterPrayerPrompt: boolean;
  memorization: {
    startAyah: number;
    endAyah: number;
    targetRepetitions: number;
    completedRepetitions: number;
    pauseSeconds: number;
    assessment: "" | "again" | "hard" | "good";
  };
  systemState: SystemState;
  accountMode: "guest" | "verified";
  toast: string;
  modal: "" | "quick-jump" | "reader-settings" | "memorization-reset";
}
