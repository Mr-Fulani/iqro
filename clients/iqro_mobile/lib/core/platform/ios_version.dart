import 'dart:io';

/// The iOS version, e.g. `17.2` or `26.1.1`, or `unknown`.
///
/// Read from `Platform.operatingSystemVersion` (NSProcessInfo's
/// `operatingSystemVersionString`, "Version 17.2 (Build 21C62)"), not from
/// device_info_plus: its iOS code reads the disk size, which needs a reason in
/// the privacy manifest (third_party/device_info_plus/README.md).
String iosVersion([String? operatingSystemVersion]) {
  final text = operatingSystemVersion ?? Platform.operatingSystemVersion;
  return RegExp(r'\d+(?:\.\d+)*').firstMatch(text)?.group(0) ?? 'unknown';
}
