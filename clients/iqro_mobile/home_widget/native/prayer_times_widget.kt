// Installed by tool/generate_prayer_widget.dart. Edit the template in home_widget/native.
class PrayerTimesHomeWidget : GlanceAppWidget() {
  override val stateDefinition = HomeWidgetGlanceStateDefinition()

  override suspend fun provideGlance(context: Context, id: GlanceId) {
    PrayerTimesWidgetSchedule.armRefresh(context, id)
    provideContent {
      val state = currentState<HomeWidgetGlanceState>()
      val data = PrayerTimesWidgetSchedule.resolve(state.preferences)
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
