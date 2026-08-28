"use client";

import { PrayerReadingPlanCard } from "../../components/PrayerReadingPlanCard";
import { ReadingPlannerDashboard } from "../../components/ReadingPlannerDashboard";
import { ReminderManager } from "../../components/ReminderManager";
import { TodayReadingCard } from "../../components/TodayReadingCard";

export default function PlannerPage() {
  return (
    <div className="planner-page">
      <ReadingPlannerDashboard />
      <TodayReadingCard />
      <PrayerReadingPlanCard />
      <ReminderManager />
    </div>
  );
}
