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


// Installed by tool/generate_prayer_widget.dart. Edit the template in home_widget/native.
struct PrayerTimesHomeWidgetEntryView: View {
  var entry: Provider.Entry
  private var data: PrayerTimesData { entry.data }
  private var target: Date? {
    guard let raw = data.nextEpoch, let millis = Double(raw) else { return nil }
    return Date(timeIntervalSince1970: millis / 1000)
  }
  private var rtl: Bool { data.locale == "ar" }

  var body: some View {
    GeometryReader { geometry in
      let gap: CGFloat = geometry.size.width < 310 ? 8 : 11
      let clockWidth = geometry.size.width * 0.265
      let scheduleWidth = geometry.size.width * 0.385
      if target == nil {
        VStack(alignment: .leading, spacing: 10) {
          Image(systemName: "sun.max.fill").font(.system(size: 25))
            .foregroundColor(Color(red: 0.94, green: 0.77, blue: 0.33))
          Text(data.dateLocation?.isEmpty == false ? data.dateLocation! : setupMessage)
            .font(.system(size: 15, weight: .medium)).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      } else {
        HStack(spacing: gap) {
          ZStack {
            PrayerClockSky(night: data.period == "night")
            VStack(spacing: 0) {
              Text(data.nextHour ?? "—")
              Text(data.nextMinute ?? "—")
            }
            .font(.system(size: geometry.size.height * 0.45, weight: .light).monospacedDigit()).minimumScaleFactor(0.65).lineLimit(1)
            .padding(.vertical, 2)
          }
          .frame(width: clockWidth)
          .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("\(data.nextHour ?? ""):\(data.nextMinute ?? "")")

          VStack(spacing: 0) {
            Text(data.nextName ?? "")
              .font(.system(size: 24, weight: .regular))
              .lineLimit(1).minimumScaleFactor(0.55)
            Spacer(minLength: 4)
            Text(data.nextLabel ?? "")
              .font(.system(size: 20)).lineLimit(1).minimumScaleFactor(0.6)
            Spacer(minLength: 4)
            countdown
              .font(.system(size: 23, weight: .semibold).monospacedDigit())
              .lineLimit(1).minimumScaleFactor(0.55)
              .environment(\.layoutDirection, .leftToRight)
          }
          .padding(.vertical, 5)
          .frame(maxWidth: .infinity)
          Rectangle().fill(Color.white.opacity(0.35)).frame(width: 1)
          VStack(spacing: 0) {
            prayerRow(data.fajrLabel, data.fajrTime)
            Spacer(minLength: 1)
            prayerRow(data.sunriseLabel, data.sunriseTime, sunrise: true)
            Spacer(minLength: 1)
            prayerRow(data.dhuhrLabel, data.dhuhrTime)
            Spacer(minLength: 1)
            prayerRow(data.asrLabel, data.asrTime)
            Spacer(minLength: 1)
            prayerRow(data.maghribLabel, data.maghribTime)
            Spacer(minLength: 1)
            prayerRow(data.ishaLabel, data.ishaTime)
          }.frame(width: scheduleWidth)
        }
      }
    }
    .foregroundColor(.white)
    .environment(\.locale, Locale(identifier: data.locale ?? "ru"))
    .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
    .applyContainerBackground(
      LinearGradient(gradient: Gradient(colors: [Color(white: 0.105), .black]), startPoint: .topLeading, endPoint: .bottomTrailing)
    )
    .widgetURL(URL(string: "iqro://open/prayer?homeWidget"))
  }

  @ViewBuilder private var countdown: some View {
    if let target = target, target > entry.date {
      if #available(iOSApplicationExtension 16.0, *) {
        Text(timerInterval: entry.date...target, countsDown: true)
          .multilineTextAlignment(.center)
      } else {
        Text(target, style: .timer).multilineTextAlignment(.center)
      }
    } else { Text("—") }
  }

  private var setupMessage: String {
    switch data.locale {
    case "ar": return "افتح IQRO واختر موقعك"
    case "tr": return "IQRO'yu açın ve konumunuzu seçin"
    case "en": return "Open IQRO and choose your location"
    default: return "Откройте IQRO и выберите местоположение"
    }
  }

  private func prayerRow(_ name: String?, _ time: String?, sunrise: Bool = false) -> some View {
    HStack(spacing: 3) {
      Text(name ?? "—")
        .font(sunrise ? .system(size: 14).italic() : .system(size: 14))
        .lineLimit(1).minimumScaleFactor(0.65)
      Spacer(minLength: 2)
      Text(time ?? "—").font(.system(size: 14).monospacedDigit())
        .lineLimit(1).minimumScaleFactor(0.8)
        .environment(\.layoutDirection, .leftToRight)
    }.accessibilityElement(children: .combine)
  }
}

private struct PrayerClockSky: View {
  let night: Bool
  var body: some View {
    GeometryReader { geo in
      ZStack {
        Color(red: night ? 0.10 : 0.20, green: night ? 0.14 : 0.17, blue: night ? 0.22 : 0.09)
        Circle().fill(Color.yellow.opacity(night ? 0 : 0.12))
          .frame(width: geo.size.width * 0.92).offset(y: -3)
        Circle().fill(night ? Color(white: 0.91) : Color(red: 1, green: 0.83, blue: 0.08))
          .frame(width: geo.size.width * 0.67).offset(y: -3)
        if night {
          Circle().fill(Color(red: 0.10, green: 0.14, blue: 0.22))
            .frame(width: geo.size.width * 0.58).offset(x: 13, y: -13)
        }
        Ellipse().fill(Color(red: 0.48, green: 0.40, blue: 0.20).opacity(night ? 0.18 : 0.65))
          .frame(width: geo.size.width * 1.6, height: geo.size.height * 0.75)
          .rotationEffect(.degrees(-24)).offset(x: 22, y: geo.size.height * 0.32)
        Ellipse().fill(Color(red: 0.15, green: 0.14, blue: 0.10).opacity(0.85))
          .frame(width: geo.size.width * 1.7, height: geo.size.height * 0.7)
          .rotationEffect(.degrees(25)).offset(x: -20, y: geo.size.height * 0.43)
      }.clipped()
    }.accessibilityHidden(true)
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
  let locale: String?
  let fajrLabel: String?
  let sunriseLabel: String?
  let dhuhrLabel: String?
  let asrLabel: String?
  let maghribLabel: String?
  let ishaLabel: String?
  let dateLocation: String?
  let nextLabel: String?
  let nextPrayer: String?
  let nextName: String?
  let nextHour: String?
  let nextMinute: String?
  let nextEpoch: String?
  let period: String?
  let fajrTime: String?
  let sunriseTime: String?
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
      locale: (defaults?.string(forKey: "\(paramPrefix).locale") ?? "ru"),
      fajrLabel: defaults?.string(forKey: "\(paramPrefix).fajrLabel"),
      sunriseLabel: defaults?.string(forKey: "\(paramPrefix).sunriseLabel"),
      dhuhrLabel: defaults?.string(forKey: "\(paramPrefix).dhuhrLabel"),
      asrLabel: defaults?.string(forKey: "\(paramPrefix).asrLabel"),
      maghribLabel: defaults?.string(forKey: "\(paramPrefix).maghribLabel"),
      ishaLabel: defaults?.string(forKey: "\(paramPrefix).ishaLabel"),
      dateLocation: (timedValues["dateLocation"] as? String) ?? "",
      nextLabel: (timedValues["nextLabel"] as? String) ?? "",
      nextPrayer: (timedValues["nextPrayer"] as? String) ?? "",
      nextName: (timedValues["nextName"] as? String) ?? "",
      nextHour: (timedValues["nextHour"] as? String) ?? "—",
      nextMinute: (timedValues["nextMinute"] as? String) ?? "—",
      nextEpoch: (timedValues["nextEpoch"] as? String) ?? "",
      period: (timedValues["period"] as? String) ?? "day",
      fajrTime: (timedValues["fajrTime"] as? String) ?? "—",
      sunriseTime: (timedValues["sunriseTime"] as? String) ?? "—",
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

// Reading plan shares the existing WidgetKit extension and App Group.
private struct ReadingPlanData {
  let values: [String: Any]
  var locale: String { values["locale"] as? String ?? "ru" }
  func text(_ key: String) -> String { values[key] as? String ?? "—" }
  var validUntil: Date { Date(timeIntervalSince1970: ((values["validUntil"] as? NSNumber)?.doubleValue ?? 0) / 1000) }
  func isCurrent(at date: Date) -> Bool { values["isCurrent"] as? Bool == true && validUntil > date }
  var rows: [[String: String]] { values["rows"] as? [[String: String]] ?? [] }
  var progress: Double { min(100, max(0, (values["progress"] as? NSNumber)?.doubleValue ?? 0)) / 100 }
  var emptyLabel: String { values["emptyLabel"] as? String ?? NSLocalizedString("home_widget_reading_plan_open", comment: "") }
  static func load() -> ReadingPlanData {
    let prefs = UserDefaults(suiteName: "group.forum.iqro.app")
    guard let raw = prefs?.string(forKey: "home_widget.ReadingPlan.snapshot"),
      let data = raw.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return ReadingPlanData(values: [:]) }
    return ReadingPlanData(values: json)
  }
}

private struct ReadingPlanEntry: TimelineEntry {
  let date: Date
  let data: ReadingPlanData
}

private struct ReadingPlanProvider: TimelineProvider {
  func placeholder(in context: Context) -> ReadingPlanEntry {
    ReadingPlanEntry(date: Date(), data: ReadingPlanData(values: [:]))
  }
  func getSnapshot(in context: Context, completion: @escaping (ReadingPlanEntry) -> Void) {
    completion(ReadingPlanEntry(date: Date(), data: .load()))
  }
  func getTimeline(in context: Context, completion: @escaping (Timeline<ReadingPlanEntry>) -> Void) {
    let data = ReadingPlanData.load()
    let now = Date()
    var entries = [ReadingPlanEntry(date: now, data: data)]
    if data.validUntil > now { entries.append(ReadingPlanEntry(date: data.validUntil, data: data)) }
    completion(Timeline(entries: entries, policy: .after(max(now, data.validUntil).addingTimeInterval(21600))))
  }
}

private struct ReadingPlanView: View {
  let entry: ReadingPlanEntry
  private var data: ReadingPlanData { entry.data }
  private let gold = Color(red: 0.92, green: 0.78, blue: 0.46)
  var body: some View {
    GeometryReader { geo in
      if data.isCurrent(at: entry.date) {
        HStack(spacing: 10) {
          ZStack {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
              .fill(Color(red: 0.20, green: 0.17, blue: 0.10))
            Image(systemName: "book.fill").font(.system(size: 54))
              .foregroundColor(gold.opacity(0.24)).accessibilityHidden(true)
            VStack(spacing: 3) {
              Text(data.text("achieved"))
                .font(.system(size: 48, weight: .light).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.45)
              Text(data.text("targetLine")).font(.system(size: 17).monospacedDigit())
                .environment(\.layoutDirection, .leftToRight)
              Text(data.text("unit")).font(.system(size: 11))
                .lineLimit(1).minimumScaleFactor(0.7)
              GeometryReader { bar in
                ZStack(alignment: .leading) {
                  Capsule().fill(gold.opacity(0.22))
                  Capsule().fill(gold).frame(width: bar.size.width * data.progress)
                }
              }.frame(height: 3).padding(.top, 7)
            }.padding(8)
          }.frame(width: geo.size.width * 0.255)
          VStack(spacing: 3) {
            Text(data.text("title")).font(.system(size: 21))
              .lineLimit(2).minimumScaleFactor(0.65).multilineTextAlignment(.center)
            Spacer(minLength: 4)
            Text(data.text("remainingLabel")).font(.system(size: 13))
              .lineLimit(1).minimumScaleFactor(0.7)
            Text(data.text("remaining"))
              .font(.system(size: 28, weight: .semibold).monospacedDigit())
              .lineLimit(1).minimumScaleFactor(0.5)
            Text(data.text("unit")).font(.system(size: 11))
              .lineLimit(1).minimumScaleFactor(0.7)
          }.frame(maxWidth: .infinity)
          Rectangle().fill(Color.white.opacity(0.35)).frame(width: 1)
          Link(destination: URL(string: "iqro://open/after-prayer?homeWidget")!) {
            VStack(spacing: 3) {
              Text(data.text("afterPrayerLabel")).font(.system(size: 12))
                .lineLimit(1).minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity, alignment: .leading)
              ForEach(Array(data.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 3) {
                  Text(row["label"] ?? "—").lineLimit(1).minimumScaleFactor(0.7)
                  Spacer(minLength: 2)
                  Text(row["value"] ?? "—").foregroundColor(gold)
                    .font(.system(size: 14).monospacedDigit())
                    .lineLimit(1).minimumScaleFactor(0.7)
                }.font(.system(size: 14)).frame(maxHeight: .infinity)
              }
              Text(data.text("pageUnit")).font(.system(size: 10))
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
          }.buttonStyle(.plain).frame(width: geo.size.width * 0.35)
        }
      } else {
        VStack(alignment: .leading, spacing: 10) {
          Image(systemName: "book.fill").font(.system(size: 26)).foregroundColor(gold)
          Text(data.emptyLabel).font(.system(size: 16))
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      }
    }
    .foregroundColor(.white)
    .environment(\.locale, Locale(identifier: data.locale))
    .environment(\.layoutDirection, data.locale == "ar" ? .rightToLeft : .leftToRight)
    .applyContainerBackground(LinearGradient(gradient: Gradient(colors: [Color(white: 0.105), .black]), startPoint: .topLeading, endPoint: .bottomTrailing))
    .widgetURL(URL(string: "iqro://open/plan?homeWidget"))
  }
}

struct ReadingPlanHomeWidget: Widget {
  let kind = "ReadingPlanHomeWidget"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: ReadingPlanProvider()) { entry in
      ReadingPlanView(entry: entry)
    }
    .configurationDisplayName(NSLocalizedString("home_widget_reading_plan_label", comment: ""))
    .description(NSLocalizedString("home_widget_reading_plan_description", comment: ""))
    .supportedFamilies([.systemMedium])
  }
}
