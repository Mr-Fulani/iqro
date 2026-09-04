import 'package:home_widget_generator/home_widget_generator.dart';

const _primaryText = HWColor.fixed(0xFFFFFFFF);
const _secondaryText = HWColor.fixed(0xBFFFFFFF);
const _accentText = HWColor.fixed(0xFFE2B665);

const _prayerNameStyle = HWTextStyle(fontSize: 10, color: _secondaryText);
const _prayerTimeStyle = HWTextStyle(
  fontSize: 14,
  fontWeight: HWFontWeight.bold,
  color: _primaryText,
);

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
    minWidth: 250,
    minHeight: 110,
    minResizeWidth: 250,
    minResizeHeight: 110,
    targetCellWidth: 4,
    targetCellHeight: 2,
    resizeMode: HWAndroidResizeMode.horizontalAndVertical,
    updatePeriodMillis: 21600000,
    backgroundColor: HWColor.themed(
      light: HWColor.fixed(0xFF073E34),
      dark: HWColor.fixed(0xFF071A16),
    ),
  ),
  iOS: HomeWidgetIOSConfiguration(
    groupId: 'group.forum.iqro.app',
    supportedFamilies: [HWWidgetFamily.systemMedium],
    backgroundColor: HWColor.themed(
      light: HWColor.fixed(0xFF073E34),
      dark: HWColor.fixed(0xFF071A16),
    ),
  ),
  widget: HWFill(
    child: HWColumn(
      mainAxisAlignment: HWMainAxisAlignment.spaceBetween,
      crossAxisAlignment: HWCrossAxisAlignment.start,
      children: [
        HWRow(
          crossAxisAlignment: HWCrossAxisAlignment.start,
          mainAxisAlignment: HWMainAxisAlignment.spaceBetween,
          children: [
            HWColumn(
              crossAxisAlignment: HWCrossAxisAlignment.start,
              children: [
                HWText(
                  HWString('title', defaultValue: 'IQRO'),
                  style: HWTextStyle(
                    fontSize: 13,
                    fontWeight: HWFontWeight.bold,
                    color: _primaryText,
                  ),
                ),
                HWText(
                  HWTimedData(HWString('dateLocation', defaultValue: '')),
                  style: HWTextStyle(fontSize: 10, color: _secondaryText),
                ),
              ],
            ),
            HWColumn(
              crossAxisAlignment: HWCrossAxisAlignment.end,
              children: [
                HWText(
                  HWTimedData(HWString('nextLabel', defaultValue: '')),
                  style: HWTextStyle(fontSize: 10, color: _secondaryText),
                ),
                HWText(
                  HWTimedData(HWString('nextPrayer', defaultValue: '')),
                  style: HWTextStyle(
                    fontSize: 17,
                    fontWeight: HWFontWeight.bold,
                    color: _accentText,
                  ),
                ),
              ],
            ),
          ],
        ),
        HWRow(
          crossAxisAlignment: HWCrossAxisAlignment.end,
          mainAxisAlignment: HWMainAxisAlignment.spaceBetween,
          children: [
            HWColumn(
              crossAxisAlignment: HWCrossAxisAlignment.start,
              children: [
                HWText(HWString('fajrLabel'), style: _prayerNameStyle),
                HWText(
                  HWTimedData(HWString('fajrTime', defaultValue: '—')),
                  style: _prayerTimeStyle,
                ),
              ],
            ),
            HWColumn(
              crossAxisAlignment: HWCrossAxisAlignment.start,
              children: [
                HWText(HWString('dhuhrLabel'), style: _prayerNameStyle),
                HWText(
                  HWTimedData(HWString('dhuhrTime', defaultValue: '—')),
                  style: _prayerTimeStyle,
                ),
              ],
            ),
            HWColumn(
              crossAxisAlignment: HWCrossAxisAlignment.start,
              children: [
                HWText(HWString('asrLabel'), style: _prayerNameStyle),
                HWText(
                  HWTimedData(HWString('asrTime', defaultValue: '—')),
                  style: _prayerTimeStyle,
                ),
              ],
            ),
            HWColumn(
              crossAxisAlignment: HWCrossAxisAlignment.start,
              children: [
                HWText(HWString('maghribLabel'), style: _prayerNameStyle),
                HWText(
                  HWTimedData(HWString('maghribTime', defaultValue: '—')),
                  style: _prayerTimeStyle,
                ),
              ],
            ),
            HWColumn(
              crossAxisAlignment: HWCrossAxisAlignment.start,
              children: [
                HWText(HWString('ishaLabel'), style: _prayerNameStyle),
                HWText(
                  HWTimedData(HWString('ishaTime', defaultValue: '—')),
                  style: _prayerTimeStyle,
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ),
)
class PrayerTimes {}
