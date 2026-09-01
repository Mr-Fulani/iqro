import Foundation
import XCTest

final class RunnerTests: XCTestCase {
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
