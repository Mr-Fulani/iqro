package forum.iqro.app

import android.content.Context
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews

/** Uses the host's Chronometer so countdown ticks don't wake the Flutter app. */
internal object PrayerTimesWidgetViews {
    fun create(context: Context, data: PrayerTimesData): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.prayer_times_widget)
        val rtl = data.locale == "ar"
        views.setInt(R.id.prayer_widget_root, "setLayoutDirection",
            if (rtl) View.LAYOUT_DIRECTION_RTL else View.LAYOUT_DIRECTION_LTR)
        val labels = listOf(data.fajrLabel, data.sunriseLabel, data.dhuhrLabel,
            data.asrLabel, data.maghribLabel, data.ishaLabel)
        val times = listOf(data.fajrTime, data.sunriseTime, data.dhuhrTime,
            data.asrTime, data.maghribTime, data.ishaTime)
        val nameIds = listOf(R.id.fajr_name, R.id.sunrise_name, R.id.dhuhr_name,
            R.id.asr_name, R.id.maghrib_name, R.id.isha_name)
        val timeIds = listOf(R.id.fajr_time, R.id.sunrise_time, R.id.dhuhr_time,
            R.id.asr_time, R.id.maghrib_time, R.id.isha_time)
        nameIds.forEachIndexed { index, id -> views.setTextViewText(id, labels[index] ?: "—") }
        timeIds.forEachIndexed { index, id -> views.setTextViewText(id, times[index] ?: "—") }
        views.setTextViewText(R.id.next_hour, data.nextHour ?: "—")
        views.setTextViewText(R.id.next_minute, data.nextMinute ?: "—")
        views.setTextViewText(R.id.next_name, data.nextName ?: "")
        views.setTextViewText(R.id.countdown_label, data.nextLabel ?: "")
        views.setInt(R.id.prayer_clock, "setBackgroundResource",
            if (data.period == "night") R.drawable.prayer_clock_night else R.drawable.prayer_clock_day)
        val target = data.nextEpoch?.toLongOrNull()
        val hasSchedule = target != null
        views.setViewVisibility(R.id.prayer_content, if (hasSchedule) View.VISIBLE else View.GONE)
        views.setViewVisibility(R.id.prayer_empty, if (hasSchedule) View.GONE else View.VISIBLE)
        val setupMessage = when (data.locale) {
            "ar" -> "افتح IQRO واختر موقعك"
            "tr" -> "IQRO'yu açın ve konumunuzu seçin"
            "en" -> "Open IQRO and choose your location"
            else -> "Откройте IQRO и выберите местоположение"
        }
        views.setTextViewText(R.id.prayer_empty, data.dateLocation?.takeIf { it.isNotEmpty() } ?: setupMessage)
        val remaining = ((target ?: 0L) - System.currentTimeMillis()).coerceAtLeast(0L)
        views.setBoolean(R.id.prayer_countdown, "setCountDown", true)
        views.setChronometer(R.id.prayer_countdown, SystemClock.elapsedRealtime() + remaining,
            null, hasSchedule && remaining > 0L)
        return views
    }
}
