package forum.iqro.app

import android.content.Context
import android.content.SharedPreferences
import androidx.glance.GlanceId
import androidx.glance.appwidget.state.getAppWidgetState
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.HomeWidgetScheduler
import org.json.JSONObject
import java.io.File

/**
 * Chooses what the prayer widget shows from the whole published timeline, so a
 * render that arrives late never counts down to a prayer that has already begun,
 * and keeps the widget's own refresh alarms armed while the app is not running.
 */
internal object PrayerTimesWidgetSchedule {
    private const val TIMED_DATA_KEY = "home_widget.PrayerTimes.timedData"

    /** A published timeline entry: when it starts and the prayer it counts down to. */
    data class Entry(val startsAt: Long, val nextPrayerAt: Long?)

    /**
     * Start of the entry for the next prayer that has not begun yet, or null once
     * the published schedule has run out. Of the entries counting down to that
     * prayer the latest one already started wins, so the date and timetable shown
     * are today's (after Isha this is still today's entry, aiming at tomorrow's Fajr).
     */
    fun activeEntryStart(entries: List<Entry>, now: Long): Long? {
        val nextPrayerAt = entries.mapNotNull { it.nextPrayerAt }.filter { it > now }.minOrNull()
            ?: return null
        val candidates = entries.filter { it.nextPrayerAt == nextPrayerAt }
        val chosen = candidates.filter { it.startsAt <= now }.maxByOrNull { it.startsAt }
            ?: candidates.minByOrNull { it.startsAt }
        return chosen?.startsAt
    }

    /** Future moments at which the widget content changes. */
    fun refreshTimes(entries: List<Entry>, now: Long): List<Long> =
        entries.flatMap { listOfNotNull(it.startsAt, it.nextPrayerAt) }
            .filter { it > now }.distinct().sorted()

    /** Countdown length; never negative, so a stale target shows zero instead. */
    fun remainingMillis(target: Long?, now: Long): Long =
        ((target ?: now) - now).coerceAtLeast(0L)

    fun resolve(prefs: SharedPreferences, now: Long = System.currentTimeMillis()): PrayerTimesData =
        PrayerTimesData.fromPreferences(prefs, activeEntryStart(readEntries(prefs), now) ?: now)

    /**
     * Re-arms the update alarms from the published timeline on every render, so
     * alarms dropped by the system (force stop, vendor battery savers) come back
     * with the next periodic or launcher-driven update instead of the next app start.
     */
    suspend fun armRefresh(context: Context, id: GlanceId) {
        val state = getAppWidgetState<HomeWidgetGlanceState>(
            context, HomeWidgetGlanceStateDefinition(), id)
        HomeWidgetScheduler.schedule(context, PrayerTimesHomeWidgetReceiver::class.java.name,
            refreshTimes(readEntries(state.preferences), System.currentTimeMillis()))
    }

    private fun readEntries(prefs: SharedPreferences): List<Entry> {
        val path = prefs.getString(TIMED_DATA_KEY, null) ?: return emptyList()
        return try {
            val file = File(path)
            if (!file.exists()) return emptyList()
            val json = JSONObject(file.readText())
            json.keys().asSequence().mapNotNull { key ->
                val startsAt = key.toLongOrNull() ?: return@mapNotNull null
                Entry(startsAt, json.optJSONObject(key)?.optString("nextEpoch")?.toLongOrNull())
            }.toList()
        } catch (_: Exception) {
            emptyList()
        }
    }
}
