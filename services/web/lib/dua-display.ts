// Port of duaShowTransliteration / duaShowTranslation in preferences_store.dart:
// what du'a cards show besides the Arabic, which they always show.

export type DuaDisplay = { transliteration: boolean; translation: boolean };

export const DUA_DISPLAY_STORAGE_KEY = "iqro_dua_display_v1";
export const DEFAULT_DUA_DISPLAY: DuaDisplay = { transliteration: true, translation: true };

/** The stored choice; anything missing or unreadable shows the text. */
export function parseDuaDisplay(raw: string | null): DuaDisplay {
  if (!raw) return DEFAULT_DUA_DISPLAY;
  try {
    const parsed = JSON.parse(raw) as Partial<DuaDisplay> | null;
    return {
      transliteration: parsed?.transliteration !== false,
      translation: parsed?.translation !== false,
    };
  } catch {
    return DEFAULT_DUA_DISPLAY;
  }
}
