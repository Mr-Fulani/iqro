export function isAllowedQuranFontUrl(value: string | undefined): value is string {
  if (!value) return false;
  try {
    const url = new URL(value);
    return (
      url.protocol === "https:" &&
      url.hostname === "verses.quran.foundation" &&
      url.port === "" &&
      url.username === "" &&
      url.password === "" &&
      url.search === "" &&
      url.hash === "" &&
      url.pathname.startsWith("/fonts/quran/") &&
      url.pathname.endsWith(".woff2")
    );
  } catch {
    return false;
  }
}
