"use client";

import { useI18n } from "../lib/i18n-context";
import { LanguageSwitcher } from "./LanguageSwitcher";
import { MoreRow } from "./MoreRow";

/**
 * The phone's Settings screen, like the app's
 * (clients/iqro_mobile/lib/features/settings/settings_screen.dart), with the
 * settings the site has.
 */
export default function SettingsPage() {
  const { t } = useI18n();
  return (
    <div className="more-page">
      <header className="more-head">
        <h1>{t("home.settings")}</h1>
      </header>

      <h2 className="more-section-title">{t("settings.language")}</h2>
      <div className="more-card">
        <LanguageSwitcher variant="menu" />
      </div>

      <h2 className="more-section-title">{t("more.subtitle")}</h2>
      <div className="more-card">
        <MoreRow href="/profile#share-app" icon="share" title={t("more.share")} subtitle={t("more.shareHint")} />
        <MoreRow href="/profile" icon="profile" title={t("more.account")} subtitle={t("settings.accountHint")} />
        <MoreRow href="/privacy" icon="privacy" title={t("footer.privacy")} subtitle={t("settings.privacyHint")} />
        <MoreRow href="/cookies" icon="cookies" title={t("footer.cookies")} />
        <MoreRow href="/sources" icon="sources" title={t("footer.sources")} />
      </div>
    </div>
  );
}
