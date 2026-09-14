// Generate the shared data bridge, then install the custom native renderers.
// The schema DSL cannot express system countdowns or the illustrated clock.
import 'dart:io';
import 'dart:convert';

Future<void> main() async {
  final result = await Process.start(Platform.resolvedExecutable, [
    'run',
    'home_widget_cli:home_widget',
    'generate',
    '--input',
    'home_widget/prayer_times.dart',
  ], mode: ProcessStartMode.inheritStdio);
  final code = await result.exitCode;
  if (code != 0) exit(code);

  final swift = File('ios/PrayerTimesHomeWidget/Widget.swift');
  final swiftSource = swift.readAsStringSync();
  final start = swiftSource.indexOf(
    'struct PrayerTimesHomeWidgetEntryView: View',
  );
  final end = swiftSource.indexOf('struct PrayerTimesHomeWidget: Widget');
  if (start < 0 || end <= start) throw StateError('Swift template changed');
  final swiftView = File(
    'home_widget/native/prayer_times_view.swift',
  ).readAsStringSync();
  swift.writeAsStringSync(
    '${swiftSource.substring(0, start)}$swiftView\n${swiftSource.substring(end)}',
  );

  swift.writeAsStringSync(
    File('home_widget/native/reading_plan_view.swift').readAsStringSync(),
    mode: FileMode.append,
  );
  final bundle = File('ios/PrayerTimesHomeWidget/WidgetBundle.swift');
  bundle.writeAsStringSync(
    bundle.readAsStringSync().replaceFirst(
      '    PrayerTimesHomeWidget()',
      '    PrayerTimesHomeWidget()\n    ReadingPlanHomeWidget()',
    ),
  );
  final catalog = File('ios/PrayerTimesHomeWidget/Localizable.xcstrings');
  final localized =
      jsonDecode(catalog.readAsStringSync()) as Map<String, dynamic>;
  (localized['strings'] as Map<String, dynamic>).addAll(
    jsonDecode(
          File(
            'home_widget/native/reading_plan_strings.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>,
  );
  catalog.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(localized)}\n',
  );

  final kotlin = File(
    'android/app/src/main/kotlin/forum/iqro/app/PrayerTimesHomeWidget.kt',
  );
  final kotlinSource = kotlin.readAsStringSync();
  final kotlinStart = kotlinSource.indexOf('class PrayerTimesHomeWidget :');
  final kotlinEnd = kotlinSource.indexOf('data class PrayerTimesData(');
  if (kotlinStart < 0 || kotlinEnd <= kotlinStart) {
    throw StateError('Kotlin template changed');
  }
  final kotlinView = File(
    'home_widget/native/prayer_times_widget.kt',
  ).readAsStringSync();
  kotlin.writeAsStringSync(
    '${kotlinSource.substring(0, kotlinStart)}$kotlinView\n${kotlinSource.substring(kotlinEnd)}',
  );
}
