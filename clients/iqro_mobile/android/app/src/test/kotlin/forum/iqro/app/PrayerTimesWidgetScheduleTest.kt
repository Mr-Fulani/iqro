package forum.iqro.app

import forum.iqro.app.PrayerTimesWidgetSchedule.Entry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDateTime
import java.time.ZoneId

class PrayerTimesWidgetScheduleTest {
    private val zone = ZoneId.of("Europe/Istanbul")

    private fun at(day: Int, hour: Int, minute: Int): Long =
        LocalDateTime.of(2026, 10, day, hour, minute).atZone(zone).toInstant().toEpochMilli()

    private fun prayers(day: Int) = listOf(
        at(day, 5, 40), at(day, 12, 50), at(day, 15, 55), at(day, 18, 24), at(day, 19, 54))

    /** Mirrors buildPrayerWidgetTimeline: midnight, then one entry per prayer. */
    private fun day(day: Int): List<Entry> {
        val today = prayers(day)
        val next = today.drop(1) + prayers(day + 1).first()
        return listOf(Entry(at(day, 0, 0), today.first())) +
            today.zip(next) { start, target -> Entry(start, target) }
    }

    private val timeline = day(14) + day(15)

    private fun nextPrayerAt(now: Long): Long? {
        val start = PrayerTimesWidgetSchedule.activeEntryStart(timeline, now) ?: return null
        return timeline.single { it.startsAt == start }.nextPrayerAt
    }

    @Test
    fun picksMaghribAfterDhuhrHasPassed() {
        assertEquals(at(14, 18, 24), nextPrayerAt(at(14, 18, 13)))
    }

    @Test
    fun movesToTomorrowsFajrAfterIsha() {
        val now = at(14, 21, 0)
        assertEquals(at(15, 5, 40), nextPrayerAt(now))
        assertEquals(at(14, 19, 54), PrayerTimesWidgetSchedule.activeEntryStart(timeline, now))
    }

    @Test
    fun showsTheNewDayAfterMidnight() {
        assertEquals(at(15, 0, 0), PrayerTimesWidgetSchedule.activeEntryStart(timeline, at(15, 0, 30)))
    }

    @Test
    fun switchesAtTheExactPrayerTime() {
        assertEquals(at(14, 15, 55), nextPrayerAt(at(14, 12, 50)))
    }

    @Test
    fun skipsEntriesWhoseTargetHasBegunEvenWhenTheyStartedLater() {
        // A malformed or stale entry must never win over an upcoming prayer.
        val entries = listOf(Entry(at(14, 5, 40), at(14, 12, 50)), Entry(at(14, 15, 55), at(14, 18, 24)))
        assertEquals(at(14, 15, 55), PrayerTimesWidgetSchedule.activeEntryStart(entries, at(14, 13, 0)))
    }

    @Test
    fun neverCountsDownToAPrayerThatHasBegun() {
        var now = at(14, 0, 0)
        while (now < at(15, 19, 54)) {
            val target = nextPrayerAt(now)
            assertTrue("at $now", target != null && target > now)
            now += 60_000
        }
    }

    @Test
    fun reportsNoPrayerOnceTheScheduleRunsOut() {
        assertNull(PrayerTimesWidgetSchedule.activeEntryStart(timeline, at(16, 6, 0)))
        assertNull(PrayerTimesWidgetSchedule.activeEntryStart(emptyList(), at(14, 6, 0)))
        assertNull(PrayerTimesWidgetSchedule.activeEntryStart(listOf(Entry(at(14, 0, 0), null)), at(14, 6, 0)))
    }

    @Test
    fun countdownIsNeverNegative() {
        val now = at(14, 18, 13)
        assertEquals(0L, PrayerTimesWidgetSchedule.remainingMillis(at(14, 12, 50), now))
        assertEquals(0L, PrayerTimesWidgetSchedule.remainingMillis(null, now))
        assertEquals(11 * 60_000L, PrayerTimesWidgetSchedule.remainingMillis(at(14, 18, 24), now))
    }

    @Test
    fun refreshesAtEveryUpcomingTransitionIncludingTheLastFajr() {
        val times = PrayerTimesWidgetSchedule.refreshTimes(timeline, at(15, 18, 30))
        assertEquals(listOf(at(15, 19, 54), at(16, 5, 40)), times)
    }
}
