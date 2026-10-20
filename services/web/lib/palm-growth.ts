import type { ReadingPlanner, ReadingToday } from "./api";

// Port of clients/iqro_mobile/lib/features/plan/palm_growth.dart. The site
// reads the same /me/today and /me/reading-planner data as the app, so for one
// reader both show the same stage. Change the rules in both places together.

/** Visual stages of the date palm that grows with regular reading. */
export const PALM_STAGES = ["seed", "sprout", "seedling", "youngPalm", "palm", "fruitingPalm"] as const;
export type PalmStage = (typeof PALM_STAGES)[number];

/**
 * How the palm feels today. None of these moods wilt or shame: after a break
 * the palm only rests in the evening shade until the reader returns.
 */
export const PALM_MOODS = ["planting", "flourishing", "growing", "waiting", "resting"] as const;
export type PalmMood = (typeof PALM_MOODS)[number];

/** Points needed for each stage, indexed by stage. */
export const PALM_STAGE_POINTS = [0, 1, 6, 16, 32, 56] as const;

/**
 * Longest streak (all time) that keeps each stage, indexed by stage. The
 * planner only returns 90 days, so this floor stops a long pause from
 * shrinking a palm the reader once grew with a steady streak.
 */
export const PALM_STAGE_LONGEST_STREAK = [0, 1, 3, 7, 14, 30] as const;

/** The planner window the app requests and counts. */
export const PALM_HISTORY_DAYS = 90;

export type PalmHistoryDay = {
  /** YYYY-MM-DD, or null when the server sent no usable date. */
  localDate: string | null;
  state: string;
  hasReading: boolean;
};

/** The fields of the app's DailyPlan that the palm reads. */
export type PalmPlan = {
  target: number;
  achieved: number;
  streak: number;
  longestStreak: number;
  localDate: string;
  history: PalmHistoryDay[];
};

export type PalmGrowth = {
  stage: PalmStage;
  mood: PalmMood;
  /** Growth points earned in the planner window (90 days). */
  points: number;
  nextStage: PalmStage | null;
  /** 0..1 progress from the current stage threshold to the next one. */
  progressToNext: number;
};

/** A day with reading is one growth point; a completed goal is two. */
export function palmDayPoints(hasReading: boolean, completed: boolean): number {
  return completed ? 2 : hasReading ? 1 : 0;
}

// Dart's double.tryParse(value?.toString() ?? '') ?? fallback.
function amount(value: string | number | null | undefined, fallback = 0): number {
  const raw = value == null ? "" : String(value).trim();
  const parsed = raw === "" ? Number.NaN : Number(raw);
  return Number.isFinite(parsed) ? parsed : fallback;
}

/** Same fields as DailyPlan.fromRemote in plan_repository.dart. */
export function palmPlanFrom(today: ReadingToday, planner: ReadingPlanner): PalmPlan {
  return {
    target: amount(today.goal?.target_amount, 6),
    achieved: amount(today.progress?.achieved_amount),
    streak: today.streak?.current_count ?? 0,
    longestStreak: today.streak?.longest_count ?? 0,
    localDate: today.local_date ?? "",
    history: (Array.isArray(planner.days) ? planner.days : []).map((day) => ({
      localDate: parseDateOnly(day.local_date) == null ? null : day.local_date,
      state: day.state ?? "no_goal",
      hasReading: day.has_reading === true,
    })),
  };
}

const DAY_MS = 86_400_000;

function parseDateOnly(value: string | null | undefined): number | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value ?? "");
  if (!match) return null;
  return Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
}

/** DailyPlan.daysForRange: the planner days from today back over the window. */
function daysForRange(plan: PalmPlan, rangeDays: number): PalmHistoryDay[] {
  const count = Math.min(90, Math.max(7, rangeDays));
  const today = parseDateOnly(plan.localDate);
  if (today == null) return plan.history;
  const first = today - (count - 1) * DAY_MS;
  return plan.history.filter((day) => {
    const date = parseDateOnly(day.localDate);
    return date != null && date >= first && date <= today;
  });
}

export function palmGrowthFor(plan: PalmPlan): PalmGrowth {
  const todayCompleted = plan.target > 0 && plan.achieved >= plan.target;
  const readToday = plan.achieved > 0;
  // Today's progress comes from the live goal, so the palm reacts as soon as
  // reading is credited instead of waiting for the planner history.
  let points = palmDayPoints(readToday, todayCompleted);
  for (const day of daysForRange(plan, PALM_HISTORY_DAYS)) {
    if (day.localDate == null || day.localDate === plan.localDate) continue;
    points += palmDayPoints(day.hasReading, day.state === "completed");
  }
  let stageIndex = 0;
  PALM_STAGES.forEach((_, index) => {
    if (points >= PALM_STAGE_POINTS[index] || plan.longestStreak >= PALM_STAGE_LONGEST_STREAK[index]) {
      stageIndex = index;
    }
  });
  const stage = PALM_STAGES[stageIndex];
  let mood: PalmMood;
  if (todayCompleted) {
    mood = "flourishing";
  } else if (readToday) {
    mood = "growing";
  } else if (plan.streak > 0) {
    mood = "waiting";
  } else if (stage === "seed") {
    mood = "planting";
  } else {
    mood = "resting";
  }
  const nextIndex = stageIndex + 1;
  const nextStage = nextIndex < PALM_STAGES.length ? PALM_STAGES[nextIndex] : null;
  let progressToNext = 1;
  if (nextStage != null) {
    const from = PALM_STAGE_POINTS[stageIndex];
    const to = PALM_STAGE_POINTS[nextIndex];
    progressToNext = Math.min(1, Math.max(0, (points - from) / (to - from)));
  }
  return { stage, mood, points, nextStage, progressToNext };
}

/** Stage photographs from the app, resized for the site's palm card. */
export const PALM_IMAGE_WIDTHS = [480, 960] as const;

export function palmStageImage(stage: PalmStage): { src: string; srcSet: string } {
  const index = PALM_STAGES.indexOf(stage);
  const path = (width: number) => `/images/palm/palm-stage-${index}-${width}.webp`;
  return {
    src: path(PALM_IMAGE_WIDTHS[0]),
    srcSet: PALM_IMAGE_WIDTHS.map((width) => `${path(width)} ${width}w`).join(", "),
  };
}
