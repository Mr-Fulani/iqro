# device_info_plus — IQRO's copy

This is [device_info_plus](https://pub.dev/packages/device_info_plus) 13.2.0 (BSD-3-Clause,
`LICENSE`) with its iOS and macOS code removed. `lib/` and `android/` are the upstream files,
unchanged; only `pubspec.yaml` differs: no `ios` and `macos` platforms, no dev dependencies.

## Why

On iOS the plugin reads the free and total disk size (`NSFileSystemFreeSize`,
`NSFileSystemSize`) every time `iosInfo` is called. Apple lists these as "required reason"
APIs of the DiskSpace category: an app that contains code calling them must name a reason in
its privacy manifest, or App Store Connect refuses the upload (ITMS-91053). The plugin's own
manifest declares nothing, and none of Apple's four reasons is true for IQRO — the app used
only the iOS version and threw the disk sizes away. Apple checks the binary, not whether the
call happens, so not calling `iosInfo` would not be enough: the code must not be in the app.

Without the `ios` platform Flutter links nothing from this package into the iPhone app. The
app reads the iOS version from `Platform.operatingSystemVersion` instead
(`lib/core/platform/ios_version.dart`). Android keeps the plugin exactly as before:
the Android SDK level, the Android version and the emulator check.

`DeviceInfoPlugin().iosInfo` therefore throws `MissingPluginException` on iOS; the app must
not call it (`test/core/ios_configuration_test.dart` checks this). The CI step
`ios/scripts/check_privacy_manifests.py` checks the built `Runner.app` for undeclared
required-reason APIs.

## Updating

Copy `lib/`, `android/` and `LICENSE` from the new upstream version, keep this
`pubspec.yaml` (update its version and dependencies from upstream), then run
`flutter pub get` and, in `ios/`, `pod install`.
