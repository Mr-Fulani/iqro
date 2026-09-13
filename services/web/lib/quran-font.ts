import type { QuranFoundationMushafPage } from "./api";

type CachedFont = { face: FontFace; promise: Promise<FontFace>; users: number };
const fonts = new Map<string, CachedFont>();

export function quranFontFamily(mushafId: number, page: QuranFoundationMushafPage): string {
  return page.rendering.available && page.rendering.mode === "page-font"
    ? `qf-mushaf-${mushafId}-page-${page.page_number}` : `qf-mushaf-${mushafId}`;
}

function trimFonts() {
  for (const [key, entry] of fonts) {
    if (fonts.size <= 10) break;
    if (entry.users || entry.face.status === "loading") continue;
    document.fonts.delete(entry.face);
    fonts.delete(key);
  }
}

export function isQuranFontReady(family: string, url: string | undefined): boolean {
  return fonts.get(`${family}:${url}`)?.face.status === "loaded";
}

export function loadQuranFont(family: string, url: string | undefined): Promise<FontFace> {
  if (!isAllowedQuranFontUrl(url)) return Promise.reject(new Error("Unsupported Quran font URL"));
  const key = `${family}:${url}`;
  const cached = fonts.get(key);
  if (cached) {
    fonts.delete(key);
    fonts.set(key, cached);
    return cached.promise;
  }
  const format = url.endsWith(".ttf") ? "truetype" : "woff2";
  const face = new FontFace(family, `url("${url}") format("${format}")`, { display: "block" });
  const entry: CachedFont = { face, users: 0, promise: face.load().then((font) => {
    document.fonts.add(font);
    trimFonts();
    return font;
  }).catch((error: unknown) => { fonts.delete(key); throw error; }) };
  fonts.set(key, entry);
  return entry.promise;
}

export function retainQuranFont(family: string, url: string | undefined): () => void {
  const entry = fonts.get(`${family}:${url}`);
  if (entry) entry.users += 1;
  return () => { if (entry) entry.users -= 1; trimFonts(); };
}

export function isAllowedQuranFontUrl(value: string | undefined): value is string {
  if (!value) return false;
  try {
    const url = new URL(value);
    return (
      url.protocol === "https:" &&
      url.port === "" &&
      url.username === "" &&
      url.password === "" &&
      url.search === "" &&
      url.hash === "" &&
      ((url.hostname === "verses.quran.foundation" &&
        url.pathname.startsWith("/fonts/quran/") && url.pathname.endsWith(".woff2")) ||
       (url.hostname === "static-cdn.tarteel.ai" &&
        url.pathname === "/qul/fonts/nastaleeq/KFGQPCNastaleeq-Regular.ttf"))
    );
  } catch {
    return false;
  }
}

export function isAllowedQuranWordImageUrl(value: string | undefined): value is string {
  if (!value) return false;
  try {
    const url = new URL(value);
    return url.origin === "https://static.qurancdn.com" && !url.username && !url.password &&
      url.search === "?v=1" && !url.hash &&
      /^\/images\/w\/(?:(?:qa-color|rq-color|qa-black)\/[1-9]\d*\/[1-9]\d*\/[1-9]\d*|common\/[1-9]\d*)\.png$/.test(url.pathname);
  } catch { return false; }
}
