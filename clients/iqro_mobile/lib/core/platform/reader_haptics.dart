import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One discrete pulse per page, never continuous vibration during scrolling.
class ReaderHaptics {
  static const channel = MethodChannel('forum.iqro.app/reader_haptics');

  /// A pulse that can be felt on a phone with a plain rotating motor, where
  /// the system's own ticks and the 22 ms of [pageChanged] are too short:
  /// [strong] is for a mark that stands out. On Android the length is sent to
  /// the motor (the phone's touch-vibration switch still applies); elsewhere
  /// the system's medium and heavy impacts are used.
  static Future<void> pulse({bool strong = false}) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await channel.invokeMethod<String>('pulse', <String, Object?>{
          'ms': strong ? strongPulseMs : pulseMs,
        });
        return;
      } on MissingPluginException {
        // Older native shells and test hosts have no custom channel.
      } on PlatformException {
        // A denied or unavailable motor must not interrupt the screen.
      }
    }
    try {
      await (strong
          ? HapticFeedback.heavyImpact()
          : HapticFeedback.mediumImpact());
    } on PlatformException {
      // Haptics are best effort.
    }
  }

  /// The lengths of [pulse] on Android, in milliseconds.
  static const pulseMs = 45;
  static const strongPulseMs = 80;

  static Future<void> pageChanged({required bool enabled}) async {
    if (!enabled) return;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await channel.invokeMethod<String>('pageTick');
        return;
      } on MissingPluginException {
        // Older native shells and test hosts have no custom channel.
      } on PlatformException {
        // A denied or unavailable motor must not interrupt reading.
      }
    }
    try {
      await HapticFeedback.lightImpact();
    } on PlatformException {
      // Haptics are best effort; page navigation remains functional.
    }
  }
}
