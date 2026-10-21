import CoreLocation
import Flutter
import UIKit
import UserNotifications
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    WorkmanagerPlugin.registerLaunchHandlers()
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "forum.iqro.app.periodic-maintenance-v1",
      earliestBeginInSeconds: NSNumber(value: 6 * 60 * 60)
    )
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
      BackupExclusionPlugin.register(in: registry)
      QiblaCompassPlugin.register(in: registry)
    }
    UNUserNotificationCenter.current().delegate =
      self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    BackupExclusionPlugin.register(in: engineBridge.pluginRegistry)
    QiblaCompassPlugin.register(in: engineBridge.pluginRegistry)
  }
}

/// Re-downloadable content must not land in iCloud backups (iOS Data Storage Guidelines).
final class BackupExclusionPlugin: NSObject, FlutterPlugin {
  static func register(in registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "BackupExclusionPlugin") else { return }
    register(with: registrar)
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "forum.iqro.app/backup_exclusion",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(BackupExclusionPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "excludeFromBackup" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let path = call.arguments as? String, !path.isEmpty else {
      result(FlutterError(code: "invalid_path", message: "Directory path is required", details: nil))
      return
    }
    var url = URL(fileURLWithPath: path, isDirectory: true)
    do {
      if try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup != true {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
      }
      result(nil)
    } catch {
      result(FlutterError(code: "exclude_failed", message: error.localizedDescription, details: nil))
    }
  }
}

/// Heading for the Qibla compass (`qibla_compass.dart`). CoreLocation runs the
/// compass only while Dart listens, so it stops when the Qibla sheet closes or the
/// app leaves the foreground. Heading needs no permission; `trueHeading` is valid
/// only when CoreLocation knows the location, otherwise Dart corrects
/// `magneticHeading` with the WMM declination. Nothing leaves the device.
final class QiblaCompassPlugin: NSObject, FlutterPlugin, FlutterStreamHandler,
  CLLocationManagerDelegate
{
  private var manager: CLLocationManager?
  private var sink: FlutterEventSink?

  static func register(in registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "QiblaCompassPlugin") else { return }
    register(with: registrar)
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterEventChannel(
      name: "forum.iqro.app/qibla_compass",
      binaryMessenger: registrar.messenger()
    )
    channel.setStreamHandler(QiblaCompassPlugin())
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    guard CLLocationManager.headingAvailable() else {
      events(FlutterError(code: "unavailable", message: "No compass", details: nil))
      return nil
    }
    let manager = CLLocationManager()
    manager.delegate = self
    manager.headingOrientation = Self.interfaceHeadingOrientation()
    self.manager = manager
    sink = events
    manager.startUpdatingHeading()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    manager?.stopUpdatingHeading()
    manager?.delegate = nil
    manager = nil
    sink = nil
    return nil
  }

  func locationManager(_ manager: CLLocationManager, didUpdateHeading heading: CLHeading) {
    // Measure from the top of the screen in the current interface orientation.
    let orientation = Self.interfaceHeadingOrientation()
    if manager.headingOrientation != orientation {
      manager.headingOrientation = orientation
    }
    sink?([
      "true": heading.trueHeading,
      "magnetic": heading.magneticHeading,
      "accuracy": heading.headingAccuracy,
    ])
  }

  /// The sheet shows its own figure-eight hint, the same as on Android.
  func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
    false
  }

  private static func interfaceHeadingOrientation() -> CLDeviceOrientation {
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    let orientation: UIInterfaceOrientation?
    if #available(iOS 16.0, *) {
      orientation = scene?.effectiveGeometry.interfaceOrientation
    } else {
      orientation = scene?.interfaceOrientation
    }
    // UIInterfaceOrientation.landscapeLeft is UIDeviceOrientation.landscapeRight.
    switch orientation ?? .portrait {
    case .landscapeLeft: return .landscapeRight
    case .landscapeRight: return .landscapeLeft
    case .portraitUpsideDown: return .portraitUpsideDown
    default: return .portrait
    }
  }
}
