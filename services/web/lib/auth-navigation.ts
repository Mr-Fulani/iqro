import type { Locale } from "./i18n";
import { localizedPath, stripLocalePrefix } from "./routing";

const POST_AUTH_RETURN_PATH_KEY = "quran_platform_post_auth_return_path";
const DEFAULT_POST_AUTH_RETURN_PATH = "/profile";
const AUTH_PATHS = new Set(["/login", "/register"]);

function isSafeReturnPath(value: string | null): value is string {
  if (!value || !value.startsWith("/") || value.startsWith("//")) return false;
  try {
    const url = new URL(value, "http://quran.local");
    return url.origin === "http://quran.local"
      && !AUTH_PATHS.has(stripLocalePrefix(url.pathname));
  } catch {
    return false;
  }
}

export function rememberPostAuthReturnPath(value: string): void {
  if (!isSafeReturnPath(value)) return;
  window.sessionStorage.setItem(POST_AUTH_RETURN_PATH_KEY, value);
}

export function consumePostAuthReturnPath(locale: Locale): string {
  const value = window.sessionStorage.getItem(POST_AUTH_RETURN_PATH_KEY);
  window.sessionStorage.removeItem(POST_AUTH_RETURN_PATH_KEY);
  return isSafeReturnPath(value) ? value : localizedPath(locale, DEFAULT_POST_AUTH_RETURN_PATH);
}
