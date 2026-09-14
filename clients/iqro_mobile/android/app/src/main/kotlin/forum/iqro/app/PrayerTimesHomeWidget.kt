// GENERATED CODE - DO NOT MODIFY BY HAND
//
// This is a placeholder Glance (Jetpack Compose) widget.
package forum.iqro.app

import androidx.compose.runtime.Composable
import android.content.Context
import androidx.compose.ui.graphics.Color
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Box
import androidx.glance.layout.fillMaxSize
import androidx.glance.text.Text
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import androidx.glance.layout.Column
import androidx.glance.text.TextStyle
import androidx.glance.layout.Row
import androidx.glance.GlanceTheme
import androidx.glance.color.ColorProvider
import androidx.compose.ui.unit.dp
import androidx.glance.layout.padding
import androidx.glance.layout.Alignment
import androidx.glance.action.clickable
import android.net.Uri
import es.antonborri.home_widget.actionStartActivity

// Installed by tool/generate_prayer_widget.dart. Edit the template in home_widget/native.
class PrayerTimesHomeWidget : GlanceAppWidget() {
  override val stateDefinition = HomeWidgetGlanceStateDefinition()

  override suspend fun provideGlance(context: Context, id: GlanceId) {
    provideContent {
      val state = currentState<HomeWidgetGlanceState>()
      val data = PrayerTimesData.fromPreferences(state.preferences)
      Box(modifier = GlanceModifier.fillMaxSize().clickable(
        onClick = actionStartActivity<MainActivity>(context,
          Uri.parse("iqro://open/prayer?homeWidget"))
      )) {
        androidx.glance.appwidget.AndroidRemoteViews(
          remoteViews = PrayerTimesWidgetViews.create(context, data),
          modifier = GlanceModifier.fillMaxSize()
        )
      }
    }
  }
}

data class PrayerTimesData(
    val title: String? = null,
    val locale: String? = null,
    val fajrLabel: String? = null,
    val sunriseLabel: String? = null,
    val dhuhrLabel: String? = null,
    val asrLabel: String? = null,
    val maghribLabel: String? = null,
    val ishaLabel: String? = null,
    val dateLocation: String? = null,
    val nextLabel: String? = null,
    val nextPrayer: String? = null,
    val nextName: String? = null,
    val nextHour: String? = null,
    val nextMinute: String? = null,
    val nextEpoch: String? = null,
    val period: String? = null,
    val fajrTime: String? = null,
    val sunriseTime: String? = null,
    val dhuhrTime: String? = null,
    val asrTime: String? = null,
    val maghribTime: String? = null,
    val ishaTime: String? = null,
) {
    companion object {
        private const val PREFERENCES_PREFIX = "home_widget.PrayerTimes"

        fun fromPreferences(prefs: android.content.SharedPreferences, now: Long = System.currentTimeMillis()): PrayerTimesData {
            val timedValues = resolveTimedValues(prefs, now)
            return PrayerTimesData(
                title = prefs.getString("${PREFERENCES_PREFIX}.title", "IQRO"),
                locale = prefs.getString("${PREFERENCES_PREFIX}.locale", "ru"),
                fajrLabel = prefs.getString("${PREFERENCES_PREFIX}.fajrLabel", null),
                sunriseLabel = prefs.getString("${PREFERENCES_PREFIX}.sunriseLabel", null),
                dhuhrLabel = prefs.getString("${PREFERENCES_PREFIX}.dhuhrLabel", null),
                asrLabel = prefs.getString("${PREFERENCES_PREFIX}.asrLabel", null),
                maghribLabel = prefs.getString("${PREFERENCES_PREFIX}.maghribLabel", null),
                ishaLabel = prefs.getString("${PREFERENCES_PREFIX}.ishaLabel", null),
                dateLocation = if (timedValues.has("dateLocation") && !timedValues.isNull("dateLocation")) timedValues.optString("dateLocation") else "",
                nextLabel = if (timedValues.has("nextLabel") && !timedValues.isNull("nextLabel")) timedValues.optString("nextLabel") else "",
                nextPrayer = if (timedValues.has("nextPrayer") && !timedValues.isNull("nextPrayer")) timedValues.optString("nextPrayer") else "",
                nextName = if (timedValues.has("nextName") && !timedValues.isNull("nextName")) timedValues.optString("nextName") else "",
                nextHour = if (timedValues.has("nextHour") && !timedValues.isNull("nextHour")) timedValues.optString("nextHour") else "—",
                nextMinute = if (timedValues.has("nextMinute") && !timedValues.isNull("nextMinute")) timedValues.optString("nextMinute") else "—",
                nextEpoch = if (timedValues.has("nextEpoch") && !timedValues.isNull("nextEpoch")) timedValues.optString("nextEpoch") else "",
                period = if (timedValues.has("period") && !timedValues.isNull("period")) timedValues.optString("period") else "day",
                fajrTime = if (timedValues.has("fajrTime") && !timedValues.isNull("fajrTime")) timedValues.optString("fajrTime") else "—",
                sunriseTime = if (timedValues.has("sunriseTime") && !timedValues.isNull("sunriseTime")) timedValues.optString("sunriseTime") else "—",
                dhuhrTime = if (timedValues.has("dhuhrTime") && !timedValues.isNull("dhuhrTime")) timedValues.optString("dhuhrTime") else "—",
                asrTime = if (timedValues.has("asrTime") && !timedValues.isNull("asrTime")) timedValues.optString("asrTime") else "—",
                maghribTime = if (timedValues.has("maghribTime") && !timedValues.isNull("maghribTime")) timedValues.optString("maghribTime") else "—",
                ishaTime = if (timedValues.has("ishaTime") && !timedValues.isNull("ishaTime")) timedValues.optString("ishaTime") else "—",
            )
        }

        private fun resolveTimedValues(prefs: android.content.SharedPreferences, now: Long): org.json.JSONObject {
            val path = prefs.getString("${PREFERENCES_PREFIX}.timedData", null) ?: return org.json.JSONObject()
            return try {
                val file = java.io.File(path)
                if (!file.exists()) return org.json.JSONObject()
                val json = org.json.JSONObject(file.readText())
                var activeKey: String? = null
                var activeTimestamp = 0L
                val keys = json.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    val timestamp = key.toLongOrNull() ?: continue
                    if (timestamp <= now && (activeKey == null || timestamp > activeTimestamp)) {
                        activeKey = key
                        activeTimestamp = timestamp
                    }
                }
                val resolvedKey = activeKey ?: return org.json.JSONObject()
                json.optJSONObject(resolvedKey) ?: org.json.JSONObject()
            } catch (_: Exception) {
                org.json.JSONObject()
            }
        }
    }
}

