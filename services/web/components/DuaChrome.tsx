import Link from "next/link";

import type { DuaCategory } from "../lib/api";
import { duaDisplayTitle } from "../lib/dua-share";
import { translate, type Locale } from "../lib/i18n";
import { localizedPath } from "../lib/routing";
import { DuaBackIcon, DuaChevronIcon, DuaCloudOffIcon, DuaMihrabIcon } from "./DuaIcons";

// The frame of the app's du'a screens (dua_screen.dart): the top bar, the
// chapter ribbon, chapter rows and the empty, error and loading states. No
// hooks, so pages render them on the server and the catalog on the client.

/** IqroTopBar: back arrow, title and a one-line subtitle. */
export function DuaTopBar({
  locale,
  title,
  subtitle,
  backHref,
  titleIsHeading = true,
}: {
  locale: Locale;
  title: string;
  subtitle?: string;
  backHref?: string;
  /** False where the chapter ribbon below carries the page's h1. */
  titleIsHeading?: boolean;
}) {
  const Title = titleIsHeading ? "h1" : "p";
  return (
    <header className="dua-topbar">
      {backHref ? (
        <Link className="dua-back" href={localizedPath(locale, backHref)} aria-label={translate(locale, "common.back")}>
          <DuaBackIcon />
        </Link>
      ) : null}
      <div className="dua-topbar-text">
        <Title className="dua-topbar-title">{title}</Title>
        {subtitle ? <p className="dua-topbar-subtitle">{subtitle}</p> : null}
      </div>
    </header>
  );
}

/** _DuaChapterBanner: the chapter the du'a belong to, as a sand ribbon. */
export function DuaChapterBanner({ title, heading = false }: { title: string; heading?: boolean }) {
  const Title = heading ? "h1" : "p";
  return <Title className="dua-chapter-banner">{title}</Title>;
}

/** _DuaChapterRow: «Глава N» and the chapter's title. */
export function DuaChapterRow({ chapter, locale }: { chapter: DuaCategory; locale: Locale }) {
  return (
    <Link
      className="dua-chapter-row"
      href={localizedPath(locale, `/dua/${chapter.collection}/categories/${chapter.slug}`)}
    >
      <span className="dua-chapter-row-icon"><DuaMihrabIcon /></span>
      <span className="dua-chapter-row-text">
        <span className="dua-chapter-row-number">
          {translate(locale, "dua.chapterNumber", { number: chapter.source_number })}
        </span>
        <span className="dua-chapter-row-title">{duaDisplayTitle(chapter.title, locale)}</span>
      </span>
      <DuaChevronIcon />
    </Link>
  );
}

/** _DuaEmpty: the du'a mark and a message. */
export function DuaEmpty({ message }: { message: string }) {
  return (
    <div className="dua-state">
      <DuaMihrabIcon />
      <p>{message}</p>
    </div>
  );
}

/** IqroAsyncError: the cloud, what failed and «Повторить». */
export function DuaError({ locale, onRetry }: { locale: Locale; onRetry: () => void }) {
  return (
    <div className="dua-state" role="alert">
      <DuaCloudOffIcon />
      <p>{translate(locale, "dua.networkError")}</p>
      <button type="button" className="dua-retry" onClick={onRetry}>
        {translate(locale, "dua.retry")}
      </button>
    </div>
  );
}

/** IqroLoading. */
export function DuaLoading({ locale }: { locale: Locale }) {
  return (
    <div className="dua-state" role="status" aria-live="polite">
      <span className="dua-spinner" aria-hidden="true" />
      <span className="sr-only">{translate(locale, "common.loading")}</span>
    </div>
  );
}
