import Foundation
import XCTest

final class RunnerTests: XCTestCase {
  func testEmbeddedPrayerWidgetHasMatchingAppVersions() throws {
    let pluginsURL = try XCTUnwrap(Bundle.main.builtInPlugInsURL)
    let widgetURL = pluginsURL.appendingPathComponent("PrayerTimesHomeWidget.appex")
    let widget = try XCTUnwrap(Bundle(url: widgetURL))

    for key in ["CFBundleVersion", "CFBundleShortVersionString"] {
      let appVersion = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: key) as? String)
      let widgetVersion = try XCTUnwrap(widget.object(forInfoDictionaryKey: key) as? String)
      XCTAssertFalse(appVersion.isEmpty, "The app must declare \(key)")
      XCTAssertEqual(widgetVersion, appVersion, "The widget must share the app's \(key)")
    }
  }

  func testInfoPlistAdvertisesBackgroundCapabilities() throws {
    let sourceRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let plistURL = sourceRoot.appendingPathComponent("Runner/Info.plist")
    let data = try Data(contentsOf: plistURL)
    let plist = try XCTUnwrap(
      PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any]
    )

    XCTAssertEqual(
      plist["BGTaskSchedulerPermittedIdentifiers"] as? [String],
      ["forum.iqro.app.periodic-maintenance-v1"]
    )
    XCTAssertEqual(
      Set(plist["UIBackgroundModes"] as? [String] ?? []),
      Set(["audio", "fetch"])
    )
    XCTAssertNotNil(plist["NSLocationWhenInUseUsageDescription"])
    XCTAssertNil(plist["NSLocationAlwaysAndWhenInUseUsageDescription"])
    XCTAssertEqual(plist["CFBundleAllowMixedLocalizations"] as? Bool, true)
  }
}
