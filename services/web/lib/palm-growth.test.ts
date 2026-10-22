import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import test from "node:test";

import type { ReadingPlanner, ReadingToday } from "./api";
import { SUPPORTED_LOCALES } from "./i18n.ts";
import { translate } from "./translate.ts";
import {
  PALM_IMAGE_WIDTHS,
  PALM_MOODS,
  PALM_STAGES,
  type PalmHistoryDay,
  type PalmPlan,
  palmGrowthFor,
  palmPlanFrom,
  palmStageImage,
} from "./palm-growth.ts";

// The cases mirror clients/iqro_mobile/test/features/palm_growth_test.dart
// ("palm growth rules") so the site and the app agree on every stage.
const TODAY = "2026-09-14";

function day(daysAgo: number, state: string, hasReading?: boolean): PalmHistoryDay {
  const date = new Date(Date.UTC(2026, 8, 14 - daysAgo));
  return {
    localDate: date.toISOString().slice(0, 10),
    state,
    hasReading: hasReading ?? (state === "completed" || state === "partial"),
  };
}

function plan({
  achieved = 0,
  streak = 0,
  longestStreak = 0,
  history = [],
}: {
  achieved?: number;
  streak?: number;
  longestStreak?: number;
  history?: PalmHistoryDay[];
} = {}): PalmPlan {
  return { target: 6, achieved, streak, longestStreak, localDate: TODAY, history };
}

function completed(days: number): PalmHistoryDay[] {
  return Array.from({ length: days }, (_, index) => day(index + 1, "completed"));
}

test("a new reader starts with a seed waiting to be planted", () => {
  const growth = palmGrowthFor(plan());
  assert.equal(growth.stage, "seed");
  assert.equal(growth.mood, "planting");
  assert.equal(growth.points, 0);
  assert.equal(growth.nextStage, "sprout");
});

test("reading today sprouts the seed at once", () => {
  const partial = palmGrowthFor(plan({ achieved: 2 }));
  assert.equal(partial.stage, "sprout");
  assert.equal(partial.mood, "growing");
  assert.equal(partial.points, 1);

  const complete = palmGrowthFor(plan({ achieved: 6 }));
  assert.equal(complete.mood, "flourishing");
  assert.equal(complete.points, 2);
});

test("a completed goal is worth two points, a reading day one", () => {
  const growth = palmGrowthFor(
    plan({
      streak: 3,
      history: [
        day(1, "completed"),
        day(2, "partial"),
        day(3, "completed"),
        day(4, "no_goal", true),
        day(5, "missed"),
      ],
    }),
  );
  assert.equal(growth.points, 6);
  assert.equal(growth.stage, "seedling");
  assert.equal(growth.mood, "waiting");
});

test("today is counted from the live goal, never twice", () => {
  const growth = palmGrowthFor(plan({ achieved: 6, history: [day(0, "completed")] }));
  assert.equal(growth.points, 2);
});

test("missed days never take growth away; the palm only rests", () => {
  const steady = Array.from({ length: 8 }, (_, index) => day(index + 1, "completed"));
  const before = palmGrowthFor(plan({ streak: 8, history: steady }));
  const after = palmGrowthFor(
    plan({
      history: [
        ...Array.from({ length: 5 }, (_, index) => day(index + 1, "missed")),
        ...Array.from({ length: 8 }, (_, index) => day(index + 6, "completed")),
      ],
    }),
  );
  assert.equal(before.stage, "youngPalm");
  assert.equal(after.stage, before.stage);
  assert.equal(after.points, before.points);
  assert.equal(after.mood, "resting");
});

test("the longest streak keeps a grown palm after a long pause", () => {
  const growth = palmGrowthFor(plan({ longestStreak: 30 }));
  assert.equal(growth.stage, "fruitingPalm");
  assert.equal(growth.mood, "resting");
  assert.equal(palmGrowthFor(plan({ longestStreak: 1 })).stage, "sprout");
  assert.equal(palmGrowthFor(plan({ longestStreak: 7 })).stage, "youngPalm");
});

test("only the 90-day planner window counts", () => {
  const growth = palmGrowthFor(plan({ history: [day(89, "completed"), day(90, "completed")] }));
  assert.equal(growth.points, 2);
});

test("stage thresholds and progress to the next stage", () => {
  assert.equal(palmGrowthFor(plan({ history: completed(8) })).stage, "youngPalm");
  assert.equal(palmGrowthFor(plan({ history: completed(16) })).stage, "palm");
  const top = palmGrowthFor(plan({ history: completed(28) }));
  assert.equal(top.stage, "fruitingPalm");
  assert.equal(top.nextStage, null);
  assert.equal(top.progressToNext, 1);
  const halfway = palmGrowthFor(plan({ history: completed(12) }));
  assert.equal(halfway.stage, "youngPalm");
  assert.ok(Math.abs(halfway.progressToNext - 0.5) < 0.001);
});

test("every stage and mood has text in every language", () => {
  for (const locale of SUPPORTED_LOCALES) {
    for (const stage of PALM_STAGES) {
      assert.notEqual(translate(locale, `palm.stage.${stage}`), "");
    }
    for (const mood of PALM_MOODS) {
      assert.notEqual(translate(locale, `palm.mood.${mood}`), "");
    }
  }
});

test("every stage has its own photograph in every size", () => {
  for (const stage of PALM_STAGES) {
    const image = palmStageImage(stage);
    for (const width of PALM_IMAGE_WIDTHS) {
      const file = `public/images/palm/palm-stage-${PALM_STAGES.indexOf(stage)}-${width}.webp`;
      assert.ok(existsSync(new URL(`../${file}`, import.meta.url)), file);
      assert.ok(image.srcSet.includes(`/${file.replace("public/", "")} ${width}w`));
    }
  }
});

test("the palm reads the same server fields as the app's DailyPlan.fromRemote", () => {
  const today: ReadingToday = {
    local_date: TODAY,
    timezone_name: "Europe/Istanbul",
    continue_reading: null,
    goal: {
      id: "goal",
      metric: "pages",
      target_amount: "3.00",
      timezone_name: "Europe/Istanbul",
      started_on: "2026-09-01",
      ended_on: null,
      status: "active",
      revision: 1,
      client_updated_at: "2026-09-01T00:00:00Z",
      device_id: null,
      created_at: "2026-09-01T00:00:00Z",
      updated_at: "2026-09-01T00:00:00Z",
    },
    progress: {
      goal_id: "goal",
      local_date: TODAY,
      metric: "pages",
      target_amount: "3.00",
      achieved_amount: "1.50",
      remaining_amount: "1.50",
      is_completed: false,
      completed_at: null,
    },
    streak: { current_count: 2, longest_count: 9, last_qualifying_date: "2026-09-13" },
  };
  const plannerDay = (localDate: string, state: ReadingPlanner["days"][number]["state"], hasReading: boolean) => ({
    local_date: localDate,
    state,
    has_reading: hasReading,
    goal: null,
    prayer_check_ins: [],
    prayer_pages: 0,
    prayer_count: 0,
    automatic_sessions: 0,
    automatic_active_seconds: 0,
    automatic_pages: 0,
    automatic_ayahs: 0,
  });
  const planner: ReadingPlanner = {
    local_date: TODAY,
    timezone_name: "Europe/Istanbul",
    days: [
      plannerDay("2026-09-12", "completed", true),
      plannerDay("2026-09-13", "partial", true),
      plannerDay(TODAY, "completed", true),
    ],
  };

  assert.deepEqual(palmPlanFrom(today, planner), {
    target: 3,
    achieved: 1.5,
    streak: 2,
    longestStreak: 9,
    localDate: TODAY,
    history: [
      { localDate: "2026-09-12", state: "completed", hasReading: true },
      { localDate: "2026-09-13", state: "partial", hasReading: true },
      { localDate: TODAY, state: "completed", hasReading: true },
    ],
  });
  const growth = palmGrowthFor(palmPlanFrom(today, planner));
  assert.equal(growth.points, 4);
  assert.equal(growth.stage, "youngPalm");
  assert.equal(growth.mood, "growing");

  // Without a goal the app falls back to a target of six and nothing achieved.
  const noGoal = palmPlanFrom({ ...today, goal: null, progress: null }, { ...planner, days: [] });
  assert.equal(noGoal.target, 6);
  assert.equal(noGoal.achieved, 0);
});
