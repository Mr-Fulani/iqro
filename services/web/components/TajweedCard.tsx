"use client";

import type { TajweedAyah, TajweedFragment, TajweedReference } from "../lib/api";
import { useI18n } from "../lib/i18n-context";
import {
  findTajweedWord,
  joinedParts,
  ruleOccurrences,
  ruleText,
  type TajweedSelection,
} from "../lib/tajweed";
import { WordAudio } from "./TajweedAudio";
import { Explanation, HighlightedWord, Letters, RuleHeading, TajweedDialog } from "./TajweedParts";

type TajweedCardProps = {
  reference: TajweedReference;
  ayahs: TajweedAyah[];
  selection: TajweedSelection;
  /** Where the rule occurrences come from: the Mushaf page or one ayah. */
  scope: "page" | "ayah";
  recitationId: string | null;
  onSelect: (selection: TajweedSelection) => void;
  onClose: () => void;
};

function fragmentGroups(fragments: readonly TajweedFragment[]): TajweedFragment[] {
  const seen = new Set<string>();
  return fragments.filter((fragment) => {
    const key = `${fragment.code}|${fragment.variant ?? ""}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

/**
 * The tajweed card: a bottom sheet on a phone, a dialog on a wide screen. It
 * explains a tapped word (every rule in it, the letters, how to read, the
 * word's audio) or one rule from the legend with its occurrences.
 */
export default function TajweedCard({
  reference,
  ayahs,
  selection,
  scope,
  recitationId,
  onSelect,
  onClose,
}: TajweedCardProps) {
  const { locale, t } = useI18n();
  const selectionKey = selection.kind === "word" ? `${selection.verseKey}#${selection.position}` : selection.code;
  const found = selection.kind === "word" ? findTajweedWord(ayahs, selection.verseKey, selection.position) : null;
  const rule = selection.kind === "rule" ? ruleText(reference, selection.code, locale) : null;

  return (
    <TajweedDialog
      title={selection.kind === "word" ? t("tajweed.wordTitle") : t("tajweed.ruleTitle")}
      focusKey={selectionKey}
      onClose={onClose}
      testId="tajweed-card"
    >
      {found && (
        <>
          <p className="tajweed-word">
            <HighlightedWord reference={reference} text={found.word.text} fragments={found.word.rules} />
            <small dir="ltr">{found.ayah.verse_key}</small>
          </p>
          {fragmentGroups(found.word.rules).map((fragment) => {
            const text = ruleText(reference, fragment.code, locale, fragment.variant);
            if (!text) return null;
            return (
              <section className="tajweed-rule" key={`${fragment.code}-${fragment.variant ?? ""}`} data-rule={fragment.code}>
                <RuleHeading reference={reference} code={fragment.code} variant={fragment.variant} />
                <h4>{t("tajweed.whyHere")}</h4>
                <p><Letters parts={joinedParts(found.ayah, found.word, fragment)} reference={reference} /></p>
                <Explanation text={text.why} />
                <h4>{t("tajweed.howToRead")}</h4>
                <Explanation text={text.how} />
              </section>
            );
          })}
          {recitationId && (
            <WordAudio recitationId={recitationId} verseKey={found.ayah.verse_key} position={found.word.position} />
          )}
        </>
      )}

      {selection.kind === "rule" && rule && (
        <section className="tajweed-rule" data-rule={rule.code}>
          <RuleHeading reference={reference} code={rule.code} />
          <h4>{t("tajweed.whenApplies")}</h4>
          <Explanation text={rule.why} />
          <h4>{t("tajweed.howToRead")}</h4>
          <Explanation text={rule.how} />
          <h4>{scope === "page" ? t("tajweed.occurrencesPage") : t("tajweed.occurrencesAyah")}</h4>
          <ul className="tajweed-occurrences">
            {ruleOccurrences(ayahs, rule.code).map((parts) => (
              <li key={`${parts[0].verseKey}-${parts[0].word.position}`}>
                <button
                  type="button"
                  onClick={() => onSelect({ kind: "word", verseKey: parts[0].verseKey, position: parts[0].word.position })}
                >
                  <Letters parts={parts} reference={reference} />
                  <small>{parts[0].verseKey}</small>
                </button>
              </li>
            ))}
          </ul>
        </section>
      )}

      {reference.review_status === "pending_teacher_review" && (
        <p className="tajweed-review-note">{t("tajweed.reviewNote")}</p>
      )}
    </TajweedDialog>
  );
}
