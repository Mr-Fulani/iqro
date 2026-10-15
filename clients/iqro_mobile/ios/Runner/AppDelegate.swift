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
    }
    UNUserNotificationCenter.current().delegate =
      self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    BackupExclusionPlugin.register(in: engineBridge.pluginRegistry)
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
