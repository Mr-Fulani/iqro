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
