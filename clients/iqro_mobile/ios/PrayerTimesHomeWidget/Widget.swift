// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Placeholder SwiftUI widget.
//
// App Group ID used here: group.forum.iqro.app

import SwiftUI
import WidgetKit

struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> PrayerTimesHomeWidgetEntry {
    PrayerTimesHomeWidgetEntry(date: Date(), data: PrayerTimesData.fromUserDefaults(nil))
  }

  func getSnapshot(in context: Context, completion: @escaping (PrayerTimesHomeWidgetEntry) -> Void) {
    let prefs = UserDefaults(suiteName: "group.forum.iqro.app")
    let data = PrayerTimesData.fromUserDefaults(prefs)

    completion(PrayerTimesHomeWidgetEntry(date: Date(), data: data))

  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
    let prefs = UserDefaults(suiteName: "group.forum.iqro.app")
    let timedEntries = PrayerTimesData.loadTimedEntries(prefs)
    let now = Date()
    var entries: [PrayerTimesHomeWidgetEntry] = [
      PrayerTimesHomeWidgetEntry(
        date: now,
        data: PrayerTimesData.fromUserDefaults(prefs, at: now, timedEntries: timedEntries)
      )
    ]
    for timedEntry in timedEntries where timedEntry.date > now {
      entries.append(
        PrayerTimesHomeWidgetEntry(
          date: timedEntry.date,
          data: PrayerTimesData.fromUserDefaults(prefs, at: timedEntry.date, timedEntries: timedEntries)
        )
      )
    }
    completion(Timeline(entries: entries, policy: .atEnd))

  }
}

struct PrayerTimesHomeWidgetEntry: TimelineEntry {
  let date: Date
  let data: PrayerTimesData
}


struct PrayerTimesHomeWidgetEntryView: View {
  var entry: Provider.Entry

  @Environment(\.colorScheme) var colorScheme

  var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    Text(entry.data.title ?? "")
                        .font(.system(size: 13.0, weight: .bold)).foregroundColor(Color(red: 1.0, green: 1.0, blue: 1.0, opacity: 1.0))
                    Text(entry.data.dateLocation ?? "")
                        .font(.system(size: 10.0)).foregroundColor(Color(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.7490196078431373))
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(entry.data.nextLabel ?? "")
                        .font(.system(size: 10.0)).foregroundColor(Color(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.7490196078431373))
                    Text(entry.data.nextPrayer ?? "")
                        .font(.system(size: 17.0, weight: .bold)).foregroundColor(Color(red: 0.8862745098039215, green: 0.7137254901960784, blue: 0.396078431372549, opacity: 1.0))
                }
            }
            Spacer()
            HStack(alignment: .bottom) {
                VStack(alignment: .leading) {
                    Text(entry.data.fajrLabel ?? "")
                        .font(.system(size: 10.0)).foregroundColor(Color(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.7490196078431373))
                    Text(entry.data.fajrTime ?? "")
                        .font(.system(size: 14.0, weight: .bold)).foregroundColor(Color(red: 1.0, green: 1.0, blue: 1.0, opacity: 1.0))
                }
                Spacer()
                VStack(alignment: .leading) {
                    Text(entry.data.dhuhrLabel ?? "")
                        .font(.system(size: 10.0)).foregroundColor(Color(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.7490196078431373))
                    Text(entry.data.dhuhrTime ?? "")
                        .font(.system(size: 14.0, weight: .bold)).foregroundColor(Color(red: 1.0, green: 1.0, blue: 1.0, opacity: 1.0))
                }
                Spacer()
                VStack(alignment: .leading) {
                    Text(entry.data.asrLabel ?? "")
                        .font(.system(size: 10.0)).foregroundColor(Color(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.7490196078431373))
                    Text(entry.data.asrTime ?? "")
                        .font(.system(size: 14.0, weight: .bold)).foregroundColor(Color(red: 1.0, green: 1.0, blue: 1.0, opacity: 1.0))
                }
                Spacer()
                VStack(alignment: .leading) {
                    Text(entry.data.maghribLabel ?? "")
                        .font(.system(size: 10.0)).foregroundColor(Color(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.7490196078431373))
                    Text(entry.data.maghribTime ?? "")
                        .font(.system(size: 14.0, weight: .bold)).foregroundColor(Color(red: 1.0, green: 1.0, blue: 1.0, opacity: 1.0))
                }
                Spacer()
                VStack(alignment: .leading) {
                    Text(entry.data.ishaLabel ?? "")
                        .font(.system(size: 10.0)).foregroundColor(Color(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.7490196078431373))
                    Text(entry.data.ishaTime ?? "")
                        .font(.system(size: 14.0, weight: .bold)).foregroundColor(Color(red: 1.0, green: 1.0, blue: 1.0, opacity: 1.0))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    .applyContainerBackground((colorScheme == .dark ? Color(red: 0.027450980392156862, green: 0.10196078431372549, blue: 0.08627450980392157, opacity: 1.0) : Color(red: 0.027450980392156862, green: 0.24313725490196078, blue: 0.20392156862745098, opacity: 1.0)))
    .widgetURL(URL(string: "iqro://open/prayer?homeWidget"))
  }
}

struct PrayerTimesHomeWidget: Widget {
  let kind: String = "PrayerTimesHomeWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: Provider()) { entry in
      PrayerTimesHomeWidgetEntryView(entry: entry)
    }
    .configurationDisplayName(NSLocalizedString("home_widget_prayer_times_label", comment: ""))
    .description(NSLocalizedString("home_widget_prayer_times_description", comment: ""))
    .supportedFamilies([.systemMedium])
  }
}

extension View {
  @ViewBuilder
  func applyContainerBackground<T: View>(_ backgroundView: T) -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      self.containerBackground(for: .widget) { backgroundView }
    } else {
      self.background(backgroundView)
    }
  }
}

struct PrayerTimesData {
  let title: String?
  let fajrLabel: String?
  let dhuhrLabel: String?
  let asrLabel: String?
  let maghribLabel: String?
  let ishaLabel: String?
  let dateLocation: String?
  let nextLabel: String?
  let nextPrayer: String?
  let fajrTime: String?
  let dhuhrTime: String?
  let asrTime: String?
  let maghribTime: String?
  let ishaTime: String?

  static let paramPrefix = "home_widget.PrayerTimes"

  static func fromUserDefaults(
    _ defaults: UserDefaults?,
    at date: Date = Date(),
    timedEntries: [(date: Date, values: [String: Any])]? = nil
  ) -> PrayerTimesData {
    let timedValues = activeTimedValues(timedEntries ?? loadTimedEntries(defaults), at: date)
    return PrayerTimesData(
      title: (defaults?.string(forKey: "\(paramPrefix).title") ?? "IQRO"),
      fajrLabel: defaults?.string(forKey: "\(paramPrefix).fajrLabel"),
      dhuhrLabel: defaults?.string(forKey: "\(paramPrefix).dhuhrLabel"),
      asrLabel: defaults?.string(forKey: "\(paramPrefix).asrLabel"),
      maghribLabel: defaults?.string(forKey: "\(paramPrefix).maghribLabel"),
      ishaLabel: defaults?.string(forKey: "\(paramPrefix).ishaLabel"),
      dateLocation: (timedValues["dateLocation"] as? String) ?? "",
      nextLabel: (timedValues["nextLabel"] as? String) ?? "",
      nextPrayer: (timedValues["nextPrayer"] as? String) ?? "",
      fajrTime: (timedValues["fajrTime"] as? String) ?? "—",
      dhuhrTime: (timedValues["dhuhrTime"] as? String) ?? "—",
      asrTime: (timedValues["asrTime"] as? String) ?? "—",
      maghribTime: (timedValues["maghribTime"] as? String) ?? "—",
      ishaTime: (timedValues["ishaTime"] as? String) ?? "—",
    )
  }

  fileprivate static func loadTimedEntries(_ defaults: UserDefaults?) -> [(date: Date, values: [String: Any])] {
    guard let path = defaults?.string(forKey: "\(paramPrefix).timedData") else { return [] }
    guard FileManager.default.fileExists(atPath: path) else { return [] }
    do {
      let raw = try Data(contentsOf: URL(fileURLWithPath: path))
      guard let json = try JSONSerialization.jsonObject(with: raw) as? [String: Any] else { return [] }
      var entries: [(date: Date, values: [String: Any])] = []
      for (key, value) in json {
        guard let millis = Double(key), let values = value as? [String: Any] else { continue }
        entries.append((date: Date(timeIntervalSince1970: millis / 1000), values: values))
      }
      entries.sort { $0.date < $1.date }
      return entries
    } catch {
      return []
    }
  }

  fileprivate static func activeTimedValues(_ entries: [(date: Date, values: [String: Any])], at date: Date) -> [String: Any] {
    var values: [String: Any] = [:]
    for entry in entries {
      if entry.date > date { break }
      values = entry.values
    }
    return values
  }
}

