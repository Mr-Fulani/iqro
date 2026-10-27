// Installed by tool/generate_prayer_widget.dart. Edit the template in home_widget/native.
class PrayerTimesHomeWidget : GlanceAppWidget() {
  override val stateDefinition = HomeWidgetGlanceStateDefinition()

  // The card is fitted to the cell it is given (HomeWidgetCard).
  override val sizeMode = androidx.glance.appwidget.SizeMode.Exact

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
          remoteViews = PrayerTimesWidgetViews.create(
            context, data, androidx.glance.LocalSize.current),
          modifier = GlanceModifier.fillMaxSize()
        )
      }
    }
  }
}
