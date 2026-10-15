"use client";

import { PrayerReadingPlanCard } from "./PrayerReadingPlanCard";
import { MemorizationPlannerCard } from "./MemorizationPlannerCard";
import { ReadingPlannerDashboard } from "./ReadingPlannerDashboard";
import { ReminderManager } from "./ReminderManager";
import { TodayReadingCard } from "./TodayReadingCard";

export default function PlannerPage() {
  return (
    <div className="planner-page">
      <ReadingPlannerDashboard />
      <TodayReadingCard />
      <PrayerReadingPlanCard />
      <MemorizationPlannerCard />
      <ReminderManager />
    </div>
  );
}
