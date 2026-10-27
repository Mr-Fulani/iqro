package forum.iqro.app

import android.content.Context
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import androidx.glance.GlanceId
import androidx.compose.ui.unit.DpSize
import androidx.glance.GlanceModifier
import androidx.glance.LocalSize
import androidx.glance.appwidget.AndroidRemoteViews
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.provideContent
import androidx.glance.currentState
import androidx.glance.layout.fillMaxSize
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import org.json.JSONObject

class ReadingPlanHomeWidgetReceiver : HomeWidgetGlanceWidgetReceiver<ReadingPlanHomeWidget>() {
    override val glanceAppWidget = ReadingPlanHomeWidget()
}

class ReadingPlanHomeWidget : GlanceAppWidget() {
    override val stateDefinition = HomeWidgetGlanceStateDefinition()
    // The card is fitted to the cell it is given (HomeWidgetCard).
    override val sizeMode = SizeMode.Exact
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            val state = currentState<HomeWidgetGlanceState>()
            val snapshot = try {
                JSONObject(state.preferences.getString("home_widget.ReadingPlan.snapshot", "{}") ?: "{}")
            } catch (_: Exception) { JSONObject() }
            AndroidRemoteViews(
                remoteViews = ReadingPlanWidgetViews.create(context, snapshot, LocalSize.current),
                modifier = GlanceModifier.fillMaxSize(),
            )
        }
    }
}

internal object ReadingPlanWidgetViews {
    // Photographs of the palm stages, cropped to the panel with its rounded
    // corners and a darker lower half baked in for the white text.
    private val PALM_STAGES = intArrayOf(
        R.drawable.reading_plan_palm_bg_0, R.drawable.reading_plan_palm_bg_1,
        R.drawable.reading_plan_palm_bg_2, R.drawable.reading_plan_palm_bg_3,
        R.drawable.reading_plan_palm_bg_4, R.drawable.reading_plan_palm_bg_5)

    fun create(context: Context, data: JSONObject, size: DpSize): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.reading_plan_widget)
        HomeWidgetCard.fit(context, views, R.id.plan_widget_frame, size)
        views.setInt(R.id.plan_widget_root, "setLayoutDirection",
            if (data.optString("locale") == "ar") View.LAYOUT_DIRECTION_RTL else View.LAYOUT_DIRECTION_LTR)
        views.setOnClickPendingIntent(R.id.plan_widget_root, HomeWidgetLaunchIntent.getActivity(
            context, MainActivity::class.java, Uri.parse("iqro://open/plan?homeWidget")))
        views.setOnClickPendingIntent(R.id.plan_prayers, HomeWidgetLaunchIntent.getActivity(
            context, MainActivity::class.java, Uri.parse("iqro://open/after-prayer?homeWidget")))
        val current = data.optBoolean("isCurrent") && data.optLong("validUntil") > System.currentTimeMillis()
        views.setViewVisibility(R.id.plan_content, if (current) View.VISIBLE else View.GONE)
        views.setViewVisibility(R.id.plan_empty, if (current) View.GONE else View.VISIBLE)
        views.setTextViewText(R.id.plan_empty, data.optString("emptyLabel", context.getString(R.string.home_widget_reading_plan_open)))
        val texts = mapOf(R.id.plan_title to "title", R.id.plan_achieved to "achieved",
            R.id.plan_target to "targetLine", R.id.plan_unit to "unit",
            R.id.plan_remaining_label to "remainingLabel", R.id.plan_remaining to "remaining",
            R.id.plan_remaining_unit to "unit", R.id.plan_prayer_heading to "afterPrayerLabel",
            R.id.plan_page_unit to "pageUnit")
        texts.forEach { (id, key) -> views.setTextViewText(id, data.optString(key, "—")) }
        val palm = PALM_STAGES[data.optInt("palmStage").coerceIn(0, PALM_STAGES.lastIndex)]
        views.setImageViewResource(R.id.plan_palm_bg, palm)
        views.setContentDescription(R.id.plan_palm_bg, data.optString("palmLabel"))
        views.setProgressBar(R.id.plan_progress, 100, data.optInt("progress").coerceIn(0,100), false)
        val labels = listOf(R.id.plan_fajr_name, R.id.plan_dhuhr_name, R.id.plan_asr_name, R.id.plan_maghrib_name, R.id.plan_isha_name)
        val values = listOf(R.id.plan_fajr_value, R.id.plan_dhuhr_value, R.id.plan_asr_value, R.id.plan_maghrib_value, R.id.plan_isha_value)
        val rows = data.optJSONArray("rows")
        labels.forEachIndexed { index, id ->
            val row = rows?.optJSONObject(index)
            views.setTextViewText(id, row?.optString("label") ?: "—")
            views.setTextViewText(values[index], row?.optString("value") ?: "—")
        }
        return views
    }
}
