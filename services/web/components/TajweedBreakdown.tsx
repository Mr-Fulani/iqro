"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import type { TajweedAyah, TajweedReference } from "../lib/api";
import { useI18n } from "../lib/i18n-context";
import {
  ruleText,
  stepRules,
  stepTiming,
  tajweedSteps,
  timedPosition,
  type TajweedGlyph,
  type TajweedStep,
} from "../lib/tajweed";
import { StepNav } from "./StepNav";
import { ClipButtons, useAyahAudio, useClipPlayer } from "./TajweedAudio";
import { colorStyle, Explanation, Letters, RuleHeading, TajweedDialog } from "./TajweedParts";
import { useStepNavigation } from "./useStepNavigation";

type TajweedBreakdownProps = {
  reference: TajweedReference;
  ayah: TajweedAyah;
  /** The ayah in its QCF V4 glyphs; without them the steps show only their words. */
  words: readonly TajweedGlyph[];
  /** The reciter whose timings play the fragments and the ayah. */
  recitationId: string | null;
  onClose: () => void;
};

/**
 * The tajweed of one ayah, step by step in reading order: the rule's place
 * lit in the ayah, why it applies here and how to read it, its sound; then a
 * summary of the rules met, each with its card.
 */
export default function TajweedBreakdown({ reference, ayah, words, recitationId, onClose }: TajweedBreakdownProps) {
  const { direction, formatNumber, locale, t } = useI18n();
  const steps = useMemo(() => tajweedSteps(ayah, reference), [ayah, reference]);
  const summary = useMemo(() => stepRules(steps), [steps]);
  // The pages are the steps and, after them, the summary.
  const { index, setIndex, go, onKeyDown } = useStepNavigation(steps.length + 1, direction);
  const dialog = useRef<HTMLDialogElement | null>(null);
  const [rule, setRule] = useState<string | null>(null);
  const [slow, setSlow] = useState(false);
  const [readingMs, setReadingMs] = useState<number | null>(null);
  const audio = useAyahAudio(recitationId, ayah.verse_key);
  const fragmentPlayer = useClipPlayer();
  const ayahPlayer = useClipPlayer(setReadingMs);
  const step = index < steps.length ? steps[index] : null;
  const isSummary = !step && rule === null;
  const stepTitle = step ? ruleText(reference, step.code, locale, step.variant ?? undefined) : null;
  const clipTiming = step && audio ? stepTiming(audio.words, step) : null;
  const reading = readingMs === null || !audio ? null : timedPosition(audio.words, readingMs);
  const lit = new Set(step?.parts.map((part) => part.word.position) ?? []);
  const litColor = step ? reference.rules.find((item) => item.code === step.code)?.color : undefined;
  const { stop: stopFragment } = fragmentPlayer;
  const { attach, playing: ayahPlaying, error: ayahError, play: playAyah, stop: stopAyah, setRate: setAyahRate } = ayahPlayer;

  // A step change stops the sound, as in a Salah lesson; the next play starts over.
  useEffect(() => {
    stopFragment();
    stopAyah();
  }, [index, rule, stopAyah, stopFragment]);

  const counter = step
    ? t("tajweed.stepOf", { current: formatNumber(index + 1), total: formatNumber(steps.length) })
    : t("tajweed.summary");
  const openStep = (target: number) => {
    setRule(null);
    setIndex(target);
  };

  return (
    <TajweedDialog
      title={<>{t("tajweed.breakdown")} <small dir="ltr">{ayah.verse_key}</small></>}
      focusKey={rule ?? (isSummary ? "summary" : "steps")}
      onClose={onClose}
      onKeyDown={(event) => {
        if (rule === null && onKeyDown(event.nativeEvent)) event.stopPropagation();
      }}
      className="tajweed-breakdown"
      testId="tajweed-breakdown"
      dialogRef={dialog}
    >
      {words.length > 0 && (
        <p className="tajweed-breakdown-ayah" dir="rtl" lang="ar" aria-hidden="true" translate="no">
          {words.map((word) => (
            <span
              key={word.key}
              className={[
                "tajweed-breakdown-word",
                word.position === null ? "is-ayah-end" : "",
                word.position !== null && lit.has(word.position) ? "is-step" : "",
                word.position !== null && word.position === reading ? "is-reading" : "",
              ].filter(Boolean).join(" ")}
              style={{
                fontFamily: `"${word.fontFamily}", serif`,
                ...(litColor && word.position !== null && lit.has(word.position) ? colorStyle(litColor) : {}),
              }}
              data-word-position={word.position ?? undefined}
            >
              {word.text}
            </span>
          ))}
        </p>
      )}
      {audio && (
        <div className="tajweed-breakdown-listen">
          <audio ref={attach} preload="none" onEnded={stopAyah} data-testid="tajweed-ayah-audio" />
          <button
            type="button"
            className="btn btn-secondary btn-sm"
            onClick={() => (ayahPlaying
              ? stopAyah()
              : void playAyah({ url: audio.url, startMs: audio.startMs, endMs: audio.endMs }, slow ? 0.75 : 1))}
            data-testid="tajweed-play-ayah"
          >
            {ayahPlaying ? t("tajweed.stop") : t("tajweed.playAyah")}
          </button>
          {ayahError && <p className="error-text" role="alert">{t("tajweed.audioError")}</p>}
        </div>
      )}

      {rule === null && (
        <div className="tajweed-breakdown-status">
          <p aria-live="polite" data-testid="tajweed-step-counter">
            {counter}
            {stepTitle && <span className="sr-only">: {stepTitle.name}</span>}
          </p>
          <span className="tajweed-breakdown-progress" aria-hidden="true">
            <span style={{ inlineSize: `${((index + 1) / (steps.length + 1)) * 100}%` }} />
          </span>
        </div>
      )}

      {step && stepTitle && (
        <section className="tajweed-rule tajweed-step" data-rule={step.code} data-step={index + 1}>
          <RuleHeading reference={reference} code={step.code} variant={step.variant ?? undefined} />
          <p className="tajweed-step-word"><Letters parts={step.parts} reference={reference} /></p>
          <h4>{t("tajweed.whyHere")}</h4>
          <Explanation text={stepTitle.why} />
          <h4>{t("tajweed.howToRead")}</h4>
          <Explanation text={stepTitle.how} />
        </section>
      )}
      {step && audio && clipTiming && (
        <ClipButtons
          player={fragmentPlayer}
          clip={{ url: audio.url, ...clipTiming }}
          slow={slow}
          onSlowChange={(value) => {
            setSlow(value);
            setAyahRate(value ? 0.75 : 1);
          }}
        />
      )}

      {isSummary && (
        <section className="tajweed-breakdown-summary" data-testid="tajweed-summary">
          <h3>{t("tajweed.summaryTitle")}</h3>
          <ul className="tajweed-legend-list">
            {summary.map((item) => {
              const text = ruleText(reference, item.code, locale);
              return text && (
                <li key={item.code}>
                  <button type="button" className="tajweed-chip" onClick={() => setRule(item.code)} data-rule={item.code}>
                    <span className="tajweed-dot" style={{ background: text.color }} aria-hidden="true" />
                    {text.name}
                  </button>
                </li>
              );
            })}
          </ul>
          <button type="button" className="btn btn-secondary btn-sm" onClick={() => openStep(0)}>
            {t("tajweed.restart")}
          </button>
        </section>
      )}

      {rule !== null && (
        <BreakdownRule
          reference={reference}
          code={rule}
          steps={summary.find((item) => item.code === rule)?.steps ?? []}
          allSteps={steps}
          onBack={() => setRule(null)}
          onStep={openStep}
        />
      )}

      {rule === null && (
        <>
          <StepNav
            className="tajweed-step-nav"
            backLabel={t("tajweed.previous")}
            nextLabel={step ? (index === steps.length - 1 ? t("tajweed.toSummary") : t("tajweed.next")) : t("tajweed.done")}
            onBack={() => go(-1)}
            onNext={step ? () => go(1) : () => dialog.current?.close()}
            isFirst={index === 0}
            isLast={!step}
          />
          <p className="tajweed-keyboard-hint">{t("tajweed.keyboardHint")}</p>
        </>
      )}

      {reference.review_status === "pending_teacher_review" && (
        <p className="tajweed-review-note">{t("tajweed.reviewNote")}</p>
      )}
    </TajweedDialog>
  );
}

/** A rule's card from the summary, with its places in the ayah as links to their steps. */
function BreakdownRule({
  reference,
  code,
  steps,
  allSteps,
  onBack,
  onStep,
}: {
  reference: TajweedReference;
  code: string;
  steps: number[];
  allSteps: TajweedStep[];
  onBack: () => void;
  onStep: (index: number) => void;
}) {
  const { direction, formatNumber, locale, t } = useI18n();
  const text = ruleText(reference, code, locale);
  if (!text) return null;
  return (
    <section className="tajweed-rule" data-rule={code}>
      <button type="button" className="btn btn-secondary btn-sm tajweed-breakdown-back" onClick={onBack}>
        <span aria-hidden="true">{direction === "rtl" ? "→" : "←"}</span> {t("tajweed.backToSummary")}
      </button>
      <RuleHeading reference={reference} code={code} />
      <h4>{t("tajweed.whenApplies")}</h4>
      <Explanation text={text.why} />
      <h4>{t("tajweed.howToRead")}</h4>
      <Explanation text={text.how} />
      <h4>{t("tajweed.occurrencesAyah")}</h4>
      <ul className="tajweed-occurrences">
        {steps.map((stepIndex) => (
          <li key={stepIndex}>
            <button type="button" onClick={() => onStep(stepIndex)}>
              <Letters parts={allSteps[stepIndex].parts} reference={reference} />
              <small>{t("tajweed.stepNumber", { number: formatNumber(stepIndex + 1) })}</small>
            </button>
          </li>
        ))}
      </ul>
    </section>
  );
}
