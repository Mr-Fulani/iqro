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
import androidx.glance.layout.Alignment
import androidx.glance.layout.Spacer
import androidx.glance.layout.Row
import androidx.glance.text.TextStyle
import androidx.glance.color.ColorProvider
import androidx.compose.ui.unit.sp
import androidx.glance.text.FontWeight
import androidx.glance.GlanceTheme
import androidx.compose.ui.unit.dp
import androidx.glance.layout.padding
import androidx.glance.action.clickable
import android.net.Uri
import es.antonborri.home_widget.actionStartActivity
import com.ryanheise.audioservice.AudioServiceActivity

class PrayerTimesHomeWidget : GlanceAppWidget() {
  override val stateDefinition = HomeWidgetGlanceStateDefinition()

  override suspend fun provideGlance(context: Context, id: GlanceId) {
    provideContent { WidgetContent(context, currentState()) }
  }

  @Composable
  private fun WidgetContent(context: Context, currentState: HomeWidgetGlanceState) {
    val prefs = currentState.preferences
    val widgetData = PrayerTimesData.fromPreferences(prefs)
    GlanceTheme {
            Box(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFF073E34), night = Color(0xFF071A16))).padding(16.dp).fillMaxSize().clickable(onClick = actionStartActivity<AudioServiceActivity>(context, Uri.parse("iqro://open/prayer?homeWidget"))), contentAlignment = Alignment.Center) {
                Column(modifier = GlanceModifier.fillMaxSize(), horizontalAlignment = Alignment.Start) {
                    Row(verticalAlignment = Alignment.Top) {
                        Column(horizontalAlignment = Alignment.Start) {
                            Text(text = widgetData.title ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFFFFFFFF), night = Color(0xFFFFFFFF)), fontSize = 13.sp, fontWeight = FontWeight.Bold))
                            Text(text = widgetData.dateLocation ?: "", style = TextStyle(color = ColorProvider(day = Color(0xBFFFFFFF), night = Color(0xBFFFFFFF)), fontSize = 10.sp))
                        }
                        Spacer(modifier = GlanceModifier.defaultWeight())
                        Column(horizontalAlignment = Alignment.End) {
                            Text(text = widgetData.nextLabel ?: "", style = TextStyle(color = ColorProvider(day = Color(0xBFFFFFFF), night = Color(0xBFFFFFFF)), fontSize = 10.sp))
                            Text(text = widgetData.nextPrayer ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFFE2B665), night = Color(0xFFE2B665)), fontSize = 17.sp, fontWeight = FontWeight.Bold))
                        }
                    }
                    Spacer(modifier = GlanceModifier.defaultWeight())
                    Row(verticalAlignment = Alignment.Bottom) {
                        Column(horizontalAlignment = Alignment.Start) {
                            Text(text = widgetData.fajrLabel ?: "", style = TextStyle(color = ColorProvider(day = Color(0xBFFFFFFF), night = Color(0xBFFFFFFF)), fontSize = 10.sp))
                            Text(text = widgetData.fajrTime ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFFFFFFFF), night = Color(0xFFFFFFFF)), fontSize = 14.sp, fontWeight = FontWeight.Bold))
                        }
                        Spacer(modifier = GlanceModifier.defaultWeight())
                        Column(horizontalAlignment = Alignment.Start) {
                            Text(text = widgetData.dhuhrLabel ?: "", style = TextStyle(color = ColorProvider(day = Color(0xBFFFFFFF), night = Color(0xBFFFFFFF)), fontSize = 10.sp))
                            Text(text = widgetData.dhuhrTime ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFFFFFFFF), night = Color(0xFFFFFFFF)), fontSize = 14.sp, fontWeight = FontWeight.Bold))
                        }
                        Spacer(modifier = GlanceModifier.defaultWeight())
                        Column(horizontalAlignment = Alignment.Start) {
                            Text(text = widgetData.asrLabel ?: "", style = TextStyle(color = ColorProvider(day = Color(0xBFFFFFFF), night = Color(0xBFFFFFFF)), fontSize = 10.sp))
                            Text(text = widgetData.asrTime ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFFFFFFFF), night = Color(0xFFFFFFFF)), fontSize = 14.sp, fontWeight = FontWeight.Bold))
                        }
                        Spacer(modifier = GlanceModifier.defaultWeight())
                        Column(horizontalAlignment = Alignment.Start) {
                            Text(text = widgetData.maghribLabel ?: "", style = TextStyle(color = ColorProvider(day = Color(0xBFFFFFFF), night = Color(0xBFFFFFFF)), fontSize = 10.sp))
                            Text(text = widgetData.maghribTime ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFFFFFFFF), night = Color(0xFFFFFFFF)), fontSize = 14.sp, fontWeight = FontWeight.Bold))
                        }
                        Spacer(modifier = GlanceModifier.defaultWeight())
                        Column(horizontalAlignment = Alignment.Start) {
                            Text(text = widgetData.ishaLabel ?: "", style = TextStyle(color = ColorProvider(day = Color(0xBFFFFFFF), night = Color(0xBFFFFFFF)), fontSize = 10.sp))
                            Text(text = widgetData.ishaTime ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFFFFFFFF), night = Color(0xFFFFFFFF)), fontSize = 14.sp, fontWeight = FontWeight.Bold))
                        }
                    }
                }
            }
    }

  }
}

data class PrayerTimesData(
    val title: String? = null,
    val fajrLabel: String? = null,
    val dhuhrLabel: String? = null,
    val asrLabel: String? = null,
    val maghribLabel: String? = null,
    val ishaLabel: String? = null,
    val dateLocation: String? = null,
    val nextLabel: String? = null,
    val nextPrayer: String? = null,
    val fajrTime: String? = null,
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
                fajrLabel = prefs.getString("${PREFERENCES_PREFIX}.fajrLabel", null),
                dhuhrLabel = prefs.getString("${PREFERENCES_PREFIX}.dhuhrLabel", null),
                asrLabel = prefs.getString("${PREFERENCES_PREFIX}.asrLabel", null),
                maghribLabel = prefs.getString("${PREFERENCES_PREFIX}.maghribLabel", null),
                ishaLabel = prefs.getString("${PREFERENCES_PREFIX}.ishaLabel", null),
                dateLocation = if (timedValues.has("dateLocation") && !timedValues.isNull("dateLocation")) timedValues.optString("dateLocation") else "",
                nextLabel = if (timedValues.has("nextLabel") && !timedValues.isNull("nextLabel")) timedValues.optString("nextLabel") else "",
                nextPrayer = if (timedValues.has("nextPrayer") && !timedValues.isNull("nextPrayer")) timedValues.optString("nextPrayer") else "",
                fajrTime = if (timedValues.has("fajrTime") && !timedValues.isNull("fajrTime")) timedValues.optString("fajrTime") else "—",
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

