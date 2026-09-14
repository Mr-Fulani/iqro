import 'package:home_widget_generator/home_widget_generator.dart';

// Data contract. Run dart run tool/generate_prayer_widget.dart to regenerate
// the bridge and install the native views with live system countdowns.
@HomeWidget(
  name: 'Время намаза',
  description: 'Ближайшая молитва и время пяти намазов',
  dartOutput: 'lib/core/widgets/prayer_times.home_widget.dart',
  widgetUrl: 'iqro://open/prayer',
  localization: HomeWidgetLocalization(
    defaultLocale: 'ru',
    supportedLocales: ['ru', 'en', 'ar', 'tr'],
    name: {'en': 'Prayer times', 'ar': 'أوقات الصلاة', 'tr': 'Namaz vakitleri'},
    description: {
      'en': 'Next prayer and all five daily prayer times',
      'ar': 'الصلاة القادمة ومواقيت الصلوات الخمس',
      'tr': 'Sıradaki namaz ve beş vakit namaz saatleri',
    },
  ),
  android: HomeWidgetAndroidConfiguration(
    minWidth: 280,
    minHeight: 140,
    minResizeWidth: 280,
    minResizeHeight: 140,
    targetCellWidth: 4,
    targetCellHeight: 2,
    resizeMode: HWAndroidResizeMode.horizontalAndVertical,
    updatePeriodMillis: 21600000,
    backgroundColor: HWColor.fixed(0xFF090909),
  ),
  iOS: HomeWidgetIOSConfiguration(
    groupId: 'group.forum.iqro.app',
    supportedFamilies: [HWWidgetFamily.systemMedium],
    backgroundColor: HWColor.fixed(0xFF090909),
  ),
  widget: HWDataOnly([
    HWString('title', defaultValue: 'IQRO'),
    HWString('locale', defaultValue: 'ru'),
    HWString('fajrLabel'),
    HWString('sunriseLabel'),
    HWString('dhuhrLabel'),
    HWString('asrLabel'),
    HWString('maghribLabel'),
    HWString('ishaLabel'),
    HWTimedData(HWString('dateLocation', defaultValue: '')),
    HWTimedData(HWString('nextLabel', defaultValue: '')),
    HWTimedData(HWString('nextPrayer', defaultValue: '')),
    HWTimedData(HWString('nextName', defaultValue: '')),
    HWTimedData(HWString('nextHour', defaultValue: '—')),
    HWTimedData(HWString('nextMinute', defaultValue: '—')),
    HWTimedData(HWString('nextEpoch', defaultValue: '')),
    HWTimedData(HWString('period', defaultValue: 'day')),
    HWTimedData(HWString('fajrTime', defaultValue: '—')),
    HWTimedData(HWString('sunriseTime', defaultValue: '—')),
    HWTimedData(HWString('dhuhrTime', defaultValue: '—')),
    HWTimedData(HWString('asrTime', defaultValue: '—')),
    HWTimedData(HWString('maghribTime', defaultValue: '—')),
    HWTimedData(HWString('ishaTime', defaultValue: '—')),
  ]),
)
class PrayerTimes {}
