import '../../l10n/generated/app_localizations.dart';
import 'plan_repository.dart';

/// Visual stages of the date palm that grows with regular reading.
enum PalmStage { seed, sprout, seedling, youngPalm, palm, fruitingPalm }

/// How the palm feels today. None of these moods wilt or shame: after a
/// break the palm only rests in the evening shade until the reader returns.
enum PalmMood {
  /// Nothing has been read yet: a date seed waits to be planted.
  planting,

  /// Today's goal is complete.
  flourishing,

  /// Something was read today, the goal is not complete yet.
  growing,

  /// The streak is alive from yesterday, today's reading is still ahead.
  waiting,

  /// The streak paused. Growth is kept; the palm rests.
  resting,
}

class PalmGrowth {
  const PalmGrowth({
    required this.stage,
    required this.mood,
    required this.points,
  });

  final PalmStage stage;
  final PalmMood mood;

  /// Growth points earned in the planner window (90 days).
  final int points;

  PalmStage? get nextStage => stage == PalmStage.fruitingPalm
      ? null
      : PalmStage.values[stage.index + 1];

  /// 0..1 progress from the current stage threshold to the next one.
  double get progressToNext {
    final next = nextStage;
    if (next == null) return 1;
    final from = palmStagePoints[stage.index];
    final to = palmStagePoints[next.index];
    return ((points - from) / (to - from)).clamp(0.0, 1.0);
  }
}

/// Points needed for each [PalmStage], indexed by stage.
const palmStagePoints = <int>[0, 1, 6, 16, 32, 56];

/// Longest streak (all time) that keeps each stage, indexed by stage. The
/// planner only returns 90 days, so this floor stops a long pause from
/// shrinking a palm the reader once grew with a steady streak.
const palmStageLongestStreak = <int>[0, 1, 3, 7, 14, 30];

/// A day with reading is one growth point; a completed goal is two.
int palmDayPoints({required bool hasReading, required bool completed}) =>
    completed ? 2 : (hasReading ? 1 : 0);

PalmGrowth palmGrowthFor(DailyPlan plan) {
  final todayCompleted = plan.target > 0 && plan.achieved >= plan.target;
  final readToday = plan.achieved > 0;
  // Today's progress comes from the live goal, so the palm reacts as soon as
  // reading is credited instead of waiting for the planner history.
  var points = palmDayPoints(hasReading: readToday, completed: todayCompleted);
  for (final day in plan.daysForRange(90)) {
    final date = day.localDate;
    if (date == null || _dateKey(date) == plan.localDate) continue;
    points += palmDayPoints(
      hasReading: day.hasReading,
      completed: day.state == 'completed',
    );
  }
  var stage = PalmStage.seed;
  for (final candidate in PalmStage.values) {
    if (points >= palmStagePoints[candidate.index] ||
        plan.longestStreak >= palmStageLongestStreak[candidate.index]) {
      stage = candidate;
    }
  }
  final PalmMood mood;
  if (todayCompleted) {
    mood = PalmMood.flourishing;
  } else if (readToday) {
    mood = PalmMood.growing;
  } else if (plan.streak > 0) {
    mood = PalmMood.waiting;
  } else if (stage == PalmStage.seed) {
    mood = PalmMood.planting;
  } else {
    mood = PalmMood.resting;
  }
  return PalmGrowth(stage: stage, mood: mood, points: points);
}

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String palmStageLabel(AppLocalizations l10n, PalmStage stage) =>
    switch (stage) {
      PalmStage.seed => l10n.palmStageSeed,
      PalmStage.sprout => l10n.palmStageSprout,
      PalmStage.seedling => l10n.palmStageSeedling,
      PalmStage.youngPalm => l10n.palmStageYoungPalm,
      PalmStage.palm => l10n.palmStagePalm,
      PalmStage.fruitingPalm => l10n.palmStageFruitingPalm,
    };

String palmMoodLabel(AppLocalizations l10n, PalmMood mood) => switch (mood) {
  PalmMood.planting => l10n.palmMoodPlanting,
  PalmMood.flourishing => l10n.palmMoodFlourishing,
  PalmMood.growing => l10n.palmMoodGrowing,
  PalmMood.waiting => l10n.palmMoodWaiting,
  PalmMood.resting => l10n.palmMoodResting,
};
