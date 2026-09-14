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
