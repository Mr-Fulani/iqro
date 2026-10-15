"use client";

import { useRouter } from "next/navigation";
import { duaTopics } from "../lib/dua-topics";
import { useI18n } from "../lib/i18n-context";
import { localizedPath } from "../lib/routing";

export function DuaTopicSelector({ value = "" }: { value?: string }) {
  const router = useRouter();
  const { locale, t } = useI18n();
  return (
    <label className="dua-topic-selector">
      <span>{t("dua.topicsTitle")}</span>
      <select
        aria-label={t("dua.topicsTitle")}
        value={value}
        onChange={(event) => router.push(localizedPath(locale,
          event.target.value ? `/dua/topics/${event.target.value}` : "/dua"))}
      >
        <option value="">{t("dua.allCategories")}</option>
        {duaTopics.map((topic) => <option key={topic.id} value={topic.id}>{topic.title[locale]}</option>)}
      </select>
    </label>
  );
}
