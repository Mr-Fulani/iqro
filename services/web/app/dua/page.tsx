"use client";

import { useI18n } from "../../lib/i18n-context";

export default function DuaPage() {
  const { t } = useI18n();

  return (
    <section className="surface">
      <div className="surface-head">
        <div>
          <p className="eyebrow">{t("dua.eyebrow")}</p>
          <h1 className="surface-title">{t("dua.title")}</h1>
          <p className="surface-subtitle">{t("dua.description")}</p>
        </div>
        <span aria-hidden="true" style={{ fontSize: 40 }}>🤲</span>
      </div>

      <div className="alert alert-info">{t("dua.placeholder")}</div>
    </section>
  );
}
